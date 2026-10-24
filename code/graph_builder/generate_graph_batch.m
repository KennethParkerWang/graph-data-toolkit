function result = generate_graph_batch(config_file, varargin)
%GENERATE_GRAPH_BATCH Generate graph-v1 files from a version-2 JSON config.
% generate_graph_batch('configs/smoke.json','DryRun',true) writes nothing.
% Each run has its own JSONL. Resume verifies committed bytes and recipes.
% One batch scheduler owns a dataset at a time; independent I/O writers use
% immutable manifest parts and a separately locked index publisher.
parser = inputParser;
parser.addRequired('config_file',@(x) ischar(x) || (isstring(x) && isscalar(x)));
parser.addParameter('DryRun',false,@(x) isscalar(x) && ismember(x,[0,1]));
parser.addParameter('RunRoot','',@(x) ischar(x) || (isstring(x) && isscalar(x)));
parser.parse(config_file,varargin{:});
setup_generators();
[config,plan,config_digest,config_path] = gg_batch_plan(parser.Results.config_file);
result = struct('planned',numel(plan),'generated',0,'skipped',0,'recovered',0,'failed',0, ...
    'output_dir',config.output_dir,'plan',plan,'config_sha256',config_digest, ...
    'generator_version','2.1.0','batch_id','','records',[],'run_log','','job_directory','');
if parser.Results.DryRun
    fprintf('DryRun: %d graphs, no files written.\n',numel(plan));
    for id = unique([plan.job_id])
        item = plan(find([plan.job_id] == id,1));
        fprintf('  job %d: %s [%s]\n',id,item.generator_id,item.source_classification);
    end
    return;
end
session = gg_run_record('start',config.output_dir,config.dataset_id,'graph_builder', ...
    config,struct('path',config_path),parser.Results.RunRoot);
result.job_directory = session.directory;
last_failure = [];
try
implementation_digest = gg_implementation_digest();
if isfile(config.output_dir), error('graphgen:BatchOutputConflict','output_dir is a file.'); end
if ~isfolder(config.output_dir), mkdir(config.output_dir); end
guard = gg_io_lock(fullfile(config.output_dir,'.graphgen.lock')); %#ok<NASGU>
prepare_dataset(config,config_digest,implementation_digest);
previous = read_previous_attempts(config.output_dir,config_digest,implementation_digest,plan);
result.batch_id = strrep(char(java.util.UUID.randomUUID()),'-','');
run_file = fullfile(config.output_dir,'manifests','generation_runs',[result.batch_id '.jsonl']);
result.run_log = run_file;
records = repmat(empty_attempt(),numel(plan),1);
source_cache = containers.Map('KeyType','char','ValueType','any');
for k = 1:numel(plan)
    item = plan(k);
    event = empty_attempt();
    copy_names = {'sample_id','job_id','combination_id','replicate','model','direction','seed','generator_id'};
    for j = 1:numel(copy_names), event.(copy_names{j}) = item.(copy_names{j}); end
    event.parameters_json = jsonencode(gg_batch_canonical(item.parameters));
    event.config_sha256 = config_digest;
    event.implementation_sha256 = implementation_digest;
    event.batch_id = result.batch_id;
    started = tic;
    failure = [];
    try
        if ~isempty(previous{k})
            if ~config.resume, error('graphgen:BatchResumeDisabled','resume=false with existing graph.'); end
            old = previous{k};
            if ~strcmp(old.parameters_json,event.parameters_json) || old.seed ~= item.seed || ...
                    ~strcmp(old.generator_id,item.generator_id)
                error('graphgen:BatchAttemptConflict','Previous attempt differs from current plan.');
            end
            sample = gg_batch_resume_graph(config.output_dir,old,item,implementation_digest);
            event.graph_id = sample.graph_id;
            event.path = old.path;
            event.status = 'skipped';
            result.skipped = result.skipped+1;
        else
            [function_name,call_args] = gg_batch_registry(item.model,item.direction,item.parameters);
            if ~isKey(source_cache,function_name)
                source_cache(function_name) = gg_source_info(function_name);
            end
            [A,meta] = feval(function_name,call_args{:},item.seed);
            prepared = gg_prepare_metadata(A,meta,function_name,implementation_digest,source_cache(function_name));
            sample = gg_io_make_sample(A,prepared);
            [record,status] = gg_io_write_graph(config.output_dir,sample);
            event.graph_id = record.graph_id;
            event.path = record.path;
            switch status
                case 'created'
                    event.status = 'generated'; result.generated = result.generated+1;
                case 'recovered'
                    event.status = 'recovered'; result.recovered = result.recovered+1;
                otherwise
                    event.status = 'skipped'; result.skipped = result.skipped+1;
            end
        end
        event.N = double(sample.N); event.M = double(sample.M);
    catch caught
        failure = caught;
        last_failure = caught;
        event.status = 'failed'; event.error_id = caught.identifier; event.error_message = caught.message;
        result.failed = result.failed+1;
    end
    event.elapsed_seconds = toc(started); event.timestamp_utc = utc_now();
    records(k) = event;
    gg_batch_append_record(run_file,event);
    try
        gg_run_record('event',session,event);
    catch record_error
        if ~isempty(failure)
            failure = addCause(failure,record_error);
            rethrow(failure);
        end
        rethrow(record_error);
    end
    if ~isempty(failure) && strcmp(config.on_error,'stop')
        % Graph parts remain committed if publishing the index detects damage.
        try, gg_io_merge_manifest(config.output_dir); catch, end
        rethrow(failure);
    end
    if mod(k,max(1,ceil(numel(plan)/100))) == 0 || k == numel(plan)
        fprintf('Processed %d/%d: generated=%d skipped=%d recovered=%d failed=%d\n', ...
            k,numel(plan),result.generated,result.skipped,result.recovered,result.failed);
    end
end
gg_io_merge_manifest(config.output_dir);
result.records = records;
result.run_log = run_file;
status = 'complete';
if result.failed > 0, status = 'failed'; end
gg_run_record('finish',session,status,task_outputs(result),task_summary(result),last_failure);
catch failure
    try
        gg_run_record('finish',session,'failed',task_outputs(result),task_summary(result),failure);
    catch logging_failure
        warning('graphrun:FailureRecord','Task failure metadata could not be saved: %s',logging_failure.message);
    end
    rethrow(failure);
end
end

function outputs = task_outputs(result)
outputs = struct('dataset_root',result.output_dir,'graphs_root',fullfile(result.output_dir,'graphs'), ...
    'graph_manifest',fullfile(result.output_dir,'manifests','graphs.jsonl'), ...
    'generation_log',result.run_log,'batch_id',result.batch_id,'config_sha256',result.config_sha256);
end

function summary = task_summary(result)
summary = struct('planned',result.planned,'generated',result.generated,'skipped',result.skipped, ...
    'recovered',result.recovered,'failed',result.failed);
end

function prepare_dataset(config,config_digest,implementation_digest)
descriptor_file = fullfile(config.output_dir,'dataset.json');
snapshot_file = fullfile(config.output_dir,'configs','generation.json');
if isfile(descriptor_file)
    descriptor = jsondecode(fileread(descriptor_file));
    required = {'dataset_id','graph_schema_version','generation_config_sha256', ...
        'generation_config_file_sha256','implementation_sha256'};
    if ~isstruct(descriptor) || ~isscalar(descriptor) || ~all(isfield(descriptor,required)) || ...
            ~strcmp(descriptor.dataset_id,config.dataset_id) || ...
            ~strcmp(descriptor.graph_schema_version,'graph-v1') || ...
            ~strcmp(descriptor.generation_config_sha256,config_digest) || ...
            ~strcmp(descriptor.implementation_sha256,implementation_digest) || ...
            ~isfile(snapshot_file) || ...
            ~strcmp(gg_io_sha256(snapshot_file,'file'),descriptor.generation_config_file_sha256)
        error('graphgen:BatchConfigConflict','Dataset configuration or implementation differs; use a new dataset.');
    end
    if ~config.resume, error('graphgen:BatchResumeDisabled','Dataset exists and resume=false.'); end
else
    entries = dir(config.output_dir);
    names = setdiff({entries.name},{'.','..','.graphgen.lock'});
    if ~isempty(names)
        error('graphgen:BatchOutputConflict','Nonempty output directory has no valid dataset.json.');
    end
    directories = {'configs','configs/metric_sets','configs/protocols','graphs','metrics', ...
        'manifests','manifests/parts','manifests/generation_runs','splits','training'};
    for k = 1:numel(directories), mkdir(fullfile(config.output_dir,directories{k})); end
    snapshot = config;
    snapshot.output_dir = '..'; % Relative to configs/generation.json after dataset relocation.
    gg_batch_write_text(snapshot_file,[jsonencode(snapshot,'PrettyPrint',true) newline],false);
    descriptor = struct('dataset_id',config.dataset_id,'graph_schema_version','graph-v1', ...
        'created_utc',utc_now(),'generation_config','configs/generation.json', ...
        'generation_config_sha256',config_digest, ...
        'generation_config_file_sha256',gg_io_sha256(snapshot_file,'file'), ...
        'implementation_sha256',implementation_digest,'implementation_version','2.1.0', ...
        'graph_root','graphs','graph_manifest','manifests/graphs.jsonl', ...
        'description','Synthetic simple graphs; metrics and attacks are separate records.');
    gg_batch_write_text(descriptor_file,[jsonencode(descriptor,'PrettyPrint',true) newline],false);
end
end

function previous = read_previous_attempts(root,config_digest,implementation_digest,plan)
count = numel(plan);
previous = cell(count,1);
files = dir(fullfile(root,'manifests','generation_runs','*.jsonl'));
for k = 1:numel(files)
    text = fileread(fullfile(files(k).folder,files(k).name));
    lines = regexp(text,'\r?\n','split');
    for j = 1:numel(lines)
        if isempty(strtrim(lines{j})), continue; end
        try, event = jsondecode(lines{j});
        catch failure
            if j == numel(lines) && ~endsWith(text,newline)
                warning('graphgen:IncompleteAttempt','Ignoring an interrupted final log line in %s.',files(k).name);
                continue;
            end
            rethrow(failure);
        end
        required = {'sample_id','config_sha256','implementation_sha256','status','graph_id', ...
            'path','generator_id','seed','parameters_json'};
        if ~isstruct(event) || ~isscalar(event) || ~all(isfield(event,required)) || ...
                ~strcmp(event.config_sha256,config_digest) || ...
                ~strcmp(event.implementation_sha256,implementation_digest) || ...
                ~isscalar(event.sample_id) || event.sample_id < 1 || event.sample_id > count || ...
                event.sample_id ~= fix(event.sample_id)
            error('graphgen:BatchAttemptConflict','Invalid or foreign generation run log.');
        end
        if ismember(event.status,{'generated','skipped','recovered'})
            id = event.sample_id;
            item = plan(id);
            if event.seed ~= item.seed || ~strcmp(event.generator_id,item.generator_id) || ...
                    ~strcmp(event.parameters_json,jsonencode(gg_batch_canonical(item.parameters)))
                error('graphgen:BatchAttemptConflict','Completed attempt does not match its plan.');
            end
            if ~isempty(previous{id}) && (~strcmp(previous{id}.graph_id,event.graph_id) || ...
                    ~strcmp(previous{id}.path,event.path))
                error('graphgen:BatchAttemptConflict','One planned sample points to different graphs.');
            end
            previous{id} = event;
        elseif ~strcmp(event.status,'failed')
            error('graphgen:BatchAttemptConflict','Unknown attempt status.');
        end
    end
end
end

function value = empty_attempt()
value = struct('sample_id',0,'job_id',0,'combination_id',0,'replicate',0, ...
    'model','','direction','','generator_id','','seed',0,'parameters_json','', ...
    'config_sha256','','implementation_sha256','','batch_id','','graph_id','','path','', ...
    'status','','N',0,'M',0,'elapsed_seconds',0,'timestamp_utc','','error_id','','error_message','');
end

function value = utc_now()
value = char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end
