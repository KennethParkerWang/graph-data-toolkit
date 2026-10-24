function r=radius(ctx,p)
%RADIUS radius with unreachable distances equal to Inf
if nargin<2,p=struct;end
D=mc.distances(ctx,p);mode=validatestring(mc.param(p,'direction','out'),{'out','in'});if strcmp(mode,'in'),D=D';end
if ctx.n==0,v=NaN;else,e=max(D,[],2);v=min(e);end
r=mc.make_result('radius',v,'graph',{}, {},~isnan(v));if isnan(v),r.status='undefined';r.reason='Empty graph.';end
end
