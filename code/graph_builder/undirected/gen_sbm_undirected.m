function [A, meta] = gen_sbm_undirected(sizes, P, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_SBM_UNDIRECTED 无向、无权简单随机块模型（SBM）。
% 用法：[A, meta] = gen_sbm_undirected(sizes, P, seed)
% 参数：sizes 为各社区的正整数规模；P 为对称社区连接概率矩阵，
%       每项位于 [0,1]；seed 默认为 1。
% 规则：不同节点对独立抽样，概率取决于所属社区；节点按社区编号。
%       不添加自环，不强制连通，不改变调用者随机数状态。
% 输出：A 为稀疏逻辑对称邻接矩阵；meta.community 为节点社区编号。
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
if ~isequal(P, P.')
    error('graphgen:SBMSymmetry', '无向 SBM 的 P 必须严格对称。');
end

guard = gg_seed(seed); %#ok<NASGU>
N = sum(sizes);
community = repelem((1:num_communities).', sizes);
rows = cell(N, 1);
cols = cell(N, 1);
for node = 1:N-1
    candidates = (node+1:N).';
    probabilities = reshape(P(community(node), community(candidates)), [], 1);
    chosen = candidates(rand(numel(candidates), 1) < probabilities);
    rows{node} = repmat(node, numel(chosen), 1);
    cols{node} = chosen;
end
edge_from = vertcat(rows{:});
edge_to = vertcat(cols{:});
upper_adjacency = sparse(edge_from, edge_to, ones(numel(edge_from), 1), N, N);
A = logical(upper_adjacency + upper_adjacency.');
params = struct('sizes', sizes, 'P', P, ...
    'construction', 'independent_unordered_pairs', ...
    'community_order', 'contiguous_blocks', 'connectivity_conditioning', false);
[A, meta] = gg_finalize(A, 'SBM', false, seed, params);
meta.community = community;
meta.reference_id = 'networkx_3_5_stochastic_block_model';
end
