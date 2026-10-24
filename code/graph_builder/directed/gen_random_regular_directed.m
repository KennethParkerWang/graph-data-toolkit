function [A, meta] = gen_random_regular_directed(varargin)
%GEN_RANDOM_REGULAR_DIRECTED Unsupported source protocol; see docs/standard_models.md.
% The former direction conversion is not retained as a named native model.
A = []; meta = []; %#ok<NASGU>
error('graphgen:UnsupportedModelDirection', ...
    'random_regular/directed has no adopted reference protocol. See docs/standard_models.md.');
end
