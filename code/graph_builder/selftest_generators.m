function results = selftest_generators()
%SELFTEST_GENERATORS Small invariant, reproducibility and boundary checks.
setup_generators();
state = rng; restore = onCleanup(@() rng(state)); %#ok<NASGU>
examples = generator_examples();
results = repmat(struct('generator_id','','N',0,'M',0,'seconds',0),size(examples,1),1);
for k = 1:size(examples,1)
    generator = examples{k,1}; args = examples{k,2}; before = rng; started = tic;
    [A,meta] = generator(args{:});
    elapsed = toc(started);
    assert(isequal(before,rng),'Generator changed caller RNG.');
    [B,other] = generator(args{:});
    assert(isequal(A,B) && isequaln(meta,other),'Identical seed changed graph or metadata.');
    assert(issparse(A) && islogical(A) && ~any(diag(A)));
    assert(isequal(size(A),[meta.num_nodes,meta.num_nodes]));
    if meta.directed
        assert(meta.num_edges == nnz(A));
    else
        assert(isequal(A,A.') && meta.num_edges == nnz(A)/2);
    end
    results(k) = struct('generator_id',func2str(generator),'N',size(A,1), ...
        'M',meta.num_edges,'seconds',elapsed);
    fprintf('PASS %-34s N=%d M=%d\n',results(k).generator_id,results(k).N,results(k).M);
end
for N = 1:8
    for M = 0:N*(N-1)/2
        assert(nnz(gen_er_gnm_undirected(N,M,1)) == 2*M);
    end
    assert(nnz(gen_er_gnm_directed(N,N*(N-1),1)) == N*(N-1));
end
assert(nnz(gen_ba_undirected(50,3,1))/2 == 141);
assert(nnz(gen_ba_undirected(4,3,1))/2 == 3);
assert(nnz(gen_hk_undirected(4,4,.5,1)) == 0);
assert(nnz(gen_chung_lu_undirected([100;100],1)) == 2);
assert(nnz(gen_rgg_undirected(20,0,2,1)) == 0);
assert(nnz(gen_rgg_undirected(20,sqrt(2),2,1)) == 380);
for N = 2:10
    for d = 0:N-1
        if mod(N*d,2) == 0
            A = gen_random_regular_undirected(N,d,13);
            assert(all(full(sum(A,2)) == d));
        end
    end
end
counts = zeros(100,1);
for seed = 1:100, counts(seed) = nnz(gen_er_undirected(20,.2,seed))/2; end
assert(abs(mean(counts)-38) < 6*sqrt(190*.2*.8/100));
fprintf('ALL_GENERATORS_OK: %d supported protocols; RNG, invariants and boundary checks.\n',size(examples,1));
end
