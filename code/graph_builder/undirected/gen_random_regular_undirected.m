function [A, meta] = gen_random_regular_undirected(N, d, seed)
% Reference: NetworkX 3.5; Copyright (c) 2004-2025 NetworkX Developers.
% BSD-3-Clause terms: sources/standard/networkx_3_5/LICENSE.txt.
%GEN_RANDOM_REGULAR_UNDIRECTED NetworkX 3.5 pairing/restart regular graph.
% [A,meta] = gen_random_regular_undirected(N,d,seed), 0<=d<N, N*d even.
% Shuffle stubs, retain valid pairs, then pair rejected stubs again.
% Restart when the reference suitability check rejects a proposal; that check
% may also reject an otherwise pairable remainder. No switch budget.
% Adapted from random_regular_graph, BSD-3-Clause; sources/standard/networkx_3_5/.
% No independent exact finite-size uniformity claim is made for this code.
if nargin < 3, seed = 1; end
validateattributes(N, {'numeric'}, {'scalar','real','finite','integer','positive'});
validateattributes(d, {'numeric'}, {'scalar','real','finite','integer','nonnegative','<',N});
N = double(N); d = double(d);
if mod(N*d,2) ~= 0
    error('graphgen:RegularParity','N*d must be even.');
end
guard = gg_seed(seed); %#ok<NASGU>
attempts = 0;
while true
    attempts = attempts+1;
    A = logical(spalloc(N,N,N*d));
    stubs = repmat((1:N).',d,1);
    success = true;
    while ~isempty(stubs)
        stubs = stubs(randperm(numel(stubs)));
        potential = zeros(N,1); order = zeros(N,1); order_count = 0;
        for pair = 1:2:numel(stubs)
            u = min(stubs(pair:pair+1)); v = max(stubs(pair:pair+1));
            if u ~= v && ~A(u,v)
                A(u,v) = true; A(v,u) = true;
            else
                if potential(u) == 0, order_count = order_count+1; order(order_count) = u; end
                potential(u) = potential(u)+1;
                if potential(v) == 0, order_count = order_count+1; order(order_count) = v; end
                potential(v) = potential(v)+1;
            end
        end
        order = order(1:order_count);
        suitable = isempty(order);
        % Preserve the reference's nested-loop variable updates verbatim.
        for first = 1:numel(order)
            s1 = order(first);
            for second = 1:numel(order)
                s2 = order(second);
                if s1 == s2, break; end
                if s1 > s2, temporary = s1; s1 = s2; s2 = temporary; end
                if ~A(s1,s2), suitable = true; break; end
            end
            if suitable, break; end
        end
        if ~suitable
            success = false; break
        end
        stubs = repelem(order,potential(order));
    end
    if success, break; end
end
params = struct('N',N,'d',d,'construction','steger_wormald_pairing_restart', ...
    'connectivity_conditioning',false,'finite_size_exact_uniform_guarantee',false);
[A,meta] = gg_finalize(A,'random_regular',false,seed,params);
meta.reference_id = 'networkx_3_5_random_regular_graph';
meta.creation_attempts = attempts;
end
