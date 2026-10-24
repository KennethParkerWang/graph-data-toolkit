function hash = sha256(bytes)
%SHA256 Lower-case hexadecimal SHA-256 of explicit bytes.
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(uint8(bytes)); hash=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
