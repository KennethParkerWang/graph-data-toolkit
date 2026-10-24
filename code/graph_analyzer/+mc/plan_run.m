function plan = plan_run(identity,selections,options)
%PLAN_RUN Validate configuration and compute run identity without metric work.
if nargin<3, options=struct(); end
allowed={'protocol','seed','repeat_index','summaries'};
if ~isempty(setdiff(fieldnames(options),allowed)), error('mc:Config','Unknown run option.'); end
for field={'graph_id','topology_hash','origin_graph_id'}
    name=field{1}; if ~isfield(identity,name)||isempty(regexp(identity.(name),'^[0-9a-f]{64}$','once'))
        error('mc:Identity','Validated original graph identity requires %s.',name);
    end
end
selections=mc.validate_selection(selections); reg=mc.registry();
definitions=struct('metric_id',{},'metric_version',{},'parameters',{});
for i=1:numel(selections)
    e=reg(strcmp({reg.metric_id},selections(i).metric_id));
    definitions(i)=struct('metric_id',e.metric_id,'metric_version',e.metric_version,'parameters',selections(i).parameters);
end
protocol=mc.param(options,'protocol',[]); seed=mc.param(options,'seed',[]); repeat=mc.param(options,'repeat_index',1);
validateattributes(repeat,{'numeric'},{'scalar','integer','positive','finite'});
protocol_id=''; randomness='none';
if ~isempty(protocol)
    protocol=mc.validate_protocol(protocol); protocol_id=mc.identity(protocol,'protocol-v1');
    random=strcmp(protocol.strategy,'random')||(strcmp(protocol.strategy,'ranked')&&strcmp(protocol.tie_break,'random'));
    if random
        validateattributes(seed,{'numeric'},{'scalar','real','integer','finite','>=',0,'<=',double(intmax('uint32'))});
        randomness='mt19937ar';
    elseif ~isempty(seed)
        error('mc:Config','Deterministic protocol must have an empty seed.');
    end
elseif ~isempty(seed)
    error('mc:Config','Static deterministic metrics do not take an attack seed.');
end
source=mc.source_digest();
summaries=mc.param(options,'summaries',struct([])); summary_definitions=struct('metric_id',{},'metric_version',{},'parameters',{});
if ~isempty(summaries)
    if isempty(protocol), error('mc:Config','Summary selections require an attack protocol.'); end
    summaries=mc.validate_selection(summaries);
    for i=1:numel(summaries)
        e=reg(strcmp({reg.metric_id},summaries(i).metric_id));
        if ~strcmp(e.category,'robustness'), error('mc:Config','Only robustness metrics belong in summaries.'); end
        summary_definitions(i)=struct('metric_id',e.metric_id,'metric_version',e.metric_version,'parameters',summaries(i).parameters);
    end
end
recipe=struct('selections',definitions,'summary_selections',summary_definitions,'protocol_id',protocol_id,'implementation_version','1.0.0','implementation_sha256',source);
[set_id,set_json]=mc.identity(recipe,'metric-set-v1');
seeds=struct('randomness',randomness,'attack_seed',seed,'repeat_index',repeat);
run_recipe=struct('graph_id',identity.graph_id,'topology_hash',identity.topology_hash,'metric_set_id',set_id,'seeds',seeds);
[run_id,run_json]=mc.identity(run_recipe,'metric-run-v1');
plan=struct('graph_id',identity.graph_id,'topology_hash',identity.topology_hash, ...
    'origin_graph_id',identity.origin_graph_id,'metric_set_id',set_id,'protocol_id',protocol_id,'run_id',run_id, ...
    'implementation_sha256',source,'metric_set_identity_json',set_json,'run_identity_json',run_json, ...
    'selections',selections,'summary_selections',summaries,'seeds',seeds,'protocol',protocol);
end
