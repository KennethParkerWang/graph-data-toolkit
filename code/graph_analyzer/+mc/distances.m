function D = distances(ctx,p)
%DISTANCES Cached exact all-pairs unweighted distances; rows are sources.
if nargin<2, p=struct; end
lim=mc.param(p,'max_nodes',5000);
validateattributes(lim,{'numeric'},{'scalar','integer','nonnegative','finite'});
if ctx.n>lim, error('mc:SizeLimit','Exact distances need N-by-N memory; N exceeds max_nodes.'); end
if isfield(ctx.cache.data,'distances'), D=ctx.cache.data.distances; return; end
if ctx.n==0, D=zeros(0); else, D=distances(ctx.G,'Method','unweighted'); end
ctx.cache.data.distances=D;
end
