function [bridge,art] = basic_cuts(ctx)
%BASIC_CUTS Iterative Tarjan low-link search on a simple undirected graph.
if ctx.directed,error('mc:NotApplicable','Cut masks use undirected definitions.');end
if isfield(ctx.cache.data,'cuts'),q=ctx.cache.data.cuts;bridge=q.bridge;art=q.art;return;end
n=ctx.n;adj=cell(n,1);for i=1:n,adj{i}=find(ctx.A(i,:));end
el=double(ctx.edge_list);emap=sparse(el(:,1),el(:,2),(1:ctx.m)',n,n);emap=emap+emap';
bridge=false(ctx.m,1);art=false(n,1);disc=zeros(n,1);low=disc;par=disc;child=disc;cursor=ones(n,1);time=0;stack=zeros(n,1);
for root=1:n
 if disc(root)>0,continue;end
 top=1;stack(top)=root;time=time+1;disc(root)=time;low(root)=time;
 while top>0
  u=stack(top);
  if cursor(u)<=numel(adj{u})
   v=adj{u}(cursor(u));cursor(u)=cursor(u)+1;
   if disc(v)==0
    par(v)=u;child(u)=child(u)+1;time=time+1;disc(v)=time;low(v)=time;top=top+1;stack(top)=v;
   elseif v~=par(u),low(u)=min(low(u),disc(v));end
  else
   top=top-1;p=par(u);
   if p==0,art(u)=child(u)>1;
   else
    low(p)=min(low(p),low(u));
    if low(u)>disc(p),bridge(full(emap(p,u)))=true;end
    if par(p)~=0&&low(u)>=disc(p),art(p)=true;end
   end
  end
 end
end
ctx.cache.data.cuts=struct('bridge',bridge,'art',art);
end
