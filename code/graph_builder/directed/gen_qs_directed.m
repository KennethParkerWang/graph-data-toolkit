function [A, meta] = gen_qs_directed(N, r, q, seed)
%GEN_QS_DIRECTED 单个r层的有向q-snapback网络。
% 用法：[A, meta] = gen_qs_directed(N, r, q, seed)
% 参数：整数N>=2、1<=r<N；回边概率0<=q<=1；seed默认1。
% 规则：固定1->2->...->N链；对i=r+1:N及l=1:floor((i-1)/r)，
%   独立以q概率添加i->(i-l*r)。不将全部r层合并，不按比例定边数。
%   r=1可有互惠弧；保证弱连通，未强制强连通。
% 输出：稀疏logical邻接A；meta包含候选回边数、期望弧数和链边数。
% 参考：https://doi.org/10.1109/TCSI.2018.2821124。
if nargin < 4
    seed = 1;
end
validateattributes(N, {'numeric'}, {'scalar', 'real', 'finite', 'integer', '>=', 2}, mfilename, 'N');
validateattributes(r, {'numeric'}, {'scalar', 'real', 'finite', 'integer', '>=', 1, '<', N}, mfilename, 'r');
validateattributes(q, {'numeric'}, {'scalar', 'real', 'finite', '>=', 0, '<=', 1}, mfilename, 'q');
N = double(N);
r = double(r);
q = double(q);
guard = gg_seed(seed); %#ok<NASGU>

% 每个回边候选单独进行伯努利试验，以端点列表构造稀疏矩阵。
source_parts = cell(N, 1);
target_parts = cell(N, 1);
source_parts{1} = 1:N-1;
target_parts{1} = 2:N;
candidates = 0;
for i = r+1:N
    targets = i-r:-r:1;
    candidates = candidates + numel(targets);
    selected = targets(rand(1, numel(targets)) < q);
    source_parts{i} = repmat(i, 1, numel(selected));
    target_parts{i} = selected;
end
sources = [source_parts{:}];
targets = [target_parts{:}];
A = sparse(sources, targets, true, N, N);
parameters = struct('N', N, 'r', r, 'q', q);
[A, meta] = gg_finalize(A, 'QS', true, seed, parameters);
meta.variant = 'single_r_layer_with_directed_chain';
meta.snapback_candidate_count = candidates;
meta.expected_num_arcs = N - 1 + q * candidates;
meta.backbone_arcs = N - 1;
meta.connectedness = 'weakly connected by the fixed directed chain; strong connectivity not enforced';
meta.reference_id = 'lou_wang_chen_2018_single_layer_qsn';
meta.reference = 'Lou, Wang, Chen (2018), Toward Stronger Robustness of Network Controllability: A Snapback Network Model';
end
