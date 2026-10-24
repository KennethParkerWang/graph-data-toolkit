function r=density(ctx,p)
%DENSITY Fraction of possible simple edges
if nargin<2,p=struct;end
v=NaN;if ctx.n>1,v=ctx.m/(ctx.n*(ctx.n-1));if ~ctx.directed,v=2*v;end,end
r=mc.basic_result('density',v,'graph',ctx,'Density requires N >= 2.');
end
