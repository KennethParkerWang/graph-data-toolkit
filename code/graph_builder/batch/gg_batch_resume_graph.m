function sample = gg_batch_resume_graph(root, event, item, implementation_digest)
%GG_BATCH_RESUME_GRAPH Verify committed bytes and request identity before skip.
if isempty(regexp(event.graph_id,'^[0-9a-f]{64}$','once'))
    error('graphgen:BatchAttemptConflict','Invalid graph ID in generation log.');
end
expected_path = ['graphs/' event.graph_id(1:2) '/' event.graph_id '.mat'];
if ~strcmp(event.path,expected_path)
    error('graphgen:BatchAttemptConflict','Invalid relative graph path in generation log.');
end
% Parts are retained so a run interrupted before index publication can resume.
parts = dir(fullfile(root,'manifests','parts',['graphs_' event.graph_id '_*.jsonl']));
rows = repmat(gg_io_record_template(),0,1);
for k = 1:numel(parts)
    part = gg_io_read_records_file(fullfile(parts(k).folder,parts(k).name));
    if numel(part) ~= 1 || ~strcmp(part.graph_id,event.graph_id)
        error('graphgen:BatchAttemptConflict','Invalid committed graph part.');
    end
    rows(end+1,1) = part; %#ok<AGROW>
end
rows = [rows; gg_io_find_published_record(root,event.graph_id)];
if isempty(rows), error('graphgen:BatchMissingCommit','Completed attempt has no graph commit record.'); end
for k = 2:numel(rows)
    if ~strcmp(gg_io_canonical_json(rows(k)),gg_io_canonical_json(rows(1)))
        error('graphgen:BatchAttemptConflict','Conflicting commit records.');
    end
end
sample = gg_io_read_graph(fullfile(root,strrep(event.path,'/',filesep)),rows(1));
if ~strcmp(sample.meta.generator_id,item.generator_id) || ...
        ~strcmp(sample.meta.model,item.model) || ...
        ~strcmp(sample.meta.implementation_sha256,implementation_digest) || ...
        sample.meta.rng.seed ~= item.seed || ~strcmp(sample.meta.rng.algorithm,'twister') || ...
        sample.directed ~= strcmp(item.direction,'directed')
    error('graphgen:BatchSampleConflict','Stored graph does not match its planned request.');
end
names = fieldnames(item.parameters);
for k = 1:numel(names)
    name = names{k};
    if ~isfield(sample.meta.parameters,name) || ...
            ~isequaln(sample.meta.parameters.(name),item.parameters.(name))
        error('graphgen:BatchSampleConflict','Stored parameter %s differs from its plan.',name);
    end
end
end
