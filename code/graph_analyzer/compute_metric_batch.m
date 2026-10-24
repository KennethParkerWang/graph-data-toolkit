function reports = compute_metric_batch(dataset_root,graph_ids,selections,options)
%COMPUTE_METRIC_BATCH Explicit graph/metric selection, preview by default.
% Read task1's manifest; never recursively discover production graphs.
if nargin<4, options=struct(); end
allowed={'preview','writer_id','protocol','seed','repeat_index','summaries','run_root','run_session'};
if ~isempty(setdiff(fieldnames(options),allowed)), error('mc:Config','Unknown batch option.'); end
dataset_root=fileparts(mc.safe_path(dataset_root,'dataset.json'));
preview=mc.param(options,'preview',true); validateattributes(preview,{'logical'},{'scalar'});
selections=mc.validate_selection(selections);
if ischar(graph_ids)||isstring(graph_ids), graph_ids=cellstr(graph_ids); end
if ~iscell(graph_ids)||isempty(graph_ids)||numel(unique(graph_ids))~=numel(graph_ids), error('mc:Config','Select a nonempty unique graph_id list.'); end
session=[]; owner=false;
if ~preview
    previous_path=path; restore=onCleanup(@()path(previous_path)); %#ok<NASGU>
    addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'graph_builder','io'),'-begin');
    session=mc.param(options,'run_session',[]); owner=isempty(session);
    if owner
        [~,dataset_id]=fileparts(char(java.io.File(dataset_root).getCanonicalPath()));
        metadata=fullfile(dataset_root,'dataset.json');
        if isfile(metadata), data=jsondecode(fileread(metadata)); if isfield(data,'dataset_id'), dataset_id=data.dataset_id; end, end
        runopts=options; for f={'preview','run_root','run_session'}, if isfield(runopts,f{1}), runopts=rmfield(runopts,f{1}); end, end
        config=struct('entry_point','compute_metric_batch','graph_ids',{graph_ids},'selections',{selections},'options',runopts);
        inputs=struct('path',{fullfile(dataset_root,'manifests','graphs.jsonl'),metadata});
        session=gg_run_record('start',dataset_root,dataset_id,'graph_analyzer',config,inputs,mc.param(options,'run_root',''));
    elseif ~isstruct(session)||~isscalar(session)||~all(isfield(session,{'directory','stage','dataset_root'}))||~strcmp(session.stage,'graph_analyzer')||~strcmpi(session.dataset_root,char(java.io.File(dataset_root).getCanonicalPath()))
        error('mc:Config','run_session must belong to this dataset and graph_analyzer stage.');
    end
    options.run_session=session;
end
try
rows=mc.read_jsonl(fullfile(dataset_root,'manifests','graphs.jsonl'));
if isempty(rows), error('mc:Input','Original graph manifest is missing or empty.'); end
for i=1:numel(graph_ids)
    if isempty(regexp(graph_ids{i},'^[0-9a-f]{64}$','once'))||sum(strcmp({rows.graph_id},graph_ids{i}))~=1
        error('mc:Input','Graph ID absent/ambiguous: %s.',graph_ids{i});
    end
end
reports=cell(numel(graph_ids),1);
for i=1:numel(graph_ids)
    row=rows(strcmp({rows.graph_id},graph_ids{i})); t=tic;
    try
        graph_path=mc.safe_path(dataset_root,row.path);
        if ~strcmp(mc.file_hash(graph_path),row.file_sha256), error('mc:Integrity','Original graph file hash mismatch.'); end
        [~,identity]=mc.read_graph(graph_path);
        for name={'graph_id','topology_hash','origin_graph_id'}
            if ~strcmp(identity.(name{1}),row.(name{1})), error('mc:Integrity','Original manifest/content identity differs: %s.',name{1}); end
        end
        reports{i}=compute_graph_metrics(dataset_root,row.path,selections,options);
    catch err
        reports{i}=struct('preview',preview,'graph_id',graph_ids{i},'status','failed','error_identifier',err.identifier,'reason',err.message,'elapsed_seconds',toc(t));
        if ~preview
            reports{i}.job_directory=session.directory;
            try
                gg_run_record('event',session,struct('event','graph_attempt_failed','report',reports{i}));
            catch record_error
                reports{i}.task_record_error=struct('identifier',record_error.identifier,'message',record_error.message);
            end
        end
    end
    fprintf('metric batch %d/%d graph=%s status=%s\n',i,numel(graph_ids),graph_ids{i},reports{i}.status);
end
if ~preview
    writer=mc.param(options,'writer_id','serial');
    if isempty(regexp(writer,'^[A-Za-z0-9_-]+$','once')), error('mc:Config','Unsafe writer ID.'); end
    directory=fullfile(dataset_root,'manifests','parts'); if ~isfolder(directory), mkdir(directory); end
    log_id=char(java.util.UUID.randomUUID()); lines=cellfun(@jsonencode,reports,'UniformOutput',false);
    attempt_path=char(java.io.File(fullfile(directory,['metric_attempts_',writer,'_',log_id,'.jsonl'])).getCanonicalPath());
    mc.write_text_atomic(attempt_path,[strjoin(lines,newline),newline]);
    if owner
        ok=cellfun(@(r)ismember(r.status,{'complete','resumed'}),reports); references={};
        for i=1:numel(reports)
            if isfield(reports{i},'record')&&isfield(reports{i}.record,'path')
                reference=reports{i}.record; reference.path=mc.safe_path(dataset_root,reference.path); references{end+1}=reference; %#ok<AGROW>
            end
        end
        summary=struct('graph_count',numel(graph_ids),'complete_count',sum(ok),'failure_count',sum(~ok),'attempt_log',attempt_path,'reports',{reports});
        if all(ok)
            gg_run_record('finish',session,'complete',references,summary);
        else
            failure=struct('identifier','mc:BatchIncomplete','message',sprintf('%d/%d graph attempts failed or remained partial.',sum(~ok),numel(ok)),'attempts',{reports(~ok)});
            gg_run_record('finish',session,'failed',references,summary,failure);
        end
    end
end
catch err
    if ~preview&&owner
        try, gg_run_record('finish',session,'failed',struct([]),struct('graph_ids',{graph_ids}),err);
        catch record_error, err=addCause(err,record_error); end
    end
    rethrow(err);
end
end
