function report = verify_task1_single_graph()
%VERIFY_TASK1_SINGLE_GRAPH Validate all registered metrics on one graph-v1 example.
% Input is Task1's official triangle-plus-isolate handoff graph. Outputs stay
% inside graph_analyzer/validation and do not modify the source graph.
t = tic;
root = fileparts(fileparts(mfilename('fullpath')));
dataset_root = fullfile(fileparts(root),'graph_builder','examples','schema_v1');
relative_path = 'graphs/c8/c89eb1a8f8398a2503fc3439f5d73715cc830aecdd2d77fba24d456cb43d49ad.mat';
source_path = mc.safe_path(dataset_root,relative_path);
[ctx,identity] = mc.read_graph(source_path);
assert(~ctx.directed && ctx.n==4 && ctx.m==3,'Unexpected Task1 fixture selected.');

% Materialize every registered selection, supplying only explicit validation
% parameters needed by metrics whose definitions require them.
reg = mc.registry();
selections = repmat(struct('metric_id','','parameters',struct()),numel(reg),1);
partition = uint32([1;1;1;2]);
for i=1:numel(reg)
    id = char(reg(i).metric_id); p = struct();
    switch id
        case {'modularity','community_sizes'}
            p.partition = partition;
        case 'structural_dedicated_feasibility'
            p.driver_node_ids = uint32(2);
        case 'exact_numeric_driver_count'
            p.state_matrix = full(ctx.A);
        case 'katz'
            p.alpha = 0.1;
        case 'deletion_impact'
            p.base_metric = struct('metric_id','global_efficiency','parameters',struct());
            p.target = 'node';
        case {'robustness_control_node','robustness_control_edge'}
            p.driver_metric_id = 'structural_driver_count';
        case {'sampled_curve_auc','first_threshold_fraction'}
            p.metric_id = 'global_efficiency';
            if strcmp(id,'first_threshold_fraction'), p.threshold = 0.5; end
    end
    selections(i).metric_id = id;
    selections(i).parameters = p;
end
results = mc.compute(ctx,selections);

% Independent analytic checks for the selected graph.
checks = repmat(struct('name','','passed',false,'actual',NaN,'expected',NaN,'tolerance',0),0,1);
checks(end+1) = check_scalar('node_count',results,4,0);
checks(end+1) = check_scalar('edge_count',results,3,0);
checks(end+1) = check_scalar('density',results,0.5,1e-12);
checks(end+1) = check_scalar('isolate_count',results,1,0);
checks(end+1) = check_vector('degree',results,[2;2;2;0],1e-12);
checks(end+1) = check_scalar('degree_mean',results,1.5,1e-12);
checks(end+1) = check_scalar('degree_variance',results,0.75,1e-12);
checks(end+1) = check_scalar('degree_heterogeneity',results,4/3,1e-12);
checks(end+1) = check_scalar('component_count',results,2,0);
checks(end+1) = check_scalar('largest_component_size',results,3,0);
checks(end+1) = check_scalar('second_largest_component_size',results,1,0);
checks(end+1) = check_scalar('largest_component_fraction',results,0.75,1e-12);
checks(end+1) = check_scalar('triangle_count',results,1,0);
checks(end+1) = check_scalar('average_clustering',results,0.75,1e-12);
checks(end+1) = check_scalar('transitivity',results,1,1e-12);
checks(end+1) = check_scalar('global_efficiency',results,0.5,1e-12);
checks(end+1) = check_scalar('algebraic_connectivity',results,0,1e-10);
checks(end+1) = check_scalar('node_connectivity',results,0,1e-12);
checks(end+1) = check_scalar('edge_connectivity',results,0,1e-12);
checks(end+1) = check_scalar('kirchhoff_index',results,Inf,0);
checks(end+1) = check_scalar('modularity',results,0,1e-12);
checks(end+1) = check_status('indegree_not_applicable',results,'indegree','not_applicable');
checks(end+1) = check_status('outdegree_not_applicable',results,'outdegree','not_applicable');
checks(end+1) = check_status('reciprocity_not_applicable',results,'reciprocity','not_applicable');
checks(end+1) = check_status('structural_driver_count_not_applicable',results,'structural_driver_count','not_applicable');
checks(end+1) = check_status('triad_census_not_applicable',results,'triad_census','not_applicable');

% A separate full single-node trajectory exercises the trajectory-only
% robustness summaries. The explicit order removes the isolated node first,
% then the triangle nodes, so the expected values are hand-computable.
protocol = struct('target','node','strategy','external', ...
    'external_sequence',double([4;1;2;3]), ...
    'sample_fractions',[0;0.25;0.5;0.75;1]);
attack = mc.attack(ctx,protocol,{'largest_component_size','global_efficiency'});
summary_selections = [ ...
    struct('metric_id','robustness_schneider','parameters',struct()), ...
    struct('metric_id','sampled_curve_auc','parameters',struct('metric_id','largest_component_size')), ...
    struct('metric_id','first_threshold_fraction','parameters',struct('metric_id','largest_component_size','threshold',1.5)), ...
    struct('metric_id','efficiency_retention_curve','parameters',struct())];
summaries = mc.summarize(ctx,attack,summary_selections);
checks(end+1) = check_summary_scalar('robustness_schneider',summaries,0.375,1e-12);
checks(end+1) = check_summary_scalar('sampled_curve_auc',summaries,1.875,1e-12);
checks(end+1) = check_summary_scalar('first_threshold_fraction',summaries,0.75,1e-12);
checks(end+1) = check_summary_vector_prefix('efficiency_retention_curve',summaries,[1;2;2],1e-12);
checks(end+1) = check_summary_status('efficiency_retention_curve_partial',summaries,'partial');

passed = all([checks.passed]);
status_counts = struct();
statuses = {results.status};
for i=1:numel(statuses)
    key = matlab.lang.makeValidName(statuses{i});
    if ~isfield(status_counts,key), status_counts.(key)=0; end
    status_counts.(key)=status_counts.(key)+1;
end
summary = repmat(struct('metric_id','','status','','valid_count',0,'value_size',[],'reason',''),numel(results),1);
for i=1:numel(results)
    summary(i).metric_id=results(i).metric_id;
    summary(i).status=results(i).status;
    summary(i).valid_count=nnz(results(i).valid_mask);
    summary(i).value_size=size(results(i).values);
    summary(i).reason=results(i).reason;
end
report = struct('passed',passed,'source_path',source_path,'graph_id',identity.graph_id, ...
    'topology_hash',identity.topology_hash,'N',ctx.n,'M',ctx.m,'directed',ctx.directed, ...
    'registered_metrics',numel(reg),'computed_selections',numel(results), ...
    'status_counts',status_counts,'analytic_checks',{checks},'metrics',{summary}, ...
    'attack_protocol',attack.protocol,'attack_status',attack.status, ...
    'attack_state_count',numel(attack.states),'summary_results',{summaries}, ...
    'elapsed_seconds',toc(t));
out = fullfile(root,'validation','task1_single_graph');
if ~isfolder(out), mkdir(out); end
save(fullfile(out,'results.mat'),'results','identity','-v7');
mc.write_text_atomic(fullfile(out,'report.json'),jsonencode(report,'PrettyPrint',true),true);
if ~passed, error('mc:Validation','Task1 single-graph analytic checks failed.'); end
end

function c=check_scalar(name,results,expected,tol)
r=one(results,name); actual=r.values; ok=strcmp(r.status,'ok')&&isscalar(actual)&&((isinf(expected)&&isinf(actual))||abs(actual-expected)<=tol);
c=struct('name',name,'passed',ok,'actual',actual,'expected',expected,'tolerance',tol);
end
function c=check_vector(name,results,expected,tol)
r=one(results,name); actual=double(r.values(:)); expected=double(expected(:)); ok=strcmp(r.status,'ok')&&isequal(size(actual),size(expected))&&all(abs(actual-expected)<=tol);
c=struct('name',name,'passed',ok,'actual',actual,'expected',expected,'tolerance',tol);
end
function c=check_status(name,results,id,expected)
r=one(results,id); ok=strcmp(r.status,expected);
c=struct('name',name,'passed',ok,'actual',r.status,'expected',expected,'tolerance',0);
end
function c=check_summary_scalar(id,results,expected,tol)
r=results(strcmp({results.metric_id},id)); assert(isscalar(r),'Summary %s missing or duplicated.',id);
actual=r.values; ok=strcmp(r.status,'ok')&&isscalar(actual)&&abs(actual-expected)<=tol;
c=struct('name',['summary_',id],'passed',ok,'actual',actual,'expected',expected,'tolerance',tol);
end
function c=check_summary_vector_prefix(id,results,expected,tol)
r=results(strcmp({results.metric_id},id)); assert(isscalar(r),'Summary %s missing or duplicated.',id);
actual=double(r.values(:)); expected=double(expected(:)); ok=all(r.valid_mask(1:numel(expected)))&&numel(actual)>=numel(expected)&&all(abs(actual(1:numel(expected))-expected)<=tol);
c=struct('name',['summary_',id],'passed',ok,'actual',actual,'expected',expected,'tolerance',tol);
end
function c=check_summary_status(id,results,expected)
r=results(strcmp({results.metric_id},strrep(id,'_partial',''))); assert(isscalar(r),'Summary missing.');
c=struct('name',id,'passed',strcmp(r.status,expected),'actual',r.status,'expected',expected,'tolerance',0);
end
function r=one(results,id)
r=results(strcmp({results.metric_id},id)); assert(isscalar(r),'Metric %s missing or duplicated.',id);
end
