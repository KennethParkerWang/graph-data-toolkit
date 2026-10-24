function records = gg_io_merge_manifest(dataset_root)
%GG_IO_MERGE_MANIFEST Verify graph parts and atomically publish sorted index.
% Takes a snapshot of complete part files; concurrent later parts are merged
% on the next call. Parts are retained for crash recovery and traceability.
manifest_dir = fullfile(dataset_root,'manifests');
if ~isfolder(manifest_dir), mkdir(manifest_dir); end
guard = gg_io_lock(fullfile(manifest_dir,'.graphs.merge.lock')); %#ok<NASGU>
records = repmat(gg_io_record_template(),0,1);
published = fullfile(manifest_dir,'graphs.jsonl');
if isfile(published), records = gg_io_read_manifest(dataset_root); end
parts = dir(fullfile(manifest_dir,'parts','graphs_*.jsonl'));
for k = 1:numel(parts)
    rows = gg_io_read_records_file(fullfile(parts(k).folder,parts(k).name));
    if numel(rows) ~= 1
        error('graphio:InvalidManifest','Each graph part must contain exactly one record.');
    end
    records = [records;rows]; %#ok<AGROW>
end
if ~isempty(records)
    [~,order] = sort({records.graph_id});
    records = records(order);
    keep = true(numel(records),1);
    for k = 2:numel(records)
        if strcmp(records(k).graph_id,records(k-1).graph_id)
            if ~strcmp(gg_io_canonical_json(records(k)),gg_io_canonical_json(records(k-1)))
                error('graphio:ManifestConflict','Conflicting records for graph %s.',records(k).graph_id);
            end
            keep(k) = false;
        end
    end
    records = records(keep);
end
lines = cell(numel(records),1);
for k = 1:numel(records)
    path = fullfile(dataset_root,strrep(records(k).path,'/',filesep));
    gg_io_read_graph(path,records(k));
    lines{k} = jsonencode(records(k));
end
text = strjoin(lines,newline);
if ~isempty(lines), text = [text newline]; end
gg_io_atomic_text(published,text);
end
