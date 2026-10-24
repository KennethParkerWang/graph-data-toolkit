function r = algebraic_connectivity(ctx,p)
%ALGEBRAIC_CONNECTIVITY Second eigenvalue of undirected unnormalized L.
if nargin<2, p=struct(); end
if ctx.directed
    r=mc.make_result('algebraic_connectivity',[],'graph',{}, {},[],'not_applicable','Undirected graphs only.'); return
end
if ctx.n<2
    r=mc.make_result('algebraic_connectivity',NaN,'graph',{}, {},false,'undefined','At least two eigenvalues are required.'); return
end
if mc.advanced_dense_limit(ctx,p)
    r=mc.make_result('algebraic_connectivity',[],'graph',{}, {},[],'not_computed','N exceeds explicit max_nodes.'); return
end
if max(conncomp(ctx.G))>1
    value=0;
else
    lambda=mc.advanced_spectrum(ctx,'laplacian'); value=max(0,lambda(2));
end
r=mc.make_result('algebraic_connectivity',value,'graph',{});
r.method='numerical';
end
