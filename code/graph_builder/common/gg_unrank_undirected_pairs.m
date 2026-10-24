function [sources, targets] = gg_unrank_undirected_pairs(pair_ranks)
%GG_UNRANK_UNDIRECTED_PAIRS Decode uniform pair IDs without sqrt boundary loss.
% For target v, IDs are T(v-1)+1 ... T(v), where T(v)=v*(v-1)/2.
% Correct the floating-point square-root estimate with exact integer bounds.
validateattributes(pair_ranks,{'double'}, ...
    {'vector','real','finite','integer','positive','<=',flintmax});
targets = ceil((1+sqrt(1+8*pair_ranks))/2);
too_small = pair_ranks > targets.*(targets-1)/2;
targets(too_small) = targets(too_small)+1;
too_large = pair_ranks <= (targets-1).*(targets-2)/2;
targets(too_large) = targets(too_large)-1;
sources = pair_ranks-(targets-1).*(targets-2)/2;
assert(all(sources >= 1 & sources < targets),'graphgen:PairUnrank','Invalid node-pair decoding.');
end
