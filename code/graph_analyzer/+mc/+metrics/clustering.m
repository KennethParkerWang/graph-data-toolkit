function r=clustering(ctx,p)
%CLUSTERING Local clustering; directed uses Fagiolo all-triangle definition
if nargin<2,p=struct;end
if ctx.directed
 S=ctx.A+ctx.A';k=mc.basic_degree(ctx,'total');rec=full(sum(ctx.A.*ctx.A',2));den=2*(k.*(k-1)-2*rec);num=zeros(ctx.n,1);
 for u=1:ctx.n,nb=find(S(u,:));num(u)=full(S(u,nb)*S(nb,nb)*S(nb,u));end
else
 q=mc.metrics.node_triangle_count(ctx,p);num=2*q.values;k=mc.basic_degree(ctx,'total');den=k.*(k-1);
end
v=zeros(ctx.n,1);ix=den>0;v(ix)=num(ix)./den(ix);
r=mc.basic_result('clustering',v,'node',ctx,'');
end
