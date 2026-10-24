function [labels, ids] = advanced_partition(ctx, p)
%ADVANCED_PARTITION Validate one finite integer community label per ctx node.
if ~isfield(p,'partition')
    error('mc:MissingParameter','partition is required in ctx.node_ids order.');
end
labels = p.partition;
if ~(isnumeric(labels) && isreal(labels) && numel(labels)==ctx.n && ...
        all(isfinite(labels(:))) && all(labels(:)==fix(labels(:))))
    error('mc:InvalidParameter','partition must contain N finite integer labels.');
end
labels = double(labels(:));
ids = unique(labels,'sorted');
end
