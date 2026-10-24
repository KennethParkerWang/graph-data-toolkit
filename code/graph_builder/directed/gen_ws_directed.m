function [A, meta] = gen_ws_directed(varargin)
%GEN_WS_DIRECTED Unsupported source protocol; see docs/standard_models.md.
% The former direction conversion is not retained as a named native model.
A = []; meta = []; %#ok<NASGU>
error('graphgen:UnsupportedModelDirection', ...
    'ws/directed has no adopted reference protocol. See docs/standard_models.md.');
end
