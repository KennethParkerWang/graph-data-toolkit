function records = gg_io_read_records_file(path)
%GG_IO_READ_RECORDS_FILE Read complete UTF-8 JSONL records; fail on bad lines.
records = repmat(gg_io_record_template(),0,1);
file = fopen(path,'rt','n','UTF-8');
if file < 0, error('graphio:FileOpen','Cannot open manifest: %s',path); end
cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
line_number = 0;
while true
    line = fgetl(file);
    if ~ischar(line), break; end
    line_number = line_number + 1;
    if isempty(strtrim(line)), error('graphio:InvalidManifest','Blank line %d in %s.',line_number,path); end
    try
        record = gg_io_check_record(jsondecode(line));
    catch problem
        error('graphio:InvalidManifest','Bad line %d in %s: %s',line_number,path,problem.message);
    end
    records(end+1,1) = record; %#ok<AGROW>
end
end
