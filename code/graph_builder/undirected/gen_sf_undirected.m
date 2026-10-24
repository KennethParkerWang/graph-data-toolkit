function [A, meta] = gen_sf_undirected(N, M, sigma, seed)
%GEN_SF_UNDIRECTED Goh-Kahng-Kim static rank-weight simple graph.
% [A,meta] = gen_sf_undirected(N,M,sigma,seed), 0<=sigma<1, default .5.
% Draw two endpoints with probabilities proportional to i^(-sigma); reject
% loops and existing edges until M distinct undirected edges are accepted.
% Definition: arXiv:cond-mat/0106565v2, page 2; sources/standard/static_sf.pdf.
% No artificial proposal cap or connectivity selection is applied.
if nargin < 3
    sigma = 0.5;
end
if nargin < 4
    seed = 1;
end
validateattributes(N, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'integer', 'positive'}, mfilename, 'N');
validateattributes(M, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'integer', 'nonnegative'}, mfilename, 'M');
validateattributes(sigma, {'numeric'}, ...
    {'real', 'finite', 'scalar', '>=', 0, '<', 1}, mfilename, 'sigma');
N = double(N);
M = double(M);
sigma = double(sigma);
if M > N*(N-1)/2
    error('graphgen:InvalidEdgeCount', 'Require M <= N*(N-1)/2.');
end
guard = gg_seed(seed); %#ok<NASGU>

weights = (1:N).'.^(-sigma);
cdf = cumsum(weights/sum(weights));
cdf(end) = 1;
upper_edges = spalloc(N, N, M);
accepted = 0;
attempts = 0;
while accepted < M
    batch_size = min(65536,max(1024,2*(M-accepted)));
    endpoints = discretize(rand(2, batch_size), [0; cdf]);
    for proposal = 1:batch_size
        attempts = attempts+1;
        first = endpoints(1, proposal);
        second = endpoints(2, proposal);
        if first == second
            continue
        end
        source = min(first, second);
        target = max(first, second);
        if ~upper_edges(source, target)
            upper_edges(source, target) = 1;
            accepted = accepted+1;
            if accepted == M
                break
            end
        end
    end
end
A = logical(upper_edges + upper_edges.');
params = struct('N', N, 'M', M, 'sigma', sigma);
[A, meta] = gg_finalize(A, 'SF_static_weight', false, seed, params);
meta.construction = 'Independent weighted endpoints, rejecting loops and duplicate edges';
meta.sampling_attempts = attempts;
meta.reference_id = 'goh_kahng_kim_2001_static_undirected';
end
