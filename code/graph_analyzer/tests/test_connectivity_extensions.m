function report=test_connectivity_extensions()
%TEST_CONNECTIVITY_EXTENSIONS Analytic edge and directed weak/strong sums.
t=tic; checks=0;
weak=struct('metric_id','largest_component_size','parameters',struct('component_mode','weak'));
strong=struct('metric_id','largest_component_size','parameters',struct('component_mode','strong'));
both=[weak;strong];
dc=mc.context(sparse([1 2 3],[2 3 1],1,3,3),true);
p=struct('target','edge','strategy','external','external_sequence',[1 2 3]);
a=mc.attack(dc,p,both);
[~,yw]=mc.attack_curve(a,weak); [~,ys]=mc.attack_curve(a,strong);
assert(isequal(yw,[3;3;2;1])&&isequal(ys,[3;1;1;1])); checks=checks+1;
rw=mc.summarize(dc,a,struct('metric_id','connectivity_robustness','parameters',struct('component_mode','weak')));
rs=mc.summarize(dc,a,struct('metric_id','connectivity_robustness','parameters',struct('component_mode','strong')));
assert(abs(rw.values-2/3)<1e-14&&abs(rs.values-1/3)<1e-14); checks=checks+1;
assert(rw.details.outer_denominator==3&&rw.details.component_denominator==3&&~rw.details.includes_initial_state); checks=checks+1;
must_error(@()mc.attack_curve(a,'largest_component_size')); checks=checks+1;
versioned=strong; versioned.metric_version='1.0.0'; [~,y]=mc.attack_curve(a,versioned); assert(isequal(y,ys)); checks=checks+1;
bad=a; bad.states(2).metrics(1).metric_version='99'; must_error(@()mc.attack_curve(bad,weak)); checks=checks+1;
% A directed path splits strongly at baseline, but remains weakly connected.
dc=mc.context(sparse(1:3,2:4,1,4,4),true);
p=struct('strategy','external','external_sequence',[4 3 2 1]); a=mc.attack(dc,p,both);
rw=mc.metrics.connectivity_robustness(dc,struct('trajectory',a,'component_mode','weak'));
rs=mc.metrics.connectivity_robustness(dc,struct('trajectory',a,'component_mode','strong'));
assert(abs(rw.values-6/16)<1e-14&&abs(rs.values-3/16)<1e-14); checks=checks+1;
assert(rw.details.normalized_curve(end)==0); checks=checks+1;
% AUC/threshold can independently select weak and strong in one trajectory.
sel=struct('metric_id','sampled_curve_auc','parameters',struct('metric_id','largest_component_size','metric_parameters',strong.parameters,'source','states'));
r=mc.summarize(dc,a,sel); assert(abs(r.values-7/8)<1e-14); checks=checks+1;
sel=struct('metric_id','first_threshold_fraction','parameters',struct('metric_id','largest_component_size','metric_parameters',weak.parameters,'threshold',2));
r=mc.summarize(dc,a,sel); assert(r.values==.5); checks=checks+1;
sel.parameters.metric_parameters=strong.parameters; r=mc.summarize(dc,a,sel); assert(r.values==0); checks=checks+1;
% Undirected edge P3: largest components after edge removals are 2,1.
A=sparse(1:2,2:3,1,3,3); pc=mc.context(A+A',false);
p=struct('target','edge','strategy','external','external_sequence',[1 2]); a=mc.attack(pc,p,weak);
r=mc.metrics.connectivity_robustness(pc,struct('trajectory',a));
assert(abs(r.values-.5)<1e-14&&r.details.raw_largest_component_size(end)==1); checks=checks+1;
% K3 edges: 3,2,1 -> 2/3, with isolates retained in N0.
kc=mc.context(sparse(ones(3)-eye(3)),false); p.external_sequence=1:3; a=mc.attack(kc,p,weak);
r=mc.metrics.connectivity_robustness(kc,struct('trajectory',a)); assert(abs(r.values-2/3)<1e-14); checks=checks+1;
% Center-first star edges: 3,2,1 -> 1/2 for original N0=4.
A=sparse(ones(1,3),2:4,1,4,4); sc=mc.context(A+A',false); a=mc.attack(sc,p,weak);
r=mc.metrics.connectivity_robustness(sc,struct('trajectory',a)); assert(abs(r.values-.5)<1e-14); checks=checks+1;
p.deletion_mode='batch'; p.batch_size=2; a=mc.attack(sc,p,weak);
r=mc.metrics.connectivity_robustness(sc,struct('trajectory',a)); assert(strcmp(r.status,'not_applicable')); checks=checks+1;
p=struct('strategy','external','external_sequence',1:4); a=mc.attack(sc,p,weak);
r=mc.metrics.connectivity_robustness(sc,struct('trajectory',a)); assert(strcmp(r.status,'not_applicable')); checks=checks+1;
z=mc.context(sparse(3,3),false); p.target='edge'; p.external_sequence=[]; a=mc.attack(z,p,weak);
r=mc.metrics.connectivity_robustness(z,struct('trajectory',a)); assert(strcmp(r.status,'undefined')); checks=checks+1;
p=struct('target','edge','strategy','external','external_sequence',1:2); a=mc.attack(pc,p,strong);
r=mc.metrics.connectivity_robustness(pc,struct('trajectory',a,'component_mode','strong')); assert(strcmp(r.status,'not_applicable')); checks=checks+1;
a=mc.attack(pc,p,{'node_count'}); r=mc.metrics.connectivity_robustness(pc,struct('trajectory',a));
assert(strcmp(r.status,'not_computed')&&~r.valid_mask); checks=checks+1;
different=mc.context(sparse(ones(3)-eye(3)),false); must_error(@()mc.metrics.connectivity_robustness(different,struct('trajectory',a))); checks=checks+1;
report=struct('checks',checks,'seconds',toc(t),'status','passed');
end
function must_error(fn)
failed=false; try, fn(); catch, failed=true; end
assert(failed,'Expected validation failure.');
end
