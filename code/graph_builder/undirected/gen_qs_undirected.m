function [A, meta] = gen_qs_undirected(varargin)
%GEN_QS_UNDIRECTED Unsupported source protocol; see docs/standard_models.md.
% The former direction conversion is not retained as a named native model.
A = []; meta = []; %#ok<NASGU>
error('graphgen:UnsupportedModelDirection', ...
    'qs/undirected has no adopted reference protocol. See docs/standard_models.md.');
end
