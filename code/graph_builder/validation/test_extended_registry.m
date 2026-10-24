function report = test_extended_registry()
%TEST_EXTENDED_REGISTRY Independent dispatch, sparse-input and source checks.
% No graph files or datasets are created. Requires all seven source entries.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root); setup_generators();
state = rng;
implementation = gg_implementation_digest();
examples = generator_examples();
names = {'lfr','degree_sequence','dc_sbm','waxman', ...
    'duplication_divergence','rhg','forest_fire'};
parameter_names = {{'N','tau1','tau2','mu','average_degree','min_community', ...
        'max_community','max_degree','max_iters'}, ...
    {'degrees','swap_attempts'},{'sizes','theta','omega'}, ...
    {'N','alpha','beta'},{'N','p','max_attempts'},{'N','R','alpha','T'}, ...
    {'N','p_forward','p_backward'}};
directions = repmat({'undirected'},size(names)); directions{end} = 'directed';
topology_checks = 0; source_checks = 0; sparse_checks = 0;
for i = 1:numel(names)
    id = ['gen_' names{i} '_' directions{i}];
    row = find(cellfun(@(handle)strcmp(func2str(handle),id),examples(:,1)));
    assert(isscalar(row),'Every new interface needs exactly one published example.');
    full_args = examples{row,2};
    parameters = struct();
    for k = 1:numel(parameter_names{i})
        parameters.(parameter_names{i}{k}) = full_args{k};
    end
    [function_name,args,normalized] = gg_batch_registry(names{i},directions{i},parameters);
    assert(strcmp(function_name,id));
    [A,meta] = examples{row,1}(full_args{:});
    [B,batch_meta] = feval(function_name,args{:},full_args{end});
    assert(isequal(A,B) && isequal(meta.parameters,batch_meta.parameters));
    assert(contains(gg_batch_source(names{i},directions{i}),[directions{i} ':']));
    gg_io_canonical_json(normalized);
    prepared = gg_prepare_metadata(A,meta,id,implementation);
    sample = gg_io_make_sample(A,prepared);
    gg_io_canonical_json(sample.meta);
    assert(strcmp(meta.reference_id,sample.meta.attributes.reference_id));
    assert(strcmp(sample.meta.source.generator_id,id));
    assert(numel(sample.meta.source.reference_files)==numel(sample.meta.source.reference_sha256));
    assert(~isempty(sample.meta.source.reference_files));
    assert(all(cellfun(@(hash)numel(hash)==64,sample.meta.source.reference_sha256)));
    source_checks = source_checks+1;

    % MATLAB numeric inputs may be sparse even when scalar. A public generator
    % must normalize them so its valid graph can be serialized as graph-v1.
    sparse_args = cellfun(@sparse,full_args,'UniformOutput',false);
    [C,sparse_meta] = examples{row,1}(sparse_args{:});
    assert(isequal(A,C) && isequal(meta.parameters,sparse_meta.parameters));
    sparse_prepared = gg_prepare_metadata(C,sparse_meta,id,implementation);
    sparse_sample = gg_io_make_sample(C,sparse_prepared);
    assert(strcmp(sample.graph_id,sparse_sample.graph_id));
    assert(strcmp(gg_io_scientific_hash(sample),gg_io_scientific_hash(sparse_sample)));
    gg_io_canonical_json(sparse_sample.meta);
    sparse_parameters = struct();
    for k = 1:numel(parameter_names{i})
        sparse_parameters.(parameter_names{i}{k}) = sparse_args{k};
    end
    [~,sparse_batch_args,sparse_normalized] = ...
        gg_batch_registry(names{i},directions{i},sparse_parameters);
    gg_io_canonical_json(sparse_normalized);
    D = feval(id,sparse_batch_args{:},full_args{end});
    assert(isequal(A,D));
    sparse_checks = sparse_checks+1;
    topology_checks = topology_checks+3;

    reverse = 'directed';
    if strcmp(directions{i},'directed'), reverse = 'undirected'; end
    expect_error(@()gg_batch_registry(names{i},reverse,struct()), ...
        'graphgen:UnsupportedModelDirection');
end

% The public DC-SBM tolerance and exact upper bound must match batch preflight.
parameters = struct('sizes',2,'theta',[.5;.5+5e-13],'omega',4);
[id,args] = gg_batch_registry('dc_sbm','undirected',parameters);
[A,meta] = feval(id,args{:},51); gg_io_canonical_json(meta);
assert(size(A,1)==2);
expect_any_error(@()gg_batch_registry('dc_sbm','undirected', ...
    struct('sizes',1,'theta',1+eps,'omega',4)));
expect_any_error(@()gen_dc_sbm_undirected(1,1+eps,4,51));

% A missing duplication budget uses the exact public default; no hidden seed.
[~,args,normalized] = gg_batch_registry('duplication_divergence','undirected',struct('N',5,'p',.4));
assert(args{3}==10000 && normalized.max_attempts==10000);
[A,meta] = gen_duplication_divergence_undirected(5,.4,[],71);
B = gen_duplication_divergence_undirected(args{:},71);
assert(isequal(A,B) && meta.parameters.max_attempts==10000);

% Matrix/vector grids require separate jobs rather than silently scalarizing.
vector_names = {'sizes','P','w','wout','win','degrees','theta','omega'};
config = struct('schema_version',2,'dataset_id','vector_grid_audit', ...
    'output_dir','output','base_seed',1,'max_graphs',10);
temporary = [tempname '.json'];
cleanup = onCleanup(@()delete_if_exists(temporary)); %#ok<NASGU>
for i = 1:numel(vector_names)
    grid = struct(); grid.(vector_names{i}) = [1,2];
    config.jobs = {struct('model','er','direction','undirected', ...
        'parameters',struct('N',5,'p',.2),'grid',grid)};
    f = fopen(temporary,'w','n','UTF-8'); assert(f>=0);
    fprintf(f,'%s',jsonencode(config)); fclose(f);
    expect_error(@()gg_batch_plan(temporary),'graphgen:BatchVectorGrid');
end
assert(isequal(rng,state),'All registry and failure checks must preserve caller RNG.');
report = struct('interfaces',numel(names),'topology_matches',topology_checks, ...
    'source_and_canonical_checks',source_checks,'sparse_full_graph_identity_checks',sparse_checks, ...
    'opposite_direction_rejections',numel(names),'vector_grid_rejections',numel(vector_names), ...
    'dc_tolerance_match',true,'duplication_default_match',true,'rng_restored',true);
fprintf('EXTENDED_REGISTRY_OK\n%s\n',jsonencode(report));
end

function expect_error(action,identifier)
try
    action();
catch exception
    assert(strcmp(exception.identifier,identifier),'Unexpected error %s.',exception.identifier);
    return;
end
error('graphgen:ExpectedFailure','Expected error %s.',identifier);
end

function expect_any_error(action)
try
    action();
catch
    return;
end
error('graphgen:ExpectedFailure','Invalid input unexpectedly passed.');
end

function delete_if_exists(path)
if isfile(path), delete(path); end
end
