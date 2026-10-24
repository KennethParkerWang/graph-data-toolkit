function [A, meta] = gen_waxman_undirected(N, alpha, beta, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_WAXMAN_UNDIRECTED Waxman-1 on uniform positions in the unit square.
% [A,meta] = gen_waxman_undirected(N,alpha,beta,seed); seed defaults to 1.
% alpha>0, 0<=beta<=1; p_ij=beta*exp(-distance_ij/(alpha*L)).
% L is the maximum ACTUAL pair distance, not a Waxman-2 random distance.
% N=1 gives an isolated node and L=0. If all positions coincide, p=beta.
% No self-loops or connectivity filtering; positions and L are retained.
% Reference: Waxman, Routing of multipoint connections (1988).
% https://doi.org/10.1109/49.12889
% Source: sources/standard/networkx_3_5/geometric.py, waxman_graph(L=None).
% MATLAB and NetworkX use different random-stream conventions.
if nargin < 4
    seed = 1;
end
validateattributes(N, {'numeric'}, {'scalar', 'real', 'finite', 'integer', 'positive'});
validateattributes(alpha, {'numeric'}, {'scalar', 'real', 'finite', 'positive'});
validateattributes(beta, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1});
N = full(double(N));
alpha = full(double(alpha));
beta = full(double(beta));
guard = gg_seed(seed); %#ok<NASGU>
positions = rand(N, 2);
L = 0;
% ponytail: exact O(N^2) distance scan; no spatial-index dependency for these sizes.
for node = 1:N-1
    distances = sqrt(sum((positions(node+1:N, :) - positions(node, :)).^2, 2));
    L = max(L, max(distances));
end
rows = cell(N, 1);
cols = cell(N, 1);
for node = 1:N-1
    candidates = (node+1:N).';
    if L == 0
        probabilities = repmat(beta, numel(candidates), 1);
    else
        distances = sqrt(sum((positions(candidates, :) - positions(node, :)).^2, 2));
        probabilities = beta * exp(-(distances / L) / alpha);
    end
    chosen = candidates(rand(numel(candidates), 1) < probabilities);
    rows{node} = repmat(node, numel(chosen), 1);
    cols{node} = chosen;
end
edge_from = vertcat(rows{:});
edge_to = vertcat(cols{:});
upper_adjacency = sparse(edge_from, edge_to, ones(numel(edge_from), 1), N, N);
A = logical(upper_adjacency + upper_adjacency.');
params = struct('N', N, 'alpha', alpha, 'beta', beta, ...
    'variant', 'waxman_1', 'L', L, 'domain', [0, 0, 1, 1], ...
    'metric', 'euclidean', 'construction', 'iid_uniform_positions', ...
    'edge_probability', 'beta*exp(-actual_distance/(alpha*L))', ...
    'zero_L_convention', 'coincident_pair_probability_beta', ...
    'connectivity_conditioning', false);
[A, meta] = gg_finalize(A, 'Waxman', false, seed, params);
meta.positions = positions;
meta.reference_id = 'networkx_3_5_waxman1_graph';
end
