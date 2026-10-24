function report = test_dc_waxman_duplication_models()
%TEST_DC_WAXMAN_DUPLICATION_MODELS Source-defined laws, boundaries and RNG.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root); setup_generators();
state = rng;

% DC-SBM is a Poisson-presence projection, not min(1,lambda) or fixed degrees.
[A, meta] = gen_dc_sbm_undirected([3,2], [0;.25;.75;.6;.4], zeros(2), 51);
assert(nnz(A)==0 && size(A,1)==5 && all(meta.parameters.expected_degree_simple_no_loops==0));
A = gen_dc_sbm_undirected([3,2], [0;.25;.75;.6;.4], ones(2)*1e6, 51);
assert(nnz(A)==12 && nnz(A(1,:))==0, 'Zero theta must preserve its isolate.');
assert_error(@()gen_dc_sbm_undirected([2,2], [.5;.4;.5;.5], eye(2), 51), ...
    'graphgen:DCSBMThetaNormalization');
assert_error(@()gen_dc_sbm_undirected([2,2], ones(4,1)/2, [1,2;3,1], 51), ...
    'graphgen:DCSBMSymmetry');
[~, meta] = gen_dc_sbm_undirected(2, [.5;.5], 4e-20, 51);
assert(all(meta.parameters.expected_degree_simple_no_loops>0), ...
    'Tiny intensities must not disappear through cancellation.');
[~, meta] = gen_dc_sbm_undirected([3,2], [0;.25;.75;.6;.4], [9,2;2,5], 51);
P = zeros(5);
for i = 1:5
    for j = i+1:5
        lambda = meta.parameters.theta(i)*meta.parameters.theta(j)* ...
            meta.parameters.omega(meta.community(i),meta.community(j));
        P(i,j) = -expm1(-lambda); P(j,i) = P(i,j);
    end
end
assert(max(abs(sum(P,2)-meta.parameters.expected_degree_simple_no_loops))<1e-14);
samples = 512; observed = zeros(samples,1);
for index = 1:samples
    observed(index) = nnz(gen_dc_sbm_undirected(2, [.5;.5], 4, 5000+index))/2;
end
probability = 1-exp(-1);
assert(abs(mean(observed)-probability) <= 7*sqrt(probability*(1-probability)/samples), ...
    'DC-SBM must use the Poisson presence probability.');
[A, meta] = gen_dc_sbm_undirected(1, 1, 5, 51);
assert(nnz(A)==0 && meta.parameters.expected_degree_simple_no_loops==0);

% An independent all-pair distance matrix checks Waxman-1 and actual L.
[A, meta] = gen_waxman_undirected(24, .37, .81, 52);
X = meta.positions;
D = hypot(X(:,1)-X(:,1).', X(:,2)-X(:,2).');
assert(abs(meta.parameters.L-max(D(:)))<1e-14);
rng(52, 'twister'); expected_positions = rand(24,2);
uniforms = rand(24*23/2,1); rng(state);
assert(isequal(expected_positions,X));
expected = false(24); pair = 0;
for i = 1:23
    for j = i+1:24
        pair = pair+1;
        expected(i,j) = uniforms(pair) < .81*exp(-D(i,j)/(.37*max(D(:))));
    end
end
assert(isequal(A,sparse(expected|expected.')), 'Waxman must use actual pair distances.');
assert(nnz(gen_waxman_undirected(30,.2,0,52))==0);
[A, meta] = gen_waxman_undirected(1,.2,1,52);
assert(nnz(A)==0 && meta.parameters.L==0 && isequal(size(meta.positions),[1,2]));

% With p=1 the source rule grows a complete bipartite graph of duplicated twins.
[A, meta] = gen_duplication_divergence_undirected(50,1,[],53);
part = false(50,1); part(2) = true;
for node = 3:50
    parent = meta.duplication_parent(node);
    assert(parent<node && ~A(node,parent));
    part(node) = part(parent);
end
assert(isequal(A,sparse(xor(part,part.'))) && meta.duplication_attempts==48);
[A, meta] = gen_duplication_divergence_undirected(80,.55,[],53);
assert(is_connected(A) && meta.duplication_attempts>=78 && ...
    meta.rejected_duplications==meta.duplication_attempts-78);
A = gen_duplication_divergence_undirected(2,.01,0,53);
assert(nnz(A)==2);
assert_error(@()gen_duplication_divergence_undirected(3,0,[],53), ...
    'graphgen:DuplicationProbability');
assert_error(@()gen_duplication_divergence_undirected(10,.2,1,53), ...
    'graphgen:DuplicationAttemptLimit');
assert(isequal(rng,state), 'Failed generations must restore the caller RNG.');

% Numeric sparse scalar inputs must have the same graph and portable metadata.
[plain, plain_meta] = gen_waxman_undirected(30,.3,.8,55);
[from_sparse, sparse_meta] = gen_waxman_undirected(sparse(30),sparse(.3),sparse(.8),sparse(55));
assert(isequal(plain,from_sparse) && isequal(plain_meta.parameters,sparse_meta.parameters));
assert(~issparse(sparse_meta.seed) && ~issparse(sparse_meta.parameters.alpha));
prepared = gg_prepare_metadata(from_sparse,sparse_meta,'gen_waxman_undirected');
gg_io_make_sample(from_sparse,prepared);
[plain, plain_meta] = gen_duplication_divergence_undirected(30,.55,10000,56);
[from_sparse, sparse_meta] = gen_duplication_divergence_undirected( ...
    sparse(30),sparse(.55),sparse(10000),sparse(56));
assert(isequal(plain,from_sparse) && isequal(plain_meta.parameters,sparse_meta.parameters));
assert(~issparse(sparse_meta.seed) && ~issparse(sparse_meta.parameters.max_attempts));
prepared = gg_prepare_metadata(from_sparse,sparse_meta,'gen_duplication_divergence_undirected');
gg_io_make_sample(from_sparse,prepared);
assert(isequal(rng,state));

% Reproduction and a representative N=400 graph for every added generator.
calls = {@()gen_dc_sbm_undirected([200,200],ones(400,1)/200,[1800,200;200,1800],61), ...
    @()gen_waxman_undirected(400,.3,.08,62), ...
    @()gen_duplication_divergence_undirected(400,.55,[],63)};
models = {'DC-SBM','Waxman','Duplication-Divergence'};
results = repmat(struct('model','','N',0,'M',0,'mean_degree',0,'seconds',0),3,1);
for index = 1:numel(calls)
    start = tic; [A, meta] = calls{index}(); elapsed = toc(start);
    [B, repeat_meta] = calls{index}();
    assert(isequal(A,B) && isequal(meta.parameters,repeat_meta.parameters) && isequal(rng,state));
    assert(issparse(A) && islogical(A) && isequal(A,A.') && ~any(diag(A)));
    assert(size(A,1)==400 && ~meta.directed && isfield(meta,'reference_id'));
    results(index) = struct('model',models{index},'N',400,'M',meta.num_edges, ...
        'mean_degree',meta.mean_degree,'seconds',elapsed);
end
report = struct('models',{models},'dc_probability_samples',samples, ...
    'dc_observed_probability',mean(observed),'dc_expected_probability',probability, ...
    'sparse_parameter_roundtrips',2,'representative_results',results);
fprintf('DC_WAXMAN_DUPLICATION_OK: 3 models, semantic boundaries, RNG and N=400 reproducibility.\n');
end

function connected = is_connected(A)
seen = false(size(A,1),1); seen(1) = true;
frontier = 1;
while ~isempty(frontier)
    neighbors = find(any(A(frontier,:),1)).';
    frontier = neighbors(~seen(neighbors));
    seen(frontier) = true;
end
connected = all(seen);
end

function assert_error(action, expected)
try
    action();
catch exception
    assert(strcmp(exception.identifier,expected), ...
        ['Expected ',expected,'; got ',exception.identifier]);
    return
end
error('graphgen:TestMissingError','Expected error %s.',expected);
end
