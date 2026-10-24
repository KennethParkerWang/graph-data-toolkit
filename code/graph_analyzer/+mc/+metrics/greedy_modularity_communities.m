function r = greedy_modularity_communities(ctx,p)
%GREEDY_MODULARITY_COMMUNITIES Deterministic agglomerative modularity heuristic.
% Start with singletons; merge the largest positive delta-Q. No global guarantee.
if nargin<2, p=struct(); end
gamma=mc.param(p,'resolution',1); tolerance=mc.param(p,'gain_tolerance',1e-12);
validateattributes(gamma,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(tolerance,{'numeric'},{'scalar','real','finite','nonnegative'});
if mc.advanced_dense_limit(ctx,p)
    r=mc.make_result('greedy_modularity_communities',[],'node',{}, {},[],'not_computed','N exceeds explicit max_nodes.'); return
end
if ctx.m==0
    r=mc.make_result('greedy_modularity_communities',nan(ctx.n,1),'node',{'node_id'},{ctx.node_ids},false(ctx.n,1),'undefined','Modularity has a zero edge denominator.'); return
end
% Process in original node-ID order so preserving IDs preserves tie decisions.
[~,order]=sort(ctx.node_ids); W=full(ctx.A(order,order)); n=ctx.n;
out=sum(W,2); in=sum(W,1).';
if ctx.directed
    contribution=W/ctx.m-gamma*(out*in.')/ctx.m^2;
else
    contribution=W/(2*ctx.m)-gamma*(out*out.')/(4*ctx.m^2);
end
gain=contribution+contribution.'; gain(1:n+1:end)=-Inf;
labels=(1:n).'; active=true(n,1); history=zeros(max(0,n-1),3); merged=0;
while nnz(active)>1
    available=find(active); best=-Inf; a=0; b=0;
    for i=1:numel(available)-1
        u=available(i);
        for j=i+1:numel(available)
            v=available(j);
            if gain(u,v)>best
                best=gain(u,v); a=u; b=v;
            end
        end
    end
    if best<=tolerance, break; end
    merged=merged+1; history(merged,:)=[double(ctx.node_ids(order(a))),double(ctx.node_ids(order(b))),best];
    others=find(active); others(others==a | others==b)=[];
    gain(a,others)=gain(a,others)+gain(b,others); gain(others,a)=gain(a,others).';
    active(b)=false; gain(b,:)=-Inf; gain(:,b)=-Inf; labels(labels==b)=a;
end
output=zeros(n,1); output(order)=double(ctx.node_ids(order(labels)));
r=mc.make_result('greedy_modularity_communities',output,'node',{'node_id'},{ctx.node_ids});
r.method='heuristic';
size_result=mc.metrics.community_sizes(ctx,struct('partition',output));
r.details=struct('modularity',mc.advanced_modularity_value(ctx,output,gamma),...
    'community_ids',size_result.axis_ids{1},'community_sizes',size_result.values,...
    'merges',history(1:merged,:),'tie_policy','smallest representative node ID pair',...
    'randomness','none','optimality','heuristic; no global optimum guarantee');
end
