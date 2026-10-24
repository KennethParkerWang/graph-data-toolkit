function indices = gg_weighted_sample(weights, count)
%GG_WEIGHTED_SAMPLE Sequential weighted sampling without replacement.
validateattributes(weights, {'numeric'}, {'real','finite','vector','nonnegative'}, mfilename, 'weights');
validateattributes(count, {'numeric'}, {'scalar','integer','nonnegative','finite'}, mfilename, 'count');
weights = double(weights(:));
if nnz(weights > 0) < count
    error('graphgen:InsufficientWeights', 'Need at least count strictly positive weights.');
end
indices = zeros(1,count);
if count == 0
    return;
end
weights = weights / max(weights);
for j = 1:count
    cumulative = cumsum(weights);
    threshold = rand * cumulative(end);
    selected = find(cumulative > threshold,1,'first');
    if isempty(selected)
        selected = find(weights > 0,1,'last');
    end
    indices(j) = selected;
    weights(selected) = 0;
end
end
