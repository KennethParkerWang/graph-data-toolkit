function r=bridge_mask(ctx,p)
%BRIDGE_MASK bridge mask
if nargin<2,p=struct;end
[b,a]=mc.basic_cuts(ctx);
r=mc.basic_result('bridge_mask',b,'edge',ctx,'');
end
