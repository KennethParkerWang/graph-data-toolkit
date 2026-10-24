function report = test_16_models_r2026b(output_root)
%TEST_16_MODELS_R2026B Validate one fixed sample for each selected model.
% Checks R2026b execution, graph invariants, metadata counts, repeatability,
% and caller RNG preservation. An optional output_root enables graph-v1
% MAT v7 round trips, merged manifest publication, and idempotent writes.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
setup_generators();
addpath(fullfile(root, 'validation'));
if nargin < 1, output_root = ''; end
save_samples = ~isempty(output_root);
if save_samples
    assert(usejava('jvm'), 'Saving graph-v1 samples requires the JVM.');
    output_root = gg_io_absolute_path(output_root);
    implementation = gg_implementation_digest();
end

validation_dir = fullfile(root, 'validation');
log_path = fullfile(validation_dir, 'r2026b_16_models_validation.log');
report_path = fullfile(validation_dir, 'r2026b_16_models_report.json');

log_file = fopen(log_path, 'wt');
if log_file < 0
    error('graphgen:ValidationLogOpen', 'Cannot open validation log: %s', log_path);
end
log_cleanup = onCleanup(@() fclose(log_file)); %#ok<NASGU>

initial_rng = rng;
write_log(log_file, 'R2026b 16-model validation started.');
write_log(log_file, 'MATLAB version: %s', version);
write_log(log_file, 'Root: %s', root);
write_log(log_file, 'JVM available: %d', usejava('jvm'));
write_log(log_file, 'Check scope: generator output, metadata, repeatability, and RNG preservation.');

% The seeds for EH/RT/RR/RH are the documented examples already used by
% the source/model validation. They are fixed here and are not substituted.
cases = {
    'er_gnp_undirected',        'gen_er_undirected',        {30, 0.1, 1},                          false, 1, 'stochastic';
    'er_gnm_undirected',        'gen_er_gnm_undirected',    {30, 60, 1},                           false, 1, 'exact:60';
    'ba_undirected',            'gen_ba_undirected',         {30, 3, 1},                            false, 1, 'exact:81';
    'sf_undirected',            'gen_sf_undirected',         {30, 60, 0.5, 1},                      false, 1, 'exact:60';
    'ws_undirected',            'gen_ws_undirected',         {30, 3, 0.1, 1},                       false, 1, 'exact:90';
    'nw_undirected',            'gen_nw_undirected',         {30, 3, 0.1, 1},                       false, 1, 'stochastic';
    'eh_directed',              'gen_eh_directed',           {20, 60, 2},                           true,  2, 'exact:60';
    'qs_directed',              'gen_qs_directed',           {30, 2, 0.05, 1},                      true,  1, 'stochastic';
    'rt_directed',              'gen_rt_directed',           {30, 57, 1},                           true,  1, 'exact:57';
    'rr_directed',              'gen_rr_directed',           {29, 41, 1},                           true,  1, 'exact:41';
    'rh_directed',              'gen_rh_directed',           {30, 36, 1},                           true,  1, 'exact:36';
    'sbm_undirected',           'gen_sbm_undirected',        {[15, 15], [0.2, 0.02; 0.02, 0.2], 1}, false, 1, 'stochastic';
    'rgg_undirected',           'gen_rgg_undirected',        {30, 0.3, 2, 1},                       false, 1, 'stochastic';
    'random_regular_undirected','gen_random_regular_undirected',{30, 4, 1},                         false, 1, 'exact:60';
    'hk_undirected',            'gen_hk_undirected',          {30, 3, 0.4, 1},                      false, 1, 'bounded:81';
    'chung_lu_undirected',      'gen_chung_lu_undirected',    {3 * ones(30, 1), 1},                 false, 1, 'stochastic';
};

result_template = struct( ...
    'id', '', ...
    'generator_id', '', ...
    'directed', false, ...
    'seed', 0, ...
    'status', 'failed', ...
    'N', 0, ...
    'M', 0, ...
    'edge_count_rule', '', ...
    'graph_id', '', 'path', '', 'scientific_sha256', '', ...
    'roundtrip_status', 'not_requested', ...
    'error_identifier', '', ...
    'error_message', '');
results = repmat(result_template, size(cases, 1), 1);

for index = 1:size(cases, 1)
    id = cases{index, 1};
    generator_id = cases{index, 2};
    args = cases{index, 3};
    directed = cases{index, 4};
    seed = cases{index, 5};
    edge_count_rule = cases{index, 6};
    results(index).id = id;
    results(index).generator_id = generator_id;
    results(index).directed = directed;
    results(index).seed = seed;
    results(index).edge_count_rule = edge_count_rule;
    write_log(log_file, '[%02d/%02d] %s (%s)', index, size(cases, 1), id, generator_id);

    try
        state_before = rng;
        generator = str2func(generator_id);
        [A1, meta1] = generator(args{:});
        state_after_first = rng;
        assert(isequal(state_after_first, state_before), ...
            'Generator changed the caller RNG state after the first call.');

        [A2, meta2] = generator(args{:});
        state_after_second = rng;
        assert(isequal(state_after_second, state_before), ...
            'Generator changed the caller RNG state after the second call.');

        if strcmp(generator_id, 'gen_sbm_undirected')
            expected_N = sum(args{1});
        elseif strcmp(generator_id, 'gen_chung_lu_undirected')
            expected_N = numel(args{1});
        else
            expected_N = args{1};
        end
        assert(isequal(size(A1), [expected_N expected_N]) && ...
            isequal(size(A2), [expected_N expected_N]), ...
            'Output node count differs from the requested node count.');
        check_generator_output(A1, meta1, directed, seed, generator_id, edge_count_rule);
        check_generator_output(A2, meta2, directed, seed, generator_id, edge_count_rule);
        assert(isequal(A1, A2), 'Repeated calls with the same seed returned different A.');
        assert(isequal(meta1, meta2), 'Repeated calls with the same seed returned different meta.');

        if save_samples
            sample = gg_io_make_sample(A1, gg_prepare_metadata(A1, meta1, generator_id, implementation));
            repeated = gg_io_make_sample(A2, gg_prepare_metadata(A2, meta2, generator_id, implementation));
            assert(strcmp(gg_io_scientific_hash(sample), gg_io_scientific_hash(repeated)), ...
                'Repeated generation changed scientific content.');
            [record, ~] = gg_io_write_graph(output_root, sample);
            saved_path = fullfile(output_root, strrep(record.path, '/', filesep));
            loaded = gg_io_read_graph(saved_path, record);
            assert(isequal(sample.A, loaded.A) && isequal(sample.edge_list, loaded.edge_list), ...
                'Saved topology differs from the generated graph.');
            % New runs have different creation timestamps. Compare every scientific
            % metadata field separately from explicitly excluded runtime fields.
            assert(strcmp(gg_io_scientific_hash(sample), gg_io_scientific_hash(loaded)), ...
                'Saved scientific metadata differs from the generated sample.');
            assert(isequaln(loaded, gg_io_read_graph(saved_path, record)), ...
                'Repeated MAT reads returned different values or types.');
            [again, status] = gg_io_write_graph(output_root, repeated);
            assert(strcmp(status, 'existing') && isequaln(again, record), ...
                'Idempotent write changed the committed record.');
            assert(strcmp(gg_io_sha256(saved_path, 'file'), record.file_sha256), ...
                'Idempotent write changed the MAT bytes.');
            results(index).graph_id = sample.graph_id;
            results(index).path = record.path;
            results(index).scientific_sha256 = record.scientific_sha256;
            results(index).roundtrip_status = 'passed';
        end

        results(index).status = 'passed';
        results(index).N = size(A1, 1);
        if directed, results(index).M = nnz(A1); else, results(index).M = nnz(A1) / 2; end
        write_log(log_file, '  PASS N=%d M=%d rule=%s', ...
            results(index).N, results(index).M, edge_count_rule);
    catch exception
        results(index).error_identifier = exception.identifier;
        results(index).error_message = exception.message;
        write_log(log_file, '  FAIL %s: %s', exception.identifier, exception.message);
    end

    assert(isequal(rng, initial_rng), ...
        'External RNG state changed while validating case %s.', id);
end

passed = sum(strcmp({results.status}, 'passed'));
failed = numel(results) - passed;
manifest_count = 0;
if save_samples && failed == 0
    records = gg_io_merge_manifest(output_root);
    manifest_count = numel(records);
    assert(manifest_count == numel(results), 'Manifest must contain exactly 16 validation samples.');
    assert(isequal(sort({records.graph_id}), sort({results.graph_id})), ...
        'Manifest identities differ from the generated samples.');
    dataset = struct('dataset_id', 'r2026b_16_model_samples', ...
        'graph_schema_version', 'graph-v1', 'graph_root', 'graphs', ...
        'graph_manifest', 'manifests/graphs.jsonl', ...
        'description', 'One small validation sample per model; no metric labels.', ...
        'matlab_version', version, 'sample_count', manifest_count);
    gg_io_atomic_text(fullfile(output_root, 'dataset.json'), [jsonencode(dataset) newline]);
end
report = struct( ...
    'implementation_version', '2.0.1', ...
    'matlab_version', version, ...
    'jvm_available', usejava('jvm'), ...
    'test_scope', 'generation, invariants, metadata, repeatability, RNG preservation; optional MAT roundtrip and idempotent write', ...
    'sample_output_root', output_root, 'manifest_count', manifest_count, ...
    'case_count', numel(results), ...
    'passed', passed, ...
    'failed', failed, ...
    'results', results, ...
    'completed_utc', char(datetime('now', 'TimeZone', 'UTC', ...
        'Format', "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")));

write_report(report_path, jsonencode(report, 'PrettyPrint', true));
write_log(log_file, 'Summary: %d passed, %d failed.', passed, failed);
write_log(log_file, 'Report: %s', report_path);

assert(isequal(rng, initial_rng), 'External RNG state changed after the complete validation.');
if failed > 0
    error('graphgen:ValidationFailed', ...
        '%d of %d model checks failed. See %s.', failed, numel(results), log_path);
end
fprintf('R2026B_16_MODELS_OK: %d models passed; report written to %s\n', ...
    passed, report_path);
end

function check_generator_output(A, meta, directed, seed, generator_id, edge_count_rule)
assert(issparse(A) && islogical(A), ...
    '%s must return a sparse logical adjacency matrix.', generator_id);
assert(ismatrix(A) && size(A, 1) == size(A, 2) && size(A, 1) >= 1, ...
    '%s returned a non-square or empty adjacency matrix.', generator_id);
assert(~any(diag(A)), '%s returned a self-loop.', generator_id);
assert(all(nonzeros(A) == 1), '%s returned a non-binary adjacency matrix.', generator_id);
assert(logical(meta.directed) == logical(directed), ...
    '%s metadata direction disagrees with the test case.', generator_id);
if ~directed
    assert(isequal(A, A.'), '%s returned a nonsymmetric undirected matrix.', generator_id);
end

N = size(A, 1);
if directed
    M = nnz(A);
else
    M = nnz(A) / 2;
end
assert(meta.num_nodes == N, '%s meta.num_nodes disagrees with A.', generator_id);
assert(meta.num_edges == M, '%s meta.num_edges disagrees with A.', generator_id);
assert(meta.seed == seed, '%s meta.seed disagrees with the requested seed.', generator_id);
assert(strcmp(meta.rng_algorithm, 'twister'), ...
    '%s did not report the expected twister RNG algorithm.', generator_id);
assert(M >= 0 && M == floor(M), '%s returned a non-integer edge count.', generator_id);
if startsWith(edge_count_rule, 'exact:')
    expected = str2double(extractAfter(edge_count_rule, 'exact:'));
    assert(M == expected, '%s returned M=%d; expected exactly %d.', generator_id, M, expected);
elseif startsWith(edge_count_rule, 'bounded:')
    maximum = str2double(extractAfter(edge_count_rule, 'bounded:'));
    assert(M <= maximum, '%s returned M=%d; expected at most %d.', generator_id, M, maximum);
end
if strcmp(generator_id, 'gen_random_regular_undirected')
    assert(all(full(sum(A, 2)) == 4), 'Random-regular graph must have degree 4 at every node.');
elseif strcmp(generator_id, 'gen_qs_directed')
    assert(all(diag(A, 1) == 1), 'QS graph must retain every forward chain edge.');
end
end

function write_log(file_id, format_string, varargin)
fprintf(file_id, '[%s] ', char(datetime('now', 'TimeZone', 'UTC', ...
    'Format', "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")));
fprintf(file_id, [format_string, '\n'], varargin{:});
end

function write_report(path, text)
file = fopen(path, 'wt');
if file < 0
    error('graphgen:ValidationReportOpen', 'Cannot open validation report: %s', path);
end
cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
fprintf(file, '%s\n', text);
end
