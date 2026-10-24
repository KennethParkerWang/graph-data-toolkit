function source = gg_source_info(generator_id)
%GG_SOURCE_INFO Resolve a supported protocol against pinned local sources.
root = fileparts(fileparts(mfilename('fullpath')));
catalogs = {'sources/standard/catalog.json','sources/author_lou/catalog.json'};
entry = []; catalog_path = '';
for k = 1:numel(catalogs)
    data = jsondecode(fileread(fullfile(root,catalogs{k})));
    if isfield(data,'entries'), rows = data.entries; else, rows = data.generators; end
    if isstruct(rows), rows = num2cell(rows); end
    for j = 1:numel(rows)
        if strcmp(rows{j}.generator_id,generator_id)
            entry = rows{j}; catalog_path = catalogs{k}; break;
        end
    end
    if ~isempty(entry), break; end
end
if isempty(entry), error('graphgen:MissingSource','No pinned source for %s.',generator_id); end
if (isfield(entry,'supported') && ~entry.supported) || (isfield(entry,'available') && ~entry.available)
    error('graphgen:UnsupportedModelDirection','No verified source protocol for %s.',generator_id);
end
if isfield(entry,'code_url')
    url = entry.code_url; reference_version = entry.reference_version;
    references = entry.reference_files;
else
    url = entry.url; reference_version = entry.source_id;
    references = cellfun(@(x) ['sources/author_lou/' x],entry.reference_files,'UniformOutput',false);
end
hashes = cell(size(references));
for k = 1:numel(references)
    hashes{k} = gg_io_sha256(fullfile(root,references{k}),'file');
end
source = struct('generator_id',generator_id,'catalog',catalog_path,'citation',entry.citation, ...
    'code_url',url,'reference_version',reference_version,'license',entry.license, ...
    'reference_files',{references},'reference_sha256',{hashes});
if isfield(entry,'source_sha256')
    actual = gg_io_sha256(fullfile(root,entry.archive),'file');
    if ~strcmp(actual,entry.source_sha256), error('graphgen:SourceChecksum','Pinned archive checksum differs.'); end
    source.archive_sha256 = actual;
end
end
