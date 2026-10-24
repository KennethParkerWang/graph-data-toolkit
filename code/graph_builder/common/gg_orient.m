function B = gg_orient(A)
%GG_ORIENT Independently orient each undirected edge with probability 1/2.
% This is an orientation variant, not a native directed graph distribution.
if size(A,1) ~= size(A,2) || ~isequal(A,A.') || any(diag(A))
    error('graphgen:InvalidOrientationInput', 'Expected a symmetric loop-free adjacency.');
end
[source, target] = find(triu(A,1));
flip = rand(numel(source),1) < 0.5;
tmp = source(flip);
source(flip) = target(flip);
target(flip) = tmp;
B = logical(sparse(source,target,ones(numel(source),1),size(A,1),size(A,1)));
end
