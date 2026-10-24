function [A, meta] = gen_ba_directed(varargin)
%GEN_BA_DIRECTED Unsupported source protocol; see docs/standard_models.md.
% The former direction conversion is not retained as a named native model.
A = []; meta = []; %#ok<NASGU>
error('graphgen:UnsupportedModelDirection', ...
    'ba/directed has no adopted reference protocol. See docs/standard_models.md.');
end
