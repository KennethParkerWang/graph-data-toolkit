function r = sampled_curve_auc(ctx,p)
%SAMPLED_CURVE_AUC Trapezoidal integral on actual observed removal fractions.
if nargin<2, p=struct(); end
a=mc.param(p,'trajectory',mc.param(ctx,'trajectory',[])); metric_id=mc.param(p,'metric_id','');
source=mc.param(p,'source','sampled'); interval=mc.param(p,'interval',[0 1]);
normalize=mc.param(p,'normalize_initial',false); id='sampled_curve_auc';
selection=metric_id; parameters=mc.param(p,'metric_parameters',[]);
if isstruct(parameters), selection=struct('metric_id',metric_id,'parameters',parameters);
elseif ~isempty(parameters), error('mc:InvalidParameter','metric_parameters must be an exact parameter struct or empty.'); end
if ~(islogical(normalize)||isnumeric(normalize))||~isscalar(normalize)||~ismember(normalize,[0 1])
    error('mc:InvalidParameter','normalize_initial must be a logical scalar.');
end
if ~isnumeric(interval)||numel(interval)~=2||any(~isfinite(interval))||interval(1)<0||interval(2)>1||interval(1)>=interval(2)
    error('mc:InvalidParameter','interval must contain increasing endpoints in [0,1].');
end
[x,y,v,d]=mc.attack_curve(a,selection,source);
r=mc.make_result(id,NaN,'graph',{}, {},false,'not_computed','Interval endpoints must be observed and all selected values valid.');
if strcmp(source,'sampled')
    requested=[a.sampled.requested_fraction]';
    if any(requested>=interval(1)&requested<=interval(2)&(~isfinite(x)|~v)), return; end
end
selected=x>=interval(1)&x<=interval(2); x=x(selected); y=y(selected); v=v(selected);
if isempty(x)||any(~v), return; end
[x,order]=sort(x); y=y(order); v=v(order);
[unique_x,first]=unique(x,'stable');
for k=1:numel(first)
    repeats=find(x==unique_x(k));
    if any(y(repeats)~=y(first(k)))||any(v(repeats)~=v(first(k)))
        error('mc:InconsistentSamples','Repeated sample positions must represent the same state.');
    end
end
x=unique_x; y=y(first); v=v(first);
if numel(x)<2||x(1)~=interval(1)||x(end)~=interval(2)||~all(v), return; end
denominator=1;
if normalize
    [initial_x,initial_y,initial_v]=mc.attack_curve(a,selection,'states');
    ix=find(initial_x==0,1);
    if isempty(ix)||~initial_v(ix), return; end
    denominator=initial_y(ix);
    if denominator==0, r.status='undefined'; r.reason='Initial metric is zero; retention normalization is undefined.'; return; end
end
r=mc.make_result(id,trapz(x,y/denominator),'graph',{}, {},true,'ok','');
r.details=struct('source',source,'source_metric_id',metric_id,'actual_fraction',x,'raw_values',y, ...
    'normalization_denominator',denominator,'interval',interval,'quadrature','trapezoidal', ...
    'source_observation_count',numel(d.removed_count),'unique_integration_count',numel(x),'protocol_id',a.protocol_id);
r.details.source_metric_definition=d.metric_definition;
end
