function output = build_run(ctx,identity,selections,options)
%BUILD_RUN Compute one explicitly configured static or attack run in memory.
if nargin<4, options=struct(); end
p=mc.plan_run(identity,selections,options); selections=p.selections;
protocol=p.protocol; seed=p.seeds.attack_seed; repeat=p.seeds.repeat_index;
t=tic; results=struct([]); attack=struct(); summaries=struct([]); status='complete';
if isempty(protocol)
    results=mc.compute(ctx,selections); states={results.status};
    if any(ismember(states,{'failed','not_computed'})), status='partial'; end
    if all(strcmp(states,'failed')), status='failed'; end
else
    attack=mc.attack(ctx,protocol,selections,seed,repeat);
    if isfield(attack,'status') && ismember(attack.status,{'failed','partial'}), status=attack.status; end
    if ~isempty(p.summary_selections)
        summaries=mc.summarize(ctx,attack,p.summary_selections);
        if any(ismember({summaries.status},{'failed','not_computed'})), status='partial'; end
    end
end
output=struct('schema_version','metric-v1','graph_id',p.graph_id,'topology_hash',p.topology_hash, ...
    'origin_graph_id',p.origin_graph_id,'metric_set_id',p.metric_set_id,'protocol_id',p.protocol_id,'run_id',p.run_id, ...
    'metric_version','1.0.0','implementation_sha256',p.implementation_sha256,'metric_set_identity_json',p.metric_set_identity_json, ...
    'run_identity_json',p.run_identity_json,'selections',selections,'summary_selections',p.summary_selections, ...
    'seeds',p.seeds,'status',status,'results',results,'attack',attack,'summaries',summaries, ...
    'created_utc',char(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
    'matlab_version',version,'elapsed_seconds',toc(t));
mc.validate_output(output);
end
