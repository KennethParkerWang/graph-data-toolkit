function r=edge_count(ctx,p)
%EDGE_COUNT Number of edges, undirected counted once
if nargin<2,p=struct;end
r=mc.basic_result('edge_count',ctx.m,'graph',ctx,'');
end
