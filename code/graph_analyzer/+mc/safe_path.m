function path = safe_path(root,relative)
%SAFE_PATH Resolve a dataset-relative path and reject traversal/absolute paths.
relative=char(relative);
if isempty(relative)||startsWith(relative,{'/','\'})||contains(relative,':')||any(strcmp(regexp(relative,'[/\\]','split'),'..'))
    error('mc:Path','Expected a relative dataset path without traversal.');
end
root=char(root); file=java.io.File(root);
if ~file.isAbsolute(), file=java.io.File(fullfile(pwd,root)); end
r=char(file.getCanonicalPath()); path=char(java.io.File(fullfile(r,relative)).getCanonicalPath());
if ~startsWith(lower(path),[lower(r),filesep]), error('mc:Path','Path leaves dataset root.'); end
end
