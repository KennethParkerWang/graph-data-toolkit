function r=betweenness(ctx,p)
%BETWEENNESS Shortest-path node betweenness with endpoints excluded
if nargin<2,p=struct;end
[node,edge]=mc.brandes(ctx);v=node;normed=mc.param(p,'normalized',false);validateattributes(normed,{'logical'},{'scalar'});
if normed
 den=((ctx.n-1)*(ctx.n-2));if ~ctx.directed,den=den/2;end
 if den>0,v=v/den;else,v(:)=NaN;end
end
r=mc.basic_result('betweenness',v,'node',ctx,'Requested normalization requires at least three nodes (node) or two (edge).');
end
