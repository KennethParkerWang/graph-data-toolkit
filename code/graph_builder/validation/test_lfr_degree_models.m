function report = test_lfr_degree_models()
%TEST_LFR_DEGREE_MODELS Independent constraints, failures and repeatability.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root); setup_generators();
state = rng;
degree_cases = {[0;0;0],[1;2;2;1],[3;3;2;2;2;2],repmat(8,400,1)};
swaps = 0;
for i = 1:numel(degree_cases)
    degrees = degree_cases{i};
    [A,meta] = gen_degree_sequence_undirected(degrees,10000,410+i);
    B = gen_degree_sequence_undirected(degrees,10000,410+i);
    assert(isequal(A,B) && isequal(rng,state));
    assert(issparse(A) && islogical(A) && isequal(A,A.') && ~any(diag(A)));
    assert(isequal(full(sum(A,2)),degrees));
    assert(meta.successful_swaps<=meta.attempted_swaps);
    swaps = swaps+meta.successful_swaps;
end
assert(swaps>0,'Nontrivial exact-degree graphs must exercise accepted swaps.');
assert_error(@()gen_degree_sequence_undirected([3;3;1;1],10,1),'graphgen:DegreeSequenceNotGraphical');
assert_error(@()gen_degree_sequence_undirected([1;1;1],10,1),'graphgen:DegreeSequenceParity');
assert_error(@()gen_degree_sequence_undirected([3;1;0],10,1),'graphgen:DegreeSequenceRange');

% All 126 sorted five-node sequences, checked by the independent Erdos-Gallai
% inequalities rather than a second Havel-Hakimi implementation.
combinations = nchoosek(1:9,5);
for i = 1:size(combinations,1)
    degrees = (combinations(i,:)-(1:5)).';
    expected_graphical = erdos_gallai(degrees);
    try
        A = gen_degree_sequence_undirected(degrees,0,420);
        assert(expected_graphical && isequal(full(sum(A,2)),degrees));
    catch exception
        if expected_graphical, rethrow(exception); end
        assert(startsWith(exception.identifier,'graphgen:DegreeSequence'));
    end
end

% These are explicit tested seeds, not automatic success-based seed selection.
settings = {[100,2.5,1.5,.2,5,10,30,20,1000,37], ...
            [400,2.5,1.5,.2,8,20,80,50,1000,38], ...
            [100,2.5,1.5,0,5,10,30,20,1000,37], ...
            [100,2.5,1.5,1,5,10,30,20,1000,37]};
lfr = repmat(struct('N',0,'M',0,'mu_target',0,'mu_actual',0, ...
    'mean_target_degree',0,'mean_actual_degree',0,'community_count',0),numel(settings),1);
% Fixed-source NetworkX 3.5 _generate_min_degree + SciPy zeta oracle values.
expected_min_degree = [2,4,2,2];
for i = 1:numel(settings)
    args = num2cell(settings{i});
    [A,meta] = gen_lfr_undirected(args{:}); B = gen_lfr_undirected(args{:});
    assert(isequal(A,B) && isequal(rng,state));
    assert(issparse(A) && islogical(A) && isequal(A,A.') && ~any(diag(A)));
    assert(meta.parameters.min_degree==expected_min_degree(i));
    assert(all(meta.target_degrees>=meta.parameters.min_degree));
    assert(all(meta.target_degrees<=meta.parameters.max_degree));
    assert(all(meta.actual_degrees>=meta.target_degrees));
    assert(mod(sum(meta.target_degrees),2)==0);
    assert(sum(meta.community_sizes)==size(A,1));
    assert(all(meta.community_sizes>=args{6}) && all(meta.community_sizes<=args{7}));
    for c = 1:numel(meta.community_sizes)
        nodes = find(meta.community==c);
        assert(numel(nodes)==meta.community_sizes(c));
        assert(all(meta.target_internal_degrees(nodes)<numel(nodes)));
    end
    actual_degrees = full(sum(A,2)); outside_degree = zeros(size(A,1),1);
    for u = 1:size(A,1)
        outside_degree(u) = nnz(A(u,meta.community~=meta.community(u)));
    end
    assert(isequal(actual_degrees,meta.actual_degrees));
    assert(isequal(outside_degree,meta.actual_external_degrees));
    assert(abs(sum(outside_degree)/nnz(A)-meta.actual_mu_edge_fraction)<eps);
    if args{4}==0, assert(sum(outside_degree)==0); end
    if args{4}==1, assert(isequal(outside_degree,actual_degrees)); end
    lfr(i) = struct('N',size(A,1),'M',nnz(A)/2,'mu_target',args{4}, ...
        'mu_actual',meta.actual_mu_edge_fraction, ...
        'mean_target_degree',mean(meta.target_degrees), ...
        'mean_actual_degree',mean(actual_degrees),'community_count',numel(meta.community_sizes));
end
assert_error(@()gen_lfr_undirected(100,2.5,1.5,.2,5,100,100,20,1000,37), ...
    'graphgen:LFRWiringCapacity');
assert_error(@()gen_lfr_undirected(101,2.5,1.5,.2,5,10,10,20,1000,37), ...
    'graphgen:LFRCommunitySequence');
assert_invalid(@()gen_lfr_undirected(100,2.5,1.5,-.1,5,10,30,20,1000,37));
assert_invalid(@()gen_lfr_undirected(100,1,1.5,.2,5,10,30,20,1000,37));
assert_invalid(@()gen_lfr_undirected(100,2.5,1.5,.2,5,10,30,100,1000,37));
assert(isequal(rng,state),'Failures must also restore the caller RNG.');
report = struct('degree_cases',numel(degree_cases),'accepted_swaps',swaps, ...
    'erdos_gallai_sequences',size(combinations,1), ...
    'lfr_cases',lfr,'rng_restoration',true,'same_seed_repeatability',true, ...
    'explicit_failure_checks',8);
fprintf('LFR_DEGREE_MODELS_OK\n%s\n',jsonencode(report));
end

function result = erdos_gallai(degrees)
degrees = sort(degrees,'descend'); N = numel(degrees);
result = mod(sum(degrees),2)==0;
for k = 1:N
    result = result && sum(degrees(1:k)) <= k*(k-1)+sum(min(degrees(k+1:end),k));
end
end

function assert_error(call,identifier)
try
    call();
catch exception
    assert(strcmp(exception.identifier,identifier), ...
        'Unexpected failure %s (expected %s).',exception.identifier,identifier);
    return;
end
error('graphgen:ExpectedFailure','Expected error %s was not raised.',identifier);
end

function assert_invalid(call)
try
    call();
catch
    return;
end
error('graphgen:ExpectedFailure','Expected parameter failure was not raised.');
end
