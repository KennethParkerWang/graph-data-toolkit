function r=transitivity(ctx,p)
%TRANSITIVITY Fraction of connected triples closed into undirected triangles
if nargin<2,p=struct;end
q=mc.metrics.node_triangle_count(ctx,p);k=mc.basic_degree(ctx,'total');v=2*sum(q.values)/sum(k.*(k-1));
r=mc.basic_result('transitivity',v,'graph',ctx,'No connected triples: transitivity is undefined.');
end
