function [A, meta] = gen_ws_undirected(N, K, beta, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_WS_UNDIRECTED 无向 Watts-Strogatz 环格重连简单图。
% 用法：[A,meta] = gen_ws_undirected(N,K,beta,seed)
% 参数：N>=3、1<=K<N/2 为整数；K 为每侧邻居数；0<=beta<=1；seed 默认 1。
% 规则：按偏移再按源节点处理顺时针骨架边，以 beta 重连其目标。
% 目标从非邻居且非自身中均匀选取；无候选时保留原边，不保证连通。
% 输出：稀疏 logical 对称 A，精确 N*K 边、平均度 2*K；meta 记录重连数。
% 参考：https://networkx.org/documentation/networkx-3.5/_modules/networkx/generators/random_graphs.html
% https://www.mathworks.com/help/matlab/math/build-watts-strogatz-small-world-graph-model.html
% K对应参考接口k/2。均匀合法候选与均匀拒绝抽样的条件分布相同。
% 邻居表维护重连状态，最后一次构造sparse；参考源码为BSD-3-Clause。
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

sources = repmat((1:N).', K, 1);
targets = reshape(mod((1:N).'+(1:K)-1, N)+1, [], 1);
neighbors = cell(N, 1);
offsets = [-K:-1, 1:K];
for node = 1:N
    neighbors{node} = mod(node+offsets-1, N)+1;
end
rewired = 0;
for offset = 1:K
    for source = 1:N
        old_target = mod(source+offset-1, N)+1;
        if rand < beta
            eligible = true(1, N);
            eligible([source, neighbors{source}]) = false;
            candidates = find(eligible);
            if ~isempty(candidates)
                target = candidates(randi(numel(candidates)));
                neighbors{source}(neighbors{source} == old_target) = target;
                neighbors{old_target}(neighbors{old_target} == source) = [];
                neighbors{target}(end+1) = source;
                targets((offset-1)*N+source) = target;
                rewired = rewired+1;
            end
        end
    end
end
A = sparse([sources; targets], [targets; sources], true, N, N);
params = struct('N', N, 'K', K, ...
    'beta', beta, 'initial_mean_degree', 2*K);
[A, meta] = gg_finalize(A, 'WS', false, seed, params);
meta.construction = 'Ring lattice; process clockwise edges by offset then source and rewire targets';
meta.rewired_edges = rewired;
meta.reference_id = 'networkx_3_5_watts_strogatz_graph';
end
