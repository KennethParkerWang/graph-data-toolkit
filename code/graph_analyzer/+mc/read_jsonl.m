function records = read_jsonl(path)
%READ_JSONL Read simple UTF-8 records; malformed lines are errors.
records=struct([]); if ~isfile(path), return; end
fid=fopen(path,'r','n','UTF-8'); if fid<0, error('mc:IO','Cannot open manifest.'); end
c=onCleanup(@()fclose(fid)); line_no=0;
while ~feof(fid)
    line=fgetl(fid); line_no=line_no+1;
    if ~ischar(line)||isempty(strtrim(line)), continue; end
    try, r=jsondecode(line); catch err, error('mc:Manifest','Invalid JSON at %s:%d: %s',path,line_no,err.message); end
    if isempty(records), records=r; else, records(end+1)=r; end %#ok<AGROW>
end
end
