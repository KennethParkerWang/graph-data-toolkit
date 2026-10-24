function results = test_author_models()
%TEST_AUTHOR_MODELS Compare successes and failures against the author sources.
% Raw references are run only after a bounded copy terminates with the same
% seed. The copy only counts randi/randperm calls; it changes no draw or rule.
root = fileparts(fileparts(mfilename('fullpath')));
setup_generators();
old_path = path;
path_guard = onCleanup(@() path(old_path));
old_rng = rng;
rng_guard = onCleanup(@() rng(old_rng));
addpath(fullfile(root,'sources','author_lou','hg'));
addpath(fullfile(root,'sources','author_lou','enc_ver1','net'));
assert(contains(which('rt'), fullfile('author_lou','hg')));
assert(contains(which('rectify'), fullfile('author_lou','enc_ver1','net')));
reference_dir = make_bounded_references(root);
reference_guard = onCleanup(@() cleanup_references(reference_dir));
addpath(reference_dir);
author_ref_budget('reset',1);
assert_error(@() author_bounded_rt(5,7),'graphgen:ReferenceRandomBudget');
cases = {'rt',30,57; 'rt',30,45; 'rt',30,90; 'rt',3,0; ...
    'rr',29,41; 'rr',30,45; 'rr',29,65; 'rr',8,16; ...
    'rh',30,36; 'rh',31,37; 'rh',32,43; 'rh',30,60; 'rh',9,12; ...
    'eh',20,60; 'eh',6,30; 'eh',6,0; 'eh',4,4};
results = repmat(empty_row(),0,1);
for c = 1:size(cases,1)
    model = cases{c,1};
    N = cases{c,2};
    M = cases{c,3};
    generator = str2func(['gen_',model,'_directed']);
    for seed = 1:12
        state = rng;
        row = empty_row();
        row.model = model;
        row.N = N;
        row.M = M;
        row.seed = seed;
        bounded = run_reference(model,N,M,seed,true);
        if strcmp(bounded.status,'budget_exhausted')
            error('graphgen:UnverifiedReference', ...
                ['Reference budget exhausted for %s N=%d M=%d seed=%d. ', ...
                 'This is unverified, not a confirmed source failure.'],model,N,M,seed);
        end
        % A terminating bounded run makes replay of the original predictable.
        reference = run_reference(model,N,M,seed,false);
        assert(strcmp(bounded.status,reference.status), 'Reference instrumentation changed status.');
        if strcmp(reference.status,'returned')
            assert(isequal(bounded.A,reference.A), 'Reference instrumentation changed graph.');
            assert(isequal(bounded.final_rng,reference.final_rng), ...
                'Reference instrumentation changed the random stream.');
        else
            assert(strcmp(bounded.error_message,reference.error_message), ...
                'Bounded and original errors differ.');
        end
        row.reference_status = reference.status;
        row.reference_error_id = reference.error_id;
        row.reference_error_message = reference.error_message;
        row.reference_error_line = reference.error_line;
        row.reference_random_calls = bounded.random_calls;
        if strcmp(reference.status,'returned')
            row.reference_self_loops = nnz(diag(reference.A));
            row.reference_reciprocal_pairs = ...
                (nnz(reference.A & reference.A.')-row.reference_self_loops)/2;
        end
        actual_error = [];
        try
            [actual, meta] = generator(N,M,seed);
        catch exception
            actual_error = exception;
            row.error_id = exception.identifier;
            if ~startsWith(exception.identifier,'graphgen:AuthorSource')
                rethrow(exception)
            end
        end
        assert(isequal(rng,state), 'Generator/reference must restore RNG.');
        if strcmp(reference.status,'runtime_error')
            assert(~isempty(actual_error), 'Organised generator succeeded after original runtime error.');
            row.status = 'confirmed_source_runtime_error';
        elseif row.reference_self_loops > 0 || ...
                (~strcmp(model,'eh') && row.reference_reciprocal_pairs > 0)
            assert(~isempty(actual_error), 'Organised generator accepted invalid original graph.');
            if row.reference_self_loops > 0
                assert(strcmp(row.error_id,'graphgen:AuthorSourceSelfLoop'));
            else
                assert(strcmp(row.error_id,'graphgen:AuthorSourceReciprocal'));
            end
            row.status = 'confirmed_invalid_source_output';
        else
            if ~isempty(actual_error)
                error('graphgen:FalseSourceFailure', ...
                    '%s N=%d M=%d seed=%d: original succeeded, organised code raised %s.', ...
                    model,N,M,seed,row.error_id);
            end
            assert(isequal(actual,logical(sparse(reference.A))), ...
                'Mismatch: %s, N=%d, M=%d, seed=%d.',model,N,M,seed);
            assert(nnz(actual)==M && isequal(size(actual),[N,N]));
            assert(issparse(actual) && islogical(actual) && ~any(diag(actual)));
            if strcmp(model,'eh')
                assert(meta.construction.rectifications == reference.rectifications);
                in_degree = full(sum(actual,1));
                out_degree = full(sum(actual,2));
                assert(all(in_degree >= floor(M/N) & in_degree <= ceil(M/N)));
                assert(all(out_degree >= floor(M/N) & out_degree <= ceil(M/N)));
            else
                assert(nnz(actual & actual.')==0);
            end
            row.status = 'matched';
        end
        results(end+1,1) = row; %#ok<AGROW>
    end
end
for model = {'eh','rt','rr','rh'}
    names = {results.model};
    states = {results.status};
    assert(any(strcmp(names,model{1}) & strcmp(states,'matched')));
    generator = str2func(['gen_',model{1},'_undirected']);
    assert_error(@() generator(30,50,1), 'graphgen:UnsupportedDirection');
end
assert_error(@() gen_rr_directed(4,4,1), 'graphgen:AuthorSourceBoundary');
assert_error(@() gen_rh_directed(6,6,1), 'graphgen:AuthorSourceBoundary');
matched = sum(strcmp({results.status},'matched'));
failed = numel(results)-matched;
fprintf('AUTHOR_MODELS_OK: %d exact matches; %d failures verified against original source.\n',matched,failed);
for model = {'eh','rt','rr','rh'}
    subset = strcmp({results.model},model{1});
    fprintf('  %s: matched=%d verified_failure=%d\n',upper(model{1}), ...
        sum(subset & strcmp({results.status},'matched')), ...
        sum(subset & ~strcmp({results.status},'matched')));
end
% Report the first deterministic fixture for each actual failure identifier.
errors = unique({results.error_id});
for k = 1:numel(errors)
    if isempty(errors{k}), continue, end
    index = find(strcmp({results.error_id},errors{k}),1);
    row = results(index);
    fprintf('  FIXTURE %s N=%d M=%d seed=%d: %s; source=%s; source_line=%d\n', ...
        row.model,row.N,row.M,row.seed,row.error_id,row.reference_status,row.reference_error_line);
end
% Keep cleanup objects alive to the end of the test.
clear reference_guard rng_guard path_guard
end

function row = empty_row()
row = struct('model','','N',0,'M',0,'seed',0,'status','','error_id','', ...
    'reference_status','','reference_error_id','','reference_error_message','', ...
    'reference_error_line',0,'reference_self_loops',0, ...
    'reference_reciprocal_pairs',0,'reference_random_calls',0);
end

function result = run_reference(model,N,M,seed,bounded)
previous = rng;
guard = onCleanup(@() rng(previous));
rng(seed,'twister');
result = struct('status','returned','A',[],'rectifications',0,'error_id','', ...
    'error_message','','error_line',0,'random_calls',0,'final_rng',struct());
if bounded
    author_ref_budget('reset',1000000);
    prefix = 'author_bounded_';
else
    prefix = '';
end
try
    if strcmp(model,'eh')
        initial = str2func([prefix,'ern']);
        rectify_fn = str2func([prefix,'rectify']);
        A = initial(N,M);
        [result.A,result.rectifications] = rectify_fn(A,N,M);
    else
        reference = str2func([prefix,model]);
        result.A = reference(N,M);
    end
catch exception
    result.status = 'runtime_error';
    result.error_id = exception.identifier;
    result.error_message = exception.message;
    if ~isempty(exception.stack)
        result.error_line = exception.stack(1).line;
    end
    if strcmp(exception.identifier,'graphgen:ReferenceRandomBudget')
        result.status = 'budget_exhausted';
    end
end
result.final_rng = rng;
if bounded
    state = author_ref_budget('read',0);
    result.random_calls = state.calls;
end
end

function directory = make_bounded_references(root)
directory = [tempname,'_author_reference_test'];
mkdir(directory);
files = {'rt','hg';'rr','hg';'rh','hg'; ...
    'ern',fullfile('enc_ver1','net');'rectify',fullfile('enc_ver1','net')};
for index = 1:size(files,1)
    name = files{index,1};
    source = fullfile(root,'sources','author_lou',files{index,2},[name,'.m']);
    text = fileread(source);
    pattern = ['(?m)^(function[^\r\n]*=\s*)',name,'\('];
    text = regexprep(text,pattern,['$1author_bounded_',name,'('],'once');
    % MATLAB \b means backspace, not a word boundary. Use explicit lookbehind.
    random_pattern = '(?<![A-Za-z0-9_])randi\s*\(';
    permutation_pattern = '(?<![A-Za-z0-9_])randperm\s*\(';
    random_calls = numel(regexp(text,random_pattern,'match'));
    assert(random_calls > 0,'Expected source random calls for instrumentation.');
    text = regexprep(text,random_pattern,'author_ref_randi(');
    text = regexprep(text,permutation_pattern,'author_ref_randperm(');
    assert(isempty(regexp(text,random_pattern,'once')));
    assert(isempty(regexp(text,permutation_pattern,'once')));
    write_text(fullfile(directory,['author_bounded_',name,'.m']),text);
end
write_text(fullfile(directory,'author_ref_budget.m'),sprintf([ ...
    'function state = author_ref_budget(action,limit)\n' ...
    'persistent calls maximum\n' ...
    'if strcmp(action,''reset'')\n calls=0; maximum=limit;\n' ...
    'elseif strcmp(action,''tick'')\n calls=calls+1;\n' ...
    ' if calls>maximum, error(''graphgen:ReferenceRandomBudget'',''Reference random-call budget exceeded.''); end\n' ...
    'end\n state=struct(''calls'',calls,''maximum'',maximum);\nend\n']));
for name = {'randi','randperm'}
    text = sprintf(['function varargout = author_ref_%s(varargin)\n' ...
        'author_ref_budget(''tick'',0);\n' ...
        '[varargout{1:nargout}] = %s(varargin{:});\nend\n'],name{1},name{1});
    write_text(fullfile(directory,['author_ref_',name{1},'.m']),text);
end
end

function write_text(filename,text)
file = fopen(filename,'w','n','UTF-8');
assert(file >= 0,'Cannot create temporary reference file.');
guard = onCleanup(@() fclose(file));
fprintf(file,'%s',text);
end

function cleanup_references(directory)
assert(startsWith(directory,tempdir) && endsWith(directory,'_author_reference_test'));
if contains(path,directory), rmpath(directory); end
clear author_ref_budget author_ref_randi author_ref_randperm
clear author_bounded_rt author_bounded_rr author_bounded_rh author_bounded_ern author_bounded_rectify
if isfolder(directory), rmdir(directory,'s'); end
end

function assert_error(operation,identifier)
try
    operation();
catch exception
    assert(strcmp(exception.identifier,identifier), ...
        'Expected %s; got %s.',identifier,exception.identifier);
    return
end
error('graphgen:TestExpectedError','Expected error %s.',identifier);
end
