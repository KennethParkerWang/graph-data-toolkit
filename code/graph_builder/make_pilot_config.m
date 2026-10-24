function config = make_pilot_config(output_file, node_counts, mean_degrees, samples, base_seed)
%MAKE_PILOT_CONFIG 按节点数与目标平均度生成无向先导实验JSON配置。
% 用法：make_pilot_config('configs/pilot.json', [100 300 500], [4 8 12], 5, 20260927)
% 参数：N和目标k为正整数列表；k须为正偶数且小于每个N。
% 规则：ER-Gnm用M=N*k/2，WS用K=k/2，BA用m=k/2并保留有限N修正。
% 输出：写JSON，不生成图；已有文件不覆盖。默认27组参数、135张图。
if nargin < 2
    node_counts = [100 300 500];
end
if nargin < 3
    mean_degrees = [4 8 12];
end
if nargin < 4
    samples = 5;
end
if nargin < 5
    base_seed = 20260927;
end
validateattributes(node_counts, {'numeric'}, {'vector', 'nonempty', 'integer', 'finite', '>=', 3});
validateattributes(mean_degrees, {'numeric'}, {'vector', 'nonempty', 'integer', 'finite', 'positive'});
validateattributes(samples, {'numeric'}, {'scalar', 'integer', 'finite', 'positive'});
validateattributes(base_seed, {'numeric'}, {'scalar', 'integer', 'finite', '>=', 0, '<=', 2^32-1});
if any(mod(mean_degrees, 2) ~= 0) || max(mean_degrees) >= min(node_counts)
    error('graphgen:PilotDegree', '此先导配置要求偶数目标k，且所有k小于所有N。');
end
planned = 3*numel(node_counts)*numel(mean_degrees)*samples;
if base_seed + planned - 1 > 2^32-1
    error('graphgen:BatchSeedOverflow', 'seed范围溢出。');
end
output_file = char(output_file);
if isfile(output_file) || isfolder(output_file)
    error('graphgen:FileExists', '配置路径已存在: %s', output_file);
end
[parent, ~, extension] = fileparts(output_file);
if ~strcmpi(extension, '.json') || (~isempty(parent) && ~isfolder(parent))
    error('graphgen:PilotPath', '使用.json文件名，父目录须已存在。');
end
jobs = cell(3*numel(node_counts)*numel(mean_degrees), 1);
index = 0;
for N = node_counts(:).'
    for k = mean_degrees(:).'
        index = index + 1;
        jobs{index} = struct('model', 'er_gnm', 'direction', 'undirected', ...
            'parameters', struct('N', N, 'M', N*k/2));
        index = index + 1;
        jobs{index} = struct('model', 'ba', 'direction', 'undirected', ...
            'parameters', struct('N', N, 'm', k/2));
        index = index + 1;
        jobs{index} = struct('model', 'ws', 'direction', 'undirected', ...
            'parameters', struct('N', N, 'K', k/2, 'beta', 0.1));
    end
end
project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
config_parent = java.io.File(output_file).getCanonicalFile().getParentFile().toPath();
dataset_path = java.io.File(fullfile(project_root,'datasets','validation_samples','pilot_dataset')).toPath();
output_dir = strrep(char(config_parent.relativize(dataset_path)),'\','/');
config = struct('schema_version', 2, 'dataset_id', 'pilot', ...
    'output_dir', output_dir, 'base_seed', base_seed, ...
    'samples_per_combination', samples, 'resume', true, ...
    'on_error', 'continue', 'max_graphs', max(10000, planned), 'jobs', {jobs});
[file_id, message] = fopen(output_file, 'w', 'n', 'UTF-8');
if file_id < 0
    error('graphgen:PilotWrite', '无法写配置: %s', message);
end
close_file = onCleanup(@() fclose(file_id));
fprintf(file_id, '%s\n', jsonencode(config, 'PrettyPrint', true));
fprintf('PILOT_CONFIG_OK: %d jobs, %d planned graphs. BA实际平均度须读meta。\n', numel(jobs), planned);
end
