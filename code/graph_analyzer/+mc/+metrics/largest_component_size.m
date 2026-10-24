function r=largest_component_size(ctx,p)
%LARGEST_COMPONENT_SIZE largest component size
if nargin<2,p=struct;end
[labels,sizes]=mc.components(ctx,mc.param(p,'component_mode','weak'));
r=mc.basic_result('largest_component_size',max([0;sizes]),'graph',ctx,'');
end
