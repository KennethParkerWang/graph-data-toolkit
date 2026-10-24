function samples = demo_generators()
%DEMO_GENERATORS Generate a small example of every implemented graph type.
% samples(i).A is sparse logical; samples(i).meta records the exact variant.
% No .mat files are saved. These parameters are examples, not a dataset plan.
setup_generators();
examples = generator_examples();
samples = repmat(struct('function_name','','A',[],'meta',struct()),size(examples,1),1);
for i = 1:size(examples,1)
    fun = examples{i,1};
    args = examples{i,2};
    [A,meta] = fun(args{:});
    samples(i).function_name = func2str(fun);
    samples(i).A = A;
    samples(i).meta = meta;
    fprintf('%-34s N=%d M=%d mean_degree=%.3f\n', ...
        func2str(fun),meta.num_nodes,meta.num_edges,meta.mean_degree);
end
end
