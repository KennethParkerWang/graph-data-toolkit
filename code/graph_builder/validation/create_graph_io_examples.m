function records = create_graph_io_examples(output_root)
%CREATE_GRAPH_IO_EXAMPLES Write small graph-v1 handoff fixtures for Python.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'io'));
if nargin < 1, output_root = fullfile(root,'examples','schema_v1'); end
fixtures = make_fixtures();
for k = 1:numel(fixtures)
    gg_io_write_graph(output_root,fixtures{k});
end
records = gg_io_merge_manifest(output_root);
dataset = struct('dataset_id','schema_v1_examples','graph_schema_version','graph-v1', ...
    'created_utc','2026-09-28T00:00:00.000Z','graph_root','graphs', ...
    'graph_manifest','manifests/graphs.jsonl','description','Graph schema interoperability fixtures.');
gg_io_atomic_text(fullfile(output_root,'dataset.json'),[jsonencode(dataset) newline]);
fprintf('GRAPH_IO_EXAMPLES_OK %d graphs in %s\n',numel(records),output_root);
end

function fixtures = make_fixtures()
base = struct('model','schema_fixture','directed',false,'seed',1, ...
    'parameters',struct('fixture',''), 'generator_version','fixture-1', ...
    'implementation_sha256',gg_io_sha256('graph-v1-fixtures-1'), ...
    'source',struct('kind','hand_constructed','description','Schema test, not a random graph model'), ...
    'created_utc','2026-09-28T00:00:00.000Z');
fixtures = cell(5,1);
meta = base; meta.parameters.fixture = 'undirected_triangle_isolate';
meta.attributes = struct('community',uint32([1;1;1;2]), ...
    'coordinates',[0,0;1,0;0,1;2,2], 'node_ids',uint32((1:4).'));
meta.custom_note = '社区与坐标保持节点顺序';
meta.source_edge_order = uint64([3;1;2]);
A = sparse([1,2,1,3,2,3],[2,1,3,1,3,2],true,4,4);
fixtures{1} = gg_io_make_sample(A,meta);
meta = base; meta.directed = true; meta.parameters.fixture = 'directed_reciprocal_isolate';
A = sparse([1,2,2],[2,1,3],true,4,4);
fixtures{2} = gg_io_make_sample(A,meta);
meta = base; meta.parameters.fixture = 'edgeless_three';
fixtures{3} = gg_io_make_sample(sparse(false(3)),meta);
meta = base; meta.directed = true; meta.parameters.fixture = 'directed_singleton';
meta.source_edge_order = zeros(0,1,'uint64');
fixtures{4} = gg_io_make_sample(sparse(false(1)),meta);
meta = base; meta.parameters.fixture = 'derived_relabeling';
meta.origin_graph_id = fixtures{1}.graph_id;
meta.transformation = struct('name','relabel','permutation',uint32([4;2;3;1]));
perm = [4,2,3,1];
fixtures{5} = gg_io_make_sample(fixtures{1}.A(perm,perm),meta);
end
