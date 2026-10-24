function [id,identity_json] = identity(value,prefix)
%IDENTITY SHA-256 of versioned canonical configuration, independent of paths.
if nargin<2, prefix='metric-set-v1'; end
identity_json=mc.canonical_json(struct('identity_version',prefix,'configuration',value));
id=mc.sha256(unicode2native(identity_json,'UTF-8'));
end
