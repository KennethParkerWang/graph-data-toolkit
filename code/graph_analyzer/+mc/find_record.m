function record = find_record(root,run_id)
%FIND_RECORD Read the published index and metrics-owned shards only.
record=struct([]); files=dir(fullfile(root,'manifests','parts','metrics_*.jsonl'));
paths={fullfile(root,'manifests','metrics.jsonl')};
for j=1:numel(files), paths{end+1}=fullfile(files(j).folder,files(j).name); end %#ok<AGROW>
for j=1:numel(paths)
    rows=mc.read_jsonl(paths{j});
    for k=1:numel(rows)
        if strcmp(rows(k).run_id,run_id)
            if isempty(record), record=rows(k);
            elseif ~strcmp(record.file_sha256,rows(k).file_sha256)||~strcmp(record.path,rows(k).path)
                error('mc:Conflict','Conflicting records for run %s.',run_id);
            end
        end
    end
end
end
