function r = adjacency_spectral_radius(ctx,p)
%ADJACENCY_SPECTRAL_RADIUS Maximum modulus of all adjacency eigenvalues.
if nargin<2, p=struct(); end
if mc.advanced_dense_limit(ctx,p)
    r=mc.make_result('adjacency_spectral_radius',[],'graph',{}, {},[],'not_computed','N exceeds explicit max_nodes.'); return
end
if ctx.n==0
    r=mc.make_result('adjacency_spectral_radius',NaN,'graph',{}, {},false,'undefined','No eigenvalues for a zero-node graph.'); return
end
lambda=mc.advanced_spectrum(ctx,'adjacency');
r=mc.make_result('adjacency_spectral_radius',max(abs(lambda)),'graph',{});
r.method='numerical';
end
