function r = structural_dedicated_feasibility(ctx,p)
%STRUCTURAL_DEDICATED_FEASIBILITY Generic controllability for specified actuators.
% Each selected node receives its own independent input. No placement optimization.
if nargin<2, p=struct(); end
if ~ctx.directed
    r=mc.make_result('structural_dedicated_feasibility',[],'graph',{}, {},[],'not_applicable','Directed independent-parameter structure required.'); return
end
if ~isfield(p,'driver_node_ids'), error('mc:MissingParameter','driver_node_ids required.'); end
ids=p.driver_node_ids(:);
if ~(isnumeric(ids) && isreal(ids) && all(isfinite(ids)) && numel(unique(ids))==numel(ids))
    error('mc:InvalidParameter','driver_node_ids must be unique finite numeric IDs.');
end
[present,local]=ismember(ids,ctx.node_ids);
if any(~present), error('mc:InvalidParameter','An actuator ID is absent from ctx.node_ids.'); end
k=numel(local); B=sparse(local,1:k,ones(k,1),ctx.n,k);
[~,~,matching]=mc.maximum_matching([ctx.A; B.']);
reachable=false(ctx.n,1); queue=zeros(ctx.n,1); queue(1:k)=local; reachable(local)=true;
head=1; tail=k;
while head<=tail
    u=queue(head); head=head+1; neighbors=find(ctx.A(u,:));
    for v=neighbors
        if ~reachable(v), tail=tail+1; queue(tail)=v; reachable(v)=true; end
    end
end
accessible=all(reachable); full_matching=matching==ctx.n;
r=mc.make_result('structural_dedicated_feasibility',accessible && full_matching,'graph',{});
r.details=struct('input_model','one independent input per specified node','accessible',accessible,...
    'full_matching',full_matching,'augmented_matching_size',matching,...
    'unreachable_node_ids',ctx.node_ids(~reachable),'driver_node_ids',ctx.node_ids(local),...
    'minimality','not tested; supplied placement only');
end
