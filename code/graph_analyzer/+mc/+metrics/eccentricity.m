function r=eccentricity(ctx,p)
%ECCENTRICITY eccentricity with unreachable distances equal to Inf
if nargin<2,p=struct;end
D=mc.distances(ctx,p);mode=validatestring(mc.param(p,'direction','out'),{'out','in'});if strcmp(mode,'in'),D=D';end
v=max(D,[],2);r=mc.make_result('eccentricity',v,'node',{'node'},{ctx.node_ids},true(size(v)),'ok','Inf denotes an unreachable target.');
end
