function r = effective_resistance(ctx,p)
%EFFECTIVE_RESISTANCE All-pairs unit-edge electrical resistance.
% Across disconnected components resistance is +Inf, valid in extended reals.
if nargin<2, p=struct(); end
if ctx.directed
    r=mc.make_result('effective_resistance',[],'matrix',{}, {},[],'not_applicable','Passive undirected unit-resistance network required.'); return
end
if mc.advanced_dense_limit(ctx,p)
    r=mc.make_result('effective_resistance',[],'matrix',{}, {},[],'not_computed','N exceeds explicit max_nodes.'); return
end
key='advanced_effective_resistance';
if isfield(ctx.cache.data,key)
    values=ctx.cache.data.(key);
else
    values=inf(ctx.n,ctx.n); component=conncomp(ctx.G).';
    for c=unique(component).'
        nodes=find(component==c); k=numel(nodes);
        if k==1, values(nodes,nodes)=0; continue; end
        W=ctx.A(nodes,nodes); L=full(spdiags(sum(W,2),0,k,k)-W);
        % L+J/k is positive definite within this connected component.
        Z=(L+ones(k)/k)\eye(k); Z=(Z+Z.')/2;
        resistance=diag(Z)+diag(Z).'-2*Z;
        tolerance=100*eps(max(1,norm(Z,Inf)))*k;
        if any(resistance(:)<-tolerance)
            error('mc:NumericalFailure','Negative resistance exceeds roundoff tolerance.');
        end
        resistance=max(0,resistance); resistance(1:k+1:end)=0;
        values(nodes,nodes)=resistance;
    end
    ctx.cache.data.(key)=values;
end
r=mc.make_result('effective_resistance',values,'matrix',{'source_node_id','target_node_id'},...
    {ctx.node_ids,ctx.node_ids},true(size(values)));
r.units='unit edge resistance';
r.method='numerical';
r.details=struct('disconnected_pairs','positive infinity; mathematically valid extended-real value',...
    'method','connected-component shifted-Laplacian solves');
end
