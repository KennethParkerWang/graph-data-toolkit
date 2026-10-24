function [A, details] = gg_rer_core(N, M)
%GG_RER_CORE Author ern + rectify(T=Inf), preserving random calls and order.
% The case-4 candidate rule can select a self-loop. Preserve the entire
% trajectory: a later rectification may remove it. Validate only the result.
validateattributes(N, {'numeric'}, {'scalar','real','finite','integer','>=',1});
validateattributes(M, {'numeric'}, {'scalar','real','finite','integer','>=',0});
N = double(N);
M = double(M);
if M > N*(N-1) || N*(N-1) > flintmax
    error('graphgen:InvalidEdgeCount', 'Directed EH requires M <= N*(N-1).');
end
A = spalloc(N, N, M);
work = 0;
limit = max(100000, 1000*(N+M));
count = 0;
while count < M
    tick();
    i = randi(N);
    j = randi(N);
    while i == j || A(i,j)
        tick();
        i = randi(N);
        j = randi(N);
    end
    A(i,j) = 1;
    count = count+1;
end
out_degree = full(sum(A,2));
in_degree = full(sum(A,1));
initial_out_variance = var(out_degree,1);
initial_in_variance = var(in_degree,1);
lower = floor(M/N);
upper = ceil(M/N);
moves = 0;
while any(out_degree < lower | out_degree > upper) || ...
        any(in_degree < lower | in_degree > upper)
    tick();
    operation = randi(4);
    candidates = deficient_nodes(operation);
    while ~isempty(candidates)
        tick();
        moves = moves+1;
        switch operation
            case 1
                extremes = find(out_degree == max(out_degree));
            case 2
                extremes = find(in_degree == max(in_degree));
            case 3
                extremes = find(out_degree == min(out_degree));
            case 4
                extremes = find(in_degree == min(in_degree));
        end
        node_i = candidates(randi(numel(candidates)));
        node_j = extremes(randi(numel(extremes)));
        switch operation
            case 1
                first = find(A(node_i,:) == 0);
                first(first == node_i) = [];
                second = find(A(node_j,:) == 1);
            case 2
                first = find(A(:,node_i) == 0);
                first(first == node_i) = [];
                second = find(A(:,node_j) == 1);
            case 3
                first = find(A(node_i,:) == 1);
                second = find(A(node_j,:) == 0);
                second(second == node_j) = [];
            case 4
                first = find(A(:,node_i) == 1);
                second = find(A(:,node_j) == 0);
                % Keep the author's node_i exclusion; do not silently fix it.
                second(second == node_i) = [];
        end
        if isempty(first) || isempty(second)
            error('graphgen:AuthorSourceCandidate', ...
                'Author rectify operation %d has an empty candidate set.', operation);
        end
        i = first(randi(numel(first)));
        j = second(randi(numel(second)));
        switch operation
            case 1
                A(node_i,i) = 1;
                A(node_j,j) = 0;
            case 2
                A(i,node_i) = 1;
                A(j,node_j) = 0;
            case 3
                A(node_i,i) = 0;
                A(node_j,j) = 1;
            case 4
                A(i,node_i) = 0;
                A(j,node_j) = 1;
        end
        out_degree = full(sum(A,2));
        in_degree = full(sum(A,1));
        candidates = deficient_nodes(operation);
    end
end
if any(diag(A))
    error('graphgen:AuthorSourceSelfLoop', ...
        'Author rectify returned %d self-loops after %d rectifications.', nnz(diag(A)), moves);
end
A = logical(A);
details = struct('initial_model', 'author_directed_ER_Gnm', ...
    'initial_in_degree_variance', initial_in_variance, ...
    'initial_out_degree_variance', initial_out_variance, ...
    'rectifications', moves, 'work_units', work, 'work_limit', limit, ...
    'in_degree_min', min(in_degree), 'in_degree_max', max(in_degree), ...
    'out_degree_min', min(out_degree), 'out_degree_max', max(out_degree), ...
    'author_mode', 'rectify with T=Inf; complete chosen operation block', ...
    'source_guard', 'fail on final self-loop, source empty candidates, or work limit', ...
    'connectedness_guaranteed', false);

    function indices = deficient_nodes(op)
        switch op
            case 1
                indices = find(out_degree < lower);
            case 2
                indices = find(in_degree < lower);
            case 3
                indices = find(out_degree > upper);
            case 4
                indices = find(in_degree > upper);
        end
    end

    function tick()
        work = work+1;
        if work > limit
            error('graphgen:AuthorSourceWorkLimit', ...
                'Author ER/RER exhausted %d work units; no replacement graph was generated.', limit);
        end
    end
end
