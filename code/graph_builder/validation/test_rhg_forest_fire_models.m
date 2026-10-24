function report = test_rhg_forest_fire_models()
%TEST_RHG_FOREST_FIRE_MODELS 独立检查几何规则、燃烧结构及 RNG 契约。
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root); setup_generators();
original_state = rng;
guard = onCleanup(@() rng(original_state)); %#ok<NASGU>

% Invert the recorded radial CDF back to the first independently drawn uniforms.
seed = 2103; N = 256; R = 8; alpha = .75;
rng(seed,'twister'); expected_uniforms = rand(N,1); rng(original_state);
[A,meta] = gen_rhg_undirected(N,R,alpha,0,seed);
actual_uniforms = (cosh(alpha*meta.r)-1)/(cosh(alpha*R)-1);
assert(max(abs(actual_uniforms-expected_uniforms)) < 5e-14, 'RHG radial CDF inversion differs.');
assert(all(meta.r>=0 & meta.r<=R) && all(meta.angles>=0 & meta.angles<2*pi));
expected = false(N);
for source = 1:N-1
    for target = source+1:N
        cosh_distance = cosh(meta.r(source))*cosh(meta.r(target)) - ...
            sinh(meta.r(source))*sinh(meta.r(target))*cos(meta.angles(source)-meta.angles(target));
        expected(source,target) = acosh(max(1,cosh_distance)) <= R;
    end
end
assert(isequal(A,sparse(expected|expected.')), 'RHG T=0 threshold differs from hyperbolic cosine rule.');
assert(isequal(rng,original_state));
assert(nnz(gen_rhg_undirected(6,0,.75,0,31))==30, 'R=0,T=0 must collapse to a complete graph.');
[tiny,tiny_meta] = gen_rhg_undirected(30,1e-10,.75,0,32);
tiny_positions = tiny_meta.r.*[cos(tiny_meta.angles),sin(tiny_meta.angles)];
tiny_expected = false(30);
for source = 1:29
    for target = source+1:30
        tiny_expected(source,target) = norm(tiny_positions(source,:)-tiny_positions(target,:)) <= 1e-10;
    end
end
assert(isequal(tiny,sparse(tiny_expected|tiny_expected.')), 'Small RHG radii must not collapse numerically.');
subtiny = gen_rhg_undirected(30,1e-200,.75,0,32);
assert(isequal(subtiny,tiny), 'RHG topology must survive a scale below the square-underflow boundary.');
[boundary,boundary_meta] = gen_rhg_undirected(10,350,2,.4,33);
assert(all(isfinite(boundary_meta.r)) && all(boundary_meta.r<=350) && issparse(boundary));
expect_error(@() gen_rhg_undirected(5,351,1,.5,1),'graphgen:RHGNumericRange');
expect_error(@() gen_rhg_undirected(5,100,8,.5,1),'graphgen:RHGNumericRange');

% At zero burning, each new node has exactly its ambassador parent.
[tree,tree_meta] = gen_forest_fire_directed(80,0,0,40);
assert(nnz(tree)==79 && all(full(sum(tree(2:end,:),2))==1));
assert(nnz(tree(1,:))==0);
parent_indices = sub2ind(size(tree),(2:80).',tree_meta.ambassadors(2:80));
assert(all(full(tree(parent_indices))));
check_forest_structure(tree);
check_forest_structure(gen_forest_fire_directed(1,.4,.3,41));
check_forest_structure(gen_forest_fire_directed(60,0,.5,42));
expect_any_error(@() gen_forest_fire_directed(10,1,.2,1));
expect_any_error(@() gen_forest_fire_directed(10,.2,1,1));
[small_forward,small_forward_meta] = gen_forest_fire_directed(30,realmin/8,.5,43);
assert(isempty(small_forward_meta.parameters.paper_backward_ratio));
assert(small_forward_meta.parameters.paper_backward_ratio_defined && ...
    ~small_forward_meta.parameters.paper_backward_ratio_finite);
assert_finite_metadata(small_forward_meta);
% This numerical regression is independent of the separately maintained source catalog.
source_fixture = struct('citation','Leskovec, Kleinberg, Faloutsos, KDD 2005', ...
    'code_url',small_forward_meta.secondary_reference_url,'verification_scope','finite metadata serialization fixture');
implementation_sha256 = gg_io_sha256(fullfile(root,'directed','gen_forest_fire_directed.m'),'file');
small_forward_prepared = gg_prepare_metadata(small_forward,small_forward_meta, ...
    'gen_forest_fire_directed',implementation_sha256,source_fixture);
small_forward_sample = gg_io_make_sample(small_forward,small_forward_prepared);
assert(small_forward_sample.N==30 && ~isempty(small_forward_sample.graph_id));

% Accepted sparse scalar inputs must produce the same full, serializable metadata.
[sparse_rhg,sparse_rhg_meta] = gen_rhg_undirected(sparse(30),sparse(8),sparse(.75),sparse(.4),sparse(61));
[full_rhg,full_rhg_meta] = gen_rhg_undirected(30,8,.75,.4,61);
[sparse_fire,sparse_fire_meta] = gen_forest_fire_directed(sparse(30),sparse(.35),sparse(.2),sparse(62));
[full_fire,full_fire_meta] = gen_forest_fire_directed(30,.35,.2,62);
assert(isequal(sparse_rhg,full_rhg) && isequal(sparse_rhg_meta,full_rhg_meta));
assert(isequal(sparse_fire,full_fire) && isequal(sparse_fire_meta,full_fire_meta));
assert_finite_metadata(sparse_rhg_meta); assert_finite_metadata(sparse_fire_meta);
assert(~isempty(gg_io_canonical_json(sparse_rhg_meta)) && ~isempty(gg_io_canonical_json(sparse_fire_meta)));

% Representative-size samples cover both models and preserve the caller stream.
cases = {@()gen_rhg_undirected(400,12,.75,.5,51), ...
    @()gen_rhg_undirected(1,12,.75,.5,51), ...
    @()gen_forest_fire_directed(400,.35,.2,52), ...
    @()gen_forest_fire_directed(100,.6,.4,53)};
summaries = repmat(struct('model','','N',0,'M',0,'mean_degree',0), numel(cases),1);
for index = 1:numel(cases)
    [sample,sample_meta] = cases{index}(); repeated = cases{index}();
    assert(isequal(sample,repeated) && isequal(rng,original_state), 'Model seed/RNG contract differs.');
    assert(issparse(sample) && islogical(sample) && ~any(diag(sample)));
    if sample_meta.directed
        check_forest_structure(sample);
    else
        assert(isequal(sample,sample.'));
    end
    summaries(index) = struct('model',sample_meta.model,'N',sample_meta.num_nodes, ...
        'M',sample_meta.num_edges,'mean_degree',sample_meta.mean_degree);
end
report = struct('radial_cdf_max_error',max(abs(actual_uniforms-expected_uniforms)), ...
    'hard_threshold_pairs',N*(N-1)/2,'zero_burn_tree_edges',nnz(tree), ...
    'subtiny_scale_edges',nnz(subtiny)/2,'finite_forward_metadata_io',true, ...
    'sparse_scalar_metadata_json',true, ...
    'representative_samples',summaries,'rng_restored',isequal(rng,original_state));
fprintf('RHG_FOREST_FIRE_MODELS_OK: CDF error %.3g; %d hard-threshold pairs; %d representative samples.\n', ...
    report.radial_cdf_max_error,report.hard_threshold_pairs,numel(cases));
disp(summaries);
end

function assert_finite_metadata(value)
if isnumeric(value)
    assert(all(isfinite(value(:))), 'Numeric metadata must contain only finite values.');
    assert(~issparse(value), 'Numeric metadata must use full arrays for portable JSON.');
elseif isstruct(value)
    names = fieldnames(value);
    for index = 1:numel(names)
        assert_finite_metadata(value.(names{index}));
    end
end
end

function check_forest_structure(A)
[source,target] = find(A);
assert(all(source>target), 'Forest-fire edges must go from newer to older nodes.');
G = digraph(A);
assert(isdag(G), 'Forest-fire graph must be a DAG.');
assert(max(conncomp(G,'Type','weak'))==1, 'Single-ambassador forest fire must be weakly connected.');
assert(issparse(A) && islogical(A) && ~any(diag(A)));
end

function expect_error(action, identifier)
try
    action();
catch exception
    assert(strcmp(exception.identifier,identifier), 'Unexpected error identifier.');
    return
end
error('graphgen:TestMissingError','Expected error %s.',identifier);
end

function expect_any_error(action)
failed = false;
try
    action();
catch
    failed = true;
end
assert(failed,'Invalid model probability was accepted.');
end
