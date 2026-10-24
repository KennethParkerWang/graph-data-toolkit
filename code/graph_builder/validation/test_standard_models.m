function report = test_standard_models()
%TEST_STANDARD_MODELS Source-defined boundaries and independent diagnostics.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root); setup_generators();
fixtures = jsondecode(fileread(fullfile(root,'sources','standard','python_set_fixtures.json')));
for index = 1:numel(fixtures.cases)
    item = fixtures.cases(index);
    actual = gg_python_int_set_order(item.inserted);
    assert(isequal(actual(:),item.expected(:)), 'CPython integer-set fixture mismatch.');
end

% Fixed outputs distinguish the adopted protocols from former local variants.
for target = [3,4,1000,117440513,120000000,134217727]
    boundary = target*(target-1)/2;
    [u,v] = gg_unrank_undirected_pairs([boundary-1,boundary,boundary+1]);
    assert(isequal(u,[target-2,target-1,1]) && isequal(v,[target,target,target+1]));
end
assert_error(@() gg_python_int_set_order(single([1,2])),'graphgen:IntegerSetRange');
assert_error(@() gg_python_int_set_order([1,2;3,4]),'graphgen:IntegerSetRange');
assert_error(@() gg_python_int_set_order([1,1]),'graphgen:IntegerSetRange');
A = gen_ba_undirected(4,3,1);
expected = logical(sparse([1 1 1 2 3 4],[2 3 4 1 1 1],1,4,4));
assert(isequal(A,expected),'BA must start from the reference star.');
[A,meta] = gen_ba_undirected(30,3,2);
assert(nnz(A)/2 == 81 && strcmp(meta.parameters.initial_graph,'star_m_plus_1'));
assert(nnz(gen_hk_undirected(4,4,.5,3)) == 0,'HK N=m must keep m isolated seeds.');
assert(nnz(gen_hk_undirected(20,1,.5,3))/2 == 19);
[A,meta] = gen_hk_undirected(40,4,.5,4);
assert(nnz(A)/2 == 4*(40-4)-meta.duplicate_fallbacks);

for directed = [false true]
    if directed
        empty = gen_er_directed(6,0,1); complete = gen_er_directed(6,1,1);
        fixed = gen_er_gnm_directed(6,17,1); expected_M = 17;
    else
        empty = gen_er_undirected(6,0,1); complete = gen_er_undirected(6,1,1);
        fixed = gen_er_gnm_undirected(6,11,1); expected_M = 11;
    end
    assert(nnz(empty)==0 && isequal(complete,logical(ones(6)-eye(6))));
    assert(nnz(fixed)/(2-double(directed)) == expected_M);
end
[A,meta] = gen_sf_directed(6,30,.4,.7,10);
assert(isequal(A,logical(ones(6)-eye(6))) && meta.parameters.sigma_out==.4);
assert(nnz(gen_sf_undirected(6,15,.4,10))==30);
[A,meta] = gen_qs_directed(8,2,1,8);
expected = logical(sparse(1:7,2:8,1,8,8));
for node = 3:8, expected(node,node-2:-2:1) = true; end
assert(isequal(A,expected) && meta.snapback_candidate_count==12);
assert(nnz(gen_qs_directed(8,2,0,8))==7);

A = gen_ws_undirected(12,2,0,9); B = gen_nw_undirected(12,2,0,9);
assert(isequal(A,B) && all(full(sum(A,2))==4));
assert(nnz(gen_ws_undirected(12,2,1,9))/2 == 24);
A = gen_sbm_undirected([3,4],eye(2),2);
assert(nnz(A)==18 && nnz(A(1:3,4:7))==0);
A = gen_sbm_directed([3,4],[0,1;0,0],2);
assert(nnz(A)==12 && all(all(A(1:3,4:7))) && nnz(A(4:7,:))==0);
[A,meta] = gen_rgg_undirected(20,.3,2,6);
expected = false(20);
for i = 1:20
    for j = i+1:20
        expected(i,j) = sum((meta.positions(i,:)-meta.positions(j,:)).^2) <= .3^2;
    end
end
assert(isequal(A,sparse(expected|expected.')));
assert(nnz(gen_rgg_undirected(6,2,2,6))==30);
for d = [0 1 2 4]
    A = gen_random_regular_undirected(20,d,9);
    assert(all(full(sum(A,2))==d) && ~any(diag(A)) && isequal(A,A.'));
end
assert_error(@() gen_random_regular_undirected(5,1,9),'graphgen:RegularParity');
[A,meta] = gen_chung_lu_undirected([20;20;0],10);
assert(nnz(A)==2 && isequal(meta.parameters.expected_degree_no_loops,[1;1;0]));
assert(nnz(gen_chung_lu_undirected(zeros(5,1),10))==0);

% All adopted directions restore the caller RNG and reproduce their seed.
cases = {@()gen_er_undirected(20,.2,31), @()gen_er_directed(20,.2,31), ...
    @()gen_er_gnm_undirected(20,30,31), @()gen_er_gnm_directed(20,30,31), ...
    @()gen_ba_undirected(20,3,31), @()gen_sf_undirected(20,30,.5,31), ...
    @()gen_sf_directed(20,40,.3,.7,31), @()gen_ws_undirected(20,2,.3,31), ...
    @()gen_nw_undirected(20,2,.3,31), @()gen_qs_directed(20,2,.3,31), ...
    @()gen_sbm_undirected([10,10],[.3,.1;.1,.3],31), ...
    @()gen_sbm_directed([10,10],[.3,.1;.2,.3],31), ...
    @()gen_rgg_undirected(20,.3,2,31), @()gen_random_regular_undirected(20,3,31), ...
    @()gen_hk_undirected(20,3,.5,31), @()gen_chung_lu_undirected(ones(20,1)*3,31)};
state = rng;
for index = 1:numel(cases)
    [A,meta] = cases{index}(); B = cases{index}();
    assert(isequal(A,B) && isequal(rng,state));
    assert(issparse(A) && islogical(A) && ~any(diag(A)));
    assert(isfield(meta,'reference_id'));
end
unsupported = {'gen_ba_directed','gen_ws_directed','gen_nw_directed', ...
    'gen_rgg_directed','gen_random_regular_directed','gen_hk_directed', ...
    'gen_chung_lu_directed','gen_qs_undirected'};
for index = 1:numel(unsupported)
    handle = str2func(unsupported{index});
    assert_error(@() handle(),'graphgen:UnsupportedModelDirection');
end

% A diagnostic catches broad distribution changes, not a proof of equivalence.
reference = jsondecode(fileread(fullfile(root,'sources','standard','networkx_diagnostics.json')));
sample_count = 128;
diagnostics = repmat(struct('model','','mean',[],'reference_mean',[],'tolerance',[]),4,1);
for model_index = 1:numel(reference.cases)
    item = reference.cases(model_index); values = zeros(sample_count,4);
    for index = 1:sample_count
        seed = 3000+index;
        switch item.model
            case 'ba', A = gen_ba_undirected(30,3,seed);
            case 'nw', A = gen_nw_undirected(30,2,.4,seed);
            case 'hk', A = gen_hk_undirected(30,3,.5,seed);
            case 'random_regular', A = gen_random_regular_undirected(30,4,seed);
        end
        degrees = full(sum(A,2));
        values(index,:) = [nnz(A)/2,mean(degrees.^2),full(trace(double(A)^3))/6,degrees(1)];
    end
    actual = mean(values,1); oracle = item.mean(:).';
    tolerance = 7*sqrt(var(values,0,1)/sample_count+item.variance(:).'/item.samples)+1e-10;
    assert(all(abs(actual-oracle)<=tolerance),['Reference diagnostic differs: ',item.model]);
    diagnostics(model_index) = struct('model',item.model,'mean',actual, ...
        'reference_mean',oracle,'tolerance',tolerance);
end
report = struct('supported_interfaces',numel(cases),'unsupported_interfaces',numel(unsupported), ...
    'set_fixtures',numel(fixtures.cases),'diagnostic_samples_per_model',sample_count, ...
    'reference_samples_per_model',1024,'diagnostics',diagnostics);
fprintf('STANDARD_MODELS_OK: %d supported, %d unsupported, %d source-set fixtures.\n', ...
    report.supported_interfaces,report.unsupported_interfaces,report.set_fixtures);
end

function assert_error(action,expected)
try
    action();
catch exception
    assert(strcmp(exception.identifier,expected), ...
        ['Expected ',expected,'; got ',exception.identifier]);
    return
end
error('graphgen:TestMissingError','Expected error %s.',expected);
end
