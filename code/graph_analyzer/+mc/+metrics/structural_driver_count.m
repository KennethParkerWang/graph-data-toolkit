function r = structural_driver_count(ctx,~)
%STRUCTURAL_DRIVER_COUNT Minimum GENERAL independent inputs, free parameters.
% One input column can connect to multiple states to ensure accessibility.
% This is not the minimum count of dedicated node actuators.
if ~ctx.directed
    r=mc.make_result('structural_driver_count',[],'graph',{}, {},[],'not_applicable','Directed independent-parameter structure required; no automatic bidirection conversion.'); return
end
s=mc.advanced_control_structure(ctx);
if ctx.n==0, count=0; ratio=NaN; else, count=max(1,ctx.n-s.matching_size); ratio=count/ctx.n; end
input_rows=zeros(numel(s.unmatched)+numel(s.source_components),1);
input_columns=zeros(size(input_rows)); links=numel(s.unmatched);
input_rows(1:links)=s.unmatched; input_columns(1:links)=(1:links).';
% Add fanout from the first input to source SCCs not already actuated.
for k=1:numel(s.source_components)
    source=s.source_components(k);
    if ~any(s.component(s.unmatched)==source)
        links=links+1; input_rows(links)=s.representatives(k); input_columns(links)=1;
    end
end
B=sparse(input_rows(1:links),input_columns(1:links),ones(links,1),ctx.n,count);
[~,~,augmented]=mc.maximum_matching([ctx.A; B.']);
if augmented~=ctx.n, error('mc:InternalError','Constructed general input pattern fails full matching.'); end
r=mc.make_result('structural_driver_count',count,'graph',{});
r.details=struct('input_model','general independent inputs; each column may drive multiple states',...
    'system','xdot=A_state*x+B*u; A_state pattern equals ctx.A transpose',...
    'matching_size',s.matching_size,'unmatched_node_ids',ctx.node_ids(s.unmatched),...
    'source_scc_count',numel(s.source_components),'source_scc_representative_node_ids',ctx.node_ids(s.representatives),...
    'input_pattern',logical(B),'input_pattern_row_node_ids',ctx.node_ids,...
    'driver_ratio',ratio,'accessibility','each source SCC receives an input; fanout permitted',...
    'parameter_model','generic independent nonzero values; not all numerical realizations');
end
