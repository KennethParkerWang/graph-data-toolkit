function record = gg_io_check_record(record)
%GG_IO_CHECK_RECORD Validate one graph manifest row and portable relative path.
template = gg_io_record_template();
if ~isstruct(record) || ~isscalar(record) || ...
        ~isequal(sort(fieldnames(record)),sort(fieldnames(template)))
    error('graphio:InvalidManifest','Graph manifest fields do not match graph-v1.');
end
record = orderfields(record,template);
for name = {'graph_id','origin_graph_id','topology_hash','file_sha256','scientific_sha256'}
    value = record.(name{1});
    if ~ischar(value) || ~isrow(value) || isempty(regexp(value,'^[0-9a-f]{64}$','once'))
        error('graphio:InvalidManifest','Invalid manifest %s.',name{1});
    end
end
expected = ['graphs/' record.graph_id(1:2) '/' record.graph_id '.mat'];
if ~ischar(record.path) || ~strcmp(record.path,expected) || ~strcmp(record.schema_version,'graph-v1')
    error('graphio:InvalidManifest','Manifest path or schema is invalid.');
end
validateattributes(record.N,{'numeric'},{'scalar','integer','>=',1,'<=',double(intmax('uint32'))});
validateattributes(record.M,{'numeric'},{'scalar','integer','nonnegative','<=',flintmax});
validateattributes(record.file_bytes,{'numeric'},{'scalar','integer','positive','<=',flintmax});
if ~islogical(record.directed) || ~isscalar(record.directed)
    error('graphio:InvalidManifest','Manifest directed must be logical.');
end
for name = {'model','generator_id','implementation_version','created_utc'}
    if ~ischar(record.(name{1})) || ~isrow(record.(name{1})) || isempty(record.(name{1}))
        error('graphio:InvalidManifest','Invalid manifest text %s.',name{1});
    end
end
end
