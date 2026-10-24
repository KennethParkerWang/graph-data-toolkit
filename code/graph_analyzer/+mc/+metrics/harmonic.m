function r=harmonic(ctx,p)
%HARMONIC Sum of reciprocal distances, unreachable contributes zero
if nargin<2,p=struct;end
D=mc.distances(ctx,p);direction=validatestring(mc.param(p,'direction','out'),{'out','in'});if strcmp(direction,'in'),D=D';end
D(1:ctx.n+1:end)=Inf;v=sum(1./D,2);normed=mc.param(p,'normalized',false);validateattributes(normed,{'logical'},{'scalar'});if normed,if ctx.n>1,v=v/(ctx.n-1);else,v(:)=NaN;end,end
r=mc.basic_result('harmonic',v,'node',ctx,'Normalized harmonic centrality requires N >= 2.');
end
