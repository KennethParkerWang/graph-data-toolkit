function gg_batch_write_text(path, text, allow_replace)
%GG_BATCH_WRITE_TEXT 同目录临时文件完成后再重命名。
if nargin < 3
    allow_replace = false;
end
if isfolder(path) || (~allow_replace && isfile(path))
    error('graphgen:BatchFileExists', '拒绝覆盖已有路径: %s', path);
end
parent = fileparts(path);
temporary = [tempname(parent) '.tmp'];
cleanup = onCleanup(@() remove_temporary(temporary));
[file, message] = fopen(temporary, 'w', 'n', 'UTF-8');
if file < 0
    error('graphgen:BatchWrite', '不能写临时文件: %s', message);
end
try
    count = fprintf(file, '%s', text);
    status = fclose(file);
catch failure
    fclose(file);
    rethrow(failure);
end
if count < 0 || status ~= 0
    error('graphgen:BatchWrite', '写入文件失败: %s', path);
end
if ~allow_replace && isfile(path)
    error('graphgen:BatchFileExists', '拒绝覆盖写入期间出现的文件: %s', path);
end
if allow_replace
    [success, message] = movefile(temporary, path, 'f');
else
    [success, message] = movefile(temporary, path);
end
if ~success
    error('graphgen:BatchWrite', '重命名临时文件失败: %s', message);
end
end

function remove_temporary(path)
if isfile(path)
    delete(path);
end
end
