function exceeded = advanced_dense_limit(ctx,p)
%ADVANCED_DENSE_LIMIT Explicit guard, never a switch to approximation.
limit = mc.param(p,'max_nodes',2000);
validateattributes(limit,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
exceeded = ctx.n > limit;
end
