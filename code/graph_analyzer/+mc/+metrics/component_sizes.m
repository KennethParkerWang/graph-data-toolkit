function r=component_sizes(ctx,p)
%COMPONENT_SIZES component sizes
if nargin<2,p=struct;end
[labels,sizes]=mc.components(ctx,mc.param(p,'component_mode','weak'));
r=mc.make_result('component_sizes',sizes,'distribution',{'component'},{(1:numel(sizes))'});
end
