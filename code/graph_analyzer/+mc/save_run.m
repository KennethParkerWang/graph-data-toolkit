function [record,resumed] = save_run(root,output,writer_id)
%SAVE_RUN Write an owned MAT-v7 result and writer-specific manifest part.
% root must be an existing task1 dataset, or an explicitly created test root.
mc.validate_output(output);
if isempty(regexp(writer_id,'^[A-Za-z0-9_-]+$','once')), error('mc:Config','Unsafe writer_id.'); end
if ~isfolder(root), error('mc:IO','Dataset root must already exist.'); end
parts=fullfile(root,'manifests','parts'); if ~isfolder(parts), mkdir(parts); end
lock=mc.acquire_lock(fullfile(parts,['metrics_',writer_id,'.lock'])); %#ok<NASGU>
existing=mc.find_record(root,output.run_id); resumed=false;
if ~isempty(existing)
    old=mc.verify_record(root,existing);
    if ~strcmp(old.status,'complete'), error('mc:Incomplete','Existing run is %s; choose a new repeat_index to retain a retry.',old.status); end
    if ~strcmp(old.run_identity_json,output.run_identity_json)||~strcmp(old.metric_set_identity_json,output.metric_set_identity_json)
        error('mc:Conflict','Existing run has different identity.');
    end
    record=existing; resumed=true; return;
end
relative=strjoin({'metrics',output.metric_set_id,output.graph_id(1:2),output.graph_id,[output.run_id,'.mat']},'/');
path=mc.safe_path(root,relative); folder=fileparts(path); if ~isfolder(folder), mkdir(folder); end
run_lock=mc.acquire_lock([path,'.lock']); %#ok<NASGU>
existing=mc.find_record(root,output.run_id);
if ~isempty(existing)
    old=mc.verify_record(root,existing);
    if ~strcmp(old.status,'complete'), error('mc:Incomplete','Existing run is incomplete.'); end
    if ~strcmp(old.run_identity_json,output.run_identity_json)||~strcmp(old.metric_set_identity_json,output.metric_set_identity_json), error('mc:Conflict','Existing identity differs.'); end
    record=existing; resumed=true; return;
end
if isfile(path), error('mc:Orphan','Unindexed result exists; inspect explicitly before recovery: %s',path); end
var=whos('output'); if var.bytes>1.8e9, error('mc:MATLimit','Result exceeds conservative MAT-v7 variable limit; reduce selected output.'); end
temp=[tempname(folder),'.mat']; cleanup=onCleanup(@()remove_temp(temp));
save(temp,'output','-v7'); check=load(temp,'output'); mc.validate_output(check.output);
if ~isequaln(check.output,output), error('mc:Integrity','MAT round-trip differs.'); end
[ok,msg]=movefile(temp,path); if ~ok, error('mc:IO','Result commit failed: %s',msg); end
info=dir(path);
record=struct('schema_version',output.schema_version,'graph_id',output.graph_id,'topology_hash',output.topology_hash, ...
    'origin_graph_id',output.origin_graph_id,'metric_set_id',output.metric_set_id,'protocol_id',output.protocol_id, ...
    'run_id',output.run_id,'status',output.status,'path',relative,'file_sha256',mc.file_hash(path),'file_bytes',info.bytes, ...
    'implementation_sha256',output.implementation_sha256,'created_utc',output.created_utc);
set_path=fullfile(root,'configs','metric_sets',[output.metric_set_id,'.json']);
mc.write_text_atomic(set_path,output.metric_set_identity_json);
if ~isempty(output.protocol_id)
    [~,txt]=mc.identity(output.attack.protocol,'protocol-v1');
    mc.write_text_atomic(fullfile(root,'configs','protocols',[output.protocol_id,'.json']),txt);
end
part=fullfile(parts,['metrics_',writer_id,'.jsonl']); rows=mc.read_jsonl(part);
lines=cell(1,numel(rows)+1); for j=1:numel(rows), lines{j}=jsonencode(rows(j)); end
lines{end}=jsonencode(record); mc.write_text_atomic(part,[strjoin(lines,newline),newline],true);
end
function remove_temp(path)
if isfile(path), delete(path); end
end
