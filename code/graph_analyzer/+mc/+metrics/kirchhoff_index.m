function r = kirchhoff_index(ctx,p)
%KIRCHHOFF_INDEX Sum of effective resistance over unordered distinct pairs.
if nargin<2, p=struct(); end
base=mc.metrics.effective_resistance(ctx,p);
if ~strcmp(base.status,'ok')
    r=mc.make_result('kirchhoff_index',[],'graph',{}, {},[],base.status,base.reason); return
end
if ctx.n==0
    r=mc.make_result('kirchhoff_index',NaN,'graph',{}, {},false,'undefined','Zero-node graph excluded from this definition.'); return
end
value=sum(base.values(triu(true(ctx.n),1)));
r=mc.make_result('kirchhoff_index',value,'graph',{}, {},true);
r.units='unit edge resistance';
r.method='numerical';
r.details=struct('pair_convention','unordered distinct pairs','disconnected_value','positive infinity');
end
