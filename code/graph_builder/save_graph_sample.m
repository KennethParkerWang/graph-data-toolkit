function [record, sample, status] = save_graph_sample(dataset_root, A, meta, generator_id)
%SAVE_GRAPH_SAMPLE Save one generated graph using graph-v1 dataset paths.
% [record,sample,status] = save_graph_sample(root,A,meta,'gen_ba_undirected')
% Publishes a graph and immutable manifest part. Call gg_io_merge_manifest
% once after a group of writes. For complete datasets use generate_graph_batch.
setup_generators();
prepared = gg_prepare_metadata(A,meta,char(generator_id));
sample = gg_io_make_sample(A,prepared);
[record,status] = gg_io_write_graph(dataset_root,sample);
end
