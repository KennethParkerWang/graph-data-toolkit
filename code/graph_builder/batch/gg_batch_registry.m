function [function_name, call_args, parameters] = gg_batch_registry(model, direction, parameters)
%GG_BATCH_REGISTRY 固定模型白名单、参数顺序、默认值与静态预检。
if ~isstruct(parameters) || ~isscalar(parameters)
    error('graphgen:BatchParameters', 'parameters 必须是 JSON 对象。');
end
if ~ismember(direction, {'directed', 'undirected'})
    error('graphgen:BatchDirection', 'direction 必须为 directed 或 undirected。');
end
if (strcmp(direction,'undirected') && ismember(model,{'eh','qs','rt','rr','rh','forest_fire'})) || ...
        (strcmp(direction,'directed') && ismember(model,{'ba','ws','nw','rgg','random_regular','hk','chung_lu', ...
        'lfr','degree_sequence','dc_sbm','waxman','duplication_divergence','rhg'}))
    error('graphgen:UnsupportedModelDirection','No verified source protocol for %s/%s.',model,direction);
end
switch model
    case 'er'
        names = {'N', 'p'};
    case {'er_gnm', 'eh', 'rt', 'rr', 'rh'}
        names = {'N', 'M'};
    case 'ba'
        names = {'N', 'm'};
    case 'sf'
        if strcmp(direction,'directed')
            names = {'N','M','sigma_out','sigma_in'};
            parameters = default_value(parameters,'sigma_out',0.5);
            parameters = default_value(parameters,'sigma_in',0.5);
        else
            names = {'N','M','sigma'};
            parameters = default_value(parameters,'sigma',0.5);
        end
    case {'ws', 'nw'}
        names = {'N', 'K', 'beta'};
    case 'qs'
        names = {'N', 'r', 'q'};
    case 'sbm'
        names = {'sizes', 'P'};
    case 'rgg'
        names = {'N', 'radius', 'dim'};
        parameters = default_value(parameters, 'dim', 2);
    case 'random_regular'
        names = {'N', 'd'};
    case 'hk'
        names = {'N', 'm', 'triad_probability'};
    case 'chung_lu'
        if strcmp(direction, 'directed')
            names = {'wout', 'win'};
        else
            names = {'w'};
        end
    case 'lfr'
        names = {'N','tau1','tau2','mu','average_degree','min_community', ...
            'max_community','max_degree','max_iters'};
    case 'degree_sequence'
        names = {'degrees','swap_attempts'};
    case 'dc_sbm'
        names = {'sizes','theta','omega'};
    case 'waxman'
        names = {'N','alpha','beta'};
    case 'duplication_divergence'
        names = {'N','p','max_attempts'};
        if isfield(parameters,'N')
            validateattributes(parameters.N,{'numeric'},{'scalar','real','finite','integer','positive'});
            parameters = default_value(parameters,'max_attempts',max(10000,100*double(parameters.N)));
        end
    case 'rhg'
        names = {'N','R','alpha','T'};
    case 'forest_fire'
        names = {'N','p_forward','p_backward'};
    otherwise
        error('graphgen:BatchModel', '未知 model: %s', model);
end
unknown = setdiff(fieldnames(parameters), names);
if ~isempty(unknown)
    error('graphgen:BatchUnknownParameter', '模型 %s 不接受参数 %s。', model, unknown{1});
end
required = names;
if strcmp(model, 'random_regular')
    required = {'N', 'd'};
end
missing = setdiff(required, fieldnames(parameters));
if ~isempty(missing)
    error('graphgen:BatchMissingParameter', '模型 %s 缺少参数 %s。', model, missing{1});
end
vector_names = {'sizes', 'P', 'w', 'wout', 'win','degrees','theta','omega'};
for index = 1:numel(names)
    name = names{index};
    if isfield(parameters, name) && ~ismember(name, vector_names)
        validateattributes(parameters.(name), {'numeric', 'logical'}, ...
            {'scalar', 'real', 'finite'}, mfilename, name);
        if ~strcmp(name, 'periodic')
            parameters.(name) = full(double(parameters.(name)));
        end
    end
end
if isfield(parameters, 'N')
    validateattributes(parameters.N, {'numeric'}, {'integer', 'positive', '<=',double(intmax('uint32'))});
    N = parameters.N;
end
if isfield(parameters, 'M')
    validateattributes(parameters.M, {'numeric'}, {'integer', 'nonnegative'});
    limit = N*(N-1)/2;
    if ismember(model, {'er_gnm','eh','sf'}) && strcmp(direction, 'directed')
        limit = 2*limit;
    end
    if parameters.M > limit
        error('graphgen:BatchEdgeCount', 'M 超过该模型的最大边/弧数。');
    end
    if strcmp(model,'er_gnm') && limit > flintmax
        error('graphgen:BatchPairPrecision','ER-Gnm pair count exceeds exact double integer capacity.');
    end
end
switch model
    case 'er'
        probability(parameters.p, 'p');
    case 'ba'
        validateattributes(parameters.m, {'numeric'}, {'integer', 'positive', '<', N});
    case 'hk'
        validateattributes(parameters.m, {'numeric'}, {'integer', 'positive', '<=', N});
        probability(parameters.triad_probability, 'triad_probability');
    case 'sf'
        if strcmp(direction,'directed')
            validateattributes(parameters.sigma_out,{'numeric'},{'>=',0,'<',1});
            validateattributes(parameters.sigma_in,{'numeric'},{'>=',0,'<',1});
        else
            validateattributes(parameters.sigma,{'numeric'},{'>=',0,'<',1});
        end
    case {'ws', 'nw'}
        validateattributes(parameters.K, {'numeric'}, {'integer', 'positive', '<', N/2});
        probability(parameters.beta, 'beta');
    case 'qs'
        validateattributes(N, {'numeric'}, {'>=', 2});
        validateattributes(parameters.r, {'numeric'}, {'integer', 'positive', '<', N});
        probability(parameters.q, 'q');
    case {'rt', 'rr', 'rh'}
        minimum_sizes = struct('rt',3,'rr',5,'rh',7);
        if N < minimum_sizes.(model)
            error('graphgen:BatchPolygonSize', 'N 低于作者 %s 实现的可执行边界。', model);
        end
    case 'sbm'
        validateattributes(parameters.sizes, {'numeric'}, ...
            {'vector', 'nonempty', 'real', 'finite', 'integer', 'positive'});
        parameters.sizes = double(parameters.sizes(:));
        if sum(parameters.sizes) > double(intmax('uint32'))
            error('graphgen:BatchNodeLimit','SBM total N exceeds graph-v1 uint32 capacity.');
        end
        num_communities = numel(parameters.sizes);
        validateattributes(parameters.P, {'numeric'}, ...
            {'real', 'finite', 'size', [num_communities num_communities], '>=', 0, '<=', 1});
        if strcmp(direction, 'undirected') && ~isequal(parameters.P, parameters.P.')
            error('graphgen:BatchSBMSymmetry', '无向 SBM 要求 P 严格对称。');
        end
    case 'rgg'
        validateattributes(parameters.radius, {'numeric'}, {'nonnegative'});
        validateattributes(parameters.dim, {'numeric'}, {'integer', 'positive'});
    case 'random_regular'
        validateattributes(parameters.d, {'numeric'}, {'integer', 'nonnegative', '<', N});
        if mod(N*parameters.d,2) ~= 0
            error('graphgen:BatchRegularParity','无向正则图要求 N*d 为偶数。');
        end
    case 'lfr'
        validateattributes(N,{'numeric'},{'>=',2});
        validateattributes(parameters.tau1,{'numeric'},{'>',1});
        validateattributes(parameters.tau2,{'numeric'},{'>',1});
        probability(parameters.mu,'mu');
        validateattributes(parameters.max_degree,{'numeric'},{'integer','>=',1,'<',N});
        validateattributes(parameters.average_degree,{'numeric'},{'>=',1,'<=',parameters.max_degree});
        validateattributes(parameters.min_community,{'numeric'},{'integer','>=',1,'<=',N});
        validateattributes(parameters.max_community,{'numeric'},{'integer','>=',parameters.min_community,'<=',N});
        validateattributes(parameters.max_iters,{'numeric'},{'integer','positive'});
    case 'degree_sequence'
        validateattributes(parameters.degrees,{'numeric'}, ...
            {'vector','nonempty','real','finite','integer','nonnegative'});
        parameters.degrees = full(double(parameters.degrees(:)));
        degree_count = numel(parameters.degrees);
        if degree_count > double(intmax('uint32')) || any(parameters.degrees >= degree_count) || ...
                mod(sum(parameters.degrees),2) ~= 0
            error('graphgen:BatchDegreeSequence','简单图度序列越界或总度不为偶数。');
        end
        validateattributes(parameters.swap_attempts,{'numeric'},{'integer','nonnegative'});
    case 'dc_sbm'
        validateattributes(parameters.sizes,{'numeric'},{'vector','nonempty','real','finite','integer','positive'});
        parameters.sizes = full(double(parameters.sizes(:)));
        block_count = numel(parameters.sizes);
        node_count = sum(parameters.sizes);
        if node_count > double(intmax('uint32'))
            error('graphgen:BatchNodeLimit','DC-SBM total N exceeds graph-v1 uint32 capacity.');
        end
        validateattributes(parameters.theta,{'numeric'},{'vector','real','finite','nonnegative','<=',1,'numel',node_count});
        parameters.theta = full(double(parameters.theta(:)));
        validateattributes(parameters.omega,{'numeric'},{'real','finite','nonnegative','size',[block_count block_count]});
        parameters.omega = full(double(parameters.omega));
        if ~isequal(parameters.omega,parameters.omega.')
            error('graphgen:BatchDCSBMSymmetry','无向 DC-SBM 要求 omega 严格对称。');
        end
        groups = repelem((1:block_count).',parameters.sizes); groups = groups(:);
        sums = accumarray(groups,parameters.theta,[block_count 1]);
        if any(abs(sums-1) > 1e-12)
            error('graphgen:BatchDCSBMTheta','每个社区内 theta 之和必须为1。');
        end
    case 'waxman'
        validateattributes(parameters.alpha,{'numeric'},{'positive'});
        probability(parameters.beta,'beta');
    case 'duplication_divergence'
        validateattributes(N,{'numeric'},{'>=',2});
        validateattributes(parameters.p,{'numeric'},{'>',0,'<=',1});
        validateattributes(parameters.max_attempts,{'numeric'},{'integer','nonnegative'});
    case 'rhg'
        validateattributes(parameters.R,{'numeric'},{'nonnegative','<=',350});
        validateattributes(parameters.alpha,{'numeric'},{'positive'});
        validateattributes(parameters.T,{'numeric'},{'nonnegative'});
        if parameters.alpha*parameters.R > 700
            error('graphgen:BatchRHGRange','alpha*R 超出稳定数值范围700。');
        end
    case 'forest_fire'
        validateattributes(parameters.p_forward,{'numeric'},{'>=',0,'<',1});
        validateattributes(parameters.p_backward,{'numeric'},{'>=',0,'<',1});
    case 'chung_lu'
        for index = 1:numel(names)
            name = names{index};
            validateattributes(parameters.(name), {'numeric'}, ...
                {'vector', 'nonempty', 'real', 'finite', 'nonnegative'});
            weights = parameters.(name);
            parameters.(name) = double(weights(:));
        end
        if strcmp(direction, 'directed')
            out_weights = parameters.wout;
            in_weights = parameters.win;
            out_sum = sum(out_weights);
            in_sum = sum(in_weights);
            if numel(out_weights) ~= numel(in_weights) || ~isfinite(out_sum) || ...
                    ~isfinite(in_sum) || abs(out_sum-in_sum) > 64*eps(max([out_sum in_sum 1]))
                error('graphgen:BatchWeights', '有向 Chung-Lu 权重必须等长且总和相等、有限。');
            end
            weight_sum = out_sum/2 + in_sum/2;
            if weight_sum > 0
                for node = 1:numel(out_weights)
                    probabilities = out_weights(node)*(in_weights/weight_sum);
                    probabilities(node) = 0;
                    if any(probabilities > 1)
                        error('graphgen:BatchWeights', 'Chung-Lu 非自环概率大于 1。');
                    end
                end
            end
        else
            weights = parameters.w;
            weight_sum = sum(weights);
            if ~isfinite(weight_sum)
                error('graphgen:BatchWeights', 'Chung-Lu 权重总和必须有限。');
            end
        end
end
function_name = ['gen_' model '_' direction];
call_args = cell(1, numel(names));
for index = 1:numel(names)
    call_args{index} = parameters.(names{index});
end
parameters = orderfields(parameters);
end

function output = default_value(input, name, value)
output = input;
if ~isfield(output, name)
    output.(name) = value;
end
end

function probability(value, name)
validateattributes(value, {'numeric'}, {'>=', 0, '<=', 1}, mfilename, name);
end
