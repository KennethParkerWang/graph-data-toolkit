function r = degree_assortativity(ctx,p)
%DEGREE_ASSORTATIVITY Pearson degree correlation across arcs / both edge orientations.
if nargin<2, p=struct(); end
source=char(mc.param(p,'source_degree','out')); target=char(mc.param(p,'target_degree','in'));
allowed={'in','out'};
if ~ismember(source,allowed) || ~ismember(target,allowed)
    error('mc:InvalidParameter','source_degree and target_degree must be in or out.');
end
[u,v]=find(ctx.A); out=full(sum(ctx.A,2)); in=full(sum(ctx.A,1)).';
if strcmp(source,'in'), x=in(u); else, x=out(u); end
if strcmp(target,'in'), y=in(v); else, y=out(v); end
if isempty(x)
    r=mc.make_result('degree_assortativity',NaN,'graph',{}, {},false,'undefined','No edges.'); return
end
x=x-mean(x); y=y-mean(y); denom=sqrt(sum(x.^2)*sum(y.^2));
if denom==0
    r=mc.make_result('degree_assortativity',NaN,'graph',{}, {},false,'undefined','An endpoint degree has zero variance.');
else
    value=max(-1,min(1,sum(x.*y)/denom));
    r=mc.make_result('degree_assortativity',value,'graph',{});
end
end
