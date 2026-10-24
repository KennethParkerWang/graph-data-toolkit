function output = gg_prepare_metadata(A, meta, generator_id, implementation_sha256, source_info)
%GG_PREPARE_METADATA Attach source provenance and portable model attributes.
% generator_id is the actual public function, e.g. gen_ba_undirected.
if nargin < 4, implementation_sha256 = gg_implementation_digest(); end
if nargin < 5, source_info = gg_source_info(generator_id); end
tokens = regexp(generator_id,'^gen_(.+)_(undirected|directed)$','tokens','once');
if isempty(tokens), error('graphgen:InvalidGeneratorID','Invalid generator_id.'); end
required = {'model','directed','seed','parameters','num_nodes','num_edges','generator_version', ...
    'rng_algorithm','matlab_version'};
if ~isstruct(meta) || ~isscalar(meta) || ~all(isfield(meta,required))
    error('graphgen:InvalidMetadata','Use metadata returned by a supported generator.');
end
[~,checked] = gg_finalize(A,meta.model,meta.directed,meta.seed,meta.parameters);
if meta.num_nodes ~= checked.num_nodes || meta.num_edges ~= checked.num_edges || ...
        logical(meta.directed) ~= strcmp(tokens{2},'directed')
    error('graphgen:MetadataMismatch','Generator metadata and adjacency disagree.');
end
output = struct('model',tokens{1},'generator_id',generator_id, ...
    'directed',logical(meta.directed),'parameters',meta.parameters, ...
    'rng',struct('algorithm',meta.rng_algorithm,'seed',uint32(meta.seed)), ...
    'implementation_version',meta.generator_version, ...
    'implementation_sha256',implementation_sha256, ...
    'source',source_info,'matlab_version',meta.matlab_version);
reserved = [required, {'mean_degree','mean_in_degree','mean_out_degree', ...
    'density','degree_convention','source_edge_order'}];
extra = setdiff(fieldnames(meta),reserved);
attributes = struct();
for k = 1:numel(extra), attributes.(extra{k}) = meta.(extra{k}); end
attributes.source_model_name = meta.model;
output.attributes = attributes;
if isfield(meta,'source_edge_order'), output.source_edge_order = meta.source_edge_order; end
end
