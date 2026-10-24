function records = merge_manifests(root)
%MERGE_MANIFESTS Verify, deduplicate and atomically publish the metric index.
folder=fullfile(root,'manifests'); if ~isfolder(folder), error('mc:IO','No manifest directory.'); end
lock=mc.acquire_lock(fullfile(folder,'metrics_merge.lock')); %#ok<NASGU>
files=dir(fullfile(folder,'parts','metrics_*.jsonl')); records=mc.read_jsonl(fullfile(folder,'metrics.jsonl'));
for j=1:numel(files)
    rows=mc.read_jsonl(fullfile(files(j).folder,files(j).name));
    if isempty(records), records=rows; elseif ~isempty(rows), records=[records(:);rows(:)]; end %#ok<AGROW>
end
if isempty(records), return; end
[~,idx]=sort({records.run_id}); records=records(idx); keep=true(size(records));
for j=1:numel(records)
    mc.verify_record(root,records(j));
    if j>1 && strcmp(records(j).run_id,records(j-1).run_id)
        if ~strcmp(mc.canonical_json(records(j)),mc.canonical_json(records(j-1))), error('mc:Conflict','Conflicting duplicate run IDs.'); end
        keep(j)=false;
    end
end
records=records(keep); lines=arrayfun(@jsonencode,records,'UniformOutput',false);
mc.write_text_atomic(fullfile(folder,'metrics.jsonl'),[strjoin(lines,newline),newline],true);
end
