function report = test_advanced()
%TEST_ADVANCED Analytic values, semantics, independent sprank, and permutation.
started=tic; checks=0; tolerance=1e-9;
P=diag(ones(3,1),1); P=P+P.'; path=mc.context(P,false);
C=P; C(1,4)=1; C(4,1)=1; cycle=mc.context(C,false);
S=zeros(5); S(1,2:5)=1; S=S+S.'; star=mc.context(S,false);
K=ones(4)-eye(4); complete=mc.context(K,false);
empty=mc.context(sparse(0,0),false); singleton=mc.context(sparse(1,1),false);
isolates=mc.context(sparse(3,3),false);
near(value('degree_assortativity',path),-0.5);
near(value('degree_assortativity',star),-1);
assert(strcmp(run('degree_assortativity',cycle).status,'undefined')); checks=checks+1;
near(value('average_neighbor_degree',path),[2;1.5;1.5;2]);
near(value('average_neighbor_degree',star),[1;4;4;4;4]);
assert(~any(run('average_neighbor_degree',isolates).valid_mask)); checks=checks+1;
rich=run('rich_club',path); near(rich.values(1:2),[0.5;1]); assert(~rich.valid_mask(3)); checks=checks+1;
near(value('modularity',path,struct('partition',[1 1 2 2])),1/6);
near(value('modularity',path,struct('partition',[1 1 1 1])),0);
near(value('community_sizes',path,struct('partition',[9 9 -1 -1])),[2;2]);
g=run('greedy_modularity_communities',path); near(g.details.modularity,1/6);
near(g.values,[1;1;3;3]); assert(all(g.details.merges(:,3)>0)); checks=checks+1;
near(value('adjacency_spectral_radius',path),2*cos(pi/5));
near(value('adjacency_spectral_radius',star),2);
near(value('adjacency_spectrum',complete),[-1;-1;-1;3]);
near(value('laplacian_spectrum',path),2-2*cos((0:3)'*pi/4));
near(value('algebraic_connectivity',cycle),2);
near(value('algebraic_connectivity',complete),4);
near(value('algebraic_connectivity',isolates),0);
near(value('natural_connectivity',complete),log((exp(3)+3*exp(-1))/4));
near(value('natural_connectivity',isolates),0);
near(value('effective_resistance',path),abs((1:4)'-(1:4)));
near(value('kirchhoff_index',path),10);
near(value('kirchhoff_index',cycle),5);
near(value('effective_resistance',complete),(ones(4)-eye(4))/2);
near(value('kirchhoff_index',complete),3);
near(value('kirchhoff_index',singleton),0);
multi=mc.context(blkdiag([0 1;1 0],0),false); resistance=run('effective_resistance',multi);
assert(isinf(resistance.values(1,3)) && all(resistance.valid_mask(:))); checks=checks+1;
assert(isinf(value('kirchhoff_index',multi))); checks=checks+1;
assert(strcmp(run('natural_connectivity',empty).status,'undefined')); checks=checks+1;
assert(strcmp(run('algebraic_connectivity',singleton).status,'undefined')); checks=checks+1;
assert(isempty(value('adjacency_spectrum',empty))); checks=checks+1;
assert(strcmp(run('adjacency_spectrum',path,struct('max_nodes',3)).status,'not_computed')); checks=checks+1;
assert(strcmp(run('reciprocity',path).status,'not_applicable')); checks=checks+1;
D=[0 1 1 0;1 0 1 0;0 0 0 1;0 0 0 0]; directed=mc.context(D,true);
near(value('reciprocity',directed),2/5);
for source={'in','out'}
    for target={'in','out'}
        [u,v]=find(D); di=sum(D,1).'; dout=sum(D,2);
        if strcmp(source{1},'in'), x=di(u); else, x=dout(u); end
        if strcmp(target{1},'in'), y=di(v); else, y=dout(v); end
        independent=corrcoef(x,y);
        near(value('degree_assortativity',directed,struct('source_degree',source{1},'target_degree',target{1})),independent(1,2));
    end
end
neighbor=run('average_neighbor_degree',directed,struct('neighbor_mode','all','target_degree','total'));
near(neighbor.values,[3;3;7/3;3]);
dc=mc.context([0 1 0;0 0 1;1 0 0],true);
near(value('adjacency_spectral_radius',dc),1);
spectrum=value('adjacency_spectrum',dc); near(sum(spectrum.^3),3);
assert(any(abs(imag(spectrum))>0.5)); checks=checks+1;
assert(strcmp(run('laplacian_spectrum',dc).status,'not_applicable')); checks=checks+1;
chain=mc.context(diag(ones(3,1),1),true); near(value('structural_driver_count',chain),1);
control=run('structural_driver_count',chain); near(double(control.details.unmatched_node_ids),1);
near(value('structural_dedicated_feasibility',chain,struct('driver_node_ids',1)),1);
near(value('structural_dedicated_feasibility',chain,struct('driver_node_ids',4)),0);
outstar=mc.context(triu(S,1),true); near(value('structural_driver_count',outstar),4);
two_cycles=mc.context(blkdiag([0 1;1 0],[0 1;1 0]),true);
general=run('structural_driver_count',two_cycles); near(general.values,1);
near(nnz(general.details.input_pattern),2);
near(value('structural_dedicated_feasibility',two_cycles,struct('driver_node_ids',1)),0);
near(value('structural_dedicated_feasibility',two_cycles,struct('driver_node_ids',[1 3])),1);
near(value('structural_driver_count',mc.context(sparse(3,3),true)),3);
near(value('structural_driver_count',mc.context(sparse(0,0),true)),0);
near(value('structural_dedicated_feasibility',mc.context(sparse(0,0),true),struct('driver_node_ids',[])),1);
assert(strcmp(run('structural_driver_count',path).status,'not_applicable')); checks=checks+1;
numericctx=mc.context(sparse(3,3),true);
near(value('exact_numeric_driver_count',numericctx,struct('state_matrix',diag([1 1 2]))),2);
near(value('exact_numeric_driver_count',numericctx,struct('state_matrix',[1 1 0;0 1 1;0 0 1])),1);
near(value('exact_numeric_driver_count',numericctx,struct('state_matrix',zeros(3))),3);
near(value('exact_numeric_driver_count',mc.context(sparse(2,2),true),struct('state_matrix',[0 -1;1 0])),1);
near(value('exact_numeric_driver_count',numericctx,struct('state_matrix',diag([1 1+1e-5 2]))),1);
near(value('exact_numeric_driver_count',numericctx,struct('state_matrix',diag([1 1+1e-5 2]),'rank_tolerance',1e-3,'eigenvalue_tolerance',1e-3)),2);
% All 64 simple directed graphs on 3 labeled nodes: compare matching to sprank.
locations=find(~eye(3));
for bits=0:63
    T=zeros(3); T(locations)=bitget(bits,1:6);
    [left,right,count]=mc.maximum_matching(T);
    assert(count==sprank(sparse(T)) && nnz(left)==count && nnz(right)==count); checks=checks+1;
    current=mc.context(T,true); r=run('structural_driver_count',current);
    near(r.values,max(1,3-sprank(sparse(T))));
    pattern=double(r.details.input_pattern);
    assert(sprank([sparse(T);sparse(pattern.')])==3); checks=checks+1;
end
% Structural matcher also accepts rectangular incidence, zero rows/columns.
near(mc_matching_count([1 1 0;1 0 0;0 1 1;0 0 1]),3);
near(mc_matching_count(zeros(0,3)),0); near(mc_matching_count(zeros(3,0)),0);
% Permuting storage order while preserving original IDs preserves vectors/matrices.
permutation=[3 1 4 2]; original=mc.context(P,false,uint32([40 10 30 20]));
relabeled=mc.context(P(permutation,permutation),false,original.node_ids(permutation));
for id={'degree_assortativity','adjacency_spectral_radius','algebraic_connectivity','natural_connectivity','kirchhoff_index'}
    near(value(id{1},original),value(id{1},relabeled));
end
for id={'average_neighbor_degree','greedy_modularity_communities'}
    x=value(id{1},original); near(value(id{1},relabeled),x(permutation));
end
x=value('effective_resistance',original); near(value('effective_resistance',relabeled),x(permutation,permutation));
partition=[1 1 2 2]; near(value('modularity',original,struct('partition',partition)),...
    value('modularity',relabeled,struct('partition',partition(permutation))));
permuted_chain=mc.context(chain.A(permutation,permutation),true,chain.node_ids(permutation));
near(value('structural_driver_count',chain),value('structural_driver_count',permuted_chain));
near(value('structural_dedicated_feasibility',permuted_chain,struct('driver_node_ids',1)),1);
% Every registry entry routes through the unified dispatcher.
entries=jsondecode(fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))),'registry','advanced.json')));
% Synthetic identities identify in-memory test fixtures only, never saved graphs.
identity=struct('graph_id',repmat('a',1,64),'topology_hash',repmat('b',1,64),'origin_graph_id',repmat('a',1,64));
envelope_checks=0;
dispatch_seconds=zeros(numel(entries),1);
for i=1:numel(entries)
    ctx=path; params=struct();
    if ismember(entries(i).metric_id,{'reciprocity','structural_driver_count','structural_dedicated_feasibility'}), ctx=chain; end
    if ismember(entries(i).metric_id,{'modularity','community_sizes'}), params.partition=[1 1 2 2]; end
    if strcmp(entries(i).metric_id,'structural_dedicated_feasibility'), params.driver_node_ids=1; end
    if strcmp(entries(i).metric_id,'exact_numeric_driver_count'), params.state_matrix=diag([1 1 2 3]); end
    result=mc.compute(ctx,struct('metric_id',entries(i).metric_id,'parameters',params));
    dispatch_seconds(i)=result.elapsed_seconds;
    assert(~ismember(result.status,{'failed','not_computed'}),result.reason); checks=checks+1;
    assert(strcmp(result.method,entries(i).method)); checks=checks+1;
    output=mc.build_run(ctx,identity,struct('metric_id',entries(i).metric_id,'parameters',params));
    mc.validate_output(output); envelope_checks=envelope_checks+1;
    if isfield(entries(i).parameter_defaults,'max_nodes')
        params.max_nodes=0;
        result=run(entries(i).metric_id,ctx,params);
        assert(strcmp(result.status,'not_computed') && isempty(result.axis_names) && isempty(result.axis_ids)); checks=checks+1;
        output=mc.build_run(ctx,identity,struct('metric_id',entries(i).metric_id,'parameters',params));
        mc.validate_output(output); envelope_checks=envelope_checks+1;
    end
end
reference_checks=0;
reference_path=fullfile(fileparts(fileparts(mfilename('fullpath'))),'validation','advanced_reference.json');
if isfile(reference_path)
    refs=jsondecode(fileread(reference_path));
    for i=1:numel(refs.cases)
        ref=refs.cases(i); ctx=mc.context(ref.adjacency,ref.directed);
        for j=1:numel(ref.expected)
            e=ref.expected(j); actual=run(e.metric_id,ctx,e.parameters);
            expected=double(e.values); if isvector(actual.values), expected=expected(:); end
            if isfield(e,'imaginary') && ~isempty(e.imaginary), expected=expected+1i*double(e.imaginary(:)); end
            near(actual.values,expected); reference_checks=reference_checks+1;
        end
    end
end
report=struct('passed',true,'checks',checks,'reference_checks',reference_checks,'envelope_checks',envelope_checks,...
    'elapsed_seconds',toc(started),'tolerance',tolerance,...
    'dispatch_metric_ids',{{entries.metric_id}},'dispatch_seconds',dispatch_seconds,...
    'details','17 metric dispatches; analytic families; 64 directed matching cases; relabeling; optional fixed NetworkX/SciPy fixtures');
    function r=run(id,ctx,p)
        if nargin<3, p=struct(); end
        fn=str2func(['mc.metrics.' id]); r=fn(ctx,p);
    end
    function out=value(id,ctx,p)
        if nargin<3, p=struct(); end
        r=run(id,ctx,p); out=r.values;
    end
    function near(actual,expected)
        assert(isequal(size(actual),size(expected)) || (isscalar(actual)&&isscalar(expected)),'Shape mismatch.');
        assert(all(abs(double(actual(:))-double(expected(:)))<=tolerance*max(1,max(abs(double(expected(:)))))), 'Numerical value mismatch.');
        checks=checks+1;
    end
end
function count=mc_matching_count(A)
[~,~,count]=mc.maximum_matching(A);
end
