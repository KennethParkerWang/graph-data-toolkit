function [A, meta] = gen_hk_undirected(N, m, triad_probability, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_HK_UNDIRECTED NetworkX 3.5 powerlaw_cluster_graph protocol.
% [A,meta] = gen_hk_undirected(N,m,p,seed), 1<=m<=N, 0<=p<=1.
% Starts with m isolated vertices. Preselects a weighted target set.
% Triangle steps retain the last preferential target; fallback pops the next
% target. A fallback may revisit a triangle target in the source algorithm;
% actual M may be below m*(N-m). This behavior is retained and counted.
% Adapted from NetworkX 3.5 (BSD-3-Clause); sources/standard/networkx_3_5/.
if nargin < 4, seed = 1; end
validateattributes(N, {'numeric'}, {'scalar','real','finite','integer','positive'});
validateattributes(m, {'numeric'}, {'scalar','real','finite','integer','>=',1,'<=',N});
validateattributes(triad_probability, {'numeric'}, {'scalar','real','finite','>=',0,'<=',1});
N = double(N); m = double(m); triad_probability = double(triad_probability);
guard = gg_seed(seed); %#ok<NASGU>
A = logical(spalloc(N,N,2*m*(N-m)));
neighbors = cell(N,1);
repeated = zeros(m+2*m*(N-m),1);
repeated(1:m) = (1:m).'; repeated_count = m;
triad_successes = 0; duplicate_fallbacks = 0;
for node = m+1:N
    selected = zeros(m,1); count = 0;
    while count < m
        candidate = repeated(randi(repeated_count));
        if ~any(selected(1:count) == candidate)
            count = count+1; selected(count) = candidate;
        end
    end
    selected = gg_python_int_set_order(selected);
    cursor = 1; target = selected(cursor); cursor = cursor+1;
    add_link(target);
    repeated_count = repeated_count+1; repeated(repeated_count) = target;
    count = 1;
    while count < m
        if rand < triad_probability
            candidates = neighbors{target};
            candidates = candidates(candidates ~= node & ~A(node,candidates));
            if ~isempty(candidates)
                other = candidates(randi(numel(candidates)));
                add_link(other);
                repeated_count = repeated_count+1; repeated(repeated_count) = other;
                triad_successes = triad_successes+1;
                count = count+1;
                continue
            end
        end
        target = selected(cursor); cursor = cursor+1;
        duplicate_fallbacks = duplicate_fallbacks+double(A(node,target));
        add_link(target);
        repeated_count = repeated_count+1; repeated(repeated_count) = target;
        count = count+1;
    end
    repeated(repeated_count+(1:m)) = node;
    repeated_count = repeated_count+m;
end
params = struct('N',N,'m',m,'triad_probability',triad_probability, ...
    'initial_graph','m_isolated_vertices','target_set_order','cpython_3_13_integer_set', ...
    'connectivity_conditioning',false);
[A,meta] = gg_finalize(A,'HK',false,seed,params);
meta.reference_id = 'networkx_3_5_powerlaw_cluster_graph';
meta.triad_successes = triad_successes;
meta.duplicate_fallbacks = duplicate_fallbacks;
    function add_link(target_node)
        if ~A(node,target_node)
            A(node,target_node) = true; A(target_node,node) = true;
            neighbors{node}(end+1) = target_node;
            neighbors{target_node}(end+1) = node;
        end
    end
end
