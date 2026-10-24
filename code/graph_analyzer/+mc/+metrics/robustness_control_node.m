function r = robustness_control_node(ctx,p)
%ROBUSTNESS_CONTROL_NODE Lou et al. 2021, Eq.6; lower is more robust.
if nargin<2, p=struct(); end
r=control_summary(ctx,p,'node','robustness_control_node');
end

function r=control_summary(ctx,p,target,id)
a=mc.param(p,'trajectory',mc.param(ctx,'trajectory',[])); driver_id=mc.param(p,'driver_metric_id','');
if ~ismember(driver_id,{'structural_driver_count','exact_numeric_driver_count'})
    error('mc:InvalidDriverMetric','Use structural_driver_count or exact_numeric_driver_count and retain its input model.');
end
r=mc.make_result(id,NaN,'graph',{}, {},false,'not_applicable','Requires a complete single-node trajectory and a driver-count metric.');
if isempty(a)||~isstruct(a)||~isfield(a,'states'), return; end
if ~strcmp(a.protocol.target,target)||a.protocol.batch_size~=1, return; end
n=a.original_node_count;
if n~=ctx.n||~isequal(a.original_node_ids,ctx.node_ids), error('mc:TrajectoryIdentity','Trajectory and context node identities differ.'); end
if n==0, r.status='undefined'; r.reason='Node control robustness requires N>0.'; return; end
[~,y,v,d]=mc.attack_curve(a,driver_id,'states');
if numel(d.removed_count)<n||~isequal(d.removed_count(1:n),(0:n-1)'), r.reason='Every integer deletion count 0:N-1 is required.'; return; end
indices=1:n; denominators=(n:-1:1)';
if ~all(v(indices)), r.status='not_computed'; r.reason='A driver-count value at Q=0:N-1 is unavailable.'; return; end
if any(y(indices)<0|y(indices)>denominators|y(indices)~=fix(y(indices)))
    error('mc:InvalidDriverCount','Driver counts must be nonnegative integers no greater than residual N.');
end
r=mc.make_result(id,mean(y(indices)./denominators),'graph',{}, {},true,'ok','');
r.details=struct('driver_metric_id',driver_id,'sum_removed_count',[0 n-1], ...
    'outer_denominator',n,'driver_fraction_denominators',denominators,'raw_driver_counts',y(indices), ...
    'normalized_curve',y(indices)./denominators,'protocol_id',a.protocol_id,'direction','lower_is_more_robust', ...
    'driver_definition',d.metric_definition);
end
