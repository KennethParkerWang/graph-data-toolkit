function [A, details] = gg_polygon_type1(N, M, sides)
%GG_POLYGON_TYPE1 Organised author rt/rr/rh code from hg.zip (2021-12-12).
% DOI 10.1109/ACCESS.2022.3141011. Random calls and candidate ordering are
% preserved. Sparse storage, shared helpers, and deterministic failure guards
% do not introduce substitute edges. Source defects: docs/author_models.md.
validateattributes(N, {'numeric'}, {'scalar','real','finite','integer','>=',sides});
validateattributes(M, {'numeric'}, {'scalar','real','finite','integer','>=',0});
N = double(N);
M = double(M);
if ~ismember(sides, [3,4,6])
    error('graphgen:InvalidPolygon', 'Only RT, RR and RH are supported.');
end
if M > N*(N-1)/2 || N*(N-1)/2 > flintmax
    error('graphgen:PolygonEdgeCount', 'Author oriented-simple graph requires M <= N*(N-1)/2.');
end
if sides ~= 3 && N == sides
    error('graphgen:AuthorSourceBoundary', ...
        'Author RR/RH tail handling uses an empty growth-loop index at N=%d.', N);
end
A = spalloc(N, N, max(M, 3*N));
for index = 1:sides
    A(index, mod(index,sides)+1) = 1;
end
work = 0;
limit = max(100000, 1000*(N+M));
add_steps = 0;
delete_steps = 0;
for index = sides+1:sides-2:N
    [u,v] = anchor(index-1);
    if sides == 3
        A(index,u) = 1;
        A(v,index) = 1;
    elseif sides == 4
        A(index,u) = 1;
        A(v,index+1) = 1;
        A(index+1,index) = 1;
    else
        A(index,u) = 1;
        A(v,index+1) = 1;
        A(index+1,index+2) = 1;
        A(index+2,index+3) = 1;
        A(index+3,index) = 1;
    end
end
if sides ~= 3
    % Keep the author's truncate-then-tail sequence, including existing nodes.
    A = A(1:N,1:N);
    if sides == 6 && N-index == 2
        index = N-1;
        [u,v] = anchor(N-1);
        A(index,index+1) = 1;
        A(index+1,u) = 1;
        A(v,index) = 1;
    end
    if N-index == 1
        index = N;
        [u,v] = anchor(N-1);
        A(index,u) = 1;
        A(v,index) = 1;
    end
end
growth_count = nnz(A);
count = growth_count;
if count > M
    while count > M
        delete_one();
        count = nnz(A);
    end
elseif count < M
    if sides == 3
        while count < M
            add_triangle();
            count = nnz(A);
        end
        while count > M
            delete_one();
            count = nnz(A);
        end
    else
        % The reference RH augmentation walks five nodes, not six.
        if sides == 4
            stop_gap = 3;
            path_nodes = 4;
        else
            stop_gap = 4;
            path_nodes = 5;
        end
        while count-M < -stop_gap
            add_path(path_nodes);
            count = nnz(A);
        end
        while count < M
            add_one();
            count = nnz(A);
        end
    end
end
check_source_graph();
if nnz(A) ~= M
    error('graphgen:AuthorSourceEdgeCount', 'Author routine produced %d instead of %d arcs.', nnz(A), M);
end
A = logical(A);
details = struct('polygon_sides', sides, 'seed_nodes', sides, ...
    'seed_arcs', sides, 'growth_arc_count', growth_count, ...
    'augmentation_calls', add_steps, 'deletion_calls', delete_steps, ...
    'work_units', work, 'work_limit', limit, ...
    'sampling', 'uniform node then uniform concatenated out/in neighbour', ...
    'node_tail_policy', 'author truncate and triangle/rectangle tail branches', ...
    'source_guard', 'validate final graph; preserve source neighbour errors; finite work limit', ...
    'connectedness_guaranteed', false, 'no_antiparallel_arcs', true);

    function [u,v] = anchor(last_node)
        tick();
        u = randi(last_node);
        neighbours = adjacent(u);
        if isempty(neighbours)
            error('graphgen:AuthorSourceEmptyNeighbour', ...
                'Author anchor selected isolated node %d.', u);
        end
        v = neighbours(randi(numel(neighbours)));
        if A(v,u)
            temporary = v;
            v = u;
            u = temporary;
        end
    end

    function neighbours = adjacent(node)
        neighbours = [find(A(node,:) == 1), find(A(:,node) == 1).'];
        if numel(unique(neighbours)) < numel(neighbours)
            error('graphgen:AuthorSourceReciprocal', ...
                'Author source produced reciprocal arcs incident to node %d.', node);
        end
    end

    function delete_one()
        tick();
        delete_steps = delete_steps+1;
        u = randi(N);
        neighbours = adjacent(u);
        if isempty(neighbours)
            if sides == 3
                error('graphgen:AuthorSourceEmptyNeighbour', ...
                    'Author RT deletion selected isolated node %d (reference calls randi(0)).', u);
            end
            return
        end
        v = neighbours(randi(numel(neighbours)));
        A(u,v) = 0;
        A(v,u) = 0;
    end

    function add_triangle()
        tick();
        add_steps = add_steps+1;
        pair = randperm(N,2);
        u = pair(1);
        v = pair(2);
        while A(u,v) || A(v,u)
            tick();
            pair = randperm(N,2);
            u = pair(1);
            v = pair(2);
        end
        neighbours = adjacent(v);
        if isempty(neighbours)
            error('graphgen:AuthorSourceEmptyNeighbour', ...
                'Author RT augmentation selected isolated node %d.', v);
        end
        w = neighbours(randi(numel(neighbours)));
        if A(w,v)
            A(v,u) = 1;
            if ~A(u,w) && ~A(w,u)
                A(u,w) = 1;
            end
        else
            A(u,v) = 1;
            if ~A(u,w) && ~A(w,u)
                A(w,u) = 1;
            end
        end
    end

    function add_path(node_count)
        tick();
        add_steps = add_steps+1;
        [first, next] = first_zero_arc();
        if ~A(next,first)
            A(first,next) = 1;
        end
        previous = next;
        for step = 3:node_count
            candidates = find(A(previous,:) == 0);
            candidates(candidates == previous) = [];
            if isempty(candidates)
                return
            end
            next = candidates(randi(numel(candidates)));
            if ~A(next,previous)
                A(previous,next) = 1;
            end
            previous = next;
        end
        if ~A(first,previous)
            A(previous,first) = 1;
        end
    end

    function add_one()
        tick();
        add_steps = add_steps+1;
        [u,v] = first_zero_arc();
        if ~A(v,u)
            A(u,v) = 1;
        end
    end

    function [u,v] = first_zero_arc()
        u = randi(N);
        candidates = find(A(u,:) == 0);
        candidates(candidates == u) = [];
        if isempty(candidates)
            % rr.m/rh.m cache len_neb1 before a loop that never updates it.
            % Stop at that nonterminating source branch instead of redrawing.
            error('graphgen:AuthorSourceStalledCandidate', ...
                'Author RR/RH candidate loop cannot terminate after selecting node %d.', u);
        end
        v = candidates(randi(numel(candidates)));
    end

    function check_source_graph()
        if any(diag(A))
            error('graphgen:AuthorSourceSelfLoop', ...
                'Author %d-gon source path produced a self-loop; no repair or redraw was applied.', sides);
        end
        if nnz(A & A.')
            error('graphgen:AuthorSourceReciprocal', ...
                'Author %d-gon source path produced reciprocal arcs; no repair or redraw was applied.', sides);
        end
    end

    function tick()
        work = work+1;
        if work > limit
            error('graphgen:AuthorSourceWorkLimit', ...
                'Author %d-gon routine exhausted %d work units; preserve this failed seed.', sides, limit);
        end
    end
end
