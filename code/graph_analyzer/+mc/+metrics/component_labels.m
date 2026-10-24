function r=component_labels(ctx,p)
%COMPONENT_LABELS component labels
if nargin<2,p=struct;end
[labels,sizes]=mc.components(ctx,mc.param(p,'component_mode','weak'));
r=mc.basic_result('component_labels',labels,'node',ctx,'');
end
