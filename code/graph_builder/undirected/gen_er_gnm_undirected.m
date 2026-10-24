function [A, meta] = gen_er_gnm_undirected(N, M, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_ER_GNM_UNDIRECTED 无向 ER G(N,M) 均匀随机简单图。
% 用法：[A,meta] = gen_er_gnm_undirected(N,M,seed)
% 参数：N 为正整数，0<=M<=N*(N-1)/2 为整数；seed 默认 1。
% 规则：从全部无序节点对中不放回抽取 M 对，不筛选连通图。
% 输出：稀疏 logical 对称 A，精确 M 条边，平均度 2*M/N；meta 含计数。
% 参考：NetworkX gnm_random_graph 的均匀固定边数分布：
% https://networkx.org/documentation/networkx-3.5/_modules/networkx/generators/random_graphs.html
% 均匀无放回抽取节点对编号，等价于参考实现均匀端点拒绝抽样。
if nargin < 3
    seed = 1;
end
validateattributes(N, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'integer', 'positive'}, mfilename, 'N');
validateattributes(M, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'integer', 'nonnegative'}, mfilename, 'M');
N = double(N);
M = double(M);
total_pairs = N*(N-1)/2;
if M > total_pairs || total_pairs > flintmax
    error('graphgen:InvalidEdgeCount', 'Require M <= N*(N-1)/2 <= flintmax.');
end
guard = gg_seed(seed); %#ok<NASGU>

if M == 0
    A = logical(sparse(N, N));
else
    pair_ranks = randperm(total_pairs, M);
    [sources, targets] = gg_unrank_undirected_pairs(pair_ranks);
    A = sparse([sources, targets], [targets, sources], true, N, N);
end
params = struct('N', N, 'M', M, 'mean_degree', 2*M/N);
[A, meta] = gg_finalize(A, 'ER_Gnm', false, seed, params);
meta.construction = 'Uniform sampling without replacement of unordered pairs';
meta.reference_id = 'networkx_3_5_gnm_random_graph';
end
