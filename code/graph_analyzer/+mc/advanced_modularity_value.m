function q = advanced_modularity_value(ctx,labels,gamma)
%ADVANCED_MODULARITY_VALUE Community-summed Newman/Leicht modularity.
if ctx.m==0, q=NaN; return; end
dout=full(sum(ctx.A,2)); din=full(sum(ctx.A,1)).';
q=0;
for c=unique(labels(:)).'
    nodes=labels==c;
    if ctx.directed
        within=nnz(ctx.A(nodes,nodes));
        expected=sum(dout(nodes))*sum(din(nodes))/ctx.m^2;
    else
        within=nnz(ctx.A(nodes,nodes))/2;
        expected=(sum(dout(nodes))/(2*ctx.m))^2;
    end
    q=q+within/ctx.m-gamma*expected;
end
end
