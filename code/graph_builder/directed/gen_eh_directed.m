function [A, meta] = gen_eh_directed(N, M, seed)
%GEN_EH_DIRECTED Author directed ER followed by random edge rectification.
% N >= 1; 0 <= M <= N*(N-1); seed defaults to 1.
% In- and out-degrees are each in [floor(M/N), ceil(M/N)] on success.
% Reciprocal arcs are allowed. Author-source invalid paths fail explicitly.
% Source: enc_ver1/net/{ern,rectify}.m (2020-04-29).
% DOI: 10.1109/TCSI.2020.2986215. See docs/author_models.md.
if nargin < 3
    seed = 1;
end
guard = gg_seed(seed); %#ok<NASGU>
[A, details] = gg_rer_core(N, M);
parameters = struct('N', N, 'M', M);
[A, meta] = gg_finalize(A, 'EH', true, seed, parameters);
meta.variant = 'author_ern_rer_enc_20200429';
meta.construction = details;
meta.in_out_degrees_balanced = true;
meta.reference = '10.1109/TCSI.2020.2986215';
meta.source_file = 'enc_ver1/net/ern.m; enc_ver1/net/rectify.m';
meta.source_sha256 = 'fde37b48ff698668377adb7b431b0363d658cad7a57bb79556dbada4c896f16f';
end
