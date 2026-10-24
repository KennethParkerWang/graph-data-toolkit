function guard = gg_io_lock(path)
%GG_IO_LOCK Acquire an atomic directory lock; caller holds returned cleanup.
path = gg_io_absolute_path(path);
folder = java.io.File(path);
if ~folder.mkdir()
    error('graphio:Locked','Lock exists or cannot be created: %s',path);
end
guard = onCleanup(@() release(path));
end

function release(path)
if isfolder(path), rmdir(path); end
end
