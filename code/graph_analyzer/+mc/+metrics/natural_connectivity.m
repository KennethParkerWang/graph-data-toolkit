function r = natural_connectivity(ctx,p)
%NATURAL_CONNECTIVITY log(mean(exp(lambda(A)))) for an undirected graph.
if nargin<2, p=struct(); end
if ctx.directed
    r=mc.make_result('natural_connectivity',[],'graph',{}, {},[],'not_applicable','This real-spectrum definition is undirected only.'); return
end
if ctx.n==0
    r=mc.make_result('natural_connectivity',NaN,'graph',{}, {},false,'undefined','Mean over zero eigenvalues.'); return
end
if mc.advanced_dense_limit(ctx,p)
    r=mc.make_result('natural_connectivity',[],'graph',{}, {},[],'not_computed','N exceeds explicit max_nodes.'); return
end
lambda=mc.advanced_spectrum(ctx,'adjacency'); shift=max(lambda);
value=shift+log(sum(exp(lambda-shift)))-log(ctx.n);
r=mc.make_result('natural_connectivity',value,'graph',{});
r.method='numerical';
end
