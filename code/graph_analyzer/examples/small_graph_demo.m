function records = small_graph_demo()
%SMALL_GRAPH_DEMO Pure small-graph examples and result fixtures for task3.
% Synthetic TEST identities below are not production graph IDs or graph files.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
fixture_root=fullfile(root,'examples','result_fixtures'); if ~isfolder(fixture_root), mkdir(fixture_root); end
names={'path4','directed_mixed','isolates3','empty0'};
As={sparse([1 2 2 3 3 4],[2 1 3 2 4 3],1,4,4), ...
    sparse([1 2 2 3],[2 1 3 4],1,5,5),sparse(3,3),sparse(0,0)};
directed=[false true false false]; records=struct([]);
selections={'node_count','edge_count','density','degree','distance_matrix','edge_betweenness','global_efficiency','degree_assortativity','adjacency_spectrum'};
for i=1:numel(names)
    ctx=mc.context(As{i},directed(i)); identity=fixture_identity(names{i});
    output=mc.build_run(ctx,identity,selections,struct()); r=mc.save_run(fixture_root,output,'examples');
    if isempty(records), records=r; else, records(end+1)=r; end %#ok<AGROW>
end
ctx=mc.context(As{1},false); identity=fixture_identity('path4');
protocol=struct('target','node','strategy','external','external_sequence',[2;4;1;3],'sample_fractions',[0;.1;.2;.5;.75;1]);
summaries=struct('metric_id',{'robustness_schneider','sampled_curve_auc','efficiency_retention_curve'}, ...
    'parameters',{struct(),struct('metric_id','largest_component_size','normalize_initial',true),struct()});
options=struct('protocol',protocol,'summaries',summaries);
o=mc.build_run(ctx,identity,{'node_count','edge_count','largest_component_size','global_efficiency'},options);
records(end+1)=mc.save_run(fixture_root,o,'examples');
protocol=struct('target','edge','strategy','random','sample_fractions',[0;.1;.5;1]);
o=mc.build_run(ctx,identity,{'node_count','edge_count','largest_component_size','global_efficiency'},struct('protocol',protocol,'seed',42));
records(end+1)=mc.save_run(fixture_root,o,'examples');
% Deliberate algorithm nonconvergence: partial run and an unavailable vector.
ctx=mc.context(As{2},true); identity=fixture_identity('directed_mixed');
failure_selections=struct('metric_id',{'node_count','pagerank'},'parameters',{struct(),struct('max_iterations',1,'tolerance',1e-15)});
o=mc.build_run(ctx,identity,failure_selections,struct());
assert(strcmp(o.status,'partial'),'Expected deliberate PageRank nonconvergence fixture.');
known=mc.find_record(fixture_root,o.run_id);
if isempty(known)
    records(end+1)=mc.save_run(fixture_root,o,'examples');
else
    mc.verify_record(fixture_root,known); records(end+1)=known;
end
mc.merge_manifests(fixture_root);
rows=cell(numel(names),1);
for i=1:numel(names)
    [u,v]=find(As{i}); rows{i}=struct('fixture_name',names{i},'directed',directed(i),'node_count',size(As{i},1),'arcs_one_based',[u(:),v(:)],'test_identity',fixture_identity(names{i}));
end
% This is explanatory fixture metadata for tests, not an original graph format.
mc.write_text_atomic(fullfile(fixture_root,'fixture_descriptions.json'),jsonencode(struct('purpose','test-only in-memory fixtures; no original graph files','fixtures',{rows}),'PrettyPrint',true),true);
fprintf('Saved %d small result fixtures to %s\n',numel(records),fixture_root);
end
function identity=fixture_identity(name)
graph_id=mc.identity(struct('fixture_name',name),'TEST-ONLY-NOT-GRAPH-ID');
topology_hash=mc.identity(struct('fixture_name',name),'TEST-ONLY-NOT-TOPOLOGY-HASH');
identity=struct('graph_id',graph_id,'topology_hash',topology_hash,'origin_graph_id',graph_id);
end
