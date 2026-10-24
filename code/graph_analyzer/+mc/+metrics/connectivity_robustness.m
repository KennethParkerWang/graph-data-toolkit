function r=connectivity_robustness(ctx,p)
%CONNECTIVITY_ROBUSTNESS Full-path LCC sum for edges or directed connectivity.
% R=(1/T0) sum_{q=1}^{T0} L_mode(q)/N0. Original denominators.
% Undirected node-only case uses robustness_schneider, not a duplicate metric.
if nargin<2, p=struct(); end
a=mc.param(p,'trajectory',mc.param(ctx,'trajectory',[]));
mode=mc.param(p,'component_mode','weak'); id='connectivity_robustness';
if ~ismember(mode,{'weak','strong'}), error('mc:InvalidParameter','component_mode must be weak or strong.'); end
r=mc.make_result(id,NaN,'graph',{}, {},false,'not_applicable','Requires a full edge-removal or directed node-removal trajectory.');
if isempty(a)||~isstruct(a)||~isfield(a,'states'), return; end
if isfield(a,'input_context_identity')&&~strcmp(a.input_context_identity,mc.attack_context_identity(ctx))
    error('mc:TrajectoryIdentity','Trajectory belongs to a different original context.');
end
if ~ctx.directed&&strcmp(a.protocol.target,'node')
    r.reason='Use robustness_schneider for undirected node removal.'; return;
end
if ~ctx.directed&&strcmp(mode,'strong')
    r.reason='Undirected connectivity uses component_mode=weak; strong is a directed interpretation.'; return;
end
n=a.original_node_count; total=a.target_count;
if n==0||total==0
    r.status='undefined'; r.reason='Original node count and original target count must both be positive.'; return;
end
selection=struct('metric_id','largest_component_size','parameters',struct('component_mode',mode));
[~,y,v,d]=mc.attack_curve(a,selection,'states');
if ~a.full_single_object_trajectory||~isequal(d.removed_count,(0:total)')
    r.reason='Every removal count 0:T0 must be observed; use sampled_curve_auc for a coarse grid.'; return;
end
if ~all(v(2:end))
    r.status='not_computed'; r.reason='A selected largest-component observation at q=1:T0 is unavailable.'; return;
end
r=mc.make_result(id,sum(y(2:end))/(total*n),'graph',{}, {},true,'ok','');
interpretation='undirected edge LCC sum; supplied attack protocol';
if ctx.directed, interpretation=['project-defined directed ',mode,'-component extension']; end
r.details=struct('target',a.protocol.target,'component_mode',mode,'interpretation',interpretation, ...
    'sum_removed_count',[1 total],'outer_denominator',total,'component_denominator',n, ...
    'raw_largest_component_size',y,'normalized_curve',y/n,'source_metric_definition',d.metric_definition, ...
    'protocol_id',a.protocol_id,'includes_initial_state',false,'includes_final_state',true);
end
