function [A, meta] = gen_hk_directed(varargin)
%GEN_HK_DIRECTED Unsupported source protocol; see docs/standard_models.md.
% The former direction conversion is not retained as a named native model.
A = []; meta = []; %#ok<NASGU>
error('graphgen:UnsupportedModelDirection', ...
    'hk/directed has no adopted reference protocol. See docs/standard_models.md.');
end
