function result = gg_run_record(action, varargin)
%GG_RUN_RECORD Store task metadata separately from scientific dataset records.
% start(root,id,stage,config,inputs[,run_root]) creates an independent job.
% work(session) creates persistent intermediate storage only when requested.
switch char(action)
    case 'start'
        dataset_root = absolute_path(varargin{1},'dataset_root',pwd);
        [dataset_id,dataset_folder] = dataset_name(varargin{2});
        stage = char(varargin{3});
        stages = {'graph_builder','graph_analyzer','dataset_builder'};
        snapshots = {'generation.json','analysis.json','build.json'};
        stage_index = find(strcmp(stage,stages),1);
        if isempty(stage_index), error('graphrun:Stage','Unknown task stage.'); end
        config = varargin{4}; inputs = input_references(varargin{5});
        project_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
        run_root = fullfile(project_root,'_local','runs');
        if numel(varargin) >= 6 && ~isempty(varargin{6}), run_root = varargin{6}; end
        run_root = absolute_path(run_root,'RunRoot',project_root);
        if isfile(run_root) || same_or_inside(run_root,dataset_root)
            error('graphrun:Root','RunRoot must be a directory outside the dataset.');
        end
        parent = fullfile(run_root,dataset_folder);
        if isfile(parent), error('graphrun:Root','Dataset task directory is a file.'); end
        identifier = strrep(char(java.util.UUID.randomUUID()),'-','');
        stamp = char(datetime('now','TimeZone','UTC','Format',"yyyyMMdd'T'HHmmssSSS"));
        job_id = [stamp '_' stage '_' identifier];
        directory = fullfile(parent,job_id);
        if exist(directory,'file'), error('graphrun:Conflict','Task directory already exists.'); end
        ensure_directory(fullfile(directory,'configs'));
        ensure_directory(fullfile(directory,'logs'));
        config_file = ['configs/' snapshots{stage_index}];
        write_json(fullfile(directory,config_file),config);
        now = utc_now();
        record = struct('schema_version','toolkit-run-v1','dataset_id',dataset_id, ...
            'dataset_folder',dataset_folder, ...
            'dataset_root',dataset_root,'job_id',job_id,'stage',stage, ...
            'status','running','started_utc',now,'updated_utc',now,'finished_utc','', ...
            'config_file',config_file,'config_file_sha256', ...
            gg_io_sha256(fullfile(directory,config_file),'file'), ...
            'work_directory',['work/' stage],'inputs',{inputs}, ...
            'outputs',struct(),'summary',struct());
        write_json(fullfile(directory,'run.json'),record);
        result = struct('directory',directory,'work_directory',fullfile(directory,'work',stage), ...
            'dataset_root',dataset_root,'dataset_id',dataset_id,'dataset_folder',dataset_folder, ...
            'job_id',job_id,'stage',stage);
        gg_run_record('event',result,struct('event','started','status','running'));
    case 'event'
        session = varargin{1}; event = varargin{2};
        if ~isstruct(event) || ~isscalar(event)
            error('graphrun:Event','Task events must be scalar structs.');
        end
        if ~isfield(event,'timestamp_utc'), event.timestamp_utc = utc_now(); end
        if ~isfield(event,'stage'), event.stage = session.stage; end
        path = fullfile(session.directory,'logs',[session.stage '.jsonl']);
        file = fopen(path,'a','n','UTF-8');
        if file < 0, error('graphrun:Write','Cannot append task log: %s',path); end
        closer = onCleanup(@() fclose(file)); %#ok<NASGU>
        if fprintf(file,'%s\n',jsonencode(event)) < 0
            error('graphrun:Write','Could not write complete task event.');
        end
        result = session;
    case 'finish'
        session = varargin{1}; status = char(varargin{2});
        if ~ismember(status,{'complete','failed'})
            error('graphrun:Status','Task finish status must be complete or failed.');
        end
        record = jsondecode(fileread(fullfile(session.directory,'run.json')));
        record.status = status; record.updated_utc = utc_now();
        record.finished_utc = record.updated_utc;
        record.outputs = varargin{3}; record.summary = varargin{4};
        if numel(varargin) >= 5 && ~isempty(varargin{5})
            problem = varargin{5};
            if isa(problem,'MException')
                problem = struct('identifier',problem.identifier,'message',problem.message,'stack',problem.stack);
            end
            ensure_directory(fullfile(session.directory,'failures'));
            write_json(fullfile(session.directory,'failures','error.json'),problem);
            record.error_file = 'failures/error.json';
        end
        report = struct('schema_version','toolkit-run-v1','job_id',session.job_id, ...
            'stage',session.stage,'status',status,'finished_utc',record.finished_utc, ...
            'outputs',record.outputs,'summary',record.summary);
        ensure_directory(fullfile(session.directory,'reports'));
        write_json(fullfile(session.directory,'reports',[session.stage '.json']),report);
        gg_run_record('event',session,struct('event','finished','status',status,'summary',record.summary));
        write_json(fullfile(session.directory,'run.json'),record);
        result = session;
    case 'work'
        session = varargin{1};
        ensure_directory(session.work_directory);
        result = session.work_directory;
    otherwise
        error('graphrun:Action','Unknown task record action.');
end
end

function references = input_references(inputs)
if isempty(inputs), references = {}; return; end
if isstruct(inputs), inputs = num2cell(inputs(:)); end
if ~iscell(inputs), error('graphrun:Inputs','Input references must be structs or cells of structs.'); end
references = cell(size(inputs));
for k = 1:numel(inputs)
    entry = inputs{k};
    if ~isstruct(entry) || ~isscalar(entry) || ~isfield(entry,'path')
        error('graphrun:Inputs','Each input reference must contain a path.');
    end
    entry.path = absolute_path(entry.path,'input path',pwd);
    entry.exists = isfile(entry.path) || isfolder(entry.path);
    entry.kind = 'missing'; entry.file_sha256 = ''; entry.hash_error = '';
    if isfolder(entry.path)
        entry.kind = 'directory';
    elseif isfile(entry.path)
        entry.kind = 'file';
        try, entry.file_sha256 = gg_io_sha256(entry.path,'file');
        catch problem, entry.hash_error = problem.message; end
    end
    references{k} = entry;
end
end

function path = absolute_path(value,label,base)
if ~(ischar(value) && isrow(value)) && ~(isstring(value) && isscalar(value))
    error('graphrun:Path','%s must be a nonempty path string.',label);
end
value = char(value);
if isempty(strtrim(value)), error('graphrun:Path','%s cannot be empty.',label); end
file = java.io.File(value);
if ~file.isAbsolute()
    file = java.io.File(fullfile(base,value));
end
path = char(file.getCanonicalPath());
end

function [value,folder] = dataset_name(value)
if ~(ischar(value) && isrow(value) && ~isempty(value)) && ...
        ~(isstring(value) && isscalar(value) && ~ismissing(value) && strlength(value) > 0)
    error('graphrun:Name','dataset_id must be a nonempty text scalar.');
end
value = char(value);
folder = value;
if length(value) > 100 || isempty(regexp(value,'^[A-Za-z0-9][A-Za-z0-9_-]*$','once')) || ...
        ~isempty(regexpi(value,'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$','once'))
    digest = gg_io_sha256(value);
    folder = ['dataset_' digest(1:12)];
end
end

function yes = same_or_inside(path,parent)
path = strrep(path,'/','\'); parent = strrep(parent,'/','\');
yes = strcmpi(path,parent) || startsWith(lower(path),[lower(parent) '\']);
end

function ensure_directory(path)
[success,message] = mkdir(path);
if ~success, error('graphrun:Write','Cannot create task directory: %s',message); end
end

function write_json(path,value)
gg_io_atomic_text(path,[jsonencode(value,'PrettyPrint',true) newline]);
end

function value = utc_now()
value = char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end
