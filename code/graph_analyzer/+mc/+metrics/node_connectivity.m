function r=node_connectivity(ctx,p)
%NODE_CONNECTIVITY Global vertex connectivity via pairwise max-flow
if nargin<2,p=struct;end
lim=mc.param(p,'max_nodes',200);validateattributes(lim,{'numeric'},{'scalar','integer','nonnegative','finite'});if ctx.n>lim,error('mc:SizeLimit','Connectivity max-flow calculation exceeds max_nodes.');end
if ctx.n<2,r=mc.basic_result('node_connectivity',NaN,'graph',ctx,'Connectivity requires N >= 2.');return;end
[~,s]=mc.components(ctx,'strong');if numel(s)>1,r=mc.basic_result('node_connectivity',0,'graph',ctx,'');return;end
n=ctx.n;C=sparse(2*n,2*n);for u=1:n,C(u,n+u)=1;end;[u,v]=find(ctx.A);C=C+sparse(n+u,v,ones(numel(u),1),2*n,2*n);
val=Inf;for u=1:n
 for v=1:n
  if u==v||(~ctx.directed&&v<u),continue;end
  val=min(val,maxflow(digraph(C),n+u,v));
 end
end
r=mc.basic_result('node_connectivity',val,'graph',ctx,'');
end
