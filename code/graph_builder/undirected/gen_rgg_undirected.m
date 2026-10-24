function [A, meta] = gen_rgg_undirected(N, radius, dim, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_RGG_UNDIRECTED Random geometric graph in the open unit cube.
% [A,meta] = gen_rgg_undirected(N,radius,dim,seed); dim defaults to 2.
% Independent uniform positions; connect pairs at Euclidean distance <= radius.
% meta.positions retains the N-by-dim coordinates. No connectivity filtering.
% NetworkX 3.5 random_geometric_graph, p=2, open boundaries.
% Reference source/license: sources/standard/networkx_3_5/geometric.py.
if nargin < 3 || isempty(dim)
    dim = 2;
end
if nargin < 4
    seed = 1;
end
validateattributes(N, {'numeric'}, {'scalar', 'real', 'finite', 'integer', 'positive'});
validateattributes(radius, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'});
validateattributes(dim, {'numeric'}, {'scalar', 'real', 'finite', 'integer', 'positive'});
N = double(N);
dim = double(dim);

guard = gg_seed(seed); %#ok<NASGU>
positions = rand(N, dim);
radius_squared = radius^2;
rows = cell(N, 1);
cols = cell(N, 1);
for node = 1:N-1
    delta = abs(positions(node+1:N, :) - positions(node, :));
    chosen = find(sum(delta.^2, 2) <= radius_squared) + node;
    rows{node} = repmat(node, numel(chosen), 1);
    cols{node} = chosen;
end
edge_from = vertcat(rows{:});
edge_to = vertcat(cols{:});
upper_adjacency = sparse(edge_from, edge_to, ones(numel(edge_from), 1), N, N);
A = logical(upper_adjacency + upper_adjacency.');
params = struct('N', N, 'radius', radius, 'dim', dim, ...
    'boundary', 'open_unit_cube', 'metric', 'euclidean', 'threshold', 'distance_le_radius', ...
    'construction', 'iid_uniform_positions', 'connectivity_conditioning', false);
[A, meta] = gg_finalize(A, 'RGG', false, seed, params);
meta.positions = positions;
meta.reference_id = 'networkx_3_5_random_geometric_graph';
end
