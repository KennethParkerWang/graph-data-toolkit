function sample = gg_io_make_sample(A, meta)
%GG_IO_MAKE_SAMPLE Convert a generator adjacency and metadata to graph-v1.
if ~isstruct(meta) || ~isscalar(meta)
    error('graphio:InvalidMetadata', 'meta must be a scalar struct.');
end
required = {'model','directed','parameters','implementation_sha256','source'};
for k = 1:numel(required)
    if ~isfield(meta, required{k}), error('graphio:MissingMetadata', 'Missing meta.%s.', required{k}); end
end
validateattributes(meta.directed, {'logical','numeric'}, {'scalar','binary'});
directed = logical(meta.directed);
if ~ismatrix(A) || size(A,1) < 1 || size(A,1) ~= size(A,2) || ...
        size(A,1) > double(intmax('uint32')) || ~(isnumeric(A) || islogical(A)) || ~isreal(A)
    error('graphio:InvalidAdjacency', 'Adjacency must be a nonempty real square matrix.');
end
if any(nonzeros(A) ~= 1) || any(diag(A) ~= 0) || (~directed && ~isequal(A,A.'))
    error('graphio:InvalidAdjacency', 'Adjacency must be simple, binary, and symmetric if undirected.');
end
A = sparse(logical(A));
if directed, [u,v] = find(A); else, [u,v] = find(triu(A,1)); end
edge_list = sortrows(uint32([u(:),v(:)]), [1,2]);
if ~isfield(meta, 'generator_id')
    if directed, suffix = 'directed'; else, suffix = 'undirected'; end
    meta.generator_id = [meta.model '_' suffix];
end
if ~isfield(meta, 'implementation_version')
    if ~isfield(meta,'generator_version'), error('graphio:MissingMetadata', 'Missing implementation version.'); end
    meta.implementation_version = meta.generator_version;
end
if ~isfield(meta, 'rng')
    if ~isfield(meta,'seed'), error('graphio:MissingMetadata', 'Missing RNG settings.'); end
    algorithm = 'twister';
    if isfield(meta,'rng_algorithm'), algorithm = meta.rng_algorithm; end
    validateattributes(meta.seed, {'numeric'}, {'scalar','integer','>=',0,'<=',double(intmax('uint32'))});
    meta.rng = struct('algorithm', algorithm, 'seed', uint32(meta.seed));
end
if ~isfield(meta,'created_utc')
    meta.created_utc = char(datetime('now', 'TimeZone','UTC', 'Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end
if ~isfield(meta,'matlab_version'), meta.matlab_version = version; end
origin = '';
if isfield(meta,'origin_graph_id'), origin = meta.origin_graph_id; meta = rmfield(meta,'origin_graph_id'); end
order = [];
if isfield(meta,'source_edge_order')
    order = meta.source_edge_order;
    validateattributes(order,{'numeric'},{'real','finite','integer','nonnegative'});
    meta = rmfield(meta,'source_edge_order');
    meta.source_edge_order_available = true;
else
    meta.source_edge_order_available = false;
end
aliases = {'directed','seed','rng_algorithm','generator_version','num_nodes','num_edges', ...
    'mean_degree','mean_in_degree','mean_out_degree','density','degree_convention'};
meta = rmfield(meta, intersect(fieldnames(meta), aliases));
sample = struct('schema_version','graph-v1','graph_id','', 'topology_hash','', ...
    'origin_graph_id','', 'N',uint32(size(A,1)), 'M',uint64(size(edge_list,1)), ...
    'directed',directed, 'A',A, 'edge_list',edge_list, 'meta',meta);
sample.topology_hash = gg_io_topology_hash(sample.N, directed, edge_list);
sample.meta.recipe_json = gg_io_recipe_json(meta, directed, sample.topology_hash, origin);
sample.graph_id = gg_io_sha256(sample.meta.recipe_json);
if isempty(origin), sample.origin_graph_id = sample.graph_id; else, sample.origin_graph_id = origin; end
if meta.source_edge_order_available, sample.source_edge_order = uint64(order(:)); end
gg_io_validate_sample(sample);
end
