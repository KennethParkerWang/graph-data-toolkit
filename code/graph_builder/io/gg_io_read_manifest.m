function records = gg_io_read_manifest(dataset_root)
%GG_IO_READ_MANIFEST Read the published graph index without scanning graphs.
path = fullfile(dataset_root,'manifests','graphs.jsonl');
if ~isfile(path), error('graphio:MissingManifest','No published graph manifest: %s',path); end
records = gg_io_read_records_file(path);
if numel(unique({records.graph_id})) ~= numel(records)
    error('graphio:DuplicateManifest','Published index has duplicate graph IDs.');
end
end
