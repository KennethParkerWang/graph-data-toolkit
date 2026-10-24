function lambda = advanced_spectrum(ctx,kind)
%ADVANCED_SPECTRUM Full eigenvalues cached for this immutable context.
key = ['advanced_spectrum_' kind];
if isfield(ctx.cache.data,key)
    lambda = ctx.cache.data.(key); return
end
switch kind
    case 'adjacency'
        M = full(ctx.A);
    case 'laplacian'
        if ctx.directed, error('mc:UndirectedRequired','Laplacian requires undirected graph.'); end
        M = full(spdiags(sum(ctx.A,2),0,ctx.n,ctx.n)-ctx.A);
    otherwise
        error('mc:InvalidParameter','Unknown eigensystem kind.');
end
if ctx.n==0
    lambda=zeros(0,1);
else
    lambda=eig(M);
    if ~ctx.directed || strcmp(kind,'laplacian')
        lambda=sort(real(lambda),'ascend');
    else
        [~,order]=sortrows([real(lambda),imag(lambda)],[1 2]); lambda=lambda(order);
    end
end
ctx.cache.data.(key)=lambda;
end
