function r=hits(ctx,p)
%HITS HITS hub and authority scores from uniform initialization
if nargin<2,p=struct;end
tol=mc.param(p,'tolerance',1e-12);maxit=mc.param(p,'max_iterations',10000);validateattributes(tol,{'numeric'},{'scalar','positive','finite'});validateattributes(maxit,{'numeric'},{'scalar','integer','positive','finite'});
if ctx.n==0||ctx.m==0,r=mc.make_result('hits',[],'matrix',{},{},[],'undefined','No edges: HITS direction is not defined.');return;end
h=ones(ctx.n,1)/sqrt(ctx.n);ok=false;
for k=1:maxit
 a=ctx.A'*h;a=a/norm(a);next=ctx.A*a;next=next/norm(next);delta=norm(next-h,1);h=next;
 if delta<=tol,ok=true;break;end
end
a=ctx.A'*h;a=a/sum(a);h=h/sum(h);
if ~ok,r=mc.make_result('hits',[],'matrix',{},{},[],'failed','HITS did not converge within max_iterations.');else,r=mc.make_result('hits',[h,a],'matrix',{'node','score'},{ctx.node_ids,{'hub','authority'}});end
r.details=struct('iterations',k,'l1_delta',delta,'initialization','uniform positive','degenerate_eigenspace','projection of uniform start, not a uniqueness claim');
end
