function r=average_path_length(ctx,p)
%AVERAGE_PATH_LENGTH Mean distance under explicit all/reachable pair policy
if nargin<2,p=struct;end
policy=validatestring(mc.param(p,'pair_policy','all'),{'all','reachable'});D=mc.distances(ctx,p);x=D(~eye(ctx.n));if strcmp(policy,'reachable'),x=x(isfinite(x));end
v=mean(x);if ~isfinite(v),v=NaN;end
r=mc.basic_result('average_path_length',v,'graph',ctx,'No eligible pairs, or an unreachable pair under all-pairs policy.');
end
