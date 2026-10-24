function r=local_efficiency(ctx,p)
%LOCAL_EFFICIENCY Global efficiency of each induced open-neighborhood subgraph
if nargin<2,p=struct;end
if ctx.directed,error('mc:NotApplicable','Local efficiency is defined here only for undirected neighborhoods.');end
v=zeros(ctx.n,1);for u=1:ctx.n
 ix=find(ctx.A(u,:));k=numel(ix);if k<2,continue;end
 c=mc.context(ctx.A(ix,ix),false);D=mc.distances(c,p);D(1:k+1:end)=Inf;v(u)=sum(1./D,'all')/(k*(k-1));
end
r=mc.basic_result('local_efficiency',v,'node',ctx,'');
end
