function r=eigenvector(ctx,p)
%EIGENVECTOR Incoming Perron eigenvector with L2 norm one; unique irreducible case
if nargin<2,p=struct;end
lim=mc.param(p,'max_nodes',2000);tol=mc.param(p,'tolerance',1e-10);validateattributes(lim,{'numeric'},{'scalar','integer','nonnegative','finite'});validateattributes(tol,{'numeric'},{'scalar','positive','finite'});
if ctx.n>lim,error('mc:SizeLimit','Dense eigenvector solve exceeds max_nodes.');end
[~,sizes]=mc.components(ctx,'strong');
if ctx.n==0||numel(sizes)~=1||ctx.m==0,r=mc.make_result('eigenvector',[],'node',{},{},[],'undefined','Requires a connected undirected or strongly connected directed graph with an edge, ensuring a unique Perron vector.');return;end
[V,E]=eig(full(ctx.A'));d=diag(E);[rho,j]=max(real(d));v=real(V(:,j));if sum(v)<0,v=-v;end;v=v/norm(v);res=norm(ctx.A'*v-rho*v);
if res>tol*max(1,rho)||min(v)<-tol,error('mc:NumericalFailure','Perron eigenvector residual or sign check failed.');end
v=max(v,0);v=v/norm(v);r=mc.basic_result('eigenvector',v,'node',ctx);r.details=struct('spectral_radius',rho,'residual',res,'normalization','l2','direction','incoming');
end
