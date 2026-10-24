function digest = gg_io_scientific_hash(sample)
%GG_IO_SCIENTIFIC_HASH Compare same-ID records without timestamps or encoding.
% The caller validates sample first. Unknown custom metadata is scientific.
meta = sample.meta;
non_scientific = {'created_utc','matlab_version','elapsed_seconds','duration_seconds', ...
    'generation_elapsed_seconds','recipe_json'};
meta = rmfield(meta,intersect(fieldnames(meta),non_scientific));
value = struct('schema_version',sample.schema_version,'graph_id',sample.graph_id, ...
    'origin_graph_id',sample.origin_graph_id,'topology_hash',sample.topology_hash, ...
    'N',sample.N,'M',sample.M,'directed',sample.directed,'meta',meta);
if isfield(sample,'source_edge_order'), value.source_edge_order = sample.source_edge_order; end
digest = gg_io_sha256(gg_io_canonical_json(value));
end
