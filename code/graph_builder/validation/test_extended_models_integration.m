function report = test_extended_models_integration(report_file)
%TEST_EXTENDED_MODELS_INTEGRATION Preserve a distinct extension acceptance report.
setup_generators();
report = struct('passed',false,'generator_version','2.1.0', ...
    'matlab_version',version,'implementation_sha256',gg_implementation_digest(), ...
    'started_utc',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')));
tests = {'selftest_generators','test_lfr_degree_models', ...
    'test_dc_waxman_duplication_models','test_rhg_forest_fire_models', ...
    'test_extended_registry','test_documented_examples','test_standard_models', ...
    'test_batch_all_models','test_batch_generation','test_graph_io','test_graph_run_storage'};
for k = 1:numel(tests)
    name = tests{k}; started = tic;
    fprintf('EXTENSION_TEST_START: %s\n',name);
    try
        if strcmp(name,'test_graph_io')
            test_graph_io(); details = struct('passed',true);
        else
            details = feval(name);
        end
        report.tests.(name) = struct('passed',true,'seconds',toc(started),'details',details);
    catch failure
        report.failed_test = name;
        report.error_identifier = failure.identifier;
        report.error_message = failure.message;
        if nargin > 0, write_report(report_file,report); end
        rethrow(failure);
    end
end
report.passed = true;
report.completed_utc = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
if nargin > 0, write_report(report_file,report); end
fprintf('EXTENDED_MODELS_INTEGRATION_OK: %d test groups.\n',numel(tests));
end

function write_report(filename,report)
parent = fileparts(filename);
if ~isfolder(parent), mkdir(parent); end
file = fopen(filename,'w','n','UTF-8'); assert(file >= 0);
guard = onCleanup(@() fclose(file)); %#ok<NASGU>
fprintf(file,'%s\n',jsonencode(report));
end
