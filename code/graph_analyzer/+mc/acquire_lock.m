function cleanup = acquire_lock(path)
%ACQUIRE_LOCK Atomic directory creation; stale locks require explicit recovery.
if ~java.io.File(path).mkdir(), error('mc:Locked','Writer lock exists: %s',path); end
cleanup=onCleanup(@()rmdir(path));
end
