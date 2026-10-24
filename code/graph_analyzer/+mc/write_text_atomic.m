function write_text_atomic(path,txt,replace)
%WRITE_TEXT_ATOMIC Same-directory UTF-8 commit, preserving existing files.
if nargin<3, replace=false; end
folder=fileparts(path); if ~isfolder(folder), mkdir(folder); end
temp=[tempname(folder),'.tmp']; cleanup=onCleanup(@()remove_temp(temp));
fid=fopen(temp,'w','n','UTF-8'); if fid<0, error('mc:IO','Cannot create temporary file.'); end
try, fwrite(fid,unicode2native(txt,'UTF-8'),'uint8'); fclose(fid); catch err, fclose(fid); rethrow(err); end
if isfile(path)&&~replace
    if strcmp(fileread(path),txt), return; end
    error('mc:Conflict','Existing content differs: %s',path);
end
if replace, [ok,msg]=movefile(temp,path,'f'); else, [ok,msg]=movefile(temp,path); end
if ~ok, error('mc:IO','Commit failed: %s',msg); end
end
function remove_temp(path)
if isfile(path), delete(path); end
end
