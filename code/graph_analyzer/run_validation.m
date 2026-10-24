function report = run_validation()
%RUN_VALIDATION Small validation only; does not touch production datasets.
root=setup_metrics(); addpath(fullfile(root,'tests')); output=fullfile(root,'validation');
if ~isfolder(output), mkdir(output); end
names={'test_basic','test_advanced','test_attacks','test_io','test_fraction_grid','test_connectivity_extensions','test_repeat_statistics','test_graph_adapter'}; suites=cell(numel(names),1); t=tic;
for i=1:numel(names)
    fprintf('Validation suite %d/%d: %s\n',i,numel(names),names{i});
    try
        suites{i}=feval(names{i}); suites{i}.suite=names{i}; suites{i}.passed=true;
    catch err
        suites{i}=struct('suite',names{i},'passed',false,'identifier',err.identifier,'message',err.message,'stack',{err.stack});
        fprintf(2,'%s failed: %s\n',names{i},err.message);
    end
end
report=struct('created_utc',char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
    'matlab_version',version,'elapsed_seconds',toc(t),'suites',{suites},'passed',all(cellfun(@(s)s.passed,suites)));
mc.write_text_atomic(fullfile(output,'validation_report.json'),jsonencode(report,'PrettyPrint',true),true);
save(fullfile(output,'validation_report.mat'),'report','-v7'); disp(report);
assert(report.passed,'mc:ValidationFailed','One or more small-graph suites failed.');
end
