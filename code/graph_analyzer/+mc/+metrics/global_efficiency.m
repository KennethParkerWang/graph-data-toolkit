function r=global_efficiency(ctx,p)
%GLOBAL_EFFICIENCY Mean reciprocal shortest path length over distinct ordered pairs
if nargin<2,p=struct;end
D=mc.distances(ctx,p);D(1:ctx.n+1:end)=Inf;v=sum(1./D,'all')/(ctx.n*(ctx.n-1));
r=mc.basic_result('global_efficiency',v,'graph',ctx,'Global efficiency requires N >= 2.');
end
