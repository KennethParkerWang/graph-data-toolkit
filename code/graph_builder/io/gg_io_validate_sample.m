function gg_io_validate_sample(sample)
%GG_IO_VALIDATE_SAMPLE Check types, edge IDs, provenance, and identity hashes.
required = {'schema_version','graph_id','topology_hash','origin_graph_id','N','M', ...
    'directed','A','edge_list','meta'};
if ~isstruct(sample) || ~isscalar(sample) || ~all(isfield(sample,required))
    error('graphio:InvalidSample', 'Missing graph-v1 fields.');
end
extra = setdiff(fieldnames(sample), [required,{'source_edge_order'}]);
if ~isempty(extra), error('graphio:InvalidSample', 'Unknown top-level field: %s.', extra{1}); end
if ~ischar(sample.schema_version) || ~strcmp(sample.schema_version,'graph-v1')
    error('graphio:InvalidSchema', 'Expected graph-v1.');
end
for name = {'graph_id','topology_hash','origin_graph_id'}
    value = sample.(name{1});
    if ~ischar(value) || ~isrow(value) || isempty(regexp(value,'^[0-9a-f]{64}$','once'))
        error('graphio:InvalidHash', '%s must be 64 lowercase hexadecimal characters.',name{1});
    end
end
if ~isa(sample.N,'uint32') || ~isscalar(sample.N) || sample.N < 1 || ...
        ~isa(sample.M,'uint64') || ~isscalar(sample.M) || ...
        ~islogical(sample.directed) || ~isscalar(sample.directed)
    error('graphio:InvalidScalar', 'N/M/directed types must be uint32/uint64/logical scalars.');
end
A = sample.A; N = double(sample.N);
if ~issparse(A) || ~islogical(A) || ~isequal(size(A),[N,N]) || any(diag(A)) || ...
        (~sample.directed && ~isequal(A,A.'))
    error('graphio:InvalidAdjacency', 'Stored adjacency violates graph-v1.');
end
if sample.directed, [u,v] = find(A); else, [u,v] = find(triu(A,1)); end
edges = sortrows(uint32([u(:),v(:)]),[1,2]);
if ~isa(sample.edge_list,'uint32') || ~isequal(sample.edge_list,edges) || sample.M ~= uint64(size(edges,1))
    error('graphio:EdgeMismatch', 'A, M and canonical edge_list disagree.');
end
meta = sample.meta;
fields = {'model','generator_id','parameters','rng','implementation_version', ...
    'implementation_sha256','source','created_utc','matlab_version','recipe_json','source_edge_order_available'};
if ~isstruct(meta) || ~isscalar(meta) || ~all(isfield(meta,fields))
    error('graphio:MissingMetadata', 'Missing graph-v1 metadata.');
end
for name = {'model','generator_id','implementation_version','created_utc','matlab_version','recipe_json'}
    if ~ischar(meta.(name{1})) || ~isrow(meta.(name{1})) || isempty(meta.(name{1}))
        error('graphio:InvalidMetadata', 'meta.%s must be a nonempty character row.',name{1});
    end
end
if ~ischar(meta.implementation_sha256) || isempty(regexp(meta.implementation_sha256,'^[0-9a-f]{64}$','once'))
    error('graphio:InvalidHash', 'Invalid implementation_sha256.');
end
if ~isstruct(meta.parameters) || ~isscalar(meta.parameters) || ~isstruct(meta.rng) || ~isscalar(meta.rng) || ...
        ~all(isfield(meta.rng,{'algorithm','seed'}))
    error('graphio:InvalidMetadata', 'parameters and rng must be scalar structs; rng needs algorithm and seed.');
end
validateattributes(meta.rng.seed,{'numeric'},{'scalar','integer','>=',0,'<=',double(intmax('uint32'))});
if ~ischar(meta.rng.algorithm) || ~isrow(meta.rng.algorithm) || isempty(meta.rng.algorithm)
    error('graphio:InvalidMetadata','rng.algorithm must be a character row.');
end
if isempty(meta.source) || (~ischar(meta.source) && ~isstruct(meta.source))
    error('graphio:InvalidMetadata','source must be a nonempty character row or struct.');
end
gg_io_canonical_json(meta);
available = isfield(sample,'source_edge_order');
if ~islogical(meta.source_edge_order_available) || ~isscalar(meta.source_edge_order_available) || ...
        meta.source_edge_order_available ~= available
    error('graphio:InvalidEdgeOrder','Source edge-order availability disagrees.');
end
if available
    order = sample.source_edge_order;
    if ~isa(order,'uint64') || ~isequal(size(order),[double(sample.M),1]) || ...
            ~isequal(sort(order),uint64((1:double(sample.M)).'))
        error('graphio:InvalidEdgeOrder','source_edge_order must be a permutation of canonical edge IDs.');
    end
end
if ~strcmp(gg_io_topology_hash(sample.N,sample.directed,sample.edge_list),sample.topology_hash)
    error('graphio:TopologyMismatch','Topology checksum mismatch.');
end
origin = '';
if ~strcmp(sample.origin_graph_id,sample.graph_id), origin = sample.origin_graph_id; end
expected = gg_io_recipe_json(meta,sample.directed,sample.topology_hash,origin);
if ~strcmp(expected,meta.recipe_json) || ~strcmp(gg_io_sha256(meta.recipe_json),sample.graph_id)
    error('graphio:IdentityMismatch','Graph identity recipe mismatch.');
end
end
