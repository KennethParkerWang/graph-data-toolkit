function r = average_neighbor_degree(ctx,p)
%AVERAGE_NEIGHBOR_DEGREE Mean target degree over distinct selected neighbors.
if nargin<2, p=struct(); end
mode=char(mc.param(p,'neighbor_mode','out')); target=char(mc.param(p,'target_degree','total'));
if ~ismember(mode,{'in','out','all'}) || ~ismember(target,{'in','out','total'})
    error('mc:InvalidParameter','Invalid neighbor_mode or target_degree.');
end
if ~ctx.directed
    W=ctx.A; d=full(sum(ctx.A,2));
else
    switch mode
        case 'in', W=ctx.A.';
        case 'out', W=ctx.A;
        case 'all', W=spones(ctx.A+ctx.A.');
    end
    switch target
        case 'in', d=full(sum(ctx.A,1)).';
        case 'out', d=full(sum(ctx.A,2));
        case 'total', d=full(sum(ctx.A,2)+sum(ctx.A,1).');
    end
end
den=full(sum(W,2)); values=full(W*d)./den; valid=den>0;
status='ok'; reason='';
if any(~valid), status='partial'; reason='Mean is undefined for nodes with no selected neighbors.'; end
if ctx.n>0 && ~any(valid), status='undefined'; end
r=mc.make_result('average_neighbor_degree',values,'node',{'node_id'},{ctx.node_ids},valid,status,reason);
end
