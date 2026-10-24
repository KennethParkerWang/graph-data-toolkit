function [record, status] = gg_io_write_graph(dataset_root, sample)
%GG_IO_WRITE_GRAPH Commit one MAT v7 graph and one immutable manifest part.
% Does not write dataset.json or generation configuration/run records.
gg_io_validate_sample(sample);
dataset_root = gg_io_absolute_path(dataset_root);
relative = ['graphs/' sample.graph_id(1:2) '/' sample.graph_id '.mat'];
destination = fullfile(dataset_root,strrep(relative,'/',filesep));
graph_dir = fileparts(destination);
part_dir = fullfile(dataset_root,'manifests','parts');
if ~isfolder(graph_dir), mkdir(graph_dir); end
if ~isfolder(part_dir), mkdir(part_dir); end
guard = gg_io_lock(fullfile(graph_dir,['.' sample.graph_id '.lock'])); %#ok<NASGU>
existing_records = find_records(dataset_root,sample.graph_id);
if isfile(destination)
    if isempty(existing_records)
        % A crash may have occurred after MAT publication but before part commit.
        existing = gg_io_read_graph(destination);
    else
        existing = gg_io_read_graph(destination,existing_records(1));
    end
    if ~strcmp(gg_io_scientific_hash(existing),gg_io_scientific_hash(sample))
        error('graphio:ScientificConflict','Same graph_id has different scientific content.');
    end
    if ~isempty(existing_records)
        record = existing_records(1);
        status = 'existing';
        return;
    end
    sample = existing;
    status = 'recovered';
else
    if ~isempty(existing_records)
        error('graphio:MissingCommittedGraph','A committed graph file is missing.');
    end
    % Conservative preflight: the entire uncompressed payload must fit below
    % 2 GB, which also bounds every individual MAT v7 variable.
    details = whos('sample');
    if details.bytes >= 1800000000
        error('graphio:MatV7Limit','Payload exceeds the graph-v1 MAT v7 safety limit (1.8 GB).');
    end
    temporary = fullfile(graph_dir,['.tmp_' char(java.util.UUID.randomUUID()) '.mat']);
    cleanup = onCleanup(@() cleanup_file(temporary)); %#ok<NASGU>
    save(temporary,'-struct','sample','-v7');
    checked = gg_io_read_graph(temporary);
    if ~strcmp(gg_io_scientific_hash(checked),gg_io_scientific_hash(sample))
        error('graphio:WriteMismatch','Temporary graph failed round-trip verification.');
    end
    [ok,message] = movefile(temporary,destination);
    if ~ok, error('graphio:CommitFailed','Cannot publish graph: %s',message); end
    status = 'created';
end
info = dir(destination);
record = gg_io_record_template();
for name = {'graph_id','origin_graph_id','topology_hash','schema_version'}
    record.(name{1}) = sample.(name{1});
end
record.path = relative;
record.N = double(sample.N);
record.M = double(sample.M);
record.directed = sample.directed;
record.model = sample.meta.model;
record.generator_id = sample.meta.generator_id;
record.implementation_version = sample.meta.implementation_version;
record.file_sha256 = gg_io_sha256(destination,'file');
record.file_bytes = info.bytes;
record.scientific_sha256 = gg_io_scientific_hash(sample);
record.created_utc = sample.meta.created_utc;
record = gg_io_check_record(record);
part = fullfile(part_dir,['graphs_' sample.graph_id '_' char(java.util.UUID.randomUUID()) '.jsonl']);
gg_io_atomic_text(part,[jsonencode(record) newline]);
end

function records = find_records(root,id)
records = repmat(gg_io_record_template(),0,1);
parts = dir(fullfile(root,'manifests','parts',['graphs_' id '_*.jsonl']));
for k = 1:numel(parts)
    rows = gg_io_read_records_file(fullfile(parts(k).folder,parts(k).name));
    if numel(rows) ~= 1 || ~strcmp(rows.graph_id,id)
        error('graphio:InvalidManifest','Graph part identity mismatch.');
    end
    records(end+1,1) = rows; %#ok<AGROW>
end
% The published record and retained parts must agree even when a part exists.
records = [records; gg_io_find_published_record(root,id)];
for k = 2:numel(records)
    if ~strcmp(gg_io_canonical_json(records(k)),gg_io_canonical_json(records(1)))
        error('graphio:ManifestConflict','Conflicting committed records for %s.',id);
    end
end
end

function cleanup_file(path)
if isfile(path), delete(path); end
end
