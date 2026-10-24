function aggregate=aggregate_repeats(root,records,selection,options)
%AGGREGATE_REPEATS Verify saved random runs and summarize matched observations.
% Retains all raw runs. Does not generate attacks, interpolate, or pool graphs.
% source: states (default), sampled, or graph-scalar summaries.
if nargin<4, options=struct(); end
if ~isstruct(options)||~isscalar(options), error('mc:AggregateOptions','Options must be a scalar struct.'); end
source=mc.param(options,'source','states');
if isfield(options,'source'), options=rmfield(options,'source'); end
if ~ismember(source,{'states','sampled','summaries'}), error('mc:AggregateOptions','source must be states, sampled or summaries.'); end
if ~isstruct(records)||isempty(records)||~all(isfield(records,{'run_id','path','file_sha256','file_bytes'}))
    error('mc:AggregateInputs','Supply one or more saved mc.save_run manifest records.');
end
if numel(unique({records.run_id}))~=numel(records), error('mc:DuplicateRepeat','Duplicate input run IDs are not independent repeats.'); end
[~,order]=sort({records.run_id}); records=records(order); records=records(:);
inputs=repmat(struct('run_id','','path','','file_sha256','','file_bytes',0,'attack_seed',0,'repeat_index',0,'status',''),numel(records),1);
group=struct(); axes=struct(); definition=struct(); seeds=zeros(numel(records),1);
values=[]; valid=[]; observation_status={};
for j=1:numel(records)
    o=mc.verify_record(root,records(j));
    if isempty(o.protocol_id)||~o.attack.randomness.used||~strcmp(o.seeds.randomness,'mt19937ar')
        error('mc:AggregateInputs','Only seeded stochastic attack runs can be aggregated as random repeats.');
    end
    g=struct('graph_id',o.graph_id,'topology_hash',o.topology_hash,'origin_graph_id',o.origin_graph_id, ...
        'metric_set_id',o.metric_set_id,'protocol_id',o.protocol_id,'implementation_sha256',o.implementation_sha256, ...
        'input_context_identity',o.attack.input_context_identity);
    [y,v,axis,def,status]=extract(o,selection,source);
    if isempty(fieldnames(def)), error('mc:AggregateSelection','Selected definition is absent from input run.'); end
    if j==1
        group=g; axes=axis; definition=def;
        values=NaN(numel(y),numel(records)); valid=false(size(values)); observation_status=cell(size(values));
    elseif ~strcmp(mc.canonical_json(group),mc.canonical_json(g))
        error('mc:AggregateGroup','Graph, topology, protocol, implementation and metric set must match.');
    elseif ~strcmp(mc.canonical_json(definition),mc.canonical_json(def))
        error('mc:MetricDefinitionMismatch','All source metric definitions/parameters/versions must match.');
    elseif ~isequaln(axes,axis)
        error('mc:AggregateAxis','Actual observation axes must match; interpolation is not performed.');
    end
    values(:,j)=y; valid(:,j)=v; observation_status(:,j)=status;
    seeds(j)=o.seeds.attack_seed;
    inputs(j)=struct('run_id',o.run_id,'path',records(j).path,'file_sha256',records(j).file_sha256, ...
        'file_bytes',records(j).file_bytes,'attack_seed',seeds(j),'repeat_index',o.seeds.repeat_index,'status',o.status);
end
if numel(unique(seeds))~=numel(seeds), error('mc:DuplicateSeed','Repeated seeds reproduce dependent paths; supply distinct seeds.'); end
statistics=mc.repeat_statistics(values,valid,options);
implementation=mc.source_digest();
recipe=struct('group',group,'inputs',inputs,'source',source,'metric_definition',definition, ...
    'statistics_options',statistics.options,'summary_implementation_sha256',implementation);
[id,identity_json]=mc.identity(recipe,'repeat-summary-v1');
aggregate=struct('schema_version','repeat-summary-1.0.0','aggregate_id',id,'identity_json',identity_json, ...
    'group',group,'inputs',inputs,'source',source,'metric_definition',definition,'axes',axes, ...
    'statistics',statistics,'observation_status',{observation_status},'summary_implementation_sha256',implementation, ...
    'quantile_method','Hyndman-Fan type 7','ci_scope','pointwise mean; not simultaneous band', ...
    'created_utc',char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
    'matlab_version',version);
mc.validate_repeat_summary(aggregate);
end
function [y,v,axes,definition,status]=extract(o,selection,source)
axes=struct('observation_index',[],'removed_count',[],'actual_removed_fraction',[], ...
    'requested_fraction',[],'requested_removed_count',[],'state_index',[]);
if strcmp(source,'summaries')
    hit=mc.match_metric(o.summaries,selection);
    if isempty(hit), error('mc:AggregateSelection','Requested scalar summary is absent.'); end
    r=o.summaries(hit);
    if ~strcmp(r.scope,'graph')||numel(r.values)>1, error('mc:AggregateSelection','Only graph-scalar summaries are supported.'); end
    y=NaN; v=false;
    if ~isempty(r.values), y=r.values; v=r.valid_mask&&isfinite(y)&&ismember(r.status,{'ok','partial'}); end
    definition=struct('metric_id',r.metric_id,'metric_version',r.metric_version,'parameters',r.parameters);
    status={r.status}; axes.observation_index=1;
else
    [x,y,v,d]=mc.attack_curve(o.attack,selection,source);
    if isempty(y), error('mc:AggregateAxis','No observations exist for selected source.'); end
    axes.observation_index=(1:numel(y))'; axes.removed_count=d.removed_count; axes.actual_removed_fraction=x;
    if strcmp(source,'sampled')
        axes.requested_fraction=[o.attack.sampled.requested_fraction]';
        axes.requested_removed_count=[o.attack.sampled.requested_removed_count]';
        axes.state_index=[o.attack.sampled.state_index]';
    else
        axes.state_index=(1:numel(y))';
    end
    definition=d.metric_definition; status=d.status;
end
end
