function [A, meta] = gen_nw_directed(varargin)
%GEN_NW_DIRECTED Unsupported source protocol; see docs/standard_models.md.
% The former direction conversion is not retained as a named native model.
A = []; meta = []; %#ok<NASGU>
error('graphgen:UnsupportedModelDirection', ...
    'nw/directed has no adopted reference protocol. See docs/standard_models.md.');
end
