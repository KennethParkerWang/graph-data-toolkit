function digest = gg_io_topology_hash(N, directed, edge_list)
%GG_IO_TOPOLOGY_HASH SHA-256 of the graph-v1 labeled topology byte stream.
validateattributes(N, {'numeric'}, {'scalar','integer','>=',1,'<=',double(intmax('uint32'))});
validateattributes(directed, {'logical','numeric'}, {'scalar','binary'});
if ~isa(edge_list, 'uint32') || ~ismatrix(edge_list) || size(edge_list,2) ~= 2
    error('graphio:InvalidEdges', 'edge_list must be M-by-2 uint32.');
end
engine = java.security.MessageDigest.getInstance('SHA-256');
header = sprintf('topology-v1\n%.0f\n%d\n%.0f\n', double(N), logical(directed), size(edge_list,1));
engine.update(unicode2native(header, 'UTF-8'));
for first = 1:10000:size(edge_list,1)
    last = min(first + 9999, size(edge_list,1));
    text = sprintf('%u,%u\n', edge_list(first:last,:).');
    engine.update(unicode2native(text, 'UTF-8'));
end
bytes = typecast(engine.digest(), 'uint8');
digest = lower(reshape(dec2hex(bytes, 2).', 1, []));
end
