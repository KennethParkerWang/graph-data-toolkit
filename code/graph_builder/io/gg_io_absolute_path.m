function path = gg_io_absolute_path(path)
%GG_IO_ABSOLUTE_PATH Resolve relative paths against MATLAB pwd, not JVM cwd.
if isstring(path) && isscalar(path), path = char(path); end
if ~ischar(path) || ~isrow(path) || isempty(path)
    error('graphio:InvalidPath','Path must be a nonempty character row.');
end
file = java.io.File(path);
if ~file.isAbsolute(), file = java.io.File(fullfile(pwd,path)); end
path = char(file.getCanonicalPath());
end
