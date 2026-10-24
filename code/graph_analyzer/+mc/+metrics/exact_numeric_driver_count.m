function r = exact_numeric_driver_count(ctx,p)
%EXACT_NUMERIC_DRIVER_COUNT Numerical PBH maximum geometric multiplicity.
% Explicit real state_matrix; unrestricted real B. Not a dedicated-node result.
if nargin<2, p=struct(); end
if ~isfield(p,'state_matrix'), error('mc:MissingParameter','state_matrix must be explicitly supplied.'); end
S=p.state_matrix;
if ~(isnumeric(S) && isreal(S) && isequal(size(S),[ctx.n ctx.n]) && all(isfinite(S(:))))
    error('mc:InvalidParameter','state_matrix must be a finite real N-by-N matrix.');
end
rank_tol=mc.param(p,'rank_tolerance',1e-9); eigen_tol=mc.param(p,'eigenvalue_tolerance',1e-7);
validateattributes(rank_tol,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(eigen_tol,{'numeric'},{'scalar','real','finite','positive'});
if mc.advanced_dense_limit(ctx,p)
    r=mc.make_result('exact_numeric_driver_count',[],'graph',{}, {},[],'not_computed','N exceeds explicit max_nodes.'); return
end
n=ctx.n; S=full(double(S)); scale=max(1,norm(S,2)); threshold=rank_tol*scale;
if n==0
    r=mc.make_result('exact_numeric_driver_count',0,'graph',{});
    r.method='numerical';
    r.details=struct('driver_ratio',NaN,'input_model','unrestricted real B'); return
end
lambda=eig(S); [~,order]=sortrows([real(lambda),imag(lambda)],[1 2]); lambda=lambda(order);
assigned=false(n,1); representatives=zeros(n,1); multiplicities=zeros(n,1); sizes=zeros(n,1); groups=0;
% Complete-link grouping: every member remains within eigen_tol*scale.
for i=1:n
    if assigned(i), continue; end
    members=i; assigned(i)=true;
    for j=i+1:n
        if ~assigned(j) && all(abs(lambda(j)-lambda(members))<=eigen_tol*scale)
            members(end+1)=j; assigned(j)=true; %#ok<AGROW>
        end
    end
    groups=groups+1; representative=mean(lambda(members));
    singular=svd(S-representative*eye(n));
    representatives(groups)=representative; multiplicities(groups)=n-sum(singular>threshold); sizes(groups)=numel(members);
end
representatives=representatives(1:groups); multiplicities=multiplicities(1:groups); sizes=sizes(1:groups);
if any(multiplicities<1 | multiplicities>sizes)
    r=mc.make_result('exact_numeric_driver_count',NaN,'graph',{}, {},false,'not_computed',...
        'Eigenvalue clustering and rank tolerances are inconsistent; inspect spectrum or adjust explicit tolerances.');
else
    r=mc.make_result('exact_numeric_driver_count',max(multiplicities),'graph',{});
end
r.details=struct('input_model','minimum independent inputs with unrestricted real B',...
    'system','xdot=state_matrix*x+B*u; rows/columns follow ctx.node_ids',...
    'eigenvalue_representatives',representatives,'geometric_multiplicities',multiplicities,...
    'eigenvalue_cluster_sizes',sizes,'eigenvalues',lambda,'matrix_scale',scale,...
    'absolute_rank_threshold',threshold,'absolute_eigenvalue_threshold',eigen_tol*scale,...
    'driver_ratio',r.values/n,'numerical_caveat','Near-defective or near-repeated eigenvalues are tolerance-sensitive; no symbolic certificate.');
r.method='numerical';
end
