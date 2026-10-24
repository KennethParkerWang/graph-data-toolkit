function r=reachable_pair_fraction(ctx,p)
%REACHABLE_PAIR_FRACTION Proportion of distinct ordered pairs with a finite path
if nargin<2,p=struct;end
D=mc.distances(ctx,p);v=(sum(isfinite(D),'all')-ctx.n)/(ctx.n*(ctx.n-1));
r=mc.basic_result('reachable_pair_fraction',v,'graph',ctx,'Requires N >= 2; ordered distinct pairs.');
end
