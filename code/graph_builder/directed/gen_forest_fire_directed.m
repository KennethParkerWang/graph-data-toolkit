function [A, meta] = gen_forest_fire_directed(N, p_forward, p_backward, seed)
%GEN_FOREST_FIRE_DIRECTED 单 ambassador、零起点几何燃烧的有向增长图。
% [A,meta] = gen_forest_fire_directed(N,p_forward,p_backward,seed)。
% 概率均在 [0,1)，seed 默认 1；几何数 K 满足 Pr(K=k)=(1-p)*p^k。
% 对旧图邻居分别向前/向后燃烧，均匀不放回选取，每轮不重复访问。
% 新点只向被烧到的旧点连边；无自环、原生 DAG，始终弱连通。
% 论文参数 r 对应 p_backward=r*p_forward（p_forward>0 时）。
% KDD05 §4.2.1 几何均值的文字与零起点约定不同；本实现明确采用
% 作者 SNAP BurnGeoFire 的 geometric(1-p)-1 约定，而非逐字宣称等价。
% Leskovec, Kleinberg, Faloutsos, KDD 2005:
% https://www-cs.stanford.edu/~jure/pubs/powergrowth-kdd05.pdf
% 零起点约定核对：https://github.com/snap-stanford/snap/blob/master/snap-core/ff.cpp
if nargin < 4
    seed = 1;
end
validateattributes(N, {'numeric'}, {'real','finite','scalar','integer','positive'}, mfilename, 'N');
validateattributes(p_forward, {'numeric'}, {'real','finite','scalar','>=',0,'<',1}, mfilename, 'p_forward');
validateattributes(p_backward, {'numeric'}, {'real','finite','scalar','>=',0,'<',1}, mfilename, 'p_backward');
validateattributes(seed, {'numeric'}, {'real','finite','scalar','integer','>=',0,'<=',2^32-1}, mfilename, 'seed');
N = full(double(N)); p_forward = full(double(p_forward)); p_backward = full(double(p_backward));
seed = full(double(seed));
guard = gg_seed(seed); %#ok<NASGU>
out_neighbors = cell(N, 1); in_neighbors = cell(N, 1);
ambassadors = zeros(N, 1);
for node = 2:N
    ambassadors(node) = randi(node-1);
    visited = false(1, node-1);
    visited(ambassadors(node)) = true;
    frontier = zeros(1, node-1);
    frontier(1) = ambassadors(node);
    head = 1; tail = 1;
    while head <= tail
        burning = frontier(head); head = head+1;
        chosen = sample_burn(out_neighbors{burning}, visited, p_forward);
        visited(chosen) = true;
        frontier(tail+(1:numel(chosen))) = chosen;
        tail = tail+numel(chosen);
        chosen = sample_burn(in_neighbors{burning}, visited, p_backward);
        visited(chosen) = true;
        frontier(tail+(1:numel(chosen))) = chosen;
        tail = tail+numel(chosen);
    end
    targets = find(visited);
    out_neighbors{node} = targets;
    for target = targets
        in_neighbors{target}(end+1) = node;
    end
end
counts = cellfun(@numel, out_neighbors);
sources = repelem((1:N).', counts);
targets = [out_neighbors{:}].';
A = logical(sparse(sources, targets, ones(numel(sources),1), N, N));
ratio = [];
ratio_finite = false;
if p_forward > 0
    ratio = p_backward/p_forward;
    ratio_finite = isfinite(ratio);
    if ~ratio_finite
        ratio = [];
    end
end
parameters = struct('N',N, 'p_forward',p_forward, 'p_backward',p_backward, ...
    'initial_nodes',1, 'ambassadors_per_new_node',1, ...
    'geometric_support','0,1,2,...', 'geometric_pmf','Pr(K=k)=(1-p)*p^k', ...
    'mean_forward_burn_count',p_forward/(1-p_forward), ...
    'mean_backward_burn_count',p_backward/(1-p_backward), ...
    'paper_backward_ratio',ratio, 'paper_backward_ratio_defined',p_forward>0, ...
    'paper_backward_ratio_finite',ratio_finite, ...
    'paper_backward_ratio_note','Empty if p_forward=0 or the ratio exceeds finite double range', ...
    'burn_processing_order','breadth_first_forward_then_backward', ...
    'edge_direction','new_node_to_old_node', 'connectivity_conditioning',false);
[A, meta] = gg_finalize(A, 'Directed_Forest_Fire', true, seed, parameters);
meta.ambassadors = ambassadors;
meta.reference_id = 'leskovec_2005_forest_fire';
meta.reference_url = 'https://www-cs.stanford.edu/~jure/pubs/powergrowth-kdd05.pdf';
meta.secondary_reference_url = 'https://github.com/snap-stanford/snap/blob/master/snap-core/ff.cpp';
meta.construction = 'Single ambassador; zero-based geometric forward/backward burns on the old graph; no revisits or reciprocal repair';
meta.geometric_convention_note = 'Zero-based SNAP geometric(1-p)-1; mean p/(1-p), not the positive-geometric mean stated in KDD05 prose';
end

function selected = sample_burn(neighbors, visited, probability)
if probability == 0
    count = 0;
else
    count = floor(log1p(-rand)/log(probability));
end
neighbors = neighbors(~visited(neighbors));
count = min(count, numel(neighbors));
if count == 0
    selected = [];
else
    selected = neighbors(randperm(numel(neighbors), count));
end
end
