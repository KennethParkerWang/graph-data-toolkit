function report = test_io()
%TEST_IO Tiny identity, persistence, resume, tampering and config checks.
t=tic; checks=0; root=fileparts(fileparts(mfilename('fullpath')));
c=mc.context(sparse([0 1 0;1 0 0;0 0 0]),false);
identity=struct('graph_id',repmat('a',1,64),'topology_hash',repmat('b',1,64),'origin_graph_id',repmat('a',1,64));
% Explicit synthetic identity fixture only; does not represent stored original graphs.
ids={'node_count','edge_count','degree','edge_betweenness','distance_matrix','global_efficiency'};
o=mc.build_run(c,identity,ids,struct()); mc.validate_output(o); checks=checks+1;
base=fullfile(root,'validation',['io_',char(java.util.UUID.randomUUID())]); mkdir(base);
[rec,resumed]=mc.save_run(base,o,'test'); assert(~resumed); checks=checks+1;
read=mc.verify_record(base,rec); assert(isequaln(read,o)); checks=checks+1;
[rec2,resumed]=mc.save_run(base,o,'test'); assert(resumed&&strcmp(rec.file_sha256,rec2.file_sha256)); checks=checks+1;
merged=mc.merge_manifests(base); assert(numel(merged)==1); checks=checks+1;
p=mc.plan_run(identity,ids,struct()); assert(strcmp(p.run_id,o.run_id)); checks=checks+1;
p2=mc.plan_run(identity,ids,struct('repeat_index',2)); assert(~strcmp(p.run_id,p2.run_id)); checks=checks+1;
assert(strcmp(mc.identity(struct('z',2,'a',1)),mc.identity(struct('a',1,'z',2)))); checks=checks+1;
must_error(@()mc.compute(c,{'invalid_metric'})); checks=checks+1;
must_error(@()mc.compute(c,struct('metric_id','degree','parameters',struct('typo',1)))); checks=checks+1;
must_error(@()mc.context([0 2;2 0],false)); checks=checks+1;
must_error(@()mc.safe_path(base,'../escape.mat')); checks=checks+1;
bad=o; bad.graph_id=repmat('c',1,64); must_error(@()mc.validate_output(bad)); checks=checks+1;
bad=o; bad.results(1).valid_mask=false(3,1); must_error(@()mc.validate_output(bad)); checks=checks+1;
badrec=rec; badrec.file_sha256=repmat('0',1,64); must_error(@()mc.verify_record(base,badrec)); checks=checks+1;
sel=struct('metric_id','edge_count','parameters',struct());
r=mc.metrics.deletion_impact(c,struct('base_metric',sel)); assert(isequal(r.values,[1;1;0])); checks=checks+1;
r=mc.metrics.deletion_impact(c,struct('base_metric',sel,'target','edge')); assert(r.values==1&&isequal(r.axis_ids{1},c.edge_ids)); checks=checks+1;
z=mc.context(sparse(2,2),false); r=mc.metrics.deletion_impact(z,struct('base_metric',sel,'relative',true)); assert(all(~r.valid_mask)); checks=checks+1;
protocol=struct('target','node','strategy','external','external_sequence',[2;1;3],'sample_fractions',[0;.1;.2;1]);
options=struct('protocol',protocol); a=mc.build_run(c,identity,{'node_count','edge_count','largest_component_size'},options);
mc.validate_output(a); [ar,~]=mc.save_run(base,a,'test'); aa=mc.verify_record(base,ar); assert(isequaln(aa,a)); checks=checks+1;
bad=a; bad.attack.states=[]; must_error(@()mc.validate_output(bad)); checks=checks+1;
bad=a; bad.attack.states(1).metrics(1).metric_id='tampered'; must_error(@()mc.validate_output(bad)); checks=checks+1;
bad=a; bad.attack.states(2).remaining_node_ids(1)=999; must_error(@()mc.validate_output(bad)); checks=checks+1;
bad=a; bad.attack.sampled(1).actual_removed_count=2; must_error(@()mc.validate_output(bad)); checks=checks+1;
bad=o; bad.results(3).values(1)=NaN; must_error(@()mc.validate_output(bad)); checks=checks+1;
bad=o; bad.results(3).axis_names={}; bad.results(3).axis_ids={}; must_error(@()mc.validate_output(bad)); checks=checks+1;
bad=o; bad.results(1).status='failed'; must_error(@()mc.validate_output(bad)); checks=checks+1;
numeric_base=struct('metric_id','exact_numeric_driver_count','parameters',struct('state_matrix',full(c.A')));
must_error(@()mc.metrics.deletion_impact(c,struct('base_metric',numeric_base,'target','edge'))); checks=checks+1;
report=struct('name','io','checks',checks,'seconds',toc(t),'fixture_root',base,'status','passed');
end
function must_error(fn)
failed=false; try, fn(); catch, failed=true; end
assert(failed,'Expected validation failure.');
end
