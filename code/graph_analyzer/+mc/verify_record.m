function output = verify_record(root,record)
%VERIFY_RECORD Check file bytes, envelope identities and complete scientific data.
path=mc.safe_path(root,record.path); info=dir(path);
if isempty(info)||info.bytes~=record.file_bytes||~strcmp(mc.file_hash(path),record.file_sha256)
    error('mc:Integrity','File missing, truncated or checksum mismatch: %s',record.path);
end
s=load(path,'output'); if ~isfield(s,'output'), error('mc:Schema','Missing output variable.'); end
output=s.output; mc.validate_output(output);
for name={'schema_version','graph_id','topology_hash','origin_graph_id','metric_set_id','protocol_id','run_id','status','implementation_sha256'}
    if ~isfield(record,name{1})||~strcmp(record.(name{1}),output.(name{1})), error('mc:Integrity','Manifest/content mismatch: %s.',name{1}); end
end
expected=strjoin({'metrics',output.metric_set_id,output.graph_id(1:2),output.graph_id,[output.run_id,'.mat']},'/');
if ~strcmp(strrep(record.path,'\','/'),expected), error('mc:Integrity','Unexpected metric result path.'); end
end
