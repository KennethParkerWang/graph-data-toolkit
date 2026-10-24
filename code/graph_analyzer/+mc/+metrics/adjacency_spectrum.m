function r = adjacency_spectrum(ctx,p)
%ADJACENCY_SPECTRUM Full adjacency eigenvalues, sorted real then imaginary.
if nargin<2, p=struct(); end
if mc.advanced_dense_limit(ctx,p)
    r=mc.make_result('adjacency_spectrum',[],'distribution',{}, {},[],'not_computed','N exceeds explicit max_nodes.'); return
end
lambda=mc.advanced_spectrum(ctx,'adjacency');
r=mc.make_result('adjacency_spectrum',lambda,'distribution',{'eigenvalue_index'},{(1:ctx.n).'});
r.method='numerical';
r.details=struct('ordering','ascending real part, then imaginary part','complex_values_allowed',ctx.directed);
end
