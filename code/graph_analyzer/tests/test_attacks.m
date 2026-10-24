function report = test_attacks()
%TEST_ATTACKS Analytic paths, endpoint sums, stable IDs and protocol differences.
t=tic; checks=0;
star=sparse([1 1 1 2 3 4],[2 3 4 1 1 1],1,4,4);
c=mc.context(star,false);
p=struct('target','node','strategy','external','external_sequence',[1 2 3 4], ...
    'sample_fractions',[0 .01 .24 .25 .49 1]);
sel={'node_count','edge_count','largest_component_size','degree','global_efficiency'};
a=mc.attack(c,p,sel);
assert(isequal([a.states.removed_count],0:4)); checks=checks+1;
assert(isequal(scalars(a,'largest_component_size'),[4;1;1;1;0])); checks=checks+1;
assert(isequal([a.sampled.requested_removed_count],[0 0 0 1 1 4])); checks=checks+1;
assert(isequal([a.sampled.state_index],[1 1 1 2 2 5])); checks=checks+1;
assert(isequal(a.states(2).removed_edge_ids,uint64([1;2;3]))); checks=checks+1;
assert(isempty(a.states(end).remaining_node_ids)&&isempty(a.states(end).remaining_edge_ids)); checks=checks+1;
r=mc.metrics.robustness_schneider(c,struct('trajectory',a));
assert(r.valid_mask && abs(r.values-3/16)<1e-14); checks=checks+1;
unified=mc.summarize(c,a,{'robustness_schneider'});
assert(strcmp(unified.status,'ok')&&abs(unified.values-3/16)<1e-14); checks=checks+1;
different=mc.context(sparse(ones(4)-eye(4)),false);
must_error(@()mc.summarize(different,a,{'robustness_schneider'}),'mc:TrajectoryIdentity'); checks=checks+1;
r=mc.metrics.sampled_curve_auc(c,struct('trajectory',a,'metric_id','largest_component_size','source','states','normalize_initial',true));
assert(abs(r.values-5/16)<1e-14); checks=checks+1;
th=mc.metrics.first_threshold_fraction(c,struct('trajectory',a,'metric_id','largest_component_size','threshold',1));
assert(th.values==.25&&th.details.removed_count==1); checks=checks+1;
th=mc.metrics.first_threshold_fraction(c,struct('trajectory',a,'metric_id','largest_component_size','threshold',-1));
assert(~th.valid_mask&&strcmp(th.status,'undefined')&&~th.details.reached); checks=checks+1;
ret=mc.metrics.efficiency_retention_curve(c,struct('trajectory',a));
assert(ret.values(1)==1&&ret.values(2)==0&&~ret.valid_mask(4)&&~ret.valid_mask(5)); checks=checks+1;

% Permuted node labels and edge table rows retain original IDs everywhere.
labels=uint32([30;10;40;20]); edge_rows=[1 4;1 2;1 3]; edge_ids=uint64([200;300;100]);
mapped=mc.context(star,false,labels,edge_rows,edge_ids);
q=p; q.external_sequence=[30 10 40 20]; b=mc.attack(mapped,q,sel);
assert(isequal(scalars(a,'largest_component_size'),scalars(b,'largest_component_size'))); checks=checks+1;
assert(isequal(b.states(2).remaining_node_ids,uint32([10;40;20]))); checks=checks+1;
assert(isequal(b.states(1).remaining_edge_ids,edge_ids)); checks=checks+1;
assert(isequal(b.states(1).remaining_edge_endpoints_original,uint32([30 20;30 10;30 40]))); checks=checks+1;

% Batch observations never claim unobserved intermediate states.
q=p; q.deletion_mode='batch'; q.batch_size=2; q.sample_fractions=[0 .25 .5 .75 1];
b=mc.attack(c,q,sel);
assert(isequal([b.states.removed_count],[0 2 4])&&~b.full_single_object_trajectory); checks=checks+1;
assert(isequal([b.sampled.state_index],[1 0 2 0 3])); checks=checks+1;
r=mc.metrics.robustness_schneider(c,struct('trajectory',b));
assert(strcmp(r.status,'not_applicable')); checks=checks+1;
q.sample_policy='previous'; bp=mc.attack(c,q,sel);
assert(isequal([bp.sampled.actual_removed_count],[0 0 2 2 4])); checks=checks+1;
assert(~bp.sampled(2).exact_count_match); checks=checks+1;
missing_auc=mc.metrics.sampled_curve_auc(c,struct('trajectory',b,'metric_id','largest_component_size'));
assert(strcmp(missing_auc.status,'not_computed')&&~missing_auc.valid_mask); checks=checks+1;
q.sample_policy='next'; bn=mc.attack(c,q,sel);
assert(isequal([bn.sampled.actual_removed_count],[0 2 2 4 4])); checks=checks+1;

% Known static/adaptive difference on P5; ties use original node IDs.
path=sparse(1:4,2:5,1,5,5); path=path+path'; pc=mc.context(path,false);
q=struct('strategy','ranked','rank_metric',struct('metric_id','degree','parameters',struct()));
s=mc.attack(pc,q,{'node_count'});
assert(isequal(s.deleted_ids,uint32([2;3;4;1;5]))); checks=checks+1;
q.ranking='adaptive'; ad=mc.attack(pc,q,{'node_count'});
assert(isequal(ad.deleted_ids(1:2),uint32([2;4]))); checks=checks+1;
q.recompute_interval=2; ad2=mc.attack(pc,q,{'node_count'});
assert(isequal(ad2.deleted_ids(1:2),uint32([2;3]))); checks=checks+1;
assert(~strcmp(ad.protocol_id,ad2.protocol_id)); checks=checks+1;
assert(isequal(ad2.ranking_at_removed_count,[0;2;4])); checks=checks+1;
q.recompute_interval=1; q.deletion_mode='batch'; q.batch_size=2;
ab=mc.attack(pc,q,{'node_count'});
assert(isequal(ab.deleted_ids(1:2),uint32([2;3]))&&~strcmp(ab.protocol_id,ad.protocol_id)); checks=checks+1;

% Edge deletion preserves nodes and IDs even when stored edge rows are unsorted.
pc=mc.context(sparse([1 2 2 3],[2 1 3 2],1,3,3),false,uint32([10;20;30]),[2 3;1 2],uint64([9;7]));
q=struct('target','edge','strategy','external','external_sequence',[9 7]);
e=mc.attack(pc,q,{'node_count','edge_count','largest_component_size','edge_betweenness'});
assert(isequal(scalars(e,'largest_component_size'),[3;2;1])); checks=checks+1;
assert(isequal(e.states(2).remaining_edge_ids,uint64(7))); checks=checks+1;
assert(isequal(e.states(2).remaining_edge_endpoints_original,uint32([10 20]))); checks=checks+1;
assert(isequal(e.states(3).remaining_node_ids,uint32([10;20;30]))); checks=checks+1;
assert(isequal(e.states(3).remaining_edge_endpoints_original,zeros(0,2,'uint32'))); checks=checks+1;
q.strategy='source_order'; q.external_sequence=[];
must_error(@()mc.attack(pc,q,{'node_count'}),'mc:MissingSourceOrder'); checks=checks+1;
pc.source_edge_order_ids=uint64([7;9]); e=mc.attack(pc,q,{'node_count'});
assert(isequal(e.deleted_ids,uint64([7;9]))); checks=checks+1;
q=struct('target','edge','strategy','ranked','ranking','adaptive', ...
    'rank_metric',struct('metric_id','edge_betweenness','parameters',struct()));
ranked_edges=mc.attack(pc,q,{'edge_count'});
assert(isequal(ranked_edges.deleted_ids,uint64([7;9]))); checks=checks+1;
q.tie_break='source_order'; pc.source_edge_order_ids=uint64([9;7]);
source_tie=mc.attack(pc,q,{'edge_count'});
assert(isequal(source_tie.deleted_ids,uint64([9;7]))); checks=checks+1;

% Per-repeat RNG is local; explicit seed required, deterministic repeats saved.
q=struct('strategy','random'); before=rng;
ra=mc.attack(c,q,{'node_count'},23,1); rb=mc.attack(c,q,{'node_count'},23,2);
assert(isequal(ra.deleted_ids,rb.deleted_ids)&&isequal(before,rng)&&rb.repeat_index==2); checks=checks+1;
must_error(@()mc.attack(c,q,{'node_count'}),'mc:MissingSeed'); checks=checks+1;

% Empty target sets retain one observed state, undefined fraction, and masks.
empty=mc.context(sparse(0,0),false);
q=struct('strategy','external','external_sequence',[],'sample_fractions',[0 .5 1]);
z=mc.attack(empty,q,{'node_count','largest_component_size'});
assert(numel(z.states)==1&&z.states.removed_count==0&&isnan(z.states.removed_fraction)); checks=checks+1;
assert(all([z.sampled.state_index]==1)&&all(~[z.sampled.fraction_valid])); checks=checks+1;
r=mc.metrics.robustness_schneider(empty,struct('trajectory',z));
assert(strcmp(r.status,'undefined')&&~r.valid_mask); checks=checks+1;
isolates=mc.context(sparse(3,3),false); q.target='edge';
z=mc.attack(isolates,q,{'node_count','global_efficiency'});
ret=mc.metrics.efficiency_retention_curve(isolates,struct('trajectory',z));
assert(strcmp(ret.status,'undefined')&&~ret.valid_mask); checks=checks+1;

% Lou node/edge endpoints tested on a directed path of length 2.
dc=mc.context(sparse(1:2,2:3,1,3,3),true);
q=struct('strategy','external','external_sequence',[2 1 3]);
da=mc.attack(dc,q,{'structural_driver_count'});
r=mc.metrics.robustness_control_node(dc,struct('trajectory',da,'driver_metric_id','structural_driver_count'));
assert(strcmp(r.status,'ok')&&abs(r.values-7/9)<1e-14); checks=checks+1;
q=struct('target','edge','strategy','external','external_sequence',[1 2]);
de=mc.attack(dc,q,{'structural_driver_count'});
r=mc.metrics.robustness_control_edge(dc,struct('trajectory',de,'driver_metric_id','structural_driver_count'));
assert(strcmp(r.status,'ok')&&abs(r.values-2/3)<1e-14); checks=checks+1;
% A node-control sum does not need the unused empty endpoint.
q=struct('strategy','external','external_sequence',[2 1],'stop_fraction',2/3);
partial=mc.attack(dc,q,{'structural_driver_count'});
r=mc.metrics.robustness_control_node(dc,struct('trajectory',partial,'driver_metric_id','structural_driver_count'));
assert(strcmp(r.status,'ok')&&abs(r.values-7/9)<1e-14); checks=checks+1;
% Exact finite-N Schneider endpoint convention for K4.
complete=mc.context(sparse(ones(4)-eye(4)),false);
q=struct('strategy','external','external_sequence',[1 2 3 4]);
ka=mc.attack(complete,q,{'largest_component_size'});
kr=mc.metrics.robustness_schneider(complete,struct('trajectory',ka));
assert(abs(kr.values-3/8)<1e-14); checks=checks+1;
% Sampling and stop rounding are literal floor/ceil/MATLAB nearest rules.
q.stop_fraction=.375; q.sample_fractions=[0 .375]; q.rounding='floor';
floored=mc.attack(complete,q,{'node_count'});
q.rounding='ceil'; ceiled=mc.attack(complete,q,{'node_count'});
q.rounding='nearest'; nearest=mc.attack(complete,q,{'node_count'});
assert(floored.states(end).removed_count==1&&ceiled.states(end).removed_count==2&&nearest.states(end).removed_count==2); checks=checks+1;
% Parameter default materialization gives identical protocol identities.
q=struct('strategy','ranked','rank_metric',struct('metric_id','degree','parameters',struct()));
assert(strcmp(mc.protocol_id(q),mc.protocol_id(mc.validate_protocol(q)))); checks=checks+1;
% Seeded wrapper: mathematically undefined efficiency endpoints are complete.
identity=struct('graph_id',repmat('a',1,64),'topology_hash',repmat('b',1,64),'origin_graph_id',repmat('a',1,64));
opts=struct('protocol',struct('strategy','random','sample_fractions',[0 .5 1]), ...
    'seed',23,'repeat_index',1,'summaries',{{'robustness_schneider','efficiency_retention_curve'}});
wrapped=mc.build_run(c,identity,{'node_count','largest_component_size','global_efficiency'},opts);
mc.validate_output(wrapped);
assert(strcmp(wrapped.status,'complete')&&numel(wrapped.summaries)==2&&strcmp(wrapped.summaries(2).status,'partial')); checks=checks+1;
root=fileparts(fileparts(mfilename('fullpath')));
fixture=fullfile(root,'validation',['attack_io_',char(java.util.UUID.randomUUID())]); mkdir(fixture);
[record,resumed]=mc.save_run(fixture,wrapped,'attack_test');
assert(~resumed&&isequaln(mc.verify_record(fixture,record),wrapped)); checks=checks+1;
[~,resumed]=mc.save_run(fixture,wrapped,'attack_test'); assert(resumed); checks=checks+1;
% Fixed numerical matrices must not silently survive node OR edge deletion.
fixed=struct('metric_id','exact_numeric_driver_count','parameters',struct('state_matrix',zeros(3)));
for target={'node','edge'}
    q=struct('target',target{1},'strategy','random');
    must_error(@()mc.attack(dc,q,fixed,23),'mc:StateMatrixPolicyRequired'); checks=checks+1;
    nested=struct('metric_id','deletion_impact','parameters',struct('target',target{1},'base_metric',fixed));
    must_error(@()mc.attack(dc,q,nested,23),'mc:StateMatrixPolicyRequired'); checks=checks+1;
    q.strategy='ranked'; q.rank_metric=fixed;
    must_error(@()mc.attack(dc,q,{'node_count'}),'mc:StateMatrixPolicyRequired'); checks=checks+1;
    q.rank_metric=nested;
    must_error(@()mc.attack(dc,q,{'node_count'}),'mc:StateMatrixPolicyRequired'); checks=checks+1;
end
% Empty unavailable graph scalars retain status instead of becoming exceptions.
smallpath=mc.context(sparse([1 2 2 3],[2 1 3 2],1,3,3),false);
limited=struct('metric_id','adjacency_spectral_radius','parameters',struct('max_nodes',2));
q=struct('strategy','external','external_sequence',[2 1 3]);
limited_path=mc.attack(smallpath,q,limited);
assert(strcmp(limited_path.states(1).metrics.status,'not_computed')&&isempty(limited_path.states(1).metrics.values)); checks=checks+1;
threshold=mc.metrics.first_threshold_fraction(smallpath,struct('trajectory',limited_path,'metric_id','adjacency_spectral_radius','threshold',0));
assert(strcmp(threshold.status,'not_computed')&&~threshold.valid_mask); checks=checks+1;
for unavailable={'failed','not_applicable','undefined'}
    fixture_path=limited_path;
    fixture_path.states(1).metrics.status=unavailable{1};
    [~,values,valid,details]=mc.attack_curve(fixture_path,'adjacency_spectral_radius');
    assert(isnan(values(1))&&~valid(1)&&strcmp(details.status{1},unavailable{1})); checks=checks+1;
end
malformed=limited_path; malformed.states(1).metrics.values=[1;2];
must_error(@()mc.attack_curve(malformed,'adjacency_spectral_radius'),'mc:InvalidSummaryMetric'); checks=checks+1;
must_error(@()mc.validate_protocol(struct('strategy','random','tie_break','random')),'mc:InvalidProtocol'); checks=checks+1;
must_error(@()mc.validate_protocol(struct('strategy','external','target','edge','tie_break','source_order')),'mc:InvalidProtocol'); checks=checks+1;
must_error(@()mc.validate_protocol(struct('strategy','source_order','target','edge','tie_break','source_order')),'mc:InvalidProtocol'); checks=checks+1;
q=struct('strategy','ranked','rank_metric',struct('metric_id','degree','parameters',struct()));
versioned=mc.validate_protocol(q); registry=mc.registry(); entry=registry(strcmp({registry.metric_id},'degree'));
assert(strcmp(versioned.rank_metric_version,entry.metric_version)); checks=checks+1;
q.rank_metric_version='invalid-version';
must_error(@()mc.validate_protocol(q),'mc:InvalidProtocol'); checks=checks+1;
must_error(@()mc.validate_protocol(struct('strategy','random','rank_metric_version','1.0.0')),'mc:InvalidProtocol'); checks=checks+1;
report=struct('suite','attacks','checks',checks,'elapsed_seconds',toc(t),'status','passed');
end

function y=scalars(a,id)
[~,y]=mc.attack_curve(a,id,'states');
end

function must_error(f,id)
try
    f();
catch ex
    assert(strcmp(ex.identifier,id),'Expected %s, got %s.',id,ex.identifier); return;
end
error('mc:Test','Expected error %s.',id);
end
