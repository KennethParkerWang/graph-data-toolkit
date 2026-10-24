function r=articulation_mask(ctx,p)
%ARTICULATION_MASK articulation mask
if nargin<2,p=struct;end
[b,a]=mc.basic_cuts(ctx);
r=mc.basic_result('articulation_mask',a,'node',ctx,'');
end
