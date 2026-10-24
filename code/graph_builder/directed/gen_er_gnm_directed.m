function [A, meta] = gen_er_gnm_directed(N, M, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_ER_GNM_DIRECTED 原生有向 G(N,M) 均匀随机简单图。
% 用法：[A,meta] = gen_er_gnm_directed(N,M,seed)
% 参数：N 为正整数，0<=M<=N*(N-1) 为整数；seed 默认 1。
% 规则：有序非自环节点对均匀、不放回抽样；允许互惠弧。
% 输出：稀疏 logical A(i,j)=1 表示 i->j；精确 M 弧，平均入/出度 M/N。
% 参考：NetworkX gnm_random_graph 的有向固定边数分布：
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
total_pairs = N*(N-1);
if M > total_pairs || total_pairs > flintmax
    error('graphgen:InvalidEdgeCount', 'Require M <= N*(N-1) <= flintmax.');
end
guard = gg_seed(seed); %#ok<NASGU>

if M == 0
    A = logical(sparse(N, N));
else
    pair_ranks = randperm(total_pairs, M)-1;
    sources = floor(pair_ranks/(N-1))+1;
    targets = mod(pair_ranks, N-1)+1;
    targets = targets + (targets >= sources);
    A = sparse(sources, targets, true, N, N);
end
params = struct('N', N, 'M', M, 'mean_out_degree', M/N);
[A, meta] = gg_finalize(A, 'Directed_ER_Gnm', true, seed, params);
meta.construction = 'Uniform sampling without replacement of ordered nonself pairs';
meta.reference_id = 'networkx_3_5_gnm_random_graph';
end
