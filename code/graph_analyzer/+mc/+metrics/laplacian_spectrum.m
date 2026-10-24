function r = laplacian_spectrum(ctx,p)
%LAPLACIAN_SPECTRUM Unnormalized undirected L=D-A, ascending eigenvalues.
if nargin<2, p=struct(); end
if ctx.directed
    r=mc.make_result('laplacian_spectrum',[],'distribution',{}, {},[],'not_applicable','Undirected Laplacian definition only.'); return
end
if mc.advanced_dense_limit(ctx,p)
    r=mc.make_result('laplacian_spectrum',[],'distribution',{}, {},[],'not_computed','N exceeds explicit max_nodes.'); return
end
lambda=mc.advanced_spectrum(ctx,'laplacian');
r=mc.make_result('laplacian_spectrum',lambda,'distribution',{'eigenvalue_index'},{(1:ctx.n).'});
r.method='numerical';
r.details=struct('laplacian','unnormalized D-A','ordering','ascending');
end
