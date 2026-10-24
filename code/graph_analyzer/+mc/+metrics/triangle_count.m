function r=triangle_count(ctx,p)
%TRIANGLE_COUNT Number of undirected triangles counted once
if nargin<2,p=struct;end
z=mc.metrics.node_triangle_count(ctx,p);r=mc.basic_result('triangle_count',sum(z.values)/3,'graph',ctx,'');
end
