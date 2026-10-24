function [labels,sizes] = components(ctx,mode)
%COMPONENTS Cached components; weak/strong explicit for directed graphs.
if nargin<2, mode='weak'; end
mode=validatestring(mode,{'weak','strong'}); key=['components_' mode];
if isfield(ctx.cache.data,key), z=ctx.cache.data.(key); labels=z.labels;sizes=z.sizes;return;end
if ctx.n==0, labels=zeros(0,1);sizes=zeros(0,1);
elseif ctx.directed, [labels,sizes]=conncomp(ctx.G,'Type',mode);labels=labels(:);sizes=sizes(:);
else, [labels,sizes]=conncomp(ctx.G);labels=labels(:);sizes=sizes(:);end
ctx.cache.data.(key)=struct('labels',labels,'sizes',sizes);
end
