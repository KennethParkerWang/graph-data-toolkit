function id = attack_context_identity(ctx)
%ATTACK_CONTEXT_IDENTITY Runtime safety check; not the persisted topology_hash.
endpoints=reshape(ctx.node_ids(ctx.edge_list),[],2);
if ~ctx.directed, endpoints=sort(endpoints,2); end
[edge_ids,order]=sort(ctx.edge_ids);
definition=struct('directed',ctx.directed,'node_ids',sort(ctx.node_ids), ...
    'edge_ids',edge_ids,'edge_endpoints_original',endpoints(order,:));
id=mc.identity(definition,'attack-context-v1');
end
