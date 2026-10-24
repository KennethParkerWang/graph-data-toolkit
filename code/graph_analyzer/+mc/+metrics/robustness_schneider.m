function r = robustness_schneider(ctx,p)
%ROBUSTNESS_SCHNEIDER R=(1/N) sum_{Q=1}^N LCC(Q)/N, exact node path.
if nargin<2, p=struct(); end
a=mc.param(p,'trajectory',mc.param(ctx,'trajectory',[])); id='robustness_schneider';
r=mc.make_result(id,NaN,'graph',{}, {},false,'not_applicable','Requires a full undirected single-node removal trajectory.');
if isempty(a)||~isstruct(a)||~isfield(a,'states'), return; end
if ctx.directed||a.directed||~strcmp(a.protocol.target,'node')||~a.full_single_object_trajectory, return; end
n=a.original_node_count;
if n==0, r.status='undefined'; r.reason='N=0 makes both normalization factors undefined.'; return; end
if n~=ctx.n||~isequal(a.original_node_ids,ctx.node_ids), error('mc:TrajectoryIdentity','Trajectory and context node identities differ.'); end
[~,y,v,d]=mc.attack_curve(a,'largest_component_size','states');
if ~isequal(d.removed_count,(0:n)'), r.reason='Every integer deletion count 0:N is required.'; return; end
if ~all(v(2:end)), r.status='not_computed'; r.reason='An LCC value at Q=1:N is unavailable.'; return; end
r=mc.make_result(id,sum(y(2:end))/(n*n),'graph',{}, {},true,'ok','');
r.details=struct('sum_removed_count',[1 n],'outer_denominator',n,'lcc_denominator',n, ...
    'raw_largest_component_size',y,'normalized_curve',y/n,'protocol_id',a.protocol_id);
end
