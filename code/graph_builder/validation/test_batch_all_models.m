function report = test_batch_all_models()
%TEST_BATCH_ALL_MODELS Compare JSON batch dispatch with direct calls.
setup_generators(); examples = generator_examples(); count = size(examples,1);
root = [tempname '_graph_batch_models_v2']; mkdir(root);
cleanup = onCleanup(@() cleanup_owned(root)); %#ok<NASGU>
config = struct('schema_version',2,'dataset_id','all_models','output_dir','output', ...
    'base_seed',101,'samples_per_combination',1,'resume',true,'on_error','stop','max_graphs',count);
jobs = cell(count,1); expected = cell(count,1);
implementation = gg_implementation_digest();
for k = 1:count
    fun = examples{k,1}; args = examples{k,2}; name = func2str(fun);
    tokens = regexp(name,'^gen_(.+)_(undirected|directed)$','tokens','once');
    names = parameter_names(tokens{1},tokens{2}); parameters = struct();
    assert(numel(args) == numel(names)+1 && args{end} == 100+k);
    for j = 1:numel(names), parameters.(names{j}) = args{j}; end
    jobs{k} = struct('model',tokens{1},'direction',tokens{2},'parameters',parameters);
    [A,meta] = fun(args{:}); expected{k} = gg_io_make_sample(A,gg_prepare_metadata(A,meta,name,implementation));
end
config.jobs = jobs; file = fullfile(root,'config.json');
f = fopen(file,'w','n','UTF-8'); fprintf(f,'%s',jsonencode(config)); fclose(f);
first = generate_graph_batch(file);
assert(first.generated == count && first.failed == 0);
descriptor = jsondecode(fileread(fullfile(first.output_dir,'dataset.json')));
assert(strcmp(first.generator_version,expected{1}.meta.implementation_version) && ...
    strcmp(descriptor.implementation_version,first.generator_version), ...
    'Batch report and dataset descriptor must record the actual generator version.');
for k = 1:count
    event = first.records(k);
    sample = gg_io_read_graph(fullfile(first.output_dir,event.path));
    assert(isequal(sample.A,expected{k}.A));
    assert(strcmp(sample.graph_id,expected{k}.graph_id));
    assert(strcmp(gg_io_scientific_hash(sample),gg_io_scientific_hash(expected{k})));
end
before = gg_io_read_manifest(first.output_dir);
second = generate_graph_batch(file); after = gg_io_read_manifest(first.output_dir);
assert(second.skipped == count && second.failed == 0 && isequaln(before,after));
report = struct('passed',true,'matched_interfaces',count,'resume_skipped',count);
fprintf('BATCH_ALL_MODELS_OK: %d JSON/direct scientific matches and unchanged resume files.\n',count);
end

function names = parameter_names(model,direction)
switch model
    case 'er', names = {'N','p'};
    case {'er_gnm','eh','rt','rr','rh'}, names = {'N','M'};
    case 'ba', names = {'N','m'};
    case 'sf'
        if strcmp(direction,'directed'), names = {'N','M','sigma_out','sigma_in'};
        else, names = {'N','M','sigma'}; end
    case {'ws','nw'}, names = {'N','K','beta'};
    case 'qs', names = {'N','r','q'};
    case 'sbm', names = {'sizes','P'};
    case 'rgg', names = {'N','radius','dim'};
    case 'random_regular', names = {'N','d'};
    case 'hk', names = {'N','m','triad_probability'};
    case 'chung_lu', names = {'w'};
    case 'lfr', names = {'N','tau1','tau2','mu','average_degree','min_community','max_community','max_degree','max_iters'};
    case 'degree_sequence', names = {'degrees','swap_attempts'};
    case 'dc_sbm', names = {'sizes','theta','omega'};
    case 'waxman', names = {'N','alpha','beta'};
    case 'duplication_divergence', names = {'N','p','max_attempts'};
    case 'rhg', names = {'N','R','alpha','T'};
    case 'forest_fire', names = {'N','p_forward','p_backward'};
    otherwise, error('test:UnmappedModel','Missing independent parameter map.');
end
end
function cleanup_owned(root)
target = char(java.io.File(root).getCanonicalPath());
parent = char(java.io.File(tempdir).getCanonicalPath());
assert(startsWith(lower(target),[lower(parent) filesep]) && endsWith(target,'_graph_batch_models_v2'));
if isfolder(target), rmdir(target,'s'); end
end
