function r=katz(ctx,p)
%KATZ Incoming Katz centrality with explicitly supplied attenuation
if nargin<2,p=struct;end
alpha=mc.param(p,'alpha',NaN);beta=mc.param(p,'beta',1);lim=mc.param(p,'max_nodes',2000);tol=mc.param(p,'tolerance',1e-10);
validateattributes(alpha,{'numeric'},{'scalar','nonnegative','finite'});validateattributes(beta,{'numeric'},{'scalar','positive','finite'});validateattributes(lim,{'numeric'},{'scalar','integer','nonnegative','finite'});validateattributes(tol,{'numeric'},{'scalar','positive','finite'});
if ctx.n>lim,error('mc:SizeLimit','Katz spectral check exceeds max_nodes.');end
if ctx.n==0,r=mc.make_result('katz',[],'node',{},{},[],'undefined','Empty graph.');return;end
rho=max(abs(eig(full(ctx.A))));if alpha*rho>=1,error('mc:InvalidParameters','Katz requires alpha*rho(A) < 1.');end
B=speye(ctx.n)-alpha*ctx.A';b=beta*ones(ctx.n,1);v=B\b;res=norm(B*v-b)/max(1,norm(b));if ~all(isfinite(v))||res>tol,error('mc:NumericalFailure','Katz residual test failed.');end
normed=mc.param(p,'normalized',true);validateattributes(normed,{'logical'},{'scalar'});if normed,v=v/norm(v);end
r=mc.basic_result('katz',v,'node',ctx);r.details=struct('spectral_radius',rho,'relative_residual',res,'direction','incoming');
end
