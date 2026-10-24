function report = test_graph_run_storage(root)
%TEST_GRAPH_RUN_STORAGE Task directories must not change graph bytes or identities.
% The optional absolute root keeps all test outputs in an isolated location.
setup_generators();
if nargin < 1, root = [tempname '_run_storage']; end
root = gg_io_absolute_path(root);
assert(~exist(root,'file'),'Test root must be a new path.'); mkdir(root);
run_root = fullfile(root,'runs');
config_file = fullfile(root,'config.json');
config = struct('schema_version',2,'dataset_id','storage_test','output_dir','dataset', ...
    'base_seed',42,'samples_per_combination',3,'resume',true,'on_error','continue', ...
    'max_graphs',10,'jobs',{{struct('model','er','direction','undirected', ...
    'parameters',struct('N',6,'p',.4))}});
write_json(config_file,config);
implementation_before = gg_implementation_digest();
preview = generate_graph_batch(config_file,'DryRun',true,'RunRoot',run_root);
assert(preview.planned == 3 && isempty(preview.job_directory));
assert(~isfolder(run_root) && ~isfolder(preview.output_dir));
assert_error(@() generate_graph_batch(config_file,'RunRoot',fullfile(preview.output_dir,'runs')),'graphrun:Root');
assert(~isfolder(preview.output_dir));

first = generate_graph_batch(config_file,'RunRoot',run_root);
assert(first.generated == 3 && first.failed == 0);
first_run = read_run(first.job_directory,'complete');
assert(~isfolder(fullfile(first.job_directory,'work')));
assert(strcmp(first_run.config_file,'configs/generation.json'));
assert(strcmp(first_run.config_file_sha256,gg_io_sha256(fullfile(first.job_directory,first_run.config_file),'file')));
assert(strcmp(first_run.inputs.path,config_file));
assert(strcmp(first_run.inputs.file_sha256,gg_io_sha256(config_file,'file')));
rows = gg_io_read_manifest(first.output_dir);
hashes = {rows.file_sha256}; ids = {rows.graph_id};
manifest_hash = gg_io_sha256(fullfile(first.output_dir,'manifests','graphs.jsonl'),'file');
descriptor_hash = gg_io_sha256(fullfile(first.output_dir,'dataset.json'),'file');
second = generate_graph_batch(config_file,'RunRoot',run_root);
read_run(second.job_directory,'complete');
assert(second.skipped == 3 && second.generated == 0);
assert(~strcmp(first.job_directory,second.job_directory));
assert(strcmp(first.config_sha256,second.config_sha256));
after = gg_io_read_manifest(first.output_dir);
assert(isequal(ids,{after.graph_id}) && isequal(hashes,{after.file_sha256}));
assert(strcmp(manifest_hash,gg_io_sha256(fullfile(first.output_dir,'manifests','graphs.jsonl'),'file')));
assert(strcmp(descriptor_hash,gg_io_sha256(fullfile(first.output_dir,'dataset.json'),'file')));

% A different scientific ID cannot claim the already committed dataset.
% This deterministic preflight failure does not depend on model availability.
config.dataset_id = 'storage_failure';
write_json(config_file,config);
assert_error(@() generate_graph_batch(config_file,'RunRoot',run_root),'graphgen:BatchConfigConflict');
failed = dir(fullfile(run_root,'storage_failure','*graph_builder*'));
assert(numel(failed) == 1);
failed_directory = fullfile(failed.folder,failed.name);
read_run(failed_directory,'failed');
assert(isfile(fullfile(failed_directory,'failures','error.json')));
problem = jsondecode(fileread(fullfile(failed_directory,'failures','error.json')));
assert(strcmp(problem.identifier,'graphgen:BatchConfigConflict'));
config.dataset_id = 'storage_stop'; config.on_error = 'stop';
write_json(config_file,config);
assert_error(@() generate_graph_batch(config_file,'RunRoot',run_root),'graphgen:BatchConfigConflict');
stopped = dir(fullfile(run_root,'storage_stop','*graph_builder*'));
assert(numel(stopped) == 1);
stopped_directory = fullfile(stopped.folder,stopped.name);
read_run(stopped_directory,'failed');
assert(isfile(fullfile(stopped_directory,'failures','error.json')));
assert(strcmp(manifest_hash,gg_io_sha256(fullfile(first.output_dir,'manifests','graphs.jsonl'),'file')));
assert(strcmp(descriptor_hash,gg_io_sha256(fullfile(first.output_dir,'dataset.json'),'file')));

% Corrupt only the first graph in this owned test dataset. Resume must reject
% its bytes, retain the error, and leave both the bytes and index untouched.
damaged = gg_io_absolute_path(fullfile(first.output_dir,first.records(1).path));
assert(startsWith(lower(damaged),[lower(root) filesep]));
file = fopen(damaged,'ab'); assert(file >= 0);
assert(fwrite(file,uint8(0),'uint8') == 1); assert(fclose(file) == 0);
damaged_hash = gg_io_sha256(damaged,'file');
config.dataset_id = 'storage_test'; config.on_error = 'continue';
write_json(config_file,config);
before_jobs = dir(fullfile(run_root,'storage_test','*graph_builder*'));
assert_error(@() generate_graph_batch(config_file,'RunRoot',run_root),'graphio:FileChecksumMismatch');
continue_directory = new_job(run_root,'storage_test',{before_jobs.name});
continued = read_run(continue_directory,'failed');
assert(continued.summary.failed == 1 && continued.summary.skipped == 2);
problem = jsondecode(fileread(fullfile(continue_directory,'failures','error.json')));
assert(strcmp(problem.identifier,'graphio:FileChecksumMismatch'));
config.on_error = 'stop'; write_json(config_file,config);
before_jobs = dir(fullfile(run_root,'storage_test','*graph_builder*'));
assert_error(@() generate_graph_batch(config_file,'RunRoot',run_root),'graphio:FileChecksumMismatch');
stop_directory = new_job(run_root,'storage_test',{before_jobs.name});
stopped_resume = read_run(stop_directory,'failed');
assert(stopped_resume.summary.failed == 1 && stopped_resume.summary.skipped == 0);
problem = jsondecode(fileread(fullfile(stop_directory,'failures','error.json')));
assert(strcmp(problem.identifier,'graphio:FileChecksumMismatch'));
assert(strcmp(damaged_hash,gg_io_sha256(damaged,'file')));
assert(strcmp(manifest_hash,gg_io_sha256(fullfile(first.output_dir,'manifests','graphs.jsonl'),'file')));
assert(strcmp(descriptor_hash,gg_io_sha256(fullfile(first.output_dir,'dataset.json'),'file')));

% Missing inputs can be recorded before the consumer rejects them.
session = gg_run_record('start',fullfile(root,'missing_dataset'),'missing_input', ...
    'graph_analyzer',struct('test',true),struct('path',fullfile(root,'missing.mat')),run_root);
value = jsondecode(fileread(fullfile(session.directory,'run.json')));
assert(~value.inputs.exists && strcmp(value.inputs.kind,'missing'));
assert(~isfolder(session.work_directory));
work = gg_run_record('work',session); assert(isfolder(work));
gg_run_record('finish',session,'failed',{},struct('failed',1), ...
    struct('identifier','test:MissingInput','message','Missing input rejected by consumer.'));
read_run(session.directory,'failed');
% Directory mapping preserves the scientific ID, including non-ASCII IDs.
for id = {'测试图集','CON','123','../bad','_private','-private',repmat('a',1,101)}
    mapped = gg_run_record('start',fullfile(root,'mapping_dataset'),id{1}, ...
        'graph_analyzer',struct('test',true),{},run_root);
    value = jsondecode(fileread(fullfile(mapped.directory,'run.json')));
    assert(strcmp(value.dataset_id,id{1}) && strcmp(mapped.dataset_id,id{1}));
    if strcmp(id{1},'123')
        expected_folder = '123';
    else
        digest = gg_io_sha256(id{1}); expected_folder = ['dataset_' digest(1:12)];
    end
    assert(strcmp(value.dataset_folder,expected_folder));
    assert(strcmp(mapped.dataset_folder,expected_folder));
    assert(startsWith(mapped.directory,[fullfile(run_root,expected_folder) filesep]));
    gg_run_record('finish',mapped,'complete',{},struct());
end
assert_error(@() gg_run_record('start',fullfile(root,'mapping_dataset'),'', ...
    'graph_builder',struct(),{},run_root),'graphrun:Name');
assert(strcmp(implementation_before,gg_implementation_digest()));
report = struct('passed',true,'root',root,'generated',3,'dry_run_writes_nothing',true, ...
    'repeat_identity_unchanged',true,'failures_preserved',true,'work_created_on_demand',true, ...
    'resume_checksum_failure_continue_and_stop',true, ...
    'dataset_ids_preserved_with_safe_folders',true, ...
    'implementation_sha256',implementation_before,'first_job_directory',first.job_directory, ...
    'second_job_directory',second.job_directory,'failed_job_directory',failed_directory, ...
    'continue_failure_job_directory',continue_directory,'stop_failure_job_directory',stop_directory, ...
    'intentionally_damaged_test_graph',damaged);
write_json(fullfile(root,'test_report.json'),report);
fprintf('RUN_STORAGE_OK: generated=3, repeated identities stable, failures retained, DryRun wrote nothing.\n');
end

function value = read_run(directory,status)
value = jsondecode(fileread(fullfile(directory,'run.json')));
assert(strcmp(value.schema_version,'toolkit-run-v1') && strcmp(value.status,status));
assert(~isempty(value.started_utc) && ~isempty(value.finished_utc));
assert(isfile(fullfile(directory,'logs',[value.stage '.jsonl'])));
assert(isfile(fullfile(directory,'reports',[value.stage '.json'])));
end

function write_json(path,value)
gg_io_atomic_text(path,[jsonencode(value,'PrettyPrint',true) newline]);
end

function directory = new_job(run_root,dataset_id,previous_names)
jobs = dir(fullfile(run_root,dataset_id,'*graph_builder*'));
names = setdiff({jobs.name},previous_names);
assert(numel(names) == 1);
directory = fullfile(run_root,dataset_id,names{1});
end

function assert_error(fun,id)
try, fun(); catch failure, assert(strcmp(failure.identifier,id),failure.message); return; end
error('test:ExpectedFailure','Expected failure: %s',id);
end
