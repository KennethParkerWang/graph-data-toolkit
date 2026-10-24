function [A, meta] = gg_finalize(A, model, is_directed, seed, parameters)
%GG_FINALIZE Validate a simple graph and attach reproducibility metadata.
% Directed A(i,j)=1 means i -> j. mean_degree means TOTAL degree for digraphs.
if ~(isnumeric(A) || islogical(A)) || ~ismatrix(A) || ...
        size(A,1) ~= size(A,2) || size(A,1) < 1 || ~isreal(A)
    error('graphgen:InvalidAdjacency', 'Adjacency must be a nonempty real square matrix.');
end
values = nonzeros(A);
if any(~isfinite(values)) || any(values ~= 1)
    error('graphgen:NotBinary', 'All nonzero adjacency entries must equal one.');
end
if any(diag(A) ~= 0)
    error('graphgen:SelfLoop', 'Simple graph generators must not produce self-loops.');
end
validateattributes(is_directed, {'logical','numeric'}, {'scalar','binary'}, mfilename, 'is_directed');
if ~is_directed && ~isequal(A, A.')
    error('graphgen:NotSymmetric', 'Undirected adjacency must be symmetric.');
end
A = sparse(logical(A));
N = size(A,1);
if is_directed
    M = nnz(A);
    degree_convention = 'mean_degree is mean total degree; mean_in/out_degree = M/N';
else
    M = nnz(A)/2;
    degree_convention = 'mean_degree = 2*M/N';
end
meta = struct('model', char(model), 'directed', logical(is_directed), ...
    'seed', full(double(seed)), 'parameters', parameters, ...
    'num_nodes', N, 'num_edges', M, 'mean_degree', 2*M/N, ...
    'degree_convention', degree_convention, ...
    'generator_version', '2.1.0', 'rng_algorithm', 'twister', ...
    'matlab_version', version);
if is_directed
    meta.mean_in_degree = M/N;
    meta.mean_out_degree = M/N;
    meta.density = M / max(1, N*(N-1));
else
    meta.density = 2*M / max(1, N*(N-1));
end
end
