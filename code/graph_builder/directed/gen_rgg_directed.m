function [A, meta] = gen_rgg_directed(varargin)
%GEN_RGG_DIRECTED Unsupported source protocol; see docs/standard_models.md.
% The former direction conversion is not retained as a named native model.
A = []; meta = []; %#ok<NASGU>
error('graphgen:UnsupportedModelDirection', ...
    'rgg/directed has no adopted reference protocol. See docs/standard_models.md.');
end
