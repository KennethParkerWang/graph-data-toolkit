function report = run_task1_validation()
%RUN_TASK1_VALIDATION Run current task1 checks and persist a compact report.
% Creates only temporary test data; keeps the report in validation/.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root); setup_generators; addpath(fullfile(root,'validation'));
report = struct('implementation_version','2.0.1','graph_schema_version','graph-v1', ...
    'matlab_version',version,'implementation_sha256',gg_implementation_digest());
report.standard = test_standard_models();
report.generators = selftest_generators();
report.documented_examples = test_documented_examples();
author_rows = test_author_models();
report.author_cases = numel(author_rows);
report.author_statuses = author_rows;
report.author_saturation = test_author_saturation();
test_graph_io;
report.graph_io = 'passed';
report.batch = test_batch_generation();
report.all_models = test_batch_all_models();
report.completed_utc = char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
assert(strcmp(report.implementation_sha256,gg_implementation_digest()), ...
    'Generator sources changed while verification was running.');
gg_io_atomic_text(fullfile(root,'validation','task1_final_report.json'),[jsonencode(report,'PrettyPrint',true) newline]);
fprintf('TASK1_VALIDATION_OK: report written to validation/task1_final_report.json\n');
end
