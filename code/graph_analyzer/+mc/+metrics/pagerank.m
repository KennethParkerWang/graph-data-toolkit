function r=pagerank(ctx,p)
%PAGERANK Stationary PageRank with uniform teleportation and dangling redistribution
if nargin<2,p=struct;end
alpha=mc.param(p,'alpha',0.85);tol=mc.param(p,'tolerance',1e-12);maxit=mc.param(p,'max_iterations',10000);
validateattributes(alpha,{'numeric'},{'scalar','nonnegative','<',1,'finite'});validateattributes(tol,{'numeric'},{'scalar','positive','finite'});validateattributes(maxit,{'numeric'},{'scalar','integer','positive','finite'});
n=ctx.n;if n==0,r=mc.make_result('pagerank',[],'node',{},{},[],'undefined','Empty graph has no probability distribution.');return;end
d=full(sum(ctx.A,2));dangling=d==0;invD=zeros(n,1);invD(~dangling)=1./d(~dangling);P=spdiags(invD,0,n,n)*ctx.A;v=ones(n,1)/n;ok=false;
for k=1:maxit
 next=alpha*(P'*v+sum(v(dangling))/n)+(1-alpha)/n;delta=norm(next-v,1);v=next;
 if delta<=tol,ok=true;break;end
end
if ~ok,r=mc.make_result('pagerank',[],'node',{},{},[],'failed','Power iteration did not reach the requested tolerance.');else,r=mc.basic_result('pagerank',v/sum(v),'node',ctx);end
r.details=struct('iterations',k,'l1_delta',delta,'teleportation','uniform','dangling_redistribution','uniform');
end
