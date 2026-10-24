function r=edge_betweenness(ctx,p)
%EDGE_BETWEENNESS Shortest-path edge betweenness with endpoints excluded
if nargin<2,p=struct;end
[node,edge]=mc.brandes(ctx);v=edge;normed=mc.param(p,'normalized',false);validateattributes(normed,{'logical'},{'scalar'});
if normed
 den=(ctx.n*(ctx.n-1));if ~ctx.directed,den=den/2;end
 if den>0,v=v/den;else,v(:)=NaN;end
end
r=mc.basic_result('edge_betweenness',v,'edge',ctx,'Requested normalization requires at least three nodes (node) or two (edge).');
end
