function d=basic_degree(ctx,mode)
%BASIC_DEGREE Total, incoming or outgoing unweighted degree.
mode=validatestring(mode,{'total','in','out'});
a=full(sum(ctx.A,2));b=full(sum(ctx.A,1))';
if ~ctx.directed, d=a; elseif strcmp(mode,'total'),d=a+b;elseif strcmp(mode,'in'),d=b;else,d=a;end
end
