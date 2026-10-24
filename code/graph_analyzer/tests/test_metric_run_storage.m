function report=test_metric_run_storage()
%TEST_RUN_STORAGE Isolated graph-v1 copies; task metadata never changes IDs.
t=tic; checks=0; root=fileparts(fileparts(mfilename('fullpath'))); code_root=fileparts(root); project=fileparts(code_root);
source=fullfile(code_root,'graph_builder','examples','schema_v1');
test_root=fullfile(project,'_local','runs','_verification',['metric_tests_',char(java.util.UUID.randomUUID())]);
base=fullfile(test_root,'dataset'); mkdir(base);
mkdir(fullfile(base,'manifests')); copyfile(fullfile(source,'manifests','graphs.jsonl'),fullfile(base,'manifests','graphs.jsonl'));
copyfile(fullfile(source,'dataset.json'),fullfile(base,'dataset.json'));
rows=mc.read_jsonl(fullfile(base,'manifests','graphs.jsonl'));
for i=1:2
    dst=mc.safe_path(base,rows(i).path); mkdir(fileparts(dst)); copyfile(mc.safe_path(source,rows(i).path),dst);
end
runs=fullfile(test_root,'jobs'); selected={'node_count','edge_count'}; before=mc.source_digest();
[~,identity]=mc.read_graph(mc.safe_path(base,rows(1).path)); plan=mc.plan_run(identity,selected,struct());
preview=compute_graph_metrics(base,rows(1).path,selected,struct('run_root',runs));
assert(preview.preview&&strcmp(preview.status,'preview')&&isempty(preview.job_directory)&&~isfolder(runs)); checks=checks+1;
batch=compute_metric_batch(base,{rows(1:2).graph_id},selected,struct('run_root',runs));
assert(all(cellfun(@(r)strcmp(r.status,'preview'),batch))&&~isfolder(runs)); checks=checks+1;
options=struct('preview',false,'writer_id','run_storage_test','run_root',runs);
result=compute_graph_metrics(base,rows(1).path,selected,options); state=job(result.job_directory);
assert(strcmp(result.run_id,plan.run_id)&&strcmp(result.metric_set_id,plan.metric_set_id)); checks=checks+1;
assert(strcmp(state.schema_version,'toolkit-run-v1')&&strcmp(state.stage,'graph_analyzer')&&strcmp(state.status,'complete')); checks=checks+1;
assert(~strcmp(state.job_id,result.run_id)&&isfile(fullfile(result.job_directory,'configs','analysis.json'))&&isfile(fullfile(result.job_directory,'logs','graph_analyzer.jsonl'))&&isfile(fullfile(result.job_directory,'reports','graph_analyzer.json'))); checks=checks+1;
assert(~isfolder(fullfile(result.job_directory,'work'))&&strcmp(state.inputs.file_sha256,rows(1).file_sha256)); checks=checks+1;
assert(strcmp(mc.file_hash(mc.safe_path(base,result.record.path)),result.record.file_sha256)); checks=checks+1;
resume=compute_graph_metrics(base,rows(1).path,selected,options);
assert(strcmp(resume.status,'resumed')&&strcmp(resume.run_id,plan.run_id)&&strcmp(resume.record.file_sha256,result.record.file_sha256)&&~strcmp(resume.job_directory,result.job_directory)); checks=checks+1;
batch=compute_metric_batch(base,{rows(1:2).graph_id},selected,options);
assert(iscell(batch)&&numel(batch)==2&&strcmp(batch{1}.job_directory,batch{2}.job_directory)); checks=checks+1;
state=job(batch{1}.job_directory); assert(strcmp(state.status,'complete')&&state.summary.graph_count==2&&state.summary.failure_count==0&&numel(state.outputs)==2); checks=checks+1;
assert(isfile(state.summary.attempt_log)&&numel(attempts(state.summary.attempt_log))==2); checks=checks+1;
% A scientific partial output is preserved in metrics, but its task fails.
limited=struct('metric_id',{'node_count','distance_matrix'},'parameters',{struct(),struct('max_nodes',0)});
partial=compute_graph_metrics(base,rows(1).path,limited,options); state=job(partial.job_directory);
assert(strcmp(partial.status,'partial')&&strcmp(state.status,'failed')&&isfile(fullfile(partial.job_directory,'failures','error.json'))); checks=checks+1;
assert(isfile(mc.safe_path(base,partial.record.path))); checks=checks+1;
% Corrupt one owned input; collect every batch failure and preserve attempt log.
dst=mc.safe_path(base,rows(2).path); fid=fopen(dst,'a'); assert(fid>=0); fwrite(fid,uint8(0)); fclose(fid);
count=numel(dir(fullfile(runs,'schema_v1_examples','*','run.json')));
must_error(@()compute_graph_metrics(base,rows(2).path,selected,options),'graphio:FileChecksumMismatch'); checks=checks+1;
jobs=dir(fullfile(runs,'schema_v1_examples','*','run.json')); assert(numel(jobs)==count+1); checks=checks+1;
states=cellfun(@(p)job(p),{jobs.folder},'UniformOutput',false);
assert(any(cellfun(@(s)strcmp(s.status,'failed'),states))); checks=checks+1;
batch=compute_metric_batch(base,{rows(1:2).graph_id},selected,options); state=job(batch{1}.job_directory);
assert(strcmp(batch{1}.status,'resumed')&&strcmp(batch{2}.status,'failed')&&strcmp(batch{1}.job_directory,batch{2}.job_directory)); checks=checks+1;
attempt_rows=attempts(state.summary.attempt_log);
assert(strcmp(state.status,'failed')&&state.summary.failure_count==1&&numel(attempt_rows)==2); checks=checks+1;
assert(strcmp(attempt_rows{1}.status,'resumed')&&strcmp(attempt_rows{2}.status,'failed')&&strcmp(attempt_rows{2}.error_identifier,'mc:Integrity')&&strcmp(attempt_rows{2}.reason,'Original graph file hash mismatch.')); checks=checks+1;
assert(strcmp(attempt_rows{1}.job_directory,attempt_rows{2}.job_directory)&&strcmp(attempt_rows{1}.job_directory,batch{1}.job_directory)); checks=checks+1;
failure=jsondecode(fileread(fullfile(batch{1}.job_directory,'failures','error.json')));
assert(contains(jsonencode(failure),'mc:Integrity')); checks=checks+1;
% Diagnostic storage failure stays an attached cause of the original error.
broken=options; broken.run_session=struct('directory',fullfile(test_root,'missing_job'),'dataset_root',char(java.io.File(base).getCanonicalPath()),'stage','graph_analyzer');
try
    compute_graph_metrics(base,rows(2).path,selected,broken);
    error('mc:Test','Expected corrupt input rejection.');
catch err
    assert(strcmp(err.identifier,'graphio:FileChecksumMismatch')&&~isempty(err.cause)&&strcmp(err.cause{1}.identifier,'graphrun:Write')); checks=checks+1;
end
assert(strcmp(before,mc.source_digest())&&strcmp(mc.file_hash(mc.safe_path(source,rows(1).path)),rows(1).file_sha256)&&strcmp(mc.file_hash(mc.safe_path(source,rows(2).path)),rows(2).file_sha256)); checks=checks+1;
report=struct('status','passed','checks',checks,'seconds',toc(t),'fixture_root',base,'task_root',runs,'source_digest',before,'scientific_run_id',plan.run_id);
mc.write_text_atomic(fullfile(test_root,'test_report.json'),jsonencode(report,'PrettyPrint',true));
end
function data=job(folder)
data=jsondecode(fileread(fullfile(folder,'run.json')));
end
function rows=attempts(filename)
% Attempt records have different fields for complete and failed graphs.
lines=regexp(strtrim(fileread(filename)),'\r?\n','split');
rows=cellfun(@jsondecode,lines,'UniformOutput',false);
end
function must_error(fn,id)
try, fn(); catch err, assert(strcmp(err.identifier,id),'Expected %s, got %s.',id,err.identifier); return; end
error('mc:Test','Expected error %s.',id);
end
