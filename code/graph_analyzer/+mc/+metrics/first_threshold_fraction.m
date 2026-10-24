function r = first_threshold_fraction(ctx,p)
%FIRST_THRESHOLD_FRACTION First observed crossing; never interpolate batch gaps.
if nargin<2, p=struct(); end
a=mc.param(p,'trajectory',mc.param(ctx,'trajectory',[])); metric_id=mc.param(p,'metric_id','');
threshold=mc.param(p,'threshold',NaN); relation=mc.param(p,'relation','le');
selection=metric_id; parameters=mc.param(p,'metric_parameters',[]);
if isstruct(parameters), selection=struct('metric_id',metric_id,'parameters',parameters);
elseif ~isempty(parameters), error('mc:InvalidParameter','metric_parameters must be an exact parameter struct or empty.'); end
if ~isnumeric(threshold)||~isscalar(threshold)||~isfinite(threshold)||~ismember(relation,{'le','ge'})
    error('mc:InvalidParameter','Specify a finite threshold and relation le/ge.');
end
[x,y,v,d]=mc.attack_curve(a,selection,'states');
if strcmp(relation,'le'), crossed=y<=threshold; else, crossed=y>=threshold; end
ix=find(v&crossed&isfinite(x),1);
id='first_threshold_fraction';
r=mc.make_result(id,NaN,'graph',{}, {},false,'undefined','Threshold not reached in observed states.');
r.details=struct('threshold',threshold,'relation',relation,'source_metric_id',metric_id,'reached',false,'protocol_id',a.protocol_id);
r.details.source_metric_definition=d.metric_definition;
if isempty(ix)
    if any(~v)||any(~isfinite(x)), r.status='not_computed'; r.reason='Unavailable observations prevent concluding whether the threshold was reached.'; end
    return;
end
if any(~v(1:ix))||any(~isfinite(x(1:ix)))
    r.status='not_computed'; r.reason='An earlier unavailable observation prevents identifying the first crossing.'; return;
end
r.values=x(ix); r.valid_mask=true; r.status='ok'; r.reason='';
r.details.reached=true; r.details.removed_count=d.removed_count(ix);
r.details.observed_only=true; r.details.state_index=ix;
end
