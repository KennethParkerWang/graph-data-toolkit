function [config, plan, config_digest, config_path] = gg_batch_plan(config_file)
%GG_BATCH_PLAN 读取并预检 JSON，展开确定顺序的标量参数网格。
config_file = char(config_file);
config_path_file = java.io.File(config_file);
% Explicit existing paths retain MATLAB-pwd semantics. Built-in configs can
% also be located from this module when the caller is in another directory.
if ~config_path_file.isAbsolute()
    candidate = fullfile(pwd,config_file);
    if ~isfile(candidate)
        module_root = fileparts(fileparts(mfilename('fullpath')));
        normalized = strrep(config_file,'\','/');
        if startsWith(normalized,'configs/')
            candidate = fullfile(module_root,config_file);
        elseif startsWith(normalized,'graph_builder/')
            candidate = fullfile(fileparts(module_root),config_file);
        elseif startsWith(normalized,'code/graph_builder/')
            candidate = fullfile(fileparts(fileparts(module_root)),config_file);
        end
    end
    config_path_file = java.io.File(candidate);
end
config_path = char(config_path_file.getCanonicalPath());
if ~isfile(config_path)
    error('graphgen:BatchConfigMissing', '配置文件不存在: %s', config_file);
end
config = jsondecode(fileread(config_path));
require_object(config, 'config');
allowed = {'schema_version', 'dataset_id', 'output_dir', 'base_seed', ...
    'samples_per_combination', 'resume', 'on_error', 'max_graphs', 'jobs'};
reject_unknown(config, allowed, 'config');
required = {'schema_version', 'dataset_id', 'output_dir', 'base_seed', 'jobs'};
require_fields(config, required, 'config');
validateattributes(config.schema_version, {'numeric'}, {'scalar', 'integer', 'finite'});
if config.schema_version ~= 2
    error('graphgen:BatchSchemaVersion', '仅支持生成配置 schema_version=2。');
end
config.dataset_id = text_value(config.dataset_id, 'dataset_id');
if isempty(regexp(config.dataset_id, '^[A-Za-z][A-Za-z0-9_-]*$', 'once'))
    error('graphgen:BatchDatasetName', 'dataset_id 必须以英文字母开头，仅含字母、数字、_、-。');
end
output_dir = text_value(config.output_dir, 'output_dir');
if isempty(output_dir)
    error('graphgen:BatchOutputPath', 'output_dir 不能为空。');
end
output_file = java.io.File(output_dir);
if ~output_file.isAbsolute()
    output_dir = fullfile(fileparts(config_path), output_dir);
end
canonical_output = java.io.File(output_dir);
config.output_dir = char(canonical_output.getCanonicalPath());
validateattributes(config.base_seed, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', '>=', 0, '<=', 2^32-1});
config = set_default(config, 'samples_per_combination', 1);
config = set_default(config, 'resume', true);
config = set_default(config, 'on_error', 'continue');
config = set_default(config, 'max_graphs', 10000);
validateattributes(config.samples_per_combination, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', 'positive'});
validateattributes(config.max_graphs, {'numeric'}, ...
    {'scalar', 'real', 'finite', 'integer', 'positive'});
validateattributes(config.resume, {'logical', 'numeric'}, {'scalar', 'binary'});
config.resume = logical(config.resume);
config.on_error = text_value(config.on_error, 'on_error');
if ~ismember(config.on_error, {'continue', 'stop'})
    error('graphgen:BatchOnError', 'on_error 仅允许 continue 或 stop。');
end
if isstruct(config.jobs)
    jobs = num2cell(config.jobs(:));
elseif iscell(config.jobs)
    jobs = config.jobs(:);
else
    error('graphgen:BatchJobs', 'jobs 必须为非空 JSON 对象数组。');
end
if isempty(jobs)
    error('graphgen:BatchJobs', 'jobs 不能为空。');
end
plan = struct('sample_id', {}, 'job_id', {}, 'combination_id', {}, 'replicate', {}, ...
    'model', {}, 'direction', {}, 'parameters', {}, 'seed', {}, 'generator_id', {}, ...
    'source_classification', {});
for job_id = 1:numel(jobs)
    job = jobs{job_id};
    require_object(job, 'job');
    reject_unknown(job, {'model', 'direction', 'parameters', 'grid', 'samples'}, 'job');
    require_fields(job, {'model', 'direction', 'parameters'}, 'job');
    job.model = text_value(job.model, 'model');
    job.direction = text_value(job.direction, 'direction');
    require_object(job.parameters, 'parameters');
    job = set_default(job, 'grid', struct());
    job = set_default(job, 'samples', config.samples_per_combination);
    require_object(job.grid, 'grid');
    validateattributes(job.samples, {'numeric'}, {'scalar', 'real', 'finite', 'integer', 'positive'});
    grid_names = sort(fieldnames(job.grid));
    grid_values = cell(size(grid_names));
    combination_count = 1;
    for index = 1:numel(grid_names)
        name = grid_names{index};
        if ismember(name, {'sizes', 'P', 'w', 'wout', 'win','degrees','theta','omega'})
            error('graphgen:BatchVectorGrid', '向量/矩阵参数 %s 不支持 grid，请分成多个 job。', name);
        end
        values = expand_grid(job.grid.(name), config.max_graphs);
        grid_values{index} = values;
        job.grid.(name) = values;
        combination_count = combination_count*numel(values);
        if combination_count*job.samples + numel(plan) > config.max_graphs
            error('graphgen:BatchMaxGraphs', '计划图数超过 max_graphs=%d。', config.max_graphs);
        end
    end
    if combination_count*job.samples + numel(plan) > config.max_graphs
        error('graphgen:BatchMaxGraphs', '计划图数超过 max_graphs=%d。', config.max_graphs);
    end
    for combination_id = 1:combination_count
        parameters = job.parameters;
        stride = 1;
        for index = 1:numel(grid_names)
            values = grid_values{index};
            value_index = mod(floor((combination_id-1)/stride), numel(values)) + 1;
            parameters.(grid_names{index}) = values(value_index);
            stride = stride*numel(values);
        end
        [generator_id, ~, parameters] = gg_batch_registry(job.model, job.direction, parameters);
        for replicate = 1:job.samples
            sample_id = numel(plan) + 1;
            seed = config.base_seed + sample_id - 1;
            if seed > 2^32-1
                error('graphgen:BatchSeedOverflow', '计划 seed 超出 twister 的 uint32 范围。');
            end
            plan(sample_id) = struct('sample_id', sample_id, 'job_id', job_id, ...
                'combination_id', combination_id, 'replicate', replicate, ...
                'model', job.model, 'direction', job.direction, 'parameters', parameters, ...
                'seed', seed, 'generator_id', generator_id, ...
                'source_classification', gg_batch_source(job.model, job.direction));
        end
    end
    jobs{job_id} = gg_batch_canonical(job);
end
config.jobs = jobs;
config = gg_batch_canonical(config);
% 路径和运行控制不属于生成配方；移动整个数据集后仍可核验续跑。
identity = rmfield(config, {'output_dir','resume','on_error','max_graphs'});
config_digest = gg_batch_digest(jsonencode(identity));
end

function values = expand_grid(specification, limit)
if isstruct(specification)
    require_object(specification, 'grid range');
    reject_unknown(specification, {'start', 'stop', 'step'}, 'grid range');
    require_fields(specification, {'start', 'stop', 'step'}, 'grid range');
    names = {'start', 'stop', 'step'};
    for index = 1:numel(names)
        validateattributes(specification.(names{index}), {'numeric'}, {'scalar', 'real', 'finite'});
    end
    if specification.step == 0 || (specification.stop-specification.start)*specification.step < 0
        error('graphgen:BatchGridRange', 'grid 的 step 不能为零且方向必须指向 stop。');
    end
    estimate = floor((specification.stop-specification.start)/specification.step) + 1;
    if ~isfinite(estimate) || estimate > limit
        error('graphgen:BatchMaxGraphs', '单个 grid 范围超过 max_graphs。');
    end
    values = specification.start:specification.step:specification.stop;
else
    validateattributes(specification, {'numeric', 'logical'}, {'vector', 'nonempty', 'real', 'finite'});
    values = specification(:).';
end
if isempty(values) || numel(values) > limit
    error('graphgen:BatchGridRange', 'grid 不能为空或超过 max_graphs。');
end
end

function require_object(value, label)
if ~isstruct(value) || ~isscalar(value)
    error('graphgen:BatchObject', '%s 必须为 JSON 对象。', label);
end
end

function require_fields(value, names, label)
missing = setdiff(names, fieldnames(value));
if ~isempty(missing)
    error('graphgen:BatchMissingField', '%s 缺少字段 %s。', label, missing{1});
end
end

function reject_unknown(value, names, label)
unknown = setdiff(fieldnames(value), names);
if ~isempty(unknown)
    error('graphgen:BatchUnknownField', '%s 有未知字段 %s。', label, unknown{1});
end
end

function value = text_value(value, label)
if ~(ischar(value) && (isrow(value) || isempty(value))) && ~(isstring(value) && isscalar(value))
    error('graphgen:BatchText', '%s 必须为字符串。', label);
end
value = char(value);
end

function output = set_default(input, name, value)
output = input;
if ~isfield(output, name)
    output.(name) = value;
end
end
