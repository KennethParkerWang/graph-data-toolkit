function [A, meta] = gen_sbm_directed(sizes, P, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_SBM_DIRECTED 原生有向、无权简单随机块模型（SBM）。
% 用法：[A, meta] = gen_sbm_directed(sizes, P, seed)
% 参数：sizes 为各社区的正整数规模；P(a,b) 为社区 a 到 b 的概率，
%       每项位于 [0,1]，无需对称；seed 默认为 1。
% 规则：各有序节点对独立抽样，排除自环；允许同时存在两个方向。
%       不强制弱/强连通，不改变调用者随机数状态。
% 输出：A 为稀疏逻辑矩阵，A(i,j)=1 表示 i->j；meta.community 为社区。
% 参考：Holland, Laskey & Leinhardt (1983), Stochastic blockmodels.
%       https://networkx.org/documentation/networkx-3.5/reference/generated/networkx.generators.community.stochastic_block_model.html
%       本实现逐行抽样，未采用 NetworkX 的稀疏跳跃算法。
if nargin < 3
    seed = 1;
end
validateattributes(sizes, {'numeric'}, ...
    {'vector', 'nonempty', 'real', 'finite', 'integer', 'positive'});
sizes = double(sizes(:));
num_communities = numel(sizes);
validateattributes(P, {'numeric'}, ...
    {'real', 'finite', 'size', [num_communities num_communities], '>=', 0, '<=', 1});

guard = gg_seed(seed); %#ok<NASGU>
N = sum(sizes);
community = repelem((1:num_communities).', sizes);
rows = cell(N, 1);
cols = cell(N, 1);
for node = 1:N
    probabilities = reshape(P(community(node), community), [], 1);
    chosen = find(rand(N, 1) < probabilities);
    chosen(chosen == node) = [];
    rows{node} = repmat(node, numel(chosen), 1);
    cols{node} = chosen;
end
edge_from = vertcat(rows{:});
edge_to = vertcat(cols{:});
A = logical(sparse(edge_from, edge_to, ones(numel(edge_from), 1), N, N));
params = struct('sizes', sizes, 'P', P, ...
    'construction', 'independent_ordered_pairs', ...
    'community_order', 'contiguous_blocks', 'reciprocal_edges_allowed', true, ...
    'connectivity_conditioning', false);
[A, meta] = gg_finalize(A, 'SBM', true, seed, params);
meta.community = community;
meta.reference_id = 'networkx_3_5_stochastic_block_model';
end
