function record = gg_io_find_published_record(dataset_root, graph_id)
%GG_IO_FIND_PUBLISHED_RECORD Lookup a graph in the current published index.
% Cache an immutable index snapshot while file identity/size/mtime match.
% Atomic replacement changes file identity. Filesystems without file keys
% are read directly rather than reusing a potentially stale snapshot.
persistent snapshots
if isempty(snapshots), snapshots = containers.Map('KeyType','char','ValueType','any'); end
path = gg_io_absolute_path(fullfile(dataset_root,'manifests','graphs.jsonl'));
record = repmat(gg_io_record_template(),0,1);
if ~isfile(path)
    if isKey(snapshots,path), remove(snapshots,path); end
    return;
end
file = java.io.File(path);
options = javaArray('java.nio.file.LinkOption',0);
attributes = java.nio.file.Files.readAttributes(file.toPath(), ...
    'basic:fileKey,size,lastModifiedTime',options);
file_key = attributes.get('fileKey');
signature = char(attributes.toString());
cacheable = ~isempty(file_key);
if cacheable && isKey(snapshots,path)
    snapshot = snapshots(path);
    if strcmp(snapshot.signature,signature)
        if isKey(snapshot.rows,graph_id), record = snapshot.rows(graph_id); end
        return;
    end
end
rows = gg_io_read_manifest(dataset_root);
lookup = containers.Map('KeyType','char','ValueType','any');
for k = 1:numel(rows), lookup(rows(k).graph_id) = rows(k); end
if isKey(lookup,graph_id), record = lookup(graph_id); end
if cacheable
    % Avoid retaining entire indexes from every temporary validation dataset.
    if snapshots.Count >= 4 && ~isKey(snapshots,path)
        snapshots = containers.Map('KeyType','char','ValueType','any');
    end
    snapshots(path) = struct('signature',signature,'rows',lookup);
end
end
