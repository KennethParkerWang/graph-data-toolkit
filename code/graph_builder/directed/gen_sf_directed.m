function [A, meta] = gen_sf_directed(N, M, sigma_out, sigma_in, seed)
%GEN_SF_DIRECTED Native directed static SF with separate in/out rank weights.
% [A,meta] = gen_sf_directed(N,M,sigma_out,sigma_in,seed).
% Each exponent is in [0,1), default .5. M <= N*(N-1).
% Independently draw source i with weight i^-sigma_out and target j with
% weight j^-sigma_in; reject loops and existing arcs until M are accepted.
% Reciprocal arcs are allowed. This is not an orientation of an undirected graph.
% Goh-Kahng-Kim, arXiv:cond-mat/0106565v2, page 3, directed construction.
if nargin < 3, sigma_out = .5; end
if nargin < 4, sigma_in = .5; end
if nargin < 5, seed = 1; end
validateattributes(N, {'numeric'}, {'scalar','real','finite','integer','positive'});
validateattributes(M, {'numeric'}, {'scalar','real','finite','integer','nonnegative'});
validateattributes(sigma_out, {'numeric'}, {'scalar','real','finite','>=',0,'<',1});
validateattributes(sigma_in, {'numeric'}, {'scalar','real','finite','>=',0,'<',1});
N = double(N); M = double(M);
sigma_out = double(sigma_out); sigma_in = double(sigma_in);
if M > N*(N-1)
    error('graphgen:InvalidEdgeCount','Require M <= N*(N-1).');
end
guard = gg_seed(seed); %#ok<NASGU>
out_weights = (1:N).'.^(-sigma_out);
in_weights = (1:N).'.^(-sigma_in);
out_cdf = cumsum(out_weights/sum(out_weights)); out_cdf(end) = 1;
in_cdf = cumsum(in_weights/sum(in_weights)); in_cdf(end) = 1;
A = logical(spalloc(N,N,M)); accepted = 0; attempts = 0;
while accepted < M
    batch_size = min(65536,max(1024,2*(M-accepted)));
    draws = rand(2,batch_size);
    sources = discretize(draws(1,:),[0;out_cdf]);
    targets = discretize(draws(2,:),[0;in_cdf]);
    for index = 1:batch_size
        attempts = attempts+1;
        u = sources(index); v = targets(index);
        if u ~= v && ~A(u,v)
            A(u,v) = true; accepted = accepted+1;
            if accepted == M, break; end
        end
    end
end
parameters = struct('N',N,'M',M,'sigma_out',sigma_out,'sigma_in',sigma_in);
[A,meta] = gg_finalize(A,'SF_static_directed',true,seed,parameters);
meta.reference_id = 'goh_kahng_kim_2001_static_directed';
meta.sampling_attempts = attempts;
end
