function [A, meta] = gen_lfr_undirected(N,tau1,tau2,mu,average_degree,min_community,max_community,max_degree,max_iters,seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_LFR_UNDIRECTED 离散幂律社区 LFR 无向简单图（NetworkX 3.5 配线流程移植）。
% 用法：[A,meta]=gen_lfr_undirected(N,tau1,tau2,mu,average_degree,...
%              min_community,max_community,max_degree,max_iters,seed)
% tau1/tau2>1；mu 在 [0,1]；社区和最大度界限必须显式给出。
% max_iters 限制度序列/社区序列抽样；分配与配线预算为 10*N*max_iters。
% seed 默认为 1，无自动更换种子，也不强制连通。
% 按 NetworkX 原流程，目标度来自幂律，逐节点补边会令部分实际度超出目标；
% mu 是配线目标，meta 记录实际逐节点度和混合比例，不声称严格满足每个度。
% 移植差异：截断 Zipf 用等价有限离散逆 CDF；MATLAB twister 随机流；
% 确定社区遍历顺序；直接禁止自环；配线遇不可行容量或预算耗尽明确失败。
% 原作者 LFR 则使用连续近似、配置模型后重连；此处不冒充作者二进制原版。
% 输出稀疏 logical 对称 A；meta.community 为逐节点社区编号。
% 原始文献：Lancichinetti, Fortunato & Radicchi (2008), Phys. Rev. E 78,
% 046110, doi:10.1103/PhysRevE.78.046110。固定参考源码为 NetworkX 3.5。
if nargin < 10, seed = 1; end
validateattributes(N,{'numeric'},{'scalar','real','finite','integer','>=',2},mfilename,'N');
N = full(double(N));
validateattributes(tau1,{'numeric'},{'scalar','real','finite','>',1},mfilename,'tau1');
tau1 = full(double(tau1));
validateattributes(tau2,{'numeric'},{'scalar','real','finite','>',1},mfilename,'tau2');
tau2 = full(double(tau2));
validateattributes(mu,{'numeric'},{'scalar','real','finite','>=',0,'<=',1},mfilename,'mu');
mu = full(double(mu));
validateattributes(max_degree,{'numeric'},{'scalar','real','finite','integer','>=',1,'<',N},mfilename,'max_degree');
max_degree = full(double(max_degree));
validateattributes(average_degree,{'numeric'},{'scalar','real','finite','>=',1,'<=',max_degree},mfilename,'average_degree');
average_degree = full(double(average_degree));
validateattributes(min_community,{'numeric'},{'scalar','real','finite','integer','>=',1,'<=',N},mfilename,'min_community');
min_community = full(double(min_community));
validateattributes(max_community,{'numeric'},{'scalar','real','finite','integer','>=',min_community,'<=',N},mfilename,'max_community');
max_community = full(double(max_community));
validateattributes(max_iters,{'numeric'},{'scalar','real','finite','integer','>=',1},mfilename,'max_iters');
max_iters = full(double(max_iters));
guard = gg_seed(seed); %#ok<NASGU>

% Port of _generate_min_degree, including its unbounded-Zipf normalization.
min_degree = generate_min_degree(tau1,average_degree,max_degree,max_iters);
[degrees,degree_trials] = powerlaw_degrees(N,tau1,min_degree,max_degree,max_iters);
[sizes,community_trials] = powerlaw_sizes(N,tau2,min_community,max_community,max_iters);
budget = 10*double(N)*double(max_iters);
communities = cell(numel(sizes),1);
community = zeros(N,1); free = (1:N).';
assignment_attempts = 0;
while ~isempty(free) && assignment_attempts < budget
    assignment_attempts = assignment_attempts+1;
    u = free(end); free(end) = [];
    c = randi(numel(sizes));
    inside_target = round_even(degrees(u)*(1-mu));
    if inside_target < sizes(c)
        communities{c}(end+1) = u;
        community(u) = c;
    else
        free(end+1) = u;
    end
    if numel(communities{c}) > sizes(c)
        % Python set.pop has implementation-specific order; choose the smallest ID.
        [removed,index] = min(communities{c});
        communities{c}(index) = [];
        community(removed) = 0;
        free(end+1) = removed;
    end
end
if ~isempty(free)
    error('graphgen:LFRCommunityAssignment', ...
        'LFR 社区分配在 %d 次预算内失败；请显式调整社区界限或预算。',budget);
end
if any(arrayfun(@(c)sum(community==c),(1:numel(sizes)).') ~= sizes)
    error('graphgen:LFRCommunityAssignment','LFR 社区规模约束未满足。');
end

A = sparse(false(N,N)); actual_degrees = zeros(N,1);
edge_attempts = 0;
for c = 1:numel(sizes)
    nodes = sort(communities{c});
    for u = nodes
        inside_target = round_even(degrees(u)*(1-mu));
        while actual_degrees(u) < inside_target
            candidates = nodes(nodes~=u);
            if isempty(candidates) || all(A(u,candidates))
                error('graphgen:LFRWiringCapacity','LFR 简单图内部配线容量不足，节点 %d。',u);
            end
            edge_attempts = edge_attempts+1;
            if edge_attempts > budget
                error('graphgen:LFRWiringBudget','LFR 配线超过 %d 次明确预算。',budget);
            end
            v = candidates(randi(numel(candidates)));
            if ~A(u,v)
                A(u,v) = true; A(v,u) = true;
                actual_degrees([u,v]) = actual_degrees([u,v])+1;
            end
        end
        while actual_degrees(u) < degrees(u)
            candidates = find(community~=c);
            if isempty(candidates) || all(A(u,candidates))
                error('graphgen:LFRWiringCapacity','LFR 简单图外部配线容量不足，节点 %d。',u);
            end
            edge_attempts = edge_attempts+1;
            if edge_attempts > budget
                error('graphgen:LFRWiringBudget','LFR 配线超过 %d 次明确预算。',budget);
            end
            % Original code samples all N nodes and rejects same-community draws.
            v = randi(N);
            if community(v)~=c && ~A(u,v)
                A(u,v) = true; A(v,u) = true;
                actual_degrees([u,v]) = actual_degrees([u,v])+1;
            end
        end
    end
end
[edge_u,edge_v] = find(A);
outside = community(edge_u)~=community(edge_v);
outside_degree = accumarray(edge_u(outside),1,[N,1]);
actual_mu = outside_degree./actual_degrees;
actual_mu(actual_degrees==0) = NaN;
params = struct('N',double(N),'tau1',double(tau1),'tau2',double(tau2), ...
    'mu',double(mu),'average_degree',double(average_degree), ...
    'min_community',double(min_community),'max_community',double(max_community), ...
    'max_degree',double(max_degree),'max_iters',double(max_iters), ...
    'min_degree',min_degree,'minimum_degree_tolerance',1e-7, ...
    'construction','networkx_3_5_discrete_powerlaws_explicit_wiring_simple_graph_port', ...
    'degree_constraint','target_lower_bounds_not_exact_degrees', ...
    'self_loops',false,'connectivity_conditioning',false, ...
    'source_differences',{{'finite_inverse_cdf_zipf','matlab_twister_rng', ...
        'ascending_community_node_order','smallest_node_eviction', ...
        'reject_self_loops_during_wiring','explicit_wiring_budget'}});
[A,meta] = gg_finalize(A,'LFR',false,seed,params);
meta.community = community;
meta.community_sizes = sizes;
meta.target_degrees = degrees;
meta.target_internal_degrees = round_even(degrees*(1-mu));
meta.actual_degrees = actual_degrees;
meta.actual_external_degrees = outside_degree;
meta.actual_mu_per_node = actual_mu;
meta.actual_mu_edge_fraction = sum(outside_degree)/sum(actual_degrees);
meta.degree_overshoot = actual_degrees-degrees;
meta.degree_sequence_trials = degree_trials;
meta.community_sequence_trials = community_trials;
meta.assignment_attempts = assignment_attempts;
meta.edge_attempts = edge_attempts;
meta.failure_budget = struct('sequence_trials',double(max_iters), ...
    'community_assignment_attempts',budget,'wiring_attempts',budget);
meta.reference_id = 'networkx_3_5_LFR_benchmark_graph';
end

function result = round_even(value)
result = floor(value+.5);
ties = (value-floor(value)) == .5;
% Python round uses ties-to-even; MATLAB round uses ties-away-from-zero.
result(ties) = floor(value(ties)) + mod(floor(value(ties)),2);
end

function minimum = generate_min_degree(gamma,target,maximum,max_iters)
upper = double(maximum); lower = 1; midpoint = (upper-lower)/2+lower;
mid_average = 0; iteration = 0;
while abs(mid_average-target) > 1e-7
    if iteration > max_iters
        error('graphgen:LFRMinimumDegree','LFR 无法在 %d 次预算内匹配平均度参数。',max_iters);
    end
    denominator = hurwitz_zeta(gamma,midpoint);
    if ~isfinite(denominator) || denominator<=0
        error('graphgen:LFRMinimumDegree','LFR 幂律参数导致不可用的 Zipf 归一化。');
    end
    mid_average = sum((floor(midpoint):maximum).^(-gamma+1))/denominator;
    if mid_average > target
        upper = midpoint; midpoint = (upper-lower)/2+lower;
    else
        lower = midpoint; midpoint = (upper-lower)/2+lower;
    end
    iteration = iteration+1;
end
minimum = round_even(midpoint);
if minimum<1 || minimum>maximum
    error('graphgen:LFRMinimumDegree','LFR 推导的最小度不在允许范围内。');
end
end

function value = hurwitz_zeta(s,q)
% Euler-Maclaurin evaluation of zeta(s,q), without a toolbox dependency.
cutoff = 32; x = q+cutoff;
value = sum((q+(0:cutoff-1)).^(-s))+x^(1-s)/(s-1)+.5*x^(-s);
coefficients = [1/12,-1/720,1/30240,-1/1209600,1/47900160,-691/1307674368000];
rising = s;
for k = 1:numel(coefficients)
    if k>1, rising = rising*(s+2*k-3)*(s+2*k-2); end
    value = value+coefficients(k)*rising*x^(-s-2*k+1);
end
end

function cdf = zipf_cdf(gamma,low,high)
% Scale by the first probability so a steep valid power law cannot underflow
% every weight to zero before normalization.
weights = exp(-gamma*(log(double(low):double(high))-log(double(low))));
cdf = cumsum(weights/sum(weights)); cdf(end) = 1;
end

function value = zipf_draw(cdf,low)
value = low+find(rand<=cdf,1,'first')-1;
end

function [sequence,trials] = powerlaw_degrees(N,gamma,low,high,max_iters)
cdf = zipf_cdf(gamma,low,high);
for trials = 1:max_iters
    sequence = zeros(N,1);
    for node = 1:N, sequence(node) = zipf_draw(cdf,low); end
    if mod(sum(sequence),2)==0, return; end
end
error('graphgen:LFRDegreeSequence','LFR 幂律度序列在 %d 次预算内未满足偶数总度。',max_iters);
end

function [sequence,trials] = powerlaw_sizes(N,gamma,low,high,max_iters)
cdf = zipf_cdf(gamma,low,high);
for trials = 1:max_iters
    sequence = zeros(0,1); total = 0;
    while total<N
        size = zipf_draw(cdf,low); sequence(end+1,1) = size; %#ok<AGROW>
        total = total+size;
    end
    if total==N, return; end
end
error('graphgen:LFRCommunitySequence','LFR 幂律社区规模在 %d 次预算内未能合计为 N。',max_iters);
end
