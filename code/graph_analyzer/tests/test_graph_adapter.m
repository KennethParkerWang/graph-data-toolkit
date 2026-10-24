function report=test_graph_adapter()
%TEST_GRAPH_ADAPTER Read task1's five tiny handoff graphs; write only owned copies.
t=tic; checks=0;
root=fileparts(fileparts(mfilename('fullpath'))); project=fileparts(root);
source=fullfile(project,'graph_builder','examples','schema_v1');
manifest=fullfile(source,'manifests','graphs.jsonl');
assert(isfile(manifest),'Task1 official small handoff manifest is required for integration tests.');
rows=mc.read_jsonl(manifest); assert(numel(rows)==5); checks=checks+1;
base=fullfile(root,'validation',['graph_adapter_',char(java.util.UUID.randomUUID())]); mkdir(base);
mkdir(fullfile(base,'manifests')); copyfile(manifest,fullfile(base,'manifests','graphs.jsonl'));
source_hash=cell(numel(rows),1); selections={'node_count','edge_count','degree','largest_component_size','global_efficiency'};
saved=struct([]); source_order_index=[];
for i=1:numel(rows)
    src=mc.safe_path(source,rows(i).path); dst=mc.safe_path(base,rows(i).path);
    source_hash{i}=mc.file_hash(src); folder=fileparts(dst); if ~isfolder(folder), mkdir(folder); end
    copyfile(src,dst);
    before_path=path; [ctx,identity,record]=mc.read_graph(dst);
    assert(strcmp(before_path,path)); checks=checks+1;
    assert(ctx.n==rows(i).N&&ctx.m==rows(i).M&&ctx.directed==rows(i).directed); checks=checks+1;
    assert(isequal(ctx.node_ids,uint32((1:ctx.n)'))&&isequal(ctx.edge_ids,uint64((1:ctx.m)'))); checks=checks+1;
    assert(strcmp(identity.graph_id,rows(i).graph_id)&&strcmp(identity.topology_hash,rows(i).topology_hash)&&strcmp(identity.origin_graph_id,rows(i).origin_graph_id)); checks=checks+1;
    assert(strcmp(record.file_sha256,rows(i).file_sha256)); checks=checks+1;
    raw=load(dst);
    if isfield(raw,'source_edge_order')
        assert(isequal(ctx.source_edge_order_ids,raw.source_edge_order)); source_order_index=i; checks=checks+1;
    else
        assert(~isfield(ctx,'source_edge_order_ids')); checks=checks+1;
    end
    if ctx.m==0, assert(isequal(size(ctx.edge_list),[0 2])); checks=checks+1; end
    preview=compute_graph_metrics(base,rows(i).path,selections);
    assert(preview.preview&&strcmp(preview.status,'preview')); checks=checks+1;
    result=compute_graph_metrics(base,rows(i).path,selections,struct('preview',false,'writer_id','graph_adapter'));
    assert(strcmp(result.status,'complete')); checks=checks+1;
    o=mc.verify_record(base,result.record);
    assert(o.results(1).values==rows(i).N&&o.results(2).values==rows(i).M); checks=checks+1;
    assert(strcmp(o.graph_id,identity.graph_id)&&strcmp(o.topology_hash,identity.topology_hash)&&strcmp(o.origin_graph_id,identity.origin_graph_id)); checks=checks+1;
    resume=compute_graph_metrics(base,rows(i).path,selections,struct('preview',false,'writer_id','graph_adapter'));
    assert(strcmp(resume.status,'resumed')&&strcmp(resume.record.file_sha256,result.record.file_sha256)); checks=checks+1;
    if isempty(saved), saved=result.record; else, saved(end+1)=result.record; end %#ok<AGROW>
end
mc.merge_manifests(base);
assert(~isempty(source_order_index)); checks=checks+1;
row=rows(source_order_index); [ctx,identity]=mc.read_graph(mc.safe_path(base,row.path));
p=struct('target','edge','strategy','source_order');
o=mc.build_run(ctx,identity,{'edge_count'},struct('protocol',p));
assert(isequal(o.attack.deleted_ids,ctx.source_edge_order_ids)); checks=checks+1;
% Explicit batch preview only: does not launch a production workload.
batch=compute_metric_batch(base,{rows.graph_id},selections);
assert(all(cellfun(@(x)strcmp(x.status,'preview'),batch))); checks=checks+1;
% Exact original fixture files and owned graph copies are unchanged.
for i=1:numel(rows)
    assert(strcmp(mc.file_hash(mc.safe_path(source,rows(i).path)),source_hash{i})); checks=checks+1;
    assert(strcmp(mc.file_hash(mc.safe_path(base,rows(i).path)),source_hash{i})); checks=checks+1;
end
% Corrupt only an explicitly owned additional copy, never task1's originals.
corrupt=fullfile(base,'corruption_case'); mkdir(corrupt); mkdir(fullfile(corrupt,'manifests'));
copyfile(manifest,fullfile(corrupt,'manifests','graphs.jsonl'));
dst=mc.safe_path(corrupt,rows(1).path); mkdir(fileparts(dst)); copyfile(mc.safe_path(source,rows(1).path),dst);
fid=fopen(dst,'a'); assert(fid>=0); fwrite(fid,uint8(0)); fclose(fid);
must_error(@()mc.read_graph(dst),'graphio:FileChecksumMismatch'); checks=checks+1;
must_error(@()mc.read_graph(fullfile(base,'not_a_graph.mat')),'mc:Input'); checks=checks+1;
[~,fixture_name]=fileparts(base);
report=struct('checks',checks,'seconds',toc(t),'status','passed','fixture_root',['validation/',fixture_name],'input_fixture_root','../graph_builder/examples/schema_v1','graph_count',numel(rows),'records',saved);
mc.write_text_atomic(fullfile(root,'validation','graph_adapter_report.json'),jsonencode(report,'PrettyPrint',true),true);
end
function must_error(fn,id)
try, fn(); catch ex, assert(strcmp(ex.identifier,id),'Expected %s, got %s',id,ex.identifier); return; end
error('mc:Test','Expected error %s.',id);
end
