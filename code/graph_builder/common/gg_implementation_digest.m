function digest = gg_implementation_digest()
%GG_IMPLEMENTATION_DIGEST Hash the complete generator implementation snapshot.
% Relative paths are sorted; each file contributes its raw-byte SHA-256.
% I/O, batch scheduling, tests and documentation do not change graph recipes.
root = fileparts(fileparts(mfilename('fullpath')));
paths = {};
for folder = {'common','directed','undirected'}
    entries = dir(fullfile(root,folder{1},'**','*.m'));
    for k = 1:numel(entries)
        absolute = fullfile(entries(k).folder,entries(k).name);
        relative = strrep(absolute(numel(root)+2:end),'\','/');
        paths{end+1,1} = relative; %#ok<AGROW>
    end
end
paths = sort([paths; {'sources/standard/catalog.json';'sources/author_lou/catalog.json'}]);
lines = cell(numel(paths),1);
for k = 1:numel(paths)
    lines{k} = [paths{k} ':' gg_io_sha256(fullfile(root,paths{k}),'file')];
end
digest = gg_io_sha256(['generator-snapshot-v1' newline strjoin(lines,newline) newline]);
end
