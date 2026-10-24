function [record,resumed]=save_repeat_summary(root,aggregate)
%SAVE_REPEAT_SUMMARY Atomically save a derived result outside raw-run manifests.
% MAT-v7 top-level variable aggregate; separate JSON checksum/provenance index.
mc.validate_repeat_summary(aggregate);
if ~isfolder(root), error('mc:IO','Dataset/test root must already exist.'); end
% Internal shape/statistics validation is insufficient to bind raw data to files.
% Reread checked sources, re-extract observations, and compare before publication.
verify_sources(root,aggregate);
relative=['analyses/repeat_statistics/',aggregate.aggregate_id,'.mat'];
path=mc.safe_path(root,relative); folder=fileparts(path); if ~isfolder(folder), mkdir(folder); end
lock=mc.acquire_lock([path,'.lock']); %#ok<NASGU>
index=[path,'.json']; resumed=false;
if isfile(path)||isfile(index)
    if ~isfile(path)||~isfile(index), error('mc:Orphan','Incomplete derived summary publication; inspect %s.',path); end
    record=jsondecode(fileread(index)); info=dir(path);
    if ~strcmp(record.aggregate_id,aggregate.aggregate_id)||~strcmp(record.path,relative)||record.file_bytes~=info.bytes||~strcmp(record.file_sha256,mc.file_hash(path))
        error('mc:Integrity','Saved repeat summary checksum/index mismatch.');
    end
    loaded=load(path,'aggregate'); mc.validate_repeat_summary(loaded.aggregate);
    if ~strcmp(loaded.aggregate.identity_json,aggregate.identity_json)||~isequaln(loaded.aggregate.statistics,aggregate.statistics)||~isequaln(loaded.aggregate.axes,aggregate.axes)
        error('mc:Conflict','Existing derived summary differs.');
    end
    resumed=true; return;
end
var=whos('aggregate'); if var.bytes>1.8e9, error('mc:MATLimit','Repeat summary exceeds conservative MAT-v7 limit.'); end
temporary=[tempname(folder),'.mat']; cleanup=onCleanup(@()remove_temp(temporary)); %#ok<NASGU>
save(temporary,'aggregate','-v7'); loaded=load(temporary,'aggregate'); mc.validate_repeat_summary(loaded.aggregate);
if ~isequaln(loaded.aggregate,aggregate), error('mc:Integrity','Repeat summary MAT round trip differs.'); end
[ok,msg]=movefile(temporary,path); if ~ok, error('mc:IO','Summary commit failed: %s',msg); end
info=dir(path);
record=struct('schema_version',aggregate.schema_version,'aggregate_id',aggregate.aggregate_id, ...
    'graph_id',aggregate.group.graph_id,'metric_set_id',aggregate.group.metric_set_id,'protocol_id',aggregate.group.protocol_id, ...
    'path',relative,'file_sha256',mc.file_hash(path),'file_bytes',info.bytes,'number_repeats',aggregate.statistics.number_repeats, ...
    'created_utc',aggregate.created_utc);
mc.write_text_atomic(index,jsonencode(record,'PrettyPrint',true));
end
function remove_temp(path)
if isfile(path), delete(path); end
end
function verify_sources(root,a)
records=struct([]); g=a.group;
for i=1:numel(a.inputs)
    input=a.inputs(i);
    r=struct('schema_version','metric-v1','graph_id',g.graph_id,'topology_hash',g.topology_hash, ...
        'origin_graph_id',g.origin_graph_id,'metric_set_id',g.metric_set_id,'protocol_id',g.protocol_id, ...
        'implementation_sha256',g.implementation_sha256,'run_id',input.run_id,'status',input.status, ...
        'path',input.path,'file_bytes',input.file_bytes,'file_sha256',input.file_sha256);
    if isempty(records), records=r; else, records(end+1)=r; end %#ok<AGROW>
end
options=a.statistics.options; options.source=a.source;
expected=mc.aggregate_repeats(root,records,a.metric_definition,options);
for name={'group','inputs','source','metric_definition','axes','statistics','observation_status'}
    if ~isequaln(a.(name{1}),expected.(name{1}))
        error('mc:Integrity','Derived summary %s differs from verified source observations.',name{1});
    end
end
end
