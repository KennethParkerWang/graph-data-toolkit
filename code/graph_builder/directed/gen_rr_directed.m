function [A, meta] = gen_rr_directed(N, M, seed)
%GEN_RR_DIRECTED Author Henneberg 4-gon generator.
% N > 4; 0 <= M <= N*(N-1)/2; seed defaults to 1.
% Keeps the author's node-then-neighbour draws, tail handling and edge edits.
% Invalid author-source paths and work-limit exhaustion fail explicitly.
% Source: hg/rr.m, 2021-12-12; DOI 10.1109/ACCESS.2022.3141011.
% See docs/author_models.md for source defects and guarded failures.
if nargin < 3
    seed = 1;
end
guard = gg_seed(seed); %#ok<NASGU>
[A, details] = gg_polygon_type1(N, M, 4);
parameters = struct('N', N, 'M', M);
[A, meta] = gg_finalize(A, 'RR', true, seed, parameters);
meta.variant = 'author_hg_rr_20211212';
meta.construction = details;
meta.reference = '10.1109/ACCESS.2022.3141011';
meta.source_file = 'hg/rr.m';
meta.source_sha256 = '58fc0da61aaae17220e0a227b9705fc86790bbc49fa59a3f4d7160d740d2b3bf';
end
