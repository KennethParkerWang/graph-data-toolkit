function result=robustness_extensions_demo()
%ROBUSTNESS_EXTENSIONS_DEMO Tiny synthetic edge/directed/grid/repeat examples.
% Only result files; identities below do not define task1 graph storage.
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
base=fullfile(root,'examples','extension_result_fixtures'); if ~isfolder(base), mkdir(base); end
ctx=mc.context(sparse([1 2 3 3 4],[2 3 1 4 2],1,4,4),true);
graph_id=mc.identity(struct('name','directed4_followup'),'TEST-ONLY-NOT-GRAPH-ID');
identity=struct('graph_id',graph_id,'topology_hash',mc.identity(struct('name','directed4_followup'),'TEST-ONLY-NOT-TOPOLOGY-HASH'),'origin_graph_id',graph_id);
weak=struct('metric_id','largest_component_size','parameters',struct('component_mode','weak'));
strong=struct('metric_id','largest_component_size','parameters',struct('component_mode','strong'));
selections=[weak;strong];
summary_weak=struct('metric_id','connectivity_robustness','parameters',struct('component_mode','weak'));
summary_strong=struct('metric_id','connectivity_robustness','parameters',struct('component_mode','strong'));
protocol=struct('target','edge','strategy','random'); records=struct([]);
for j=1:4
    opts=struct('protocol',protocol,'seed',100+j,'repeat_index',j,'summaries',[summary_weak;summary_strong]);
    output=mc.build_run(ctx,identity,selections,opts); r=mc.save_run(base,output,'extensions_demo');
    if isempty(records), records=r; else, records(end+1)=r; end %#ok<AGROW>
end
stats=struct('confidence_method','student_t','missing_policy','propagate');
weak_curve=mc.aggregate_repeats(base,records,weak,stats);
weak_record=mc.save_repeat_summary(base,weak_curve);
strong_curve=mc.aggregate_repeats(base,records,strong,stats);
strong_record=mc.save_repeat_summary(base,strong_curve);
stats.source='summaries'; robustness=mc.aggregate_repeats(base,records,summary_weak,stats);
robustness_record=mc.save_repeat_summary(base,robustness);
% A coarse grid controls actual batches: floor([0 .1 .25 .5 .75 1]*5).
protocol.version='1.1.0'; protocol.deletion_mode='fraction_grid';
protocol.attack_fractions=[0 .1 .25 .5 .75 1]; protocol.sample_fractions=protocol.attack_fractions;
auc=struct('metric_id','sampled_curve_auc','parameters',struct('metric_id','largest_component_size', ...
    'metric_parameters',weak.parameters,'source','states','normalize_initial',true));
output=mc.build_run(ctx,identity,selections,struct('protocol',protocol,'seed',200,'summaries',auc));
grid_record=mc.save_run(base,output,'extensions_demo'); mc.merge_manifests(base);
result=struct('fixture_root',base,'repeat_records',records,'grid_record',grid_record, ...
    'aggregate_records',[weak_record;strong_record;robustness_record]);
mc.write_text_atomic(fullfile(base,'fixture_description.json'),jsonencode(struct( ...
    'purpose','Synthetic small in-memory graph; identities are not task1 graph identities', ...
    'node_count',4,'arcs_one_based',[1 2;2 3;3 1;3 4;4 2], ...
    'full_edge_repeats',4,'seeds',(101:104)','grid_requested_fraction',protocol.attack_fractions', ...
    'grid_actual_count',[output.attack.states.removed_count]','aggregate_count',3),'PrettyPrint',true),true);
fprintf('Saved 4 tiny edge repeats, 1 coarse-grid run and 3 separate repeat summaries.\n');
end
