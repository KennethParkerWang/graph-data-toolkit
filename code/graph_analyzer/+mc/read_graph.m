function [ctx,identity,record] = read_graph(graph_path)
%READ_GRAPH Use only the formal task1 graph schema and official reader.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
schema=fullfile(root,'graph_builder','docs','graph_schema_v1.md');
if ~isfile(schema)
    error('mc:GraphSchemaPending','Task1 graph_schema_v1.md is not published; use mc.context for independent functions.');
end
io=fullfile(root,'graph_builder','io');
if ~isfile(fullfile(io,'gg_io_read_graph.m'))||~isfile(fullfile(io,'gg_io_read_manifest.m'))
    error('mc:GraphReaderPending','Task1 official graph-v1 reader is missing.');
end
if ~(ischar(graph_path)||(isstring(graph_path)&&isscalar(graph_path)))
    error('mc:Input','Expected a graph-v1 file path.');
end
graph_path=char(graph_path); file=java.io.File(graph_path);
if ~file.isAbsolute(), file=java.io.File(fullfile(pwd,graph_path)); end
graph_path=char(file.getCanonicalPath());
[folder,id,ext]=fileparts(graph_path); [graphs_folder,prefix]=fileparts(folder);
[dataset_root,graphs_name]=fileparts(graphs_folder);
if isempty(regexp(id,'^[0-9a-f]{64}$','once'))||~strcmp(ext,'.mat')||~strcmp(graphs_name,'graphs')||~strcmp(prefix,id(1:2))
    error('mc:Input','Expected published graph-v1 path graphs/<prefix>/<graph_id>.mat.');
end
% Use task1's published index and complete checksum/scientific validation.
% Restore the MATLAB search path after the official reader finishes.
previous_path=path; restore=onCleanup(@()path(previous_path)); %#ok<NASGU>
addpath(io,'-begin');
rows=gg_io_read_manifest(dataset_root);
hit=find(strcmp({rows.graph_id},id));
if numel(hit)~=1, error('mc:Input','Graph ID is absent or ambiguous in the published graph manifest.'); end
record=rows(hit);
expected=mc.safe_path(dataset_root,record.path);
if ~strcmpi(expected,graph_path), error('mc:Input','Graph path differs from its published manifest record.'); end
sample=gg_io_read_graph(graph_path,record);
n=double(sample.N); m=double(sample.M);
ctx=mc.context(sample.A,sample.directed,uint32((1:n)'),sample.edge_list,uint64((1:m)'));
if isfield(sample,'source_edge_order')
    ctx.source_edge_order_ids=sample.source_edge_order(:);
end
identity=struct('graph_id',sample.graph_id,'topology_hash',sample.topology_hash,'origin_graph_id',sample.origin_graph_id);
end
