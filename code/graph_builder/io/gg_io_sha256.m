function digest = gg_io_sha256(value, mode)
%GG_IO_SHA256 SHA-256 of UTF-8 text, bytes, or a file without loading it fully.
if nargin < 2, mode = 'text'; end
engine = java.security.MessageDigest.getInstance('SHA-256');
switch char(mode)
    case 'text'
        if isstring(value) && isscalar(value), value = char(value); end
        if ~ischar(value) || (~isrow(value) && ~isempty(value))
            error('graphio:InvalidText', 'Text must be a character row.');
        end
        engine.update(unicode2native(value, 'UTF-8'));
    case 'bytes'
        if ~isa(value, 'uint8'), error('graphio:InvalidBytes', 'Bytes must be uint8.'); end
        engine.update(value(:));
    case 'file'
        file = fopen(value, 'rb');
        if file < 0, error('graphio:FileOpen', 'Cannot open file: %s', value); end
        cleanup = onCleanup(@() fclose(file)); %#ok<NASGU>
        while true
            block = fread(file, 1024 * 1024, '*uint8');
            if isempty(block), break; end
            engine.update(block);
        end
    otherwise
        error('graphio:InvalidHashMode', 'Unknown SHA-256 mode: %s', mode);
end
bytes = typecast(engine.digest(), 'uint8');
digest = lower(reshape(dec2hex(bytes, 2).', 1, []));
end
