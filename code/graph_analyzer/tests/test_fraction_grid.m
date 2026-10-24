function report=test_fraction_grid()
%TEST_FRACTION_GRID Small analytic scheduling and result-integrity regressions.
t=tic; checks=0;
c=mc.context(sparse(1:7,2:8,1,8,8),true);
p=struct('version','1.1.0','deletion_mode','fraction_grid','target','edge', ...
    'strategy','external','external_sequence',1:7,'attack_fractions',[0 .1 .2 .3 .4 1], ...
    'sample_fractions',[0 .1 .2 .3 .4 .5 1]);
a=mc.attack(c,p,{'edge_count','node_count'});
assert(isequal([a.states.removed_count],[0 1 2 7])); checks=checks+1;
assert(isequal(a.schedule.requested_removed_count,[0;0;1;2;2;7])); checks=checks+1;
assert(isequal(a.schedule.increment,[0;0;1;1;0;5])); checks=checks+1;
assert(isequal(a.schedule.state_index,[1;1;2;3;3;4])); checks=checks+1;
assert(isequal(a.schedule.round_index,[0;0;1;2;2;3])); checks=checks+1;
assert(isequal(a.schedule.actual_removed_fraction,[0;0;1;2;2;7]/7)); checks=checks+1;
assert(isequal([a.sampled.state_index],[1 1 2 3 3 0 4])); checks=checks+1;
assert(~a.full_single_object_trajectory&&isequal(a.deleted_ids,uint64((1:7)'))); checks=checks+1;
assert(isequal([a.states.edge_count],[7 6 5 0])&&all([a.states.node_count]==8)); checks=checks+1;
q=p; q.sample_fractions=[.99 .6]; b=mc.attack(c,q,{'node_count'});
assert(isequal([a.states.removed_count],[b.states.removed_count])&&isequal(a.deleted_ids,b.deleted_ids)); checks=checks+1;
q=p; q.rounding='ceil'; b=mc.attack(c,q,{'node_count'});
assert(isequal(b.schedule.requested_removed_count,[0;1;2;3;3;7])); checks=checks+1;
q=p; q.rounding='nearest'; b=mc.attack(c,q,{'node_count'});
assert(isequal(b.schedule.requested_removed_count,[0;1;1;2;3;7])); checks=checks+1;
q=p; q.stop_fraction=.4; q.attack_fractions=[0 .1 .4]; b=mc.attack(c,q,{'edge_count'});
assert(isequal([b.states.removed_count],[0 2])&&~b.full_single_object_trajectory); checks=checks+1;
q=p; q.attack_fractions=(0:7)/7; b=mc.attack(c,q,{'edge_count'});
assert(b.full_single_object_trajectory&&numel(b.states)==8); checks=checks+1;
q=p; q.attack_fractions=1; b=mc.attack(c,q,{'edge_count'});
assert(isequal([b.states.removed_count],[0 7])&&b.schedule.increment==7); checks=checks+1;
q=p; q.stop_fraction=0; q.attack_fractions=[0 0]; b=mc.attack(c,q,{'edge_count'});
assert(numel(b.states)==1&&isequal(b.schedule.state_index,[1;1])); checks=checks+1;
% Zero increments are not deletion rounds; rank only on genuine batches.
A=sparse(1:4,2:5,1,5,5); pc=mc.context(A+A',false);
q=struct('version','1.1.0','deletion_mode','fraction_grid','attack_fractions',[0 .01 .2 .2 .6 1], ...
    'strategy','ranked','ranking','adaptive','rank_metric',struct('metric_id','degree','parameters',struct()));
b=mc.attack(pc,q,{'node_count'});
assert(isequal([b.states.removed_count],[0 1 3 5])); checks=checks+1;
assert(isequal(b.ranking_at_removed_count,[0;1;3])); checks=checks+1;
assert(isequal(b.deleted_ids,uint32([2;4;3;1;5]))); checks=checks+1;
q.recompute_interval=2; b=mc.attack(pc,q,{'node_count'});
assert(isequal(b.ranking_at_removed_count,[0;3])&&isequal(b.deleted_ids(1:3),uint32([2;3;4]))); checks=checks+1;
q=p; q.strategy='random'; q.external_sequence=[]; before=rng;
b=mc.attack(c,q,{'edge_count'},42,1); b2=mc.attack(c,q,{'edge_count'},42,2);
assert(isequal(before,rng)&&isequal(b.deleted_ids,b2.deleted_ids)); checks=checks+1;
% Empty populations preserve requested grid and explicitly undefined fractions.
z=mc.context(sparse(3,3),false); q=p; q.external_sequence=[];
b=mc.attack(z,q,{'node_count','edge_count'});
assert(numel(b.states)==1&&all(b.schedule.state_index==1)&&all(isnan(b.schedule.actual_removed_fraction))&&all(~b.schedule.fraction_valid)); checks=checks+1;
% Legacy normalization/IDs and legacy saved examples stay readable.
legacy=mc.validate_protocol(struct('strategy','random'));
assert(~isfield(legacy,'attack_fractions')&&strcmp(legacy.version,'1.0.0')); checks=checks+1;
assert(strcmp(mc.protocol_id(legacy),mc.protocol_id(struct('strategy','random')))); checks=checks+1;
root=fileparts(fileparts(mfilename('fullpath')));
fixtures=dir(fullfile(root,'examples','result_fixtures','metrics','**','*.mat'));
for j=1:numel(fixtures)
    loaded=load(fullfile(fixtures(j).folder,fixtures(j).name),'output'); mc.validate_output(loaded.output); checks=checks+1;
end
% Persistence and tampering use synthetic identities confined to validation.
identity=struct('graph_id',repmat('c',1,64),'topology_hash',repmat('d',1,64),'origin_graph_id',repmat('c',1,64));
o=mc.build_run(c,identity,{'edge_count'},struct('protocol',p)); mc.validate_output(o); checks=checks+1;
base=fullfile(root,'validation',['fraction_grid_',char(java.util.UUID.randomUUID())]); mkdir(base);
[record,~]=mc.save_run(base,o,'fraction_grid_test'); read=mc.verify_record(base,record);
assert(isequaln(read,o)); checks=checks+1;
bad=o; bad.attack.schedule.increment(end)=1; must_error(@()mc.validate_output(bad)); checks=checks+1;
bad=o; bad.attack.states(2).removed_count=5; must_error(@()mc.validate_output(bad)); checks=checks+1;
bad=o; bad.attack.full_single_object_trajectory=true; must_error(@()mc.validate_output(bad)); checks=checks+1;
% A matching hash cannot legalize a protocol that contradicts its stop/grid.
bad=o.attack; bad.protocol.stop_fraction=.5; bad.protocol_id=mc.identity(bad.protocol,'protocol-v1');
recipe=jsondecode(o.metric_set_identity_json);
must_error(@()mc.validate_attack_result(bad,recipe.configuration.selections,o.seeds)); checks=checks+1;
bad=o.attack; bad.protocol.attack_fractions=[0;1;.5;1]; bad.protocol_id=mc.identity(bad.protocol,'protocol-v1');
must_error(@()mc.validate_attack_result(bad,recipe.configuration.selections,o.seeds)); checks=checks+1;
for f={[],[.5 .3 1],[-.1 1],[0 NaN 1],[0 .9],[0 1.1],1i}
    bad=p; bad.attack_fractions=f{1}; must_error(@()mc.validate_protocol(bad)); checks=checks+1;
end
bad=p; bad.version='1.0.0'; must_error(@()mc.validate_protocol(bad)); checks=checks+1;
bad=p; bad=rmfield(bad,'version'); must_error(@()mc.validate_protocol(bad)); checks=checks+1;
bad=p; bad.batch_size=2; must_error(@()mc.validate_protocol(bad)); checks=checks+1;
bad=p; bad.deletion_mode='single'; must_error(@()mc.validate_protocol(bad)); checks=checks+1;
bad=p; bad.stop_fraction=.5; must_error(@()mc.validate_protocol(bad)); checks=checks+1;
report=struct('checks',checks,'seconds',toc(t),'status','passed','fixture_root',base);
end
function must_error(fn)
failed=false; try, fn(); catch, failed=true; end
assert(failed,'Expected validation failure.');
end
