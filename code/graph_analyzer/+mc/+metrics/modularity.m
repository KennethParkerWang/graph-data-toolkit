function r = modularity(ctx,p)
%MODULARITY Given-partition modularity, with explicit resolution gamma.
if nargin<2, p=struct(); end
labels=mc.advanced_partition(ctx,p); gamma=mc.param(p,'resolution',1);
validateattributes(gamma,{'numeric'},{'scalar','real','finite','positive'});
q=mc.advanced_modularity_value(ctx,labels,gamma);
if ctx.m==0
    r=mc.make_result('modularity',q,'graph',{}, {},false,'undefined','The graph has no edges.');
else
    r=mc.make_result('modularity',q,'graph',{});
end
end
