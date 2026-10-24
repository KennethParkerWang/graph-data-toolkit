function [A, meta] = gen_rhg_undirected(N, R, alpha, T, seed)
%GEN_RHG_UNDIRECTED 曲率 -1 的有限温度随机双曲图。
% [A,meta] = gen_rhg_undirected(N,R,alpha,T,seed)，seed 默认 1。
% 径向 CDF=(cosh(alpha*r)-1)/(cosh(alpha*R)-1)，角度均匀。
% T=0 按 d<=R 连边；T>0 按 1/(1+exp((d-R)/(2*T))) 独立连边。
% R 不直接指定实际平均度；不按连通性或度数筛选生成结果。
% 数值范围：0<=R<=350、alpha>0、alpha*R<=700、T>=0。
% 参考：Krioukov et al., Phys. Rev. E 82, 036106 (2010), 式 (5),(17),(41)。
% https://arxiv.org/abs/1006.5169
if nargin < 5
    seed = 1;
end
validateattributes(N, {'numeric'}, {'real','finite','scalar','integer','positive'}, mfilename, 'N');
validateattributes(R, {'numeric'}, {'real','finite','scalar','nonnegative'}, mfilename, 'R');
validateattributes(alpha, {'numeric'}, {'real','finite','scalar','positive'}, mfilename, 'alpha');
validateattributes(T, {'numeric'}, {'real','finite','scalar','nonnegative'}, mfilename, 'T');
validateattributes(seed, {'numeric'}, {'real','finite','scalar','integer','>=',0,'<=',2^32-1}, mfilename, 'seed');
N = full(double(N)); R = full(double(R)); alpha = full(double(alpha)); T = full(double(T));
seed = full(double(seed));
if R > 350 || ~isfinite(alpha*R) || alpha*R > 700
    error('graphgen:RHGNumericRange', '要求 R<=350 且 alpha*R<=700，避免双曲函数溢出。');
end
guard = gg_seed(seed); %#ok<NASGU>
uniform_r = rand(N, 1);
half_scale = alpha*R/2;
if half_scale == 0
    % R=0 collapses the disk; underflow of alpha*R uses its uniform-disk limit.
    r = R*sqrt(uniform_r);
else
    % Equivalent to acosh(1+U*(cosh(alpha*R)-1))/alpha without cancellation.
    r = R*(asinh(sqrt(uniform_r)*sinh(half_scale))/half_scale);
end
r = min(R, max(0, r));
angles = 2*pi*rand(N, 1);
rows = cell(N, 1); cols = cell(N, 1);
for node = 1:N-1
    others = node+1:N;
    delta = angles(node)-angles(others);
    % cosh(d)=cosh(ri)*cosh(rj)-sinh(ri)*sinh(rj)*cos(delta).
    % The equivalent asinh identity also resolves very small radii accurately.
    distance = 2*asinh(hypot(sinh((r(node)-r(others))/2), ...
        sqrt(sinh(r(node)))*sqrt(sinh(r(others))).*sin(delta/2)));
    if T == 0
        chosen = others(distance <= R);
    else
        z = (distance-R)/(2*T);
        probability = zeros(size(z));
        positive = z >= 0;
        e = exp(-z(positive));
        probability(positive) = e./(1+e);
        probability(~positive) = 1./(1+exp(z(~positive)));
        chosen = others(rand(size(probability)) < probability);
    end
    rows{node} = repmat(node, numel(chosen), 1);
    cols{node} = chosen(:);
end
source = vertcat(rows{:}); target = vertcat(cols{:});
upper = sparse(source, target, ones(numel(source),1), N, N);
A = logical(upper+upper.');
parameters = struct('N',N, 'R',R, 'alpha',alpha, 'T',T, 'curvature',-1, ...
    'radial_distribution','alpha*sinh(alpha*r)/(cosh(alpha*R)-1)', ...
    'coordinate_system','native_hyperbolic_polar', ...
    'connection_probability','T=0: distance<=R; T>0: logistic((R-distance)/(2*T))', ...
    'connectivity_conditioning',false, 'numeric_max_R',350, 'numeric_max_alpha_R',700);
[A, meta] = gg_finalize(A, 'RHG', false, seed, parameters);
meta.r = r;
meta.angles = angles;
meta.reference_id = 'krioukov_2010_hyperbolic_geometry';
meta.reference_url = 'https://arxiv.org/abs/1006.5169';
meta.construction = 'Independent unordered-pair trials in a curvature -1 disk; stable exact hyperbolic distance';
end
