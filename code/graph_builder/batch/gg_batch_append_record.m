function gg_batch_append_record(path, record)
%GG_BATCH_APPEND_RECORD 每次结果立即追加 UTF-8 JSONL，并关闭以刷新。
[file, message] = fopen(path, 'a', 'n', 'UTF-8');
if file < 0
    error('graphgen:BatchManifestWrite', '不能追加 manifest: %s', message);
end
try
    count = fprintf(file, '%s\n', jsonencode(record));
    status = fclose(file);
catch failure
    fclose(file);
    rethrow(failure);
end
if count < 0 || status ~= 0
    error('graphgen:BatchManifestWrite', 'manifest 追加失败。');
end
end
