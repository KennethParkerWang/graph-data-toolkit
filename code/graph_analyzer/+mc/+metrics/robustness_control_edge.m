function r = robustness_control_edge(ctx,p)
%ROBUSTNESS_CONTROL_EDGE Lou et al. 2021, Eq.7; lower is more robust.
if nargin<2, p=struct(); end
a=mc.param(p,'trajectory',mc.param(ctx,'trajectory',[])); driver_id=mc.param(p,'driver_metric_id',''); id='robustness_control_edge';
if ~ismember(driver_id,{'structural_driver_count','exact_numeric_driver_count'})
    error('mc:InvalidDriverMetric','Use structural_driver_count or exact_numeric_driver_count and retain its input model.');
end
r=mc.make_result(id,NaN,'graph',{}, {},false,'not_applicable','Requires a complete single-edge trajectory and a driver-count metric.');
if isempty(a)||~isstruct(a)||~isfield(a,'states'), return; end
if ~strcmp(a.protocol.target,'edge')||~a.full_single_object_trajectory, return; end
n=a.original_node_count; m=a.original_edge_count;
if n~=ctx.n||~isequal(a.original_node_ids,ctx.node_ids), error('mc:TrajectoryIdentity','Trajectory and context node identities differ.'); end
if n==0, r.status='undefined'; r.reason='Driver fraction requires N>0.'; return; end
[~,y,v,d]=mc.attack_curve(a,driver_id,'states');
if ~isequal(d.removed_count,(0:m)'), r.reason='Every integer deletion count 0:M is required.'; return; end
if ~all(v), r.status='not_computed'; r.reason='A driver-count value at Q=0:M is unavailable.'; return; end
if any(y<0|y>n|y~=fix(y)), error('mc:InvalidDriverCount','Driver counts must be integers in [0,N].'); end
r=mc.make_result(id,sum(y)/(n*(m+1)),'graph',{}, {},true,'ok','');
r.details=struct('driver_metric_id',driver_id,'sum_removed_count',[0 m], ...
    'outer_denominator',m+1,'driver_fraction_denominator',n,'raw_driver_counts',y, ...
    'normalized_curve',y/n,'protocol_id',a.protocol_id,'direction','lower_is_more_robust', ...
    'driver_definition',d.metric_definition);
end
