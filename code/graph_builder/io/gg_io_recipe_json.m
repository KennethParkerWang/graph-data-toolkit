function text = gg_io_recipe_json(meta, directed, topology_hash, origin_graph_id)
%GG_IO_RECIPE_JSON Build the identity recipe; paths and run time are excluded.
recipe = struct('schema_version', 'graph-v1', 'model', meta.model, ...
    'generator_id', meta.generator_id, 'directed', logical(directed), ...
    'parameters', meta.parameters, 'rng', meta.rng, ...
    'implementation_version', meta.implementation_version, ...
    'implementation_sha256', meta.implementation_sha256, ...
    'topology_hash', topology_hash);
if nargin > 3 && ~isempty(origin_graph_id)
    if ~isfield(meta, 'transformation')
        error('graphio:MissingTransformation', 'Derived graphs require meta.transformation.');
    end
    recipe.origin_graph_id = origin_graph_id;
    recipe.transformation = meta.transformation;
end
text = gg_io_canonical_json(recipe);
end
