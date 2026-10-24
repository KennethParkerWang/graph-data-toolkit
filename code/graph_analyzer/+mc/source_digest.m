function hash = source_digest()
%SOURCE_DIGEST Reproducible digest over installed MATLAB and registry sources.
root=fileparts(fileparts(mfilename('fullpath')));
files=[dir(fullfile(root,'+mc','**','*.m'));dir(fullfile(root,'registry','*.json'))];
paths=cell(numel(files),1);
for i=1:numel(files), paths{i}=strrep(fullfile(files(i).folder,files(i).name),[root,filesep],''); end
[paths,order]=sort(paths); records=cell(numel(files),1);
for i=1:numel(order)
    p=fullfile(root,paths{i}); records{i}=[strrep(paths{i},'\','/'),':',mc.file_hash(p)];
end
hash=mc.sha256(unicode2native(strjoin(records,newline),'UTF-8'));
end
