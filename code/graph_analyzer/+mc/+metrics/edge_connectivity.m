function r=edge_connectivity(ctx,p)
%EDGE_CONNECTIVITY Global edge connectivity via pairwise max-flow
if nargin<2,p=struct;end
lim=mc.param(p,'max_nodes',200);validateattributes(lim,{'numeric'},{'scalar','integer','nonnegative','finite'});if ctx.n>lim,error('mc:SizeLimit','Connectivity max-flow calculation exceeds max_nodes.');end
if ctx.n<2,r=mc.basic_result('edge_connectivity',NaN,'graph',ctx,'Connectivity requires N >= 2.');return;end
[~,s]=mc.components(ctx,'strong');if numel(s)>1,r=mc.basic_result('edge_connectivity',0,'graph',ctx,'');return;end
n=ctx.n;H=digraph(ctx.A);
val=Inf;for u=1:n
 for v=1:n
  if u==v||(~ctx.directed&&v<u),continue;end
  val=min(val,maxflow(H,u,v));
 end
end
r=mc.basic_result('edge_connectivity',val,'graph',ctx,'');
end
