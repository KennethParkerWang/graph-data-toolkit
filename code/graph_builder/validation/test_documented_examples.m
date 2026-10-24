function report = test_documented_examples()
%TEST_DOCUMENTED_EXAMPLES Execute the 27 concrete model-guide examples.
setup_generators;
cases = {
    @gen_er_undirected,{100,.06,1}; @gen_er_directed,{100,.03,1};
    @gen_er_gnm_undirected,{100,300,1}; @gen_er_gnm_directed,{100,300,1};
    @gen_ba_undirected,{100,3,1};
    @gen_sf_undirected,{100,300,.5,1}; @gen_sf_directed,{100,300,.4,.7,1};
    @gen_ws_undirected,{100,3,.1,1}; @gen_nw_undirected,{100,3,.1,1};
    @gen_eh_directed,{20,60,2}; @gen_qs_directed,{100,2,.05,1};
    @gen_rt_directed,{30,57,1}; @gen_rr_directed,{29,41,1}; @gen_rh_directed,{30,36,1};
    @gen_sbm_undirected,{[50,50],[.12,.01;.01,.12],1};
    @gen_sbm_directed,{[50,50],[.1,.03;.01,.1],1};
    @gen_rgg_undirected,{100,.15,2,1}; @gen_random_regular_undirected,{100,6,1};
    @gen_hk_undirected,{100,3,.4,1};
    @gen_chung_lu_undirected,{[2*ones(50,1);8*ones(50,1)],1};
    @gen_lfr_undirected,{400,2.5,1.5,.2,8,20,80,50,1000,38};
    @gen_degree_sequence_undirected,{8*ones(400,1),10000,41};
    @gen_dc_sbm_undirected,{[200,200],ones(400,1)/200,[1800,200;200,1800],61};
    @gen_waxman_undirected,{400,.3,.08,62};
    @gen_duplication_divergence_undirected,{400,.55,[],63};
    @gen_rhg_undirected,{400,12,.75,.5,51};
    @gen_forest_fire_directed,{400,.35,.2,52}};
for k = 1:size(cases,1)
    generator = cases{k,1}; args = cases{k,2};
    [A,meta] = generator(args{:});
    assert(issparse(A) && islogical(A) && size(A,1) == meta.num_nodes && ~any(diag(A)));
    if ~meta.directed, assert(isequal(A,A.')); end
end
report = struct('passed',true,'examples',size(cases,1));
fprintf('DOCUMENTED_EXAMPLES_OK: %d model-guide calls.\n',report.examples);
end
