function hash = file_hash(path)
%FILE_HASH Stream file bytes; this is not the original topology hash.
fid=fopen(path,'rb'); if fid<0, error('mc:IO','Cannot open %s.',path); end
c=onCleanup(@()fclose(fid)); md=java.security.MessageDigest.getInstance('SHA-256');
while ~feof(fid), md.update(fread(fid,1024*1024,'*uint8')); end
hash=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
