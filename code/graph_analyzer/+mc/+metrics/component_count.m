function r=component_count(ctx,p)
%COMPONENT_COUNT component count
if nargin<2,p=struct;end
[labels,sizes]=mc.components(ctx,mc.param(p,'component_mode','weak'));
r=mc.basic_result('component_count',numel(sizes),'graph',ctx,'');
end
