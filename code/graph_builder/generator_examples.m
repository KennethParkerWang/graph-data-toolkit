function examples = generator_examples()
%GENERATOR_EXAMPLES Small calls for the 27 supported source protocols.
% Columns: function handle, positional arguments. No files or datasets created.
N = 50;
w = 4*ones(N,1);
examples = {
    @gen_er_undirected, {N, 0.12, 101};
    @gen_er_directed, {N, 0.06, 102};
    @gen_er_gnm_undirected, {N, 150, 103};
    @gen_er_gnm_directed, {N, 150, 104};
    @gen_ba_undirected, {N, 3, 105};
    @gen_sf_undirected, {N, 150, 0.5, 106};
    @gen_sf_directed, {N, 150, 0.5, 0.5, 107};
    @gen_ws_undirected, {N, 3, 0.15, 108};
    @gen_nw_undirected, {N, 3, 0.15, 109};
    @gen_eh_directed, {20, 60, 110};
    @gen_qs_directed, {N, 2, 0.15, 111};
    @gen_rt_directed, {30, 57, 112};
    @gen_rr_directed, {29, 41, 113};
    @gen_rh_directed, {30, 36, 114};
    @gen_sbm_undirected, {[25 25], [0.2 0.02;0.02 0.2], 115};
    @gen_sbm_directed, {[25 25], [0.1 0.04;0.01 0.1], 116};
    @gen_rgg_undirected, {N, 0.20, 2, 117};
    @gen_random_regular_undirected, {N, 6, 118};
    @gen_hk_undirected, {N, 3, 0.5, 119};
    @gen_chung_lu_undirected, {w, 120};
    @gen_lfr_undirected, {100,2.5,1.5,.2,5,10,30,20,1000,121};
    @gen_degree_sequence_undirected, {4*ones(N,1),500,122};
    @gen_dc_sbm_undirected, {[25 25],ones(N,1)/25,[120 10;10 120],123};
    @gen_waxman_undirected, {N,.3,.4,124};
    @gen_duplication_divergence_undirected, {N,.4,10000,125};
    @gen_rhg_undirected, {N,8,.75,.5,126};
    @gen_forest_fire_directed, {N,.35,.2,127}
};
end
