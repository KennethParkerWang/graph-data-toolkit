function sample = gg_io_read_graph(path, expected_record)
%GG_IO_READ_GRAPH Load graph-v1; with an index row, check file bytes first.
if nargin > 1 && ~isempty(expected_record)
    expected_record = gg_io_check_record(expected_record);
    info = dir(path);
    if isempty(info) || info.isdir || info.bytes ~= expected_record.file_bytes || ...
            ~strcmp(gg_io_sha256(path,'file'),expected_record.file_sha256)
        error('graphio:FileChecksumMismatch','File checksum or size mismatch: %s',path);
    end
end
sample = load(path);
gg_io_validate_sample(sample);
if nargin > 1 && ~isempty(expected_record)
    compare = {'graph_id','origin_graph_id','topology_hash','schema_version'};
    for k = 1:numel(compare)
        if ~strcmp(sample.(compare{k}),expected_record.(compare{k}))
            error('graphio:ManifestMismatch','Manifest %s disagrees with graph.',compare{k});
        end
    end
    if double(sample.N) ~= expected_record.N || double(sample.M) ~= expected_record.M || ...
            sample.directed ~= expected_record.directed || ...
            ~strcmp(sample.meta.model,expected_record.model) || ...
            ~strcmp(sample.meta.generator_id,expected_record.generator_id) || ...
            ~strcmp(sample.meta.implementation_version,expected_record.implementation_version) || ...
            ~strcmp(gg_io_scientific_hash(sample),expected_record.scientific_sha256)
        error('graphio:ManifestMismatch','Manifest scientific content disagrees with graph.');
    end
end
end
