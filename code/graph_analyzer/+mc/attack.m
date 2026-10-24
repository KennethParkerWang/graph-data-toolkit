function a = attack(ctx,protocol,selections,seed,repeat_index)
%ATTACK Run one attack repeat with original-ID deletion and residual mappings.
% Recompute interval counts deletion rounds, so one batch has one ranking.
% Samples reference observed states only; batch gaps never become full paths.
if nargin<4, seed=[]; end
if nargin<5, repeat_index=1; end
t0=tic;
require_state_update_policy(selections);
if isstruct(protocol)&&isscalar(protocol)&&isfield(protocol,'rank_metric')
    require_state_update_policy(protocol.rank_metric);
end
p=mc.validate_protocol(protocol);
selections=mc.validate_selection(selections);
stochastic=strcmp(p.strategy,'random')||(strcmp(p.strategy,'ranked')&&strcmp(p.tie_break,'random'));
if stochastic && isempty(seed), error('mc:MissingSeed','Random attacks/ties require an explicit seed.'); end
if ~isempty(seed) && (~isnumeric(seed)||~isscalar(seed)||~isfinite(seed)||seed<0||seed>double(intmax('uint32'))||seed~=fix(seed))
    error('mc:InvalidSeed','Seed must be an integer in [0,2^32-1].');
end
if ~isnumeric(repeat_index)||~isscalar(repeat_index)||~isfinite(repeat_index)||repeat_index<1||repeat_index~=fix(repeat_index)
    error('mc:InvalidRepeat','repeat_index must be a positive integer.');
end
if stochastic, stream=RandStream('mt19937ar','Seed',double(seed)); else, stream=[]; end
if strcmp(p.target,'node'), ids=ctx.node_ids; total=ctx.n; else, ids=ctx.edge_ids; total=ctx.m; end
source=[];
if strcmp(p.strategy,'source_order')||strcmp(p.tie_break,'source_order')
    if ~isfield(ctx,'source_edge_order_ids') || numel(ctx.source_edge_order_ids)~=ctx.m || ~isequal(sort(double(ctx.source_edge_order_ids(:))),sort(double(ctx.edge_ids(:))))
        error('mc:MissingSourceOrder','A verified source_edge_order_ids permutation is required; canonical edge order is not a substitute.');
    end
    source=ctx.source_edge_order_ids(:);
end
[boundaries,schedule]=mc.attack_schedule(p,total);
limit=boundaries(end);
if strcmp(p.strategy,'external')
    if any(~ismember(p.external_sequence,double(ids))) || numel(p.external_sequence)<limit
        error('mc:InvalidSequence','External sequence must supply existing original IDs through the requested stop count.');
    end
    queue=cast(p.external_sequence,'like',ids);
elseif strcmp(p.strategy,'random')
    queue=ids(randperm(stream,total));
elseif strcmp(p.strategy,'source_order')
    queue=source;
else
    queue=rank_ids(ctx,p,stream,source);
end
remaining_nodes=true(ctx.n,1); remaining_edges=true(ctx.m,1);
states=cell(numel(boundaries),1);
states{1}=observe(ctx,0,0,cast(zeros(0,1),'like',ids), ...
    cast(zeros(0,1),'like',ctx.node_ids),cast(zeros(0,1),'like',ctx.edge_ids),selections,total);
deleted=cast(zeros(0,1),'like',ids); count=0; round_index=0; state_index=1;
ranking_at_counts=[];
if strcmp(p.strategy,'ranked'), ranking_at_counts=0; end
while count<limit
    if strcmp(p.strategy,'ranked') && strcmp(p.ranking,'adaptive') && round_index>0 && mod(round_index,p.recompute_interval)==0
        current=residual(ctx,remaining_nodes,remaining_edges);
        queue=rank_ids(current,p,stream,source);
        ranking_at_counts(end+1,1)=count; %#ok<AGROW>
    end
    batch_n=boundaries(state_index+1)-count;
    chosen=queue(1:batch_n); queue(1:batch_n)=[];
    previous_edges=remaining_edges;
    if strcmp(p.target,'node')
        remaining_nodes(ismember(ctx.node_ids,chosen))=false;
        remaining_edges=remaining_edges & remaining_nodes(ctx.edge_list(:,1)) & remaining_nodes(ctx.edge_list(:,2));
        removed_nodes=chosen;
    else
        remaining_edges(ismember(ctx.edge_ids,chosen))=false;
        removed_nodes=cast(zeros(0,1),'like',ctx.node_ids);
    end
    removed_edges=ctx.edge_ids(previous_edges & ~remaining_edges);
    deleted=[deleted;chosen(:)]; %#ok<AGROW>
    count=count+batch_n; round_index=round_index+1; state_index=state_index+1;
    current=residual(ctx,remaining_nodes,remaining_edges);
    states{state_index}=observe(current,count,round_index,chosen,removed_nodes,removed_edges,selections,total);
end
states=vertcat(states{1:state_index});
sampled=sample_states(states,p,total);
a=struct('schema_version','attack-1.0.0','implementation_version','1.0.0', ...
    'input_context_identity',mc.attack_context_identity(ctx), ...
    'protocol_id',mc.protocol_id(p),'protocol',p,'attack_seed',seed,'repeat_index',repeat_index, ...
    'randomness',struct('used',stochastic,'algorithm','none','seed',seed), ...
    'original_node_count',ctx.n,'original_edge_count',ctx.m,'directed',ctx.directed, ...
    'original_node_ids',ctx.node_ids,'original_edge_ids',ctx.edge_ids, ...
    'target_count',total,'deleted_ids',deleted,'ranking_at_removed_count',ranking_at_counts, ...
    'states',states,'sampled',sampled,'full_single_object_trajectory',p.batch_size==1 && count==total, ...
    'status','ok','reason','','elapsed_seconds',toc(t0));
if stochastic, a.randomness.algorithm='mt19937ar'; end
if strcmp(p.version,'1.1.0')
    a.schema_version='attack-1.1.0'; a.implementation_version='1.1.0';
    a.schedule=schedule;
    a.full_single_object_trajectory=isequal(boundaries,(0:total)');
end
if any(strcmp({states.status},'partial')), a.status='partial'; a.reason='At least one observed metric failed or was not computed.'; end
if total==0
    a.fraction_status='undefined';
else
    a.fraction_status='ok';
end
end

function require_state_update_policy(selection)
% A fixed numerical matrix is external input, not changed by graph deletion.
% Reject before the first observation, including nested marginal rankings.
if ischar(selection)||isstring(selection)
    blocked=any(strcmp(cellstr(selection),'exact_numeric_driver_count'));
elseif iscell(selection)
    for j=1:numel(selection), require_state_update_policy(selection{j}); end
    return;
elseif isstruct(selection)
    blocked=false;
    for j=1:numel(selection)
        if isfield(selection(j),'metric_id')&&strcmp(selection(j).metric_id,'exact_numeric_driver_count')
            blocked=true; break;
        end
        if isfield(selection(j),'metric_id')&&strcmp(selection(j).metric_id,'deletion_impact') ...
                &&isfield(selection(j),'parameters')&&isstruct(selection(j).parameters) ...
                &&isfield(selection(j).parameters,'base_metric')
            require_state_update_policy(selection(j).parameters.base_metric);
        end
    end
else
    return; % Normal configuration validation supplies the type error.
end
if blocked
    error('mc:StateMatrixPolicyRequired', ...
        ['exact_numeric_driver_count cannot be observed or used for ranking during node or edge attacks: ', ...
        'an explicit per-step state-matrix update policy is required and is not implemented.']);
end
end

function q=round_count(f,n,mode)
x=f*n;
switch mode
    case 'floor', q=floor(x);
    case 'ceil', q=ceil(x);
    case 'nearest', q=round(x);
end
q=max(0,min(n,q));
end

function out=residual(ctx,nodes,edges)
map=zeros(ctx.n,1); map(nodes)=1:nnz(nodes);
list=reshape(map(ctx.edge_list(edges,:)),[],2);
n=nnz(nodes);
A=sparse(list(:,1),list(:,2),1,n,n);
if ~ctx.directed, A=A+A'; end
out=mc.context(A,ctx.directed,ctx.node_ids(nodes),list,ctx.edge_ids(edges));
end

function state=observe(ctx,count,round_index,removed_ids,removed_nodes,removed_edges,selections,total)
metrics=mc.compute(ctx,selections);
fraction=NaN; if total>0, fraction=count/total; end
state=struct('round_index',round_index,'removed_count',count,'removed_fraction',fraction, ...
    'fraction_valid',total>0,'removed_ids',removed_ids(:),'removed_node_ids',removed_nodes(:), ...
    'removed_edge_ids',removed_edges(:),'remaining_node_ids',ctx.node_ids, ...
    'remaining_edge_ids',ctx.edge_ids,'remaining_edge_endpoints_original',reshape(ctx.node_ids(ctx.edge_list),[],2), ...
    'node_count',ctx.n,'edge_count',ctx.m,'metrics',metrics,'status','ok');
if ~isempty(metrics) && any(ismember({metrics.status},{'failed','not_computed'})), state.status='partial'; end
end

function ids=rank_ids(ctx,p,stream,source)
if strcmp(p.target,'node'), expected=ctx.node_ids; else, expected=ctx.edge_ids; end
if isempty(expected), ids=expected; return; end
r=mc.compute(ctx,p.rank_metric);
if numel(r)~=1 || ~strcmp(r.scope,p.target) || ~isvector(r.values) || any(~r.valid_mask(:)) || any(~isfinite(r.values(:))) || ~strcmp(r.status,'ok')
    error('mc:InvalidRanking','Ranking must return one finite, valid %s vector.',p.target);
end
if numel(r.axis_ids)~=1 || ~isequal(sort(double(r.axis_ids{1}(:))),sort(double(expected(:)))) || numel(r.values)~=numel(expected)
    error('mc:InvalidRanking','Ranking axis IDs must exactly identify the residual objects.');
end
ids=cast(r.axis_ids{1}(:),'like',expected); scores=double(r.values(:));
if strcmp(p.score_order,'desc'), scores=-scores; end
switch p.tie_break
    case 'original_id', secondary=double(ids);
    case 'source_order', [~,secondary]=ismember(ids,source);
    case 'random', secondary=rand(stream,numel(ids),1);
end
[~,order]=sortrows([scores secondary double(ids)],[1 2 3]);
ids=ids(order);
end

function s=sample_states(states,p,total)
f=p.sample_fractions;
counts=[states.removed_count]';
template=struct('requested_fraction',NaN,'requested_removed_count',0,'state_index',0, ...
    'actual_removed_count',NaN,'actual_removed_fraction',NaN,'fraction_valid',false, ...
    'exact_count_match',false,'status','not_computed','reason','Requested count was not observed.','metrics',[]);
s=repmat(template,numel(f),1);
for j=1:numel(f)
    target=round_count(f(j),total,p.rounding);
    s(j).requested_fraction=f(j); s(j).requested_removed_count=target;
    switch p.sample_policy
        case 'exact', ix=find(counts==target,1);
        case 'previous', ix=find(counts<=target,1,'last');
        case 'next', ix=find(counts>=target,1);
    end
    if ~isempty(ix)
        s(j).state_index=ix; s(j).actual_removed_count=counts(ix);
        s(j).actual_removed_fraction=states(ix).removed_fraction;
        s(j).fraction_valid=states(ix).fraction_valid;
        s(j).exact_count_match=counts(ix)==target;
        s(j).status=states(ix).status; s(j).reason=''; s(j).metrics=states(ix).metrics;
    end
end
end
