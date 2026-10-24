function [A, meta] = gen_chung_lu_undirected(w, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_CHUNG_LU_UNDIRECTED NetworkX expected-degree graph without self-loops.
% [A,meta] = gen_chung_lu_undirected(w,seed), finite nonnegative vector w.
% Each unordered pair has independent probability min(1,w(i)*w(j)/sum(w)).
% Zero total weight gives an empty graph. Actual expected degrees account for
% removed self-loops and clipped probabilities; weights are not exact degrees.
% NetworkX 3.5 expected_degree_graph(selfloops=false), BSD-3-Clause.
% Source and license: sources/standard/networkx_3_5/degree_seq.py.
if nargin < 2
    seed = 1;
end
validateattributes(w, {'numeric'}, ...
    {'vector', 'nonempty', 'real', 'finite', 'nonnegative'});
w = double(w(:));
N = numel(w);
weight_sum = sum(w);
if ~isfinite(weight_sum)
    error('graphgen:WeightSum', '权重总和必须有限。');
end
guard = gg_seed(seed); %#ok<NASGU>
rows = cell(N, 1);
cols = cell(N, 1);
if weight_sum > 0
    normalized_weights = w/weight_sum;
    for node = 1:N-1
        probabilities = min(1,w(node)*normalized_weights(node+1:N));
        chosen = find(rand(N-node, 1) < probabilities) + node;
        rows{node} = repmat(node, numel(chosen), 1);
        cols{node} = chosen;
    end
    expected_degree = zeros(N,1);
    for node = 1:N
        probabilities = min(1,w(node)*normalized_weights);
        probabilities(node) = 0;
        expected_degree(node) = sum(probabilities);
    end
else
    expected_degree = zeros(N, 1);
end
edge_from = vertcat(rows{:});
edge_to = vertcat(cols{:});
upper_adjacency = sparse(edge_from, edge_to, ones(numel(edge_from), 1), N, N);
A = logical(upper_adjacency + upper_adjacency.');
params = struct('w', w, 'weight_sum', weight_sum, ...
    'expected_degree_no_loops', expected_degree, ...
    'construction', 'independent_pairs_product_weights_without_loops', ...
    'probability_above_one', 'clip_to_one', 'connectivity_conditioning', false);
[A, meta] = gg_finalize(A, 'Chung_Lu_no_loops', false, seed, params);
meta.reference_id = 'networkx_3_5_expected_degree_graph';
end
