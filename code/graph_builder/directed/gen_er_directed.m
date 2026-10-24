function [A, meta] = gen_er_directed(N, p, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_ER_DIRECTED 原生有向 ER G(N,p) 简单图。
% 用法：[A,meta] = gen_er_directed(N,p,seed)
% 参数：N 为正整数；p 在 [0,1]；seed 默认 1。
% 规则：i~=j 的有序节点对独立采样，允许互惠弧，不保证连通。
% 输出：稀疏 logical A(i,j)=1 表示 i->j；期望平均入/出度均为 (N-1)*p。
% 参考：NetworkX gnp_random_graph 的有向节点对定义：
% https://networkx.org/documentation/networkx-3.5/_modules/networkx/generators/random_graphs.html
% 批量生成独立伯努利试验，保持逐对试验的概率定义。
if nargin < 3
    seed = 1;
end
validateattributes(N, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'integer', 'positive'}, mfilename, 'N');
validateattributes(p, {'numeric'}, ...
    {'real', 'finite', 'scalar', '>=', 0, '<=', 1}, mfilename, 'p');
N = double(N);
p = double(p);
guard = gg_seed(seed); %#ok<NASGU>

row_cells = cell(N, 1);
col_cells = cell(N, 1);
for source = 1:N
    targets = find(rand(1, N-1) < p);
    targets = targets + (targets >= source);
    row_cells{source} = repmat(source, 1, numel(targets));
    col_cells{source} = targets;
end
sources = [row_cells{:}];
targets = [col_cells{:}];
A = sparse(sources, targets, true, N, N);
params = struct('N', N, 'p', p, 'expected_mean_out_degree', (N-1)*p);
[A, meta] = gg_finalize(A, 'Directed_ER_Gnp', true, seed, params);
meta.construction = 'Independent Bernoulli trials on ordered nonself pairs';
meta.reference_id = 'networkx_3_5_gnp_random_graph';
end
