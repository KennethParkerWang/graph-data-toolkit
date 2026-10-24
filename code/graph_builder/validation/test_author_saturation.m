function report = test_author_saturation(require_guard)
%TEST_AUTHOR_SATURATION Reproduce nonterminating author RR/RH branches safely.
% Copies stop on entry to loops with an invariant zero-length condition.
% A draw budget bounds every reference probe; exhausting it is a test failure.
if nargin < 1, require_guard = true; end
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root); setup_generators();
cases = {'rr',5,9,75; 'rh',7,20,136};
report = repmat(struct( ...
    'model','','N',0,'M',0,'seed',0, 'reference_guard','', ...
    'generator_error','','returned_edges',0, ...
    'reference_while_condition_is_invariant',false,'passed',false), 0, 1);
for index = 1:size(cases,1)
    model = cases{index,1}; N = cases{index,2}; M = cases{index,3}; seed = cases{index,4};
    previous_path = path;
    previous_rng = rng;
    directory = [tempname(fullfile(root,'validation')) '_saturation_probe'];
    mkdir(directory);
    cleanup = onCleanup(@() clean_probe(directory, previous_path, previous_rng));
    source = fileread(fullfile(root,'sources','author_lou','hg',[model '.m']));
    loops = regexp(source, 'while ~len_neb1(?<body>[\s\S]*?)end', 'names');
    assert(numel(loops) == 2, 'Expected two documented stale-length source loops.');
    for k = 1:numel(loops)
        assert(isempty(regexp(loops(k).body, 'len_neb1\s*=', 'once')), ...
            'Reference loop now updates its condition; revisit this regression.');
    end
    source = strrep(source, ['function adj=' model '(n,m)'], ...
        'function adj=saturation_reference(n,m)');
    source = strrep(source, 'while ~len_neb1', ...
        ['if ~len_neb1, error(''graphgen:ReferenceStaleLength'', ' ...
        '''Source entered a loop with invariant zero candidate length.''); end' newline ...
        'while ~len_neb1']);
    source = regexprep(source, '(?<![A-Za-z0-9_])randi\s*\(', 'saturation_randi(');
    write_file(fullfile(directory,'saturation_reference.m'), source);
    write_file(fullfile(directory,'saturation_randi.m'), sprintf([ ...
        'function value = saturation_randi(varargin)\n' ...
        'persistent count\nif isempty(count), count=0; end\n' ...
        'count=count+1; if count>10000, error(''graphgen:ProbeBudget'', ''Unverified reference timeout.''); end\n' ...
        'value=randi(varargin{:});\nend\n']));
    addpath(directory);
    rng(seed,'twister');
    reference_error = '';
    try
        saturation_reference(N,M);
    catch exception
        reference_error = exception.identifier;
    end
    assert(strcmp(reference_error,'graphgen:ReferenceStaleLength'), ...
        'Fixture did not reach the proven infinite loop: %s.',reference_error);
    rng(previous_rng);
    actual_error = '';
    actual_M = 0;
    try
        generator = str2func(['gen_' model '_directed']);
        A = generator(N,M,seed);
        actual_M = nnz(A);
    catch exception
        actual_error = exception.identifier;
    end
    assert(isequal(rng,previous_rng),'Generator failed to restore caller RNG.');
    row = struct('model',model,'N',N,'M',M,'seed',seed, ...
        'reference_guard',reference_error,'generator_error',actual_error, ...
        'returned_edges',actual_M,'reference_while_condition_is_invariant',true, ...
        'passed',strcmp(actual_error,'graphgen:AuthorSourceStalledCandidate'));
    if require_guard
        assert(row.passed, 'Generator changed a nonterminating source branch: %s.',actual_error);
    end
    report(end+1) = row; %#ok<AGROW>
    fprintf('AUTHOR_SATURATION_PROBE: %s\n',jsonencode(row));
    clear cleanup
end
end

function write_file(filename,text)
f = fopen(filename,'w','n','UTF-8');
assert(f >= 0);
cleanup = onCleanup(@() fclose(f));
fprintf(f,'%s',text);
end

function clean_probe(directory, previous_path, previous_rng)
path(previous_path); rng(previous_rng);
clear saturation_reference saturation_randi
parent = fileparts(fileparts(mfilename('fullpath')));
expected_parent = fullfile(parent,'validation');
assert(strcmp(fileparts(directory),expected_parent) && endsWith(directory,'_saturation_probe'));
if isfolder(directory), rmdir(directory,'s'); end
end
