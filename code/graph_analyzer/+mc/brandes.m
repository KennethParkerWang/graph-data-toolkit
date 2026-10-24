function [node,edge] = brandes(ctx)
%BRANDES Exact unweighted Brandes dependency accumulation (2001).
% Floating path counts are checked for overflow, never silently saturated.
if isfield(ctx.cache.data,'brandes'),q=ctx.cache.data.brandes;node=q.node;edge=q.edge;return;end
n=ctx.n;node=zeros(n,1);edge=zeros(ctx.m,1);neigh=cell(n,1);
for v=1:n,neigh{v}=find(ctx.A(v,:));end
el=double(ctx.edge_list);emap=sparse(el(:,1),el(:,2),(1:ctx.m)',n,n);
if ~ctx.directed,emap=emap+emap';end
for s=1:n
 pred=cell(n,1);sigma=zeros(n,1);sigma(s)=1;d=-ones(n,1);d(s)=0;
 queue=zeros(n,1);queue(1)=s;head=1;tail=1;
 while head<=tail
  v=queue(head);head=head+1;
  for w=neigh{v}
   if d(w)<0,tail=tail+1;queue(tail)=w;d(w)=d(v)+1;end
   if d(w)==d(v)+1,sigma(w)=sigma(w)+sigma(v);pred{w}(end+1)=v;end
  end
 end
 if any(~isfinite(sigma)),error('mc:NumericalOverflow','Shortest-path multiplicities overflowed double.');end
 delta=zeros(n,1);
 for j=tail:-1:1
  w=queue(j);
  for v=pred{w}
   contribution=sigma(v)/sigma(w)*(1+delta(w));
   delta(v)=delta(v)+contribution;idx=full(emap(v,w));edge(idx)=edge(idx)+contribution;
  end
  if w~=s,node(w)=node(w)+delta(w);end
 end
end
if ~ctx.directed,node=node/2;edge=edge/2;end
ctx.cache.data.brandes=struct('node',node,'edge',edge);
end
