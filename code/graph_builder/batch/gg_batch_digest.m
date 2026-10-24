function digest = gg_batch_digest(value)
%GG_BATCH_DIGEST SHA-256；文本使用 UTF-8，其余输入须为 uint8 字节。
if ischar(value) || (isstring(value) && isscalar(value))
    bytes = unicode2native(char(value), 'UTF-8');
elseif isa(value, 'uint8')
    bytes = value;
else
    error('graphgen:BatchDigestInput', '校验和输入必须是文本或 uint8。');
end
if ~usejava('jvm')
    error('graphgen:BatchNeedsJVM', '批量完整性校验需要 MATLAB 的默认 JVM。');
end
engine = javaMethod('getInstance', 'java.security.MessageDigest', 'SHA-256');
engine.update(typecast(uint8(bytes(:)), 'int8'));
result = typecast(engine.digest(), 'uint8');
digest = lower(reshape(dec2hex(result, 2).', 1, []));
end
