function [A, meta] = gen_degree_sequence_undirected(degrees, swap_attempts, seed)
%GEN_DEGREE_SEQUENCE_UNDIRECTED 保持逐节点度数的无向简单随机图。
% 用法：[A,meta] = gen_degree_sequence_undirected(degrees,swap_attempts,seed)
% degrees 为按节点编号给出的非负整数度序列；swap_attempts 为非负整数。
% 先用确定性的 Havel-Hakimi 构图，再尝试随机双边交换；不强制连通。
% 不图示、奇数总度或越界序列明确报错，不通过去重修改目标度数。
% 该有限交换采样不保证均匀，也不是 Bayati 随机度序列算法。
% seed 默认为 1，调用者随机数状态在成功和失败时均恢复。
% 参考：Havel (1955); Hakimi (1962), SIAM J. Appl. Math. 10:496-506,
%       doi:10.1137/0110037; NetworkX 3.5 double_edge_swap 的简单图交换条件。
if nargin < 3, seed = 1; end
validateattributes(degrees, {'numeric'}, ...
    {'vector','nonempty','real','finite','integer','nonnegative'}, mfilename, 'degrees');
degrees = full(double(degrees(:)));
N = numel(degrees);
validateattributes(swap_attempts, {'numeric'}, ...
    {'scalar','real','finite','integer','nonnegative'}, mfilename, 'swap_attempts');
swap_attempts = full(double(swap_attempts));
if any(degrees >= N)
    error('graphgen:DegreeSequenceRange', '简单图每个节点的度必须小于节点数。');
end
if mod(sum(degrees),2) ~= 0
    error('graphgen:DegreeSequenceParity', '无向图总度必须为偶数。');
end
guard = gg_seed(seed); %#ok<NASGU>
A = sparse(false(N,N));
residual = degrees;
for iteration = 1:N
    % Equal residual degrees use ascending original node ID as a stable tie-break.
    ordered = sortrows([-residual,(1:N).'],[1,2]);
    u = ordered(1,2); d = residual(u);
    if d == 0, break; end
    residual(u) = 0;
    candidates = ordered(2:d+1,2);
    if any(residual(candidates) <= 0)
        error('graphgen:DegreeSequenceNotGraphical', 'Havel-Hakimi 判定该度序列不图示。');
    end
    A(u,candidates) = true; A(candidates,u) = true;
    residual(candidates) = residual(candidates)-1;
end
if any(residual) || ~isequal(full(sum(A,2)),degrees)
    error('graphgen:DegreeSequenceNotGraphical', '该序列不能生成具有指定逐节点度的简单图。');
end
[left,right] = find(triu(A,1));
edges = [left,right]; M = size(edges,1);
successful_swaps = 0;
for attempt = 1:swap_attempts
    if M < 2, break; end
    indexes = randperm(M,2);
    endpoints = edges(indexes,:);
    if rand < .5, endpoints(1,:) = endpoints(1,[2,1]); end
    if rand < .5, endpoints(2,:) = endpoints(2,[2,1]); end
    u = endpoints(1,1); v = endpoints(1,2);
    x = endpoints(2,1); y = endpoints(2,2);
    if numel(unique([u,v,x,y])) < 4 || A(u,y) || A(x,v), continue; end
    A(u,v) = false; A(v,u) = false;
    A(x,y) = false; A(y,x) = false;
    A(u,y) = true; A(y,u) = true;
    A(x,v) = true; A(v,x) = true;
    edges(indexes,:) = sort([u,y;x,v],2);
    successful_swaps = successful_swaps+1;
end
attempted_swaps = swap_attempts;
if M < 2, attempted_swaps = 0; end
params = struct('degrees',degrees,'swap_attempts',double(swap_attempts), ...
    'construction','deterministic_havel_hakimi_then_random_double_edge_swaps', ...
    'tie_break','ascending_node_id','sampling','finite_swaps_not_uniform', ...
    'connectivity_conditioning',false);
[A,meta] = gg_finalize(A,'DEGREE-SEQUENCE',false,seed,params);
meta.target_degrees = degrees;
meta.actual_degrees = full(sum(A,2));
meta.attempted_swaps = attempted_swaps;
meta.successful_swaps = successful_swaps;
meta.reference_id = 'havel_hakimi_degree_preserving_swap';
end
