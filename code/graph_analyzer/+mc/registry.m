function entries = registry()
%REGISTRY Load all versioned metric definitions. No metric runs here.
root=fileparts(fileparts(mfilename('fullpath')));
files=dir(fullfile(root,'registry','*.json')); entries=struct([]);
for f=1:numel(files)
    part=jsondecode(fileread(fullfile(files(f).folder,files(f).name)));
    if isempty(part), continue; end
    if isempty(entries), entries=part(:); else, entries=[entries;part(:)]; end %#ok<AGROW>
end
if isempty(entries), error('mc:Registry','No metric definitions installed.'); end
ids={entries.metric_id};
if numel(unique(ids))~=numel(ids), error('mc:Registry','Duplicate metric IDs.'); end
end
