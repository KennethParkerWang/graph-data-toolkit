function report=test_basic()
%TEST_BASIC Analytic families, NetworkX 3.5 references, 64 triads and relabeling.
root=fileparts(fileparts(mfilename('fullpath')));addpath(root);
refs=jsondecode(fileread(fullfile(root,'validation','basic_reference.json')));
reg=jsondecode(fileread(fullfile(root,'registry','basic.json')));checks=0;started=tic;
for f=1:numel(refs.fixtures)
 z=refs.fixtures(f);A=sparse(z.n,z.n);el=z.edges;
 if ~isempty(el),A=sparse(el(:,1)+1,el(:,2)+1,1,z.n,z.n);if ~z.directed,A=A+A';end,end
 c=mc.context(A,z.directed);names=fieldnames(z.expected);
 for j=1:numel(names)
  id=names{j};p=struct;if strcmp(id,'katz'),p.alpha=.1;end
  fun=str2func(['mc.metrics.' id]);r=fun(c,p);expected=z.expected.(id);
  assert(strcmp(r.status,'ok'),'%s/%s status %s: %s',z.name,id,r.status,r.reason);
  close(r.values,expected,1e-8,[z.name '/' id]);checks=checks+1;
 end
 % Invoke every supported basic metric via direct API and registry dispatcher.
 for j=1:numel(reg)
  e=reg(j);kind='undirected';if c.directed,kind='directed';end
  if ~ismember(kind,cellstr(string(e.graph_types))),continue;end
  p=e.parameter_defaults;if strcmp(e.metric_id,'katz'),p.alpha=.1;end
  fun=str2func(['mc.metrics.' e.metric_id]);r=fun(c,p);
  assert(~strcmp(r.status,'failed'),'%s failed on %s: %s',e.metric_id,z.name,r.reason);
  assert(isequal(size(r.values),size(r.valid_mask)),'Mask shape mismatch');
  for axis=1:numel(r.axis_ids),assert(numel(r.axis_ids{axis})==size(r.values,axis),'Axis length mismatch: %s',e.metric_id);end
  got=mc.compute(c,struct('metric_id',e.metric_id,'parameters',p));
  assert(strcmp(got.status,r.status),'Dispatcher differs for %s: %s',e.metric_id,got.reason);
  assert(isequaln(got.values,r.values),'Dispatcher values differ for %s',e.metric_id);checks=checks+1;
 end
 % Component memberships agree with reachability, including isolated nodes.
 [lab,sz]=mc.components(c,'weak');assert(sum(sz)==c.n);
 for aa=1:c.n,for bb=1:c.n
  weakA=spones(c.A+c.A');weakG=graph(weakA);dd=distances(weakG,aa,bb);assert(isfinite(dd)==(lab(aa)==lab(bb)));
 end,end
 % Permute node rows and IDs; preserve original edge IDs exactly.
 if c.n>1
  perm=c.n:-1:1;inverse=zeros(c.n,1);inverse(perm)=1:c.n;
  mapped=inverse(double(c.edge_list));if ~c.directed,mapped=sort(mapped,2);end
  cp=mc.context(A(perm,perm),c.directed,c.node_ids(perm),mapped,c.edge_ids);
  for id={'degree','core_number','closeness','harmonic','betweenness','clustering','pagerank'}
   fun=str2func(['mc.metrics.' id{1}]);x=fun(c,struct);y=fun(cp,struct);
   close(y.values,x.values(perm),1e-9,['permutation/' id{1}]);assert(isequal(y.axis_ids{1},c.node_ids(perm)));checks=checks+1;
  end
  x=mc.metrics.edge_betweenness(c,struct);y=mc.metrics.edge_betweenness(cp,struct);close(y.values,x.values,1e-10,'edge ID preservation');checks=checks+1;
  x=mc.metrics.distance_matrix(c,struct);y=mc.metrics.distance_matrix(cp,struct);assert(isequal(x.values(perm,perm),y.values));checks=checks+1;
 end
end
% Exhaustive induced triad classification: 64 adjacency patterns.
pairs=[1 2;2 1;1 3;3 1;2 3;3 2];
for code=0:63
 ix=logical(bitget(code,1:6));A=sparse(pairs(ix,1),pairs(ix,2),1,3,3);c=mc.context(A,true);r=mc.metrics.triad_census(c,struct);
 expected=refs.triad_types_64{code+1};actual=r.axis_ids{1}{find(r.values)};
 assert(strcmp(expected,actual),'Triad classification code %d',code);assert(sum(r.values)==1);checks=checks+1;
end
% Empty/singleton and unreachable conventions are intentional, not fake zeros.
c=mc.context(sparse(0,0),false);
for id={'density','global_efficiency','average_path_length','degree_mean','degree_variance','degree_heterogeneity','average_clustering','radius','diameter','largest_component_fraction'}
 fun=str2func(['mc.metrics.' id{1}]);r=fun(c,struct);assert(strcmp(r.status,'undefined'));checks=checks+1;
end
c=mc.context(sparse(3,3),false);r=mc.metrics.eccentricity(c,struct);assert(all(isinf(r.values))&&all(r.valid_mask));checks=checks+1;
r=mc.metrics.transitivity(c,struct);assert(strcmp(r.status,'undefined'));checks=checks+1;
A=sparse([1 2],[2 3],1,3,3);c=mc.context(A,true);
r=mc.metrics.average_path_length(c,struct('pair_policy','reachable'));close(r.values,4/3,1e-12,'reachable path length');checks=checks+1;
r=mc.metrics.closeness(c,struct('direction','in'));close(r.values,[0;.5;2/3],1e-12,'in-closeness');checks=checks+1;
r=mc.metrics.harmonic(c,struct('direction','in','normalized',true));close(r.values,[0;.5;.75],1e-12,'in-harmonic');checks=checks+1;
r=mc.metrics.component_count(c,struct('component_mode','strong'));assert(r.values==3);checks=checks+1;
r=mc.metrics.eigenvector(c,struct);assert(strcmp(r.status,'undefined'));checks=checks+1;
% Brandes normalizations and custom edge ordering.
c=mc.context(sparse([1 2 2 3],[2 1 3 2],1,3,3),false,uint32([10;20;30]),uint32([2 3;1 2]),uint64([91;72]));
r=mc.metrics.betweenness(c,struct('normalized',true));close(r.values,[0;1;0],1e-12,'normalized betweenness');checks=checks+1;
r=mc.metrics.edge_betweenness(c,struct('normalized',true));close(r.values,[2/3;2/3],1e-12,'normalized edge betweenness');assert(isequal(r.axis_ids{1},uint64([91;72])));checks=checks+1;
% HITS equations and deterministic repeated-singular-value convention.
c=mc.context(sparse([1 1 2],[2 3 3],1,3,3),true);r=mc.metrics.hits(c,struct);assert(strcmp(r.status,'ok'));h=r.values(:,1);a=r.values(:,2);close(c.A*a/sum(c.A*a),h,1e-9,'HITS hubs');close(c.A'*h/sum(c.A'*h),a,1e-9,'HITS authorities');checks=checks+2;
r=mc.metrics.pagerank(c,struct('max_iterations',1,'tolerance',1e-15));assert(strcmp(r.status,'failed'));checks=checks+1;
% Explicit size limits and parameter-domain failures must be visible.
try,mc.metrics.katz(c,struct('alpha',-1));error('test:ExpectedFailure','Missing failure');catch e,assert(~strcmp(e.identifier,'test:ExpectedFailure'));end;checks=checks+1;
try,mc.metrics.distance_matrix(c,struct('max_nodes',2));error('test:ExpectedFailure','Missing failure');catch e,assert(strcmp(e.identifier,'mc:SizeLimit'));end;checks=checks+1;
report=struct('checks',checks,'fixtures',numel(refs.fixtures),'exhaustive_triads',64,'seconds',toc(started),'tolerance',1e-8,'reference',refs.reference);
fprintf('test_basic PASS: %d checks, %.3f seconds\n',checks,report.seconds);
end
function close(actual,expected,tol,label)
assert(numel(actual)==numel(expected),'%s element count mismatch',label);
if isempty(actual),return;end
if isequal(size(actual),size(expected)),d=abs(double(actual)-double(expected));else,d=abs(double(actual(:))-double(expected(:)));end
assert(all(d(:)<=tol*max(1,max(abs(double(expected(:)))))),'%s numerical mismatch: maximum error %.3g',label,max(d(:)));
end
