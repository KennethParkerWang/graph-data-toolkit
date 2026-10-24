function r=distance_matrix(ctx,p)
%DISTANCE_MATRIX All-pairs shortest directed or undirected distance
if nargin<2,p=struct;end
D=mc.distances(ctx,p);r=mc.make_result('distance_matrix',D,'matrix',{'source_node','target_node'},{ctx.node_ids,ctx.node_ids},true(size(D)),'ok','Inf denotes unreachable pairs.');r.units='edges';
end
