function gg_io_atomic_text(path, text)
%GG_IO_ATOMIC_TEXT Publish UTF-8 text by same-directory temporary rename.
path = gg_io_absolute_path(path);
parent = fileparts(path);
temporary = fullfile(parent, ['.tmp_' char(java.util.UUID.randomUUID())]);
file = fopen(temporary,'wb');
if file < 0, error('graphio:FileOpen','Cannot write temporary file.'); end
cleanup = onCleanup(@() cleanup_file(temporary)); %#ok<NASGU>
try
    bytes = unicode2native(text,'UTF-8');
    count = fwrite(file,bytes,'uint8');
    closed = fclose(file);
catch problem
    fclose(file);
    rethrow(problem);
end
if count ~= numel(bytes) || closed ~= 0
    error('graphio:WriteFailed','Could not flush complete text file.');
end
try
    source = java.io.File(temporary);
    destination = java.io.File(path);
    options = javaArray('java.nio.file.CopyOption',2);
    options(1) = java.nio.file.StandardCopyOption.ATOMIC_MOVE;
    options(2) = java.nio.file.StandardCopyOption.REPLACE_EXISTING;
    java.nio.file.Files.move(source.toPath(),destination.toPath(),options);
catch problem
    error('graphio:CommitFailed','Atomic rename is required on this filesystem: %s',problem.message);
end
end

function cleanup_file(path)
if isfile(path), delete(path); end
end
