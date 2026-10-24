function r=second_largest_component_size(ctx,p)
%SECOND_LARGEST_COMPONENT_SIZE second largest component size
if nargin<2,p=struct;end
[labels,sizes]=mc.components(ctx,mc.param(p,'component_mode','weak'));
s=sort([0;0;sizes],'descend');r=mc.basic_result('second_largest_component_size',s(2),'graph',ctx,'');
end
