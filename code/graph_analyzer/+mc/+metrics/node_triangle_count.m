function r=node_triangle_count(ctx,p)
%NODE_TRIANGLE_COUNT Number of undirected triangles incident to each node
if nargin<2,p=struct;end
if ctx.directed,error('mc:NotApplicable','Undirected triangles only.');end
v=zeros(ctx.n,1);for u=1:ctx.n,nb=find(ctx.A(u,:));v(u)=nnz(ctx.A(nb,nb))/2;end
r=mc.basic_result('node_triangle_count',v,'node',ctx,'');
end
