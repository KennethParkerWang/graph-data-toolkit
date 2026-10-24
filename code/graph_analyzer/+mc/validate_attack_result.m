function validate_attack_result(a,definitions,seeds)
%VALIDATE_ATTACK_RESULT Validate nested trajectory completeness and original IDs.
required={'protocol','protocol_id','states','sampled','deleted_ids','original_node_count','original_edge_count','original_node_ids','original_edge_ids','target_count','full_single_object_trajectory','attack_seed','repeat_index','randomness'};
if ~isstruct(a)||~isscalar(a)||~all(isfield(a,required))||isempty(a.states), error('mc:Schema','Missing attack states or metadata.'); end
if ~strcmp(a.protocol_id,mc.identity(a.protocol,'protocol-v1'))||~isequal(a.attack_seed,seeds.attack_seed)||a.repeat_index~=seeds.repeat_index||~strcmp(a.randomness.algorithm,seeds.randomness)
    error('mc:Schema','Attack identity/random settings mismatch.');
end
p=a.protocol; n=a.original_node_count; m=a.original_edge_count;
if numel(a.original_node_ids)~=n||numel(unique(a.original_node_ids))~=n||numel(a.original_edge_ids)~=m||numel(unique(a.original_edge_ids))~=m
    error('mc:Schema','Original attack IDs do not match counts.');
end
if strcmp(p.target,'node'), total=n; ids=a.original_node_ids; else, total=m; ids=a.original_edge_ids; end
if a.target_count~=total||numel(unique(a.deleted_ids))~=numel(a.deleted_ids)||any(~ismember(a.deleted_ids,ids)), error('mc:Schema','Attack target/deletion IDs mismatch.'); end
if ~isfield(p,'version')||~ismember(p.version,{'1.0.0','1.1.0'}), error('mc:Schema','Unsupported attack protocol version.'); end
[expected,schedule]=mc.attack_schedule(p,total); limit=expected(end);
full=p.batch_size==1&&limit==total;
if strcmp(p.version,'1.1.0')
    full=isequal(expected,(0:total)');
    if ~isfield(a,'schedule')||~isequaln(a.schedule,schedule)||~strcmp(a.schema_version,'attack-1.1.0')
        error('mc:Schema','Fraction-grid schedule metadata differs from configured boundaries.');
    end
elseif strcmp(p.deletion_mode,'fraction_grid')
    error('mc:Schema','Fraction grid is not defined in protocol 1.0.0.');
end
if ~isequal([a.states.removed_count]',expected)||numel(a.deleted_ids)~=limit||a.full_single_object_trajectory~=full
    error('mc:Schema','Attack states do not cover configured deletion boundaries.');
end
original_edges=a.states(1).remaining_edge_endpoints_original;
if ~isequal(size(original_edges),[m,2])||any(~ismember(original_edges(:),a.original_node_ids)), error('mc:Schema','Invalid original edge endpoints in trajectory.'); end
for i=1:numel(a.states)
    s=a.states(i); removed=double(a.deleted_ids(1:s.removed_count));
    nodes=a.original_node_ids; edges=a.original_edge_ids;
    if strcmp(p.target,'node')
        nodes=nodes(~ismember(nodes,removed)); keep=all(~ismember(original_edges,removed),2);
    else, keep=~ismember(edges,removed);
    end
    nodes=nodes(:); edges=edges(keep); edges=edges(:);
    if ~isequal(s.remaining_node_ids,nodes)||~isequal(s.remaining_edge_ids,edges)||~isequal(s.remaining_edge_endpoints_original,original_edges(keep,:))||s.node_count~=numel(nodes)||s.edge_count~=numel(edges)
        error('mc:Schema','Residual original-ID mapping inconsistent at step %d.',i);
    end
    if i==1, start=1; else, start=a.states(i-1).removed_count+1; end
    if ~isequal(double(s.removed_ids(:)),double(a.deleted_ids(start:s.removed_count)))||s.round_index~=i-1, error('mc:Schema','Per-step deletion IDs mismatch.'); end
    removed_nodes=nodes([]); removed_edges=edges([]);
    if i>1
        previous=a.states(i-1);
        removed_edges=previous.remaining_edge_ids(~ismember(previous.remaining_edge_ids,edges));
        if strcmp(p.target,'node'), removed_nodes=a.deleted_ids(start:s.removed_count); end
    end
    if ~isequal(double(s.removed_node_ids(:)),double(removed_nodes(:)))||~isequal(double(s.removed_edge_ids(:)),double(removed_edges(:))), error('mc:Schema','Per-step removed node/edge mapping mismatch.'); end
    fraction=NaN; if total>0, fraction=s.removed_count/total; end
    if ~isequaln(s.removed_fraction,fraction)||s.fraction_valid~=(total>0), error('mc:Schema','Attack fraction mismatch.'); end
    if numel(s.metrics)~=numel(definitions), error('mc:Schema','Trajectory metric count mismatch.'); end
    for j=1:numel(s.metrics)
        r=s.metrics(j); d=definitions(j);
        if ~strcmp(r.metric_id,d.metric_id)||~strcmp(r.metric_version,d.metric_version)||~strcmp(mc.canonical_json(r.parameters),mc.canonical_json(d.parameters))
            error('mc:Schema','Trajectory metric definition mismatch.');
        end
        if ~isempty(r.values)&&ismember(r.scope,{'node','edge'})
            axis=nodes; if strcmp(r.scope,'edge'), axis=edges; end
            if isempty(r.axis_ids)||~isequal(r.axis_ids{1},axis), error('mc:Schema','Metric object axis differs from residual IDs.'); end
        end
    end
end
if numel(a.sampled)~=numel(p.sample_fractions), error('mc:Schema','Sample count differs from requested fractions.'); end
for i=1:numel(a.sampled)
    s=a.sampled(i); count=round_count(p.sample_fractions(i),total,p.rounding);
    if s.requested_fraction~=p.sample_fractions(i)||s.requested_removed_count~=count, error('mc:Schema','Requested sample fields mismatch.'); end
    switch p.sample_policy
        case 'exact', ix=find(expected==count,1);
        case 'previous', ix=find(expected<=count,1,'last');
        case 'next', ix=find(expected>=count,1);
    end
    if isempty(ix)
        if s.state_index~=0||~strcmp(s.status,'not_computed')||~isempty(s.metrics), error('mc:Schema','Unobserved sample incorrectly marked available.'); end
    elseif s.state_index~=ix||s.actual_removed_count~=a.states(ix).removed_count||~isequaln(s.actual_removed_fraction,a.states(ix).removed_fraction)||s.fraction_valid~=a.states(ix).fraction_valid||s.exact_count_match~=(expected(ix)==count)||~isequaln(s.metrics,a.states(ix).metrics)
        error('mc:Schema','Sample differs from its observed trajectory state.');
    end
end
end
function value=round_count(f,n,mode)
switch mode, case 'floor', value=floor(f*n); case 'ceil', value=ceil(f*n); case 'nearest', value=round(f*n); end
value=max(0,min(n,value));
end
