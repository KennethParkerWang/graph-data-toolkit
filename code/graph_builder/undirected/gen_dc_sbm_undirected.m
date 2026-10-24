function [A, meta] = gen_dc_sbm_undirected(sizes, theta, omega, seed)
%GEN_DC_SBM_UNDIRECTED Karrer-Newman DC-SBM projected to a simple graph.
% [A,meta] = gen_dc_sbm_undirected(sizes,theta,omega,seed)
% sizes: positive integer community sizes, in contiguous node order.
% theta: nonnegative node propensities, summing to one in each community.
% omega: finite nonnegative symmetric community intensity matrix.
% For i<j, draw independently with p_ij=1-exp(-theta_i*theta_j*omega_rs).
% This is the presence/absence projection of the paper's Poisson multigraph,
% with self-loops removed. Its degrees are not the original Poisson means.
% Isolates are kept; connectivity is not conditioned; seed defaults to 1.
% Reference: Karrer & Newman, Phys. Rev. E 83, 016107 (2011), Eqs. 14-15.
% https://doi.org/10.1103/PhysRevE.83.016107
if nargin < 4
    seed = 1;
end
validateattributes(sizes, {'numeric'}, ...
    {'vector', 'nonempty', 'real', 'finite', 'integer', 'positive'});
sizes = full(double(sizes(:)));
N = sum(sizes);
num_communities = numel(sizes);
validateattributes(theta, {'numeric'}, ...
    {'vector', 'numel', N, 'real', 'finite', '>=', 0, '<=', 1});
theta = full(double(theta(:)));
validateattributes(omega, {'numeric'}, ...
    {'real', 'finite', 'size', [num_communities num_communities], 'nonnegative'});
omega = full(double(omega));
if ~isequal(omega, omega.')
    error('graphgen:DCSBMSymmetry', 'Undirected DC-SBM omega must be symmetric.');
end
community = repelem((1:num_communities).', sizes);
community = community(:);
theta_sums = accumarray(community, theta, [num_communities, 1]);
if any(abs(theta_sums - 1) > 1e-12)
    error('graphgen:DCSBMThetaNormalization', ...
        'theta must sum to one in each community (absolute tolerance 1e-12).');
end

guard = gg_seed(seed); %#ok<NASGU>
rows = cell(N, 1);
cols = cell(N, 1);
expected_degree = zeros(N, 1);
% ponytail: exact O(N^2) pair scan; use sparse sampling only if scale requires it.
for node = 1:N-1
    candidates = (node+1:N).';
    intensities = (theta(node) * ...
        reshape(omega(community(node), community(candidates)), [], 1)) .* theta(candidates);
    probabilities = -expm1(-intensities);
    expected_degree(node) = expected_degree(node) + sum(probabilities);
    expected_degree(candidates) = expected_degree(candidates) + probabilities;
    chosen = candidates(rand(numel(candidates), 1) < probabilities);
    rows{node} = repmat(node, numel(chosen), 1);
    cols{node} = chosen;
end
edge_from = vertcat(rows{:});
edge_to = vertcat(cols{:});
upper_adjacency = sparse(edge_from, edge_to, ones(numel(edge_from), 1), N, N);
A = logical(upper_adjacency + upper_adjacency.');
params = struct('sizes', sizes, 'theta', theta, 'omega', omega, ...
    'theta_normalization', 'sum_per_community_one', ...
    'construction', 'poisson_multigraph_presence_projection_without_self_loops', ...
    'edge_probability', '1-exp(-theta_i*theta_j*omega_rs)', ...
    'community_order', 'contiguous_blocks', 'connectivity_conditioning', false, ...
    'original_poisson_expected_degree_is_preserved', false, ...
    'expected_degree_simple_no_loops', expected_degree);
[A, meta] = gg_finalize(A, 'DC-SBM', false, seed, params);
meta.community = community;
meta.reference_id = 'dc_sbm_karrer_newman_2011_simple_projection';
end
