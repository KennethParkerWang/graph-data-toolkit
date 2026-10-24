function [A, meta] = gen_duplication_divergence_undirected(N, p, max_attempts, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_DUPLICATION_DIVERGENCE_UNDIRECTED Connected duplication-divergence model.
% [A,meta] = gen_duplication_divergence_undirected(N,p,max_attempts,seed)
% N>=2 and 0<p<=1. Begin with edge (1,2); choose an old node uniformly,
% duplicate its neighbors, retain each copied edge independently with p.
% Reject a copy retaining no edges, so rejected copies do not increase N.
% This is NetworkX 3.5's connected variant, not partial_duplication_graph.
% max_attempts defaults to max(10000,100*N); seed defaults to 1.
% An exhausted global budget raises an error without changing seed or p.
% Unlike NetworkX, p=0 is rejected explicitly to avoid an infinite loop.
% Reference: Ispolatov, Krapivsky & Yuryev, Phys. Rev. E 71, 061911 (2005).
% https://doi.org/10.1103/PhysRevE.71.061911
% MATLAB and NetworkX use different random-stream conventions.
validateattributes(N, {'numeric'}, {'scalar', 'real', 'finite', 'integer', '>=', 2});
validateattributes(p, {'numeric'}, {'scalar', 'real', 'finite'});
if p <= 0 || p > 1
    error('graphgen:DuplicationProbability', 'Connected duplication-divergence requires 0<p<=1.');
end
N = full(double(N));
p = full(double(p));
if nargin < 3 || isempty(max_attempts)
    max_attempts = max(10000, 100*N);
end
if nargin < 4
    seed = 1;
end
validateattributes(max_attempts, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', 'nonnegative'});
max_attempts = full(double(max_attempts));
guard = gg_seed(seed); %#ok<NASGU>
A = logical(sparse([1, 2], [2, 1], [1, 1], N, N));
current_N = 2;
attempts = 0;
parents = zeros(N, 1);
while current_N < N
    if attempts >= max_attempts
        error('graphgen:DuplicationAttemptLimit', ...
            'Reached %d/%d nodes after %d attempts with seed %g; p was unchanged.', ...
            current_N, N, attempts, seed);
    end
    attempts = attempts + 1;
    source = randi(current_N);
    neighbors = find(A(source, 1:current_N));
    retained = neighbors(rand(size(neighbors)) < p);
    if isempty(retained)
        continue
    end
    current_N = current_N + 1;
    A(current_N, retained) = true;
    A(retained, current_N) = true;
    parents(current_N) = source;
end
params = struct('N', N, 'p', p, 'max_attempts', max_attempts, ...
    'initial_graph', 'two_nodes_one_edge', ...
    'construction', 'uniform_node_duplication_independent_edge_retention', ...
    'connectivity_conditioning', 'reject_zero_retained_neighbors', ...
    'budget_scope', 'global_duplication_attempts', ...
    'attempt_limit_policy', 'error_without_seed_or_parameter_change');
[A, meta] = gg_finalize(A, 'Duplication-Divergence', false, seed, params);
meta.duplication_parent = parents;
meta.duplication_attempts = attempts;
meta.rejected_duplications = attempts - (N-2);
meta.reference_id = 'networkx_3_5_duplication_divergence_graph';
end
