function [A, meta] = gen_ba_undirected(N, m, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_BA_UNDIRECTED BA graph with the NetworkX 3.5 default star seed.
% [A,meta] = gen_ba_undirected(N,m,seed), 1 <= m < N; seed defaults to 1.
% Each new vertex selects m distinct old vertices by repeated degree draws.
% Degrees stay fixed during the target-set draw. M = m*(N-m).
% Adapted from NetworkX 3.5 barabasi_albert_graph (BSD-3-Clause).
% Reference and license: sources/standard/networkx_3_5/.
if nargin < 3, seed = 1; end
validateattributes(N, {'numeric'}, {'scalar','real','finite','integer','>=',2});
validateattributes(m, {'numeric'}, {'scalar','real','finite','integer','>=',1,'<',N});
N = double(N); m = double(m);
guard = gg_seed(seed); %#ok<NASGU>
M = m*(N-m);
sources = zeros(M,1); targets = zeros(M,1);
sources(1:m) = 1; targets(1:m) = (2:m+1).';
edge_count = m;
repeated = zeros(2*M,1);
repeated(1:m) = 1; repeated(m+1:2*m) = (2:m+1).';
repeated_count = 2*m;
for node = m+2:N
    chosen = zeros(m,1); count = 0;
    while count < m
        candidate = repeated(randi(repeated_count));
        if ~any(chosen(1:count) == candidate)
            count = count+1; chosen(count) = candidate;
        end
    end
    chosen = gg_python_int_set_order(chosen);
    indices = edge_count+(1:m);
    sources(indices) = node; targets(indices) = chosen;
    edge_count = edge_count+m;
    repeated(repeated_count+(1:m)) = chosen;
    repeated(repeated_count+m+(1:m)) = node;
    repeated_count = repeated_count+2*m;
end
A = sparse([sources;targets],[targets;sources],true,N,N);
params = struct('N',N,'m',m,'initial_graph','star_m_plus_1','expected_edges',M);
[A,meta] = gg_finalize(A,'BA',false,seed,params);
meta.reference_id = 'networkx_3_5_barabasi_albert_graph';
meta.reference_protocol = 'star seed; unique draws from degree-repeated vertices';
end
