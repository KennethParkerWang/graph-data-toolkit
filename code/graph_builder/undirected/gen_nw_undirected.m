function [A, meta] = gen_nw_undirected(N, K, beta, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_NW_UNDIRECTED Newman-Watts-Strogatz graph, NetworkX 3.5 protocol.
% [A,meta] = gen_nw_undirected(N,K,beta,seed), K is neighbors on each side.
% Backbone insertion and original-edge enumeration follow NetworkX Graph.
% One Bernoulli trial per original edge; uniform eligible shortcut endpoint.
% Adapted from NetworkX 3.5, BSD-3-Clause; sources/standard/networkx_3_5/.
if nargin < 4
    seed = 1;
end
validateattributes(N, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'integer', '>=', 3}, mfilename, 'N');
validateattributes(K, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'integer', 'positive'}, mfilename, 'K');
validateattributes(beta, {'numeric'}, ...
    {'real', 'finite', 'scalar', '>=', 0, '<=', 1}, mfilename, 'beta');
N = double(N);
K = double(K);
beta = double(beta);
if 2*K >= N
    error('graphgen:InvalidRingDegree', 'Require 1 <= K < N/2.');
end
guard = gg_seed(seed); %#ok<NASGU>

backbone_edges = N*K;
sources = zeros(2*backbone_edges, 1);
targets = zeros(2*backbone_edges, 1);
sources(1:backbone_edges) = repmat((1:N).', K, 1);
targets(1:backbone_edges) = reshape(mod((1:N).'+(1:K)-1, N)+1, [], 1);
neighbors = cell(N,1);
for index = 1:backbone_edges
    u = sources(index); v = targets(index);
    neighbors{u}(end+1) = v;
    neighbors{v}(end+1) = u;
end
% Graph.edges() visits nodes in order, then neighbors in insertion order.
original_sources = zeros(backbone_edges,1); cursor = 0;
for node = 1:N
    outward = neighbors{node}(neighbors{node} > node);
    original_sources(cursor+(1:numel(outward))) = node;
    cursor = cursor+numel(outward);
end
shortcuts = 0;
for index = 1:backbone_edges
    source = original_sources(index);
    if rand < beta
        eligible = true(1,N);
        eligible([source,neighbors{source}]) = false;
        candidates = find(eligible);
        if ~isempty(candidates)
            target = candidates(randi(numel(candidates)));
            neighbors{source}(end+1) = target;
            neighbors{target}(end+1) = source;
            shortcuts = shortcuts+1;
            sources(backbone_edges+shortcuts) = source;
            targets(backbone_edges+shortcuts) = target;
        end
    end
end
sources = sources(1:backbone_edges+shortcuts);
targets = targets(1:backbone_edges+shortcuts);
A = sparse([sources; targets], [targets; sources], true, N, N);
params = struct('N', N, 'K', K, 'beta', beta, 'backbone_edges', N*K);
[A, meta] = gg_finalize(A, 'NW', false, seed, params);
meta.construction = 'NetworkX 3.5 original Graph.edges order; preserve ring and add shortcuts';
meta.shortcut_edges = shortcuts;
meta.reference_id = 'networkx_3_5_newman_watts_strogatz_graph';
end
