function r = efficiency_retention_curve(ctx,p)
%EFFICIENCY_RETENTION_CURVE E(Q)/E(0), preserving undefined/failed observations.
if nargin<2, p=struct(); end
a=mc.param(p,'trajectory',mc.param(ctx,'trajectory',[])); metric_id=mc.param(p,'metric_id','global_efficiency');
if ~strcmp(metric_id,'global_efficiency'), error('mc:InvalidParameter','Efficiency retention requires global_efficiency.'); end
[x,y,v,d]=mc.attack_curve(a,metric_id,'states');
initial=find(d.removed_count==0,1); id='efficiency_retention_curve';
r=mc.make_result(id,NaN(size(y)),'trajectory',{'removed_count'},{d.removed_count},false(size(y)),'not_computed','Initial efficiency is missing or unavailable.');
r.details=struct('actual_fraction',x,'raw_efficiency',y,'normalization_denominator',NaN,'source_metric_id',metric_id,'protocol_id',a.protocol_id);
if isempty(initial), return; end
if ~v(initial)
    if strcmp(d.status{initial},'undefined'), r.status='undefined'; r.reason='Initial efficiency is mathematically undefined.'; end
    return;
end
if y(initial)==0, r.status='undefined'; r.reason='Initial efficiency is zero; retention normalization is undefined.'; return; end
r.values=y/y(initial); r.valid_mask=v;
r.details.normalization_denominator=y(initial);
if all(v), r.status='ok'; r.reason=''; else, r.status='partial'; r.reason='Some efficiency observations are unavailable.'; end
end
