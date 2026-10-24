function results = summarize(ctx,trajectory,selections)
%SUMMARIZE Bind a runtime trajectory without hashing it as configuration.
% Formula/parameter identity belongs to selections; observations are data.
if ~isstruct(trajectory)||~isscalar(trajectory)||~isfield(trajectory,'states')
    error('mc:InvalidTrajectory','A scalar mc.attack trajectory is required.');
end
if isfield(trajectory,'input_context_identity')&&~strcmp(trajectory.input_context_identity,mc.attack_context_identity(ctx))
    error('mc:TrajectoryIdentity','Trajectory belongs to a different original graph context.');
end
ctx.trajectory=trajectory;
results=mc.compute(ctx,selections);
end
