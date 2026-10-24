function [A, meta] = gen_chung_lu_directed(varargin)
%GEN_CHUNG_LU_DIRECTED Unsupported source protocol; see docs/standard_models.md.
% The former direction conversion is not retained as a named native model.
A = []; meta = []; %#ok<NASGU>
error('graphgen:UnsupportedModelDirection', ...
    'chung_lu/directed has no adopted reference protocol. See docs/standard_models.md.');
end
