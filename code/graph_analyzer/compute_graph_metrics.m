function report = compute_graph_metrics(dataset_root,graph_relative_path,selections,options)
%COMPUTE_GRAPH_METRICS Single graph entry using the official task1 reader.
% Default preview=true: validation/identity only; no metric computation/save.
if nargin<4, options=struct(); end
allowed={'preview','writer_id','protocol','seed','repeat_index','summaries','run_root','run_session'};
if ~isempty(setdiff(fieldnames(options),allowed)), error('mc:Config','Unknown single-graph option.'); end
dataset_root=fileparts(mc.safe_path(dataset_root,'dataset.json'));
preview=mc.param(options,'preview',true); validateattributes(preview,{'logical'},{'scalar'});
writer=mc.param(options,'writer_id','serial'); runopts=options;
for f={'preview','writer_id','run_root','run_session'}, if isfield(runopts,f{1}), runopts=rmfield(runopts,f{1}); end, end
graph_path=mc.safe_path(dataset_root,graph_relative_path); session=[]; owner=false;
if ~preview
    previous_path=path; restore=onCleanup(@()path(previous_path)); %#ok<NASGU>
    addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))),'graph_builder','io'),'-begin');
    session=mc.param(options,'run_session',[]); owner=isempty(session);
    if owner
        [~,dataset_id]=fileparts(char(java.io.File(dataset_root).getCanonicalPath()));
        metadata=fullfile(dataset_root,'dataset.json');
        if isfile(metadata), data=jsondecode(fileread(metadata)); if isfield(data,'dataset_id'), dataset_id=data.dataset_id; end, end
        config=struct('entry_point','compute_graph_metrics','graph_path',graph_relative_path,'selections',{selections},'options',runopts,'writer_id',writer);
        session=gg_run_record('start',dataset_root,dataset_id,'graph_analyzer',config,struct('path',graph_path),mc.param(options,'run_root',''));
    elseif ~isstruct(session)||~isscalar(session)||~all(isfield(session,{'directory','stage','dataset_root'}))||~strcmp(session.stage,'graph_analyzer')||~strcmpi(session.dataset_root,char(java.io.File(dataset_root).getCanonicalPath()))
        error('mc:Config','run_session must belong to this dataset and graph_analyzer stage.');
    end
end
try
    [ctx,identity,source_record]=mc.read_graph(graph_path); plan=mc.plan_run(identity,selections,runopts);
    report=struct('preview',preview,'run_id',plan.run_id,'metric_set_id',plan.metric_set_id,'graph_id',identity.graph_id,'status','preview','record',struct(),'job_directory','');
    if preview, return; end
    report.job_directory=session.directory;
    gg_run_record('event',session,struct('event','graph_started','graph_id',identity.graph_id,'path',graph_path,'file_sha256',source_record.file_sha256,'run_id',plan.run_id));
    old=mc.find_record(dataset_root,plan.run_id);
    if ~isempty(old)
        saved=mc.verify_record(dataset_root,old);
        if ~strcmp(saved.status,'complete'), error('mc:Incomplete','Existing incomplete run: %s',saved.status); end
        if ~strcmp(saved.metric_set_identity_json,plan.metric_set_identity_json)||~strcmp(saved.run_identity_json,plan.run_identity_json), error('mc:Conflict','Resume identity mismatch.'); end
        report.status='resumed'; report.record=old;
    else
        output=mc.build_run(ctx,identity,selections,runopts); [record,resumed]=mc.save_run(dataset_root,output,writer);
        report.record=record; report.status=output.status; if resumed, report.status='resumed'; end
    end
    gg_run_record('event',session,struct('event','graph_finished','report',report));
    if owner
        reference=report.record; reference.path=mc.safe_path(dataset_root,reference.path);
        if ismember(report.status,{'complete','resumed'})
            gg_run_record('finish',session,'complete',reference,report);
        else
            failure=struct('identifier','mc:Incomplete','message',['Metric output status: ',report.status]);
            gg_run_record('finish',session,'failed',reference,report,failure);
        end
    end
catch err
    if ~preview
        try
            gg_run_record('event',session,struct('event','graph_failed','path',graph_path,'error_identifier',err.identifier,'reason',err.message));
            if owner, gg_run_record('finish',session,'failed',struct([]),struct('graph_path',graph_relative_path),err); end
        catch record_error
            err=addCause(err,record_error);
        end
    end
    rethrow(err);
end
end
