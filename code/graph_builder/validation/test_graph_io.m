function test_graph_io()
%TEST_GRAPH_IO Verify graph-v1 round trips, identity, conflicts and recovery.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'io'));
temporary = [tempname '_graph_io_test'];
mkdir(temporary);
cleanup = onCleanup(@() remove_temporary(temporary)); %#ok<NASGU>
original_directory = pwd;
directory_cleanup = onCleanup(@() cd(original_directory)); %#ok<NASGU>
assert(strcmp(gg_io_sha256('abc'), ...
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'));
records = create_graph_io_examples(temporary);
assert(numel(records) == 5);
for k = 1:numel(records)
    record = records(k);
    path = fullfile(temporary,strrep(record.path,'/',filesep));
    sample = gg_io_read_graph(path,record);
    original_hash = gg_io_sha256(path,'file');
    [again,status] = gg_io_write_graph(temporary,sample);
    assert(strcmp(status,'existing') && strcmp(again.file_sha256,original_hash));
    assert(strcmp(gg_io_sha256(path,'file'),original_hash));
    sample.meta.created_utc = '2030-01-01T00:00:00.000Z';
    sample.meta.elapsed_seconds = 99.5;
    sample.meta.matlab_version = 'different runtime';
    [again,status] = gg_io_write_graph(temporary,sample);
    assert(strcmp(status,'existing') && strcmp(again.file_sha256,original_hash));
end
sample = gg_io_read_graph(fullfile(temporary,strrep(records(1).path,'/',filesep)),records(1));
bad = sample; bad.meta.custom_scientific_value = 123;
expect_error(@() gg_io_write_graph(temporary,bad),'graphio:ScientificConflict');
bad = sample; bad.edge_list = flipud(bad.edge_list);
if ~isequal(bad.edge_list,sample.edge_list)
    expect_error(@() gg_io_validate_sample(bad),'graphio:EdgeMismatch');
end
bad = sample; bad.meta.parameters.extra = 123;
expect_error(@() gg_io_validate_sample(bad),'graphio:IdentityMismatch');
bad = sample; bad.meta.unsupported = @sin;
expect_error(@() gg_io_validate_sample(bad),'graphio:InvalidMetadata');
for k = 1:numel(records)
    current = gg_io_read_graph(fullfile(temporary,strrep(records(k).path,'/',filesep)),records(k));
    if isfield(current,'source_edge_order') && current.M > 0
        bad = current; bad.source_edge_order(1) = 0;
        expect_error(@() gg_io_validate_sample(bad),'graphio:InvalidEdgeOrder');
        bad = current; bad.source_edge_order = flipud(bad.source_edge_order);
        expect_error(@() gg_io_write_graph(temporary,bad),'graphio:ScientificConflict');
        changed_meta = current.meta;
        changed_meta.directed = current.directed;
        changed_meta.source_edge_order = current.source_edge_order;
        changed_meta.rng.seed = uint32(current.meta.rng.seed + 1);
        changed_seed = gg_io_make_sample(current.A,changed_meta);
        assert(strcmp(changed_seed.topology_hash,current.topology_hash));
        assert(~strcmp(changed_seed.graph_id,current.graph_id));
        break;
    end
end
% An interrupted write with a fully validated MAT but no part can recover.
orphan_root = fullfile(temporary,'orphan');
graph_path = fullfile(orphan_root,'graphs',sample.graph_id(1:2),[sample.graph_id '.mat']);
mkdir(fileparts(graph_path));
save(graph_path,'-struct','sample','-v7');
[orphan_record,status] = gg_io_write_graph(orphan_root,sample);
assert(strcmp(status,'recovered'));
assert(isscalar(gg_io_merge_manifest(orphan_root)));
% Corruption is rejected before MAT load and never overwritten.
file = fopen(graph_path,'ab'); fwrite(file,uint8('corruption')); fclose(file);
damaged_hash = gg_io_sha256(graph_path,'file');
expect_error(@() gg_io_read_graph(graph_path,orphan_record),'graphio:FileChecksumMismatch');
expect_error(@() gg_io_write_graph(orphan_root,sample),'graphio:FileChecksumMismatch');
assert(strcmp(gg_io_sha256(graph_path,'file'),damaged_hash));
% A conflicting part must not replace the last published manifest.
index = fullfile(temporary,'manifests','graphs.jsonl');
index_hash = gg_io_sha256(index,'file');
conflict = records(1); conflict.file_bytes = conflict.file_bytes + 1;
part = fullfile(temporary,'manifests','parts',['graphs_' conflict.graph_id '_conflict.jsonl']);
gg_io_atomic_text(part,[jsonencode(conflict) newline]);
expect_error(@() gg_io_merge_manifest(temporary),'graphio:ManifestConflict');
assert(strcmp(gg_io_sha256(index,'file'),index_hash));
delete(part);
% Published rows and immutable parts must agree before a write returns skip.
conflict_rows = records;
conflict_rows(1).file_bytes = conflict_rows(1).file_bytes + 1;
lines = arrayfun(@jsonencode,conflict_rows,'UniformOutput',false);
gg_io_atomic_text(index,[strjoin(lines,newline) newline]);
expect_error(@() gg_io_write_graph(temporary,sample),'graphio:ManifestConflict');
lines = arrayfun(@jsonencode,records,'UniformOutput',false);
gg_io_atomic_text(index,[strjoin(lines,newline) newline]);
% Public relative paths resolve against MATLAB cd, not Java's user.dir.
cd(temporary);
[relative_record,relative_status] = gg_io_write_graph('relative_dataset',sample);
assert(strcmp(relative_status,'created'));
assert(isfile(fullfile(temporary,'relative_dataset',relative_record.path)));
assert(isscalar(gg_io_merge_manifest('relative_dataset')));
gg_io_atomic_text('relative_text.txt','relative path');
assert(strcmp(fileread(fullfile(temporary,'relative_text.txt')),'relative path'));
cd(original_directory);
% Traversal and matrix-valued field shape ambiguity must be rejected.
bad_record = records(1); bad_record.path = '../outside.mat';
expect_error(@() gg_io_check_record(bad_record),'graphio:InvalidManifest');
assert(~strcmp(gg_io_canonical_json([1,2]),gg_io_canonical_json([1;2])));
assert(strcmp(gg_io_canonical_json(struct('b',2,'a',1)), ...
    gg_io_canonical_json(struct('a',1,'b',2))));
empty_root = fullfile(temporary,'empty');
assert(isempty(gg_io_merge_manifest(empty_root)));
assert(isempty(gg_io_read_manifest(empty_root)));
fprintf('GRAPH_IO_TEST_OK 5 fixtures; round-trip, resume, corruption, conflicts, recovery, shape and empty index\n');
end

function expect_error(action,identifier)
try
    action();
catch problem
    assert(strcmp(problem.identifier,identifier),'Expected %s, received %s: %s',identifier,problem.identifier,problem.message);
    return;
end
error('graphio:TestMissingError','Expected %s.',identifier);
end

function remove_temporary(path)
resolved = char(java.io.File(path).getCanonicalPath());
temp_root = char(java.io.File(tempdir).getCanonicalPath());
if ~startsWith(lower(resolved),[lower(temp_root) filesep]) || ~endsWith(resolved,'_graph_io_test')
    error('graphio:UnsafeTestCleanup','Refusing cleanup outside the test temp directory.');
end
if isfolder(resolved), rmdir(resolved,'s'); end
end
