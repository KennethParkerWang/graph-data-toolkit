function r=core_number(ctx,p)
%CORE_NUMBER Largest k-core containing each node; directed uses total degree
if nargin<2,p=struct;end
d=mc.basic_degree(ctx,'total');live=true(ctx.n,1);v=zeros(ctx.n,1);floorK=0;
for z=1:ctx.n
 candidates=d;candidates(~live)=Inf;[k,u]=min(candidates);floorK=max(floorK,k);v(u)=floorK;live(u)=false;
 if ctx.directed,inc=full(ctx.A(u,:)+ctx.A(:,u)')';else,inc=full(ctx.A(u,:))';end
 d(live)=d(live)-inc(live);
end
r=mc.basic_result('core_number',v,'node',ctx,'');
end
