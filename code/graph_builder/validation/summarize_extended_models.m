function report = summarize_extended_models(dataset_root)
%SUMMARIZE_EXTENDED_MODELS Read committed graph-v1 files; retain all failures.
% Writes one immutable reports/graph_diagnostics.json and two CSV tables.
% Does not regenerate graphs, change parameters or select seeds by success.
module_root = fileparts(fileparts(mfilename('fullpath')));
addpath(module_root); setup_generators();
if nargin < 1
    dataset_root = fullfile(fileparts(fileparts(module_root)),'datasets', ...
        'archive_batches','synthetic','model_validation_90_20261007');
end
dataset_root = char(java.io.File(dataset_root).getCanonicalPath());
descriptor = jsondecode(fileread(fullfile(dataset_root,'dataset.json')));
config = jsondecode(fileread(fullfile(dataset_root,'configs','generation.json')));
index_path = fullfile(dataset_root,'manifests','graphs.jsonl');
index = read_json_lines(index_path);
rows = repmat(empty_row(),numel(index),1);
for k = 1:numel(index)
    record = index{k};
    sample = gg_io_read_graph(fullfile(dataset_root,record.path),record);
    A = sample.A; N = double(sample.N); M = double(sample.M);
    meta = sample.meta; params = meta.parameters; attributes = meta.attributes;
    degree = full(sum(A,2));
    if sample.directed
        degree = degree+full(sum(A,1)).';
        G = digraph(A);
        components = conncomp(G,'Type','weak');
        strong_count = max(conncomp(G,'Type','strong'));
    else
        components = conncomp(graph(A)); strong_count = NaN;
    end
    row = empty_row();
    row.graph_id = record.graph_id; row.model = record.model;
    row.seed = double(meta.rng.seed); row.N = N; row.M = M;
    row.directed = logical(sample.directed); row.mean_degree = mean(degree);
    row.component_count_weak = max(components);
    row.component_count_strong = strong_count;
    row.largest_component_size = max(accumarray(components(:),1));
    row.isolate_count = nnz(degree==0); row.min_degree = min(degree);
    row.max_degree = max(degree); row.std_degree = std(degree);
    switch record.model
        case 'lfr'
            labels = attributes.community(:);
            [u,v] = find(A); outside = labels(u)~=labels(v);
            outside_degree = accumarray(u(outside),1,[N,1]);
            actual_mu = sum(outside_degree)/sum(degree);
            overshoot = degree-attributes.target_degrees(:);
            assert(isequal(degree,attributes.actual_degrees(:)) && all(overshoot>=0));
            assert(isequal(outside_degree,attributes.actual_external_degrees(:)));
            assert(abs(actual_mu-attributes.actual_mu_edge_fraction)<1e-14);
            row.lfr_mu_requested = params.mu; row.lfr_mu_actual = actual_mu;
            row.lfr_mean_target_degree = mean(attributes.target_degrees);
            row.lfr_degree_overshoot_mean = mean(overshoot);
            row.lfr_degree_overshoot_max = max(overshoot);
            row.lfr_community_count = max(labels);
        case 'degree_sequence'
            row.degree_sequence_max_abs_error = max(abs(degree-params.degrees(:)));
            assert(row.degree_sequence_max_abs_error==0);
            row.successful_swaps = attributes.successful_swaps;
            row.attempted_swaps = attributes.attempted_swaps;
        case 'dc_sbm'
            expected = params.expected_degree_simple_no_loops(:);
            row.expected_mean_degree = mean(expected);
            row.degree_rmse_against_expectation = sqrt(mean((degree-expected).^2));
            sums = accumarray(attributes.community(:),params.theta(:));
            row.dc_theta_group_max_error = max(abs(sums-1));
        case 'waxman'
            X = attributes.positions;
            D = hypot(X(:,1)-X(:,1).',X(:,2)-X(:,2).');
            L = max(D(:)); row.waxman_L = params.L;
            row.waxman_L_abs_error = abs(L-params.L);
            assert(row.waxman_L_abs_error<1e-13);
            if L==0, P = repmat(params.beta,N,N);
            else, P = params.beta*exp(-(D/L)/params.alpha); end
            P(1:N+1:end) = 0;
            row.expected_mean_degree = sum(P(:))/N;
        case 'duplication_divergence'
            row.duplication_attempts = attributes.duplication_attempts;
            row.rejected_duplications = attributes.rejected_duplications;
            assert(row.component_count_weak==1);
            assert(row.rejected_duplications==row.duplication_attempts-(N-2));
            part = false(N,1); part(2) = true;
            for node = 3:N, part(node) = part(attributes.duplication_parent(node)); end
            [u,v] = find(A); row.duplication_bipartite = double(all(part(u)~=part(v)));
            assert(row.duplication_bipartite);
        case 'rhg'
            r = attributes.r(:); angle = attributes.angles(:);
            row.rhg_min_radius = min(r); row.rhg_max_radius = max(r);
            assert(all(r>=0 & r<=params.R) && all(angle>=0 & angle<2*pi));
            expectation = 0;
            for u = 1:N-1
                other = u+1:N;
                cd = cosh(r(u))*cosh(r(other))- ...
                    sinh(r(u))*sinh(r(other)).*cos(angle(u)-angle(other));
                distance = acosh(max(1,cd));
                if params.T==0, probability = double(distance<=params.R);
                else, probability = 1./(1+exp((distance-params.R)/(2*params.T))); end
                expectation = expectation+sum(probability);
            end
            row.expected_mean_degree = 2*expectation/N;
        case 'forest_fire'
            [u,v] = find(A);
            row.forest_fire_is_dag = double(isdag(G));
            row.forest_fire_new_to_old = double(all(u>v));
            assert(row.forest_fire_is_dag && row.forest_fire_new_to_old && ...
                row.component_count_weak==1);
        case 'nw'
            row.nw_shortcut_edges = attributes.shortcut_edges;
            assert(M==N*params.K+row.nw_shortcut_edges);
            assert(row.component_count_weak==1);
        case 'chung_lu'
            expected = params.expected_degree_no_loops(:);
            row.expected_mean_degree = mean(expected);
            row.degree_rmse_against_expectation = sqrt(mean((degree-expected).^2));
    end
    rows(k) = row;
end

logs = dir(fullfile(dataset_root,'manifests','generation_runs','*.jsonl'));
attempts = {};
for k = 1:numel(logs)
    attempts = [attempts;read_json_lines(fullfile(logs(k).folder,logs(k).name))]; %#ok<AGROW>
end
failed = attempts(cellfun(@(x)strcmp(x.status,'failed'),attempts));
jobs = config.jobs;
if isstruct(jobs), jobs = num2cell(jobs); end
groups = repmat(struct('model','','N',0,'planned_count',0,'saved_count',0, ...
    'failed_attempt_count',0,'M_min',NaN,'M_mean',NaN,'M_max',NaN, ...
    'mean_degree_min',NaN,'mean_degree_mean',NaN,'mean_degree_max',NaN, ...
    'components_weak_min',NaN,'components_weak_max',NaN, ...
    'isolate_count_min',NaN,'isolate_count_max',NaN, ...
    'lfr_mu_actual_mean',NaN,'lfr_degree_overshoot_mean',NaN),numel(jobs),1);
planned = 0;
for k = 1:numel(jobs)
    job = jobs{k}; p = job.parameters;
    if isfield(p,'N')
        N = p.N;
    elseif isfield(p,'sizes')
        N = sum(p.sizes);
    elseif isfield(p,'degrees')
        N = numel(p.degrees);
    else
        N = numel(p.w);
    end
    selected = rows(strcmp({rows.model},job.model) & [rows.N]==N);
    group = groups(k); group.model = job.model; group.N = N;
    group.planned_count = config.samples_per_combination;
    if isfield(job,'samples'), group.planned_count = job.samples; end
    planned = planned+group.planned_count; group.saved_count = numel(selected);
    group.failed_attempt_count = sum(cellfun(@(x)x.job_id==k,failed));
    if ~isempty(selected)
        group.M_min = min([selected.M]); group.M_mean = mean([selected.M]);
        group.M_max = max([selected.M]);
        group.mean_degree_min = min([selected.mean_degree]);
        group.mean_degree_mean = mean([selected.mean_degree]);
        group.mean_degree_max = max([selected.mean_degree]);
        group.components_weak_min = min([selected.component_count_weak]);
        group.components_weak_max = max([selected.component_count_weak]);
        group.isolate_count_min = min([selected.isolate_count]);
        group.isolate_count_max = max([selected.isolate_count]);
        group.lfr_mu_actual_mean = mean([selected.lfr_mu_actual]);
        group.lfr_degree_overshoot_mean = mean([selected.lfr_degree_overshoot_mean]);
    end
    groups(k) = group;
end
report = struct('schema_version','synthetic-validation-diagnostics-v1', ...
    'dataset_id',descriptor.dataset_id,'planned_count',planned,'saved_count',numel(rows), ...
    'generation_attempt_count',numel(attempts),'failed_attempt_count',numel(failed), ...
    'implementation_sha256',descriptor.implementation_sha256, ...
    'generation_config_sha256',descriptor.generation_config_sha256, ...
    'manifest_sha256',gg_io_sha256(index_path,'file'), ...
    'generation_config_file_sha256',gg_io_sha256(fullfile(dataset_root,'configs','generation.json'),'file'), ...
    'graph_manifest','manifests/graphs.jsonl','graphs',rows,'groups',groups, ...
    'failed_attempts',{failed});
reports_dir = fullfile(dataset_root,'reports');
if ~isfolder(reports_dir), mkdir(reports_dir); end
json_path = fullfile(reports_dir,'graph_diagnostics.json');
csv_path = fullfile(reports_dir,'graph_diagnostics.csv');
groups_path = fullfile(reports_dir,'model_statistics.csv');
assert(~isfile(json_path) && ~isfile(csv_path) && ~isfile(groups_path), ...
    'Diagnostics already exist; preserve the prior report instead of replacing it.');
gg_batch_write_text(json_path,[jsonencode(report,'PrettyPrint',true) newline],false);
writetable(struct2table(rows),csv_path,'Encoding','UTF-8');
writetable(struct2table(groups),groups_path,'Encoding','UTF-8');
fprintf('EXTENDED_DIAGNOSTICS_OK: %d/%d saved; %d failed attempts.\n', ...
    report.saved_count,report.planned_count,report.failed_attempt_count);
disp(struct2table(groups));
end

function rows = read_json_lines(path)
lines = regexp(fileread(path),'\r?\n','split');
lines = lines(~cellfun(@(x)isempty(strtrim(x)),lines));
rows = cellfun(@jsondecode,lines(:),'UniformOutput',false);
end

function row = empty_row()
row = struct('graph_id','','model','','seed',0,'N',0,'M',0,'directed',false, ...
    'mean_degree',0,'component_count_weak',0,'component_count_strong',NaN, ...
    'largest_component_size',0,'isolate_count',0,'min_degree',0,'max_degree',0, ...
    'std_degree',0,'expected_mean_degree',NaN,'degree_rmse_against_expectation',NaN, ...
    'lfr_mu_requested',NaN,'lfr_mu_actual',NaN,'lfr_mean_target_degree',NaN, ...
    'lfr_degree_overshoot_mean',NaN,'lfr_degree_overshoot_max',NaN,'lfr_community_count',NaN, ...
    'degree_sequence_max_abs_error',NaN,'successful_swaps',NaN,'attempted_swaps',NaN, ...
    'dc_theta_group_max_error',NaN,'waxman_L',NaN,'waxman_L_abs_error',NaN, ...
    'duplication_attempts',NaN,'rejected_duplications',NaN,'duplication_bipartite',NaN, ...
    'rhg_min_radius',NaN,'rhg_max_radius',NaN,'forest_fire_is_dag',NaN, ...
    'forest_fire_new_to_old',NaN,'nw_shortcut_edges',NaN);
end
