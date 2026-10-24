function report = test_batch_generation()
%TEST_BATCH_GENERATION Verify planning, commits, resume, corruption and moves.
setup_generators();
root = [tempname '_graph_batch_v2']; mkdir(root);
old_pwd = pwd; cleanup = onCleanup(@() cleanup_owned(root,old_pwd)); %#ok<NASGU>
config_file = fullfile(root,'config.json');
config = struct('schema_version',2,'dataset_id','batch_test','output_dir','output', ...
    'base_seed',10,'samples_per_combination',2,'resume',true,'on_error','continue', ...
    'max_graphs',100,'jobs',{{ ...
    struct('model','er_gnm','direction','undirected','parameters',struct('M',20), ...
        'grid',struct('N',struct('start',8,'stop',10,'step',2))), ...
    struct('model','er','direction','directed','parameters',struct('N',8,'p',.2),'samples',1)}});
write_json(config_file,config);
cd(root);
preview = generate_graph_batch('config.json','DryRun',true);
assert(preview.planned == 5 && isequal([preview.plan.seed],10:14));
assert(~isfolder(preview.output_dir)); cd(old_pwd);
first = generate_graph_batch(config_file);
assert(first.generated == 5 && first.failed == 0);
rows = gg_io_read_manifest(first.output_dir);
assert(numel(rows) == 5 && all(startsWith({rows.path},'graphs/')));
before = {rows.file_sha256};
second = generate_graph_batch(config_file);
assert(second.skipped == 5 && second.generated == 0 && second.failed == 0);
after = gg_io_read_manifest(first.output_dir);
assert(isequal(before,{after.file_sha256}));
assert(numel(dir(fullfile(first.output_dir,'manifests','generation_runs','*.jsonl'))) == 2);
assert(isfile(fullfile(first.output_dir,'dataset.json')));
assert(isfile(fullfile(first.output_dir,'configs','generation.json')));

% Moving the dataset changes no identity or relative graph path.
moved = fullfile(root,'relocated');
assert(movefile(first.output_dir,moved));
config.output_dir = 'relocated'; write_json(config_file,config);
third = generate_graph_batch(config_file);
assert(third.skipped == 5 && strcmp(third.config_sha256,first.config_sha256));
portable = generate_graph_batch(fullfile(moved,'configs','generation.json'));
assert(portable.skipped == 5 && strcmp(portable.output_dir,third.output_dir));
invalid = config; invalid.base_seed = 11; write_json(config_file,invalid);
assert_error(@() generate_graph_batch(config_file),'graphgen:BatchConfigConflict');

% Unknown model, unsupported direction, bad grids and seed overflow reject
% at preview time and cannot create an output directory.
invalid = config; invalid.jobs{1}.model = 'system'; write_json(config_file,invalid);
assert_throws(@() generate_graph_batch(config_file,'DryRun',true));
invalid = config; invalid.jobs{1}.model = 'eh'; write_json(config_file,invalid);
assert_error(@() generate_graph_batch(config_file,'DryRun',true),'graphgen:UnsupportedModelDirection');
invalid = config; invalid.jobs{1}.grid.N = 'system(''untrusted'')'; write_json(config_file,invalid);
assert_throws(@() generate_graph_batch(config_file,'DryRun',true));
invalid = config; invalid.base_seed = 2^32-1; write_json(config_file,invalid);
assert_error(@() generate_graph_batch(config_file,'DryRun',true),'graphgen:BatchSeedOverflow');
invalid = config; invalid.max_graphs = 4; write_json(config_file,invalid);
assert_error(@() generate_graph_batch(config_file,'DryRun',true),'graphgen:BatchMaxGraphs');
invalid = config; invalid.jobs{1}.grid.N = 200000000; write_json(config_file,invalid);
assert_error(@() generate_graph_batch(config_file,'DryRun',true),'graphgen:BatchPairPrecision');

% A deliberately mismatched completed log cannot skip a different graph.
logs = dir(fullfile(moved,'manifests','generation_runs','*.jsonl'));
log_file = fullfile(logs(1).folder,logs(1).name); original_log = fileread(log_file);
tampered = strrep(original_log,'"seed":10','"seed":999');
write_text(log_file,tampered); write_json(config_file,config);
try
    rejected = generate_graph_batch(config_file);
    assert(rejected.failed >= 1);
catch failure
    assert(startsWith(failure.identifier,'graphgen:Batch'));
end
write_text(log_file,original_log);

% Committed bytes must be checked before resume, never overwritten.
damaged = fullfile(moved,rows(1).path); write_text(damaged,'corrupt');
assert_throws(@() generate_graph_batch(config_file));
assert(strcmp(fileread(damaged),'corrupt'));

% Matrix-valued parameters remain one parameter value.
config.output_dir = 'matrix_output'; config.jobs = {struct('model','sbm', ...
    'direction','directed','parameters',struct('sizes',[3,4],'P',[0,1;0,0]),'samples',1)};
write_json(config_file,config); matrix = generate_graph_batch(config_file);
assert(matrix.generated == 1 && matrix.failed == 0);
row = gg_io_read_manifest(matrix.output_dir); sample = gg_io_read_graph(fullfile(matrix.output_dir,row.path),row);
assert(sample.N == 7 && sample.M == 12 && nnz(sample.A(1:3,4:7)) == 12);

% A source-defined runtime failure is logged; the next job still runs.
config.output_dir = 'failure_output'; config.base_seed = 1;
config.jobs = {struct('model','rt','direction','directed','parameters',struct('N',3,'M',0),'samples',1), ...
    struct('model','er','direction','undirected','parameters',struct('N',4,'p',0),'samples',1)};
write_json(config_file,config); failure_run = generate_graph_batch(config_file);
assert(failure_run.failed == 1 && failure_run.generated == 1);
assert(contains(fileread(failure_run.run_log),'AuthorSource'));
config.output_dir = 'stop_output'; config.on_error = 'stop'; write_json(config_file,config);
assert_throws(@() generate_graph_batch(config_file));
stop_logs = dir(fullfile(root,'stop_output','manifests','generation_runs','*.jsonl'));
assert(numel(stop_logs) == 1 && contains(fileread(fullfile(stop_logs.folder,stop_logs.name)),'AuthorSource'));
pilot_file = fullfile(root,'pilot.json'); make_pilot_config(pilot_file,[30,50],[4,8],2,100);
pilot = generate_graph_batch(pilot_file,'DryRun',true); assert(pilot.planned == 24);
report = struct('passed',true,'primary_graphs',5,'resume_and_move',true, ...
    'byte_corruption_rejected',true,'runtime_failure_logged',true,'pilot_planned',24);
fprintf('BATCH_GENERATION_OK: graph-v1 commits, resume, move, validation, corruption and failure logs.\n');
end

function write_json(path,value), write_text(path,jsonencode(value)); end
function write_text(path,text)
f = fopen(path,'w','n','UTF-8'); assert(f >= 0); guard = onCleanup(@() fclose(f)); %#ok<NASGU>
fprintf(f,'%s',text);
end
function assert_throws(fun)
threw = false; try, fun(); catch, threw = true; end
assert(threw,'Expected rejection.');
end
function assert_error(fun,id)
threw = false; try, fun(); catch failure, assert(strcmp(failure.identifier,id),failure.message); threw = true; end
assert(threw,'Expected specific rejection.');
end
function cleanup_owned(root,old_pwd)
cd(old_pwd);
target = char(java.io.File(root).getCanonicalPath());
parent = char(java.io.File(tempdir).getCanonicalPath());
assert(startsWith(lower(target),[lower(parent) filesep]) && endsWith(target,'_graph_batch_v2'));
if isfolder(target), rmdir(target,'s'); end
end
