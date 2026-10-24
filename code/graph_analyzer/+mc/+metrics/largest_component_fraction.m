function r=largest_component_fraction(ctx,p)
%LARGEST_COMPONENT_FRACTION largest component fraction
if nargin<2,p=struct;end
[labels,sizes]=mc.components(ctx,mc.param(p,'component_mode','weak'));
r=mc.basic_result('largest_component_fraction',max([0;sizes])/ctx.n,'graph',ctx,'Requires at least one node; denominator is current N.');
end
