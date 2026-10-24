function text = gg_io_canonical_json(value)
%GG_IO_CANONICAL_JSON Deterministic JSON preserving numeric type and shape.
% Numeric/logical arrays use dtype, shape and column-major values. Struct
% keys are sorted. Recipe readers hash the saved text without reserializing.
if isstruct(value)
    if ~isscalar(value)
        entries = arrayfun(@(x) gg_io_canonical_json(x), value(:), 'UniformOutput', false);
        text = ['{"__struct_array__":true,"shape":' shape_json(size(value)) ...
            ',"values":[' strjoin(entries, ',') ']}'];
        return;
    end
    names = sort(fieldnames(value));
    entries = cell(size(names));
    for k = 1:numel(names)
        entries{k} = [jsonencode(names{k}) ':' gg_io_canonical_json(value.(names{k}))];
    end
    text = ['{' strjoin(entries, ',') '}'];
elseif isnumeric(value) || islogical(value)
    if issparse(value) || ~isreal(value) || any(~isfinite(value(:)))
        error('graphio:InvalidMetadata', 'Metadata arrays must be finite, real, and full.');
    end
    if ~ismember(class(value), {'double','single','logical','uint8','uint16','uint32', ...
            'uint64','int8','int16','int32','int64'})
        error('graphio:InvalidMetadata', 'Unsupported numeric type.');
    end
    entries = cell(numel(value), 1);
    for k = 1:numel(value)
        if islogical(value)
            if value(k), entries{k} = 'true'; else, entries{k} = 'false'; end
        elseif isinteger(value)
            if startsWith(class(value), 'u'), number = sprintf('%u', value(k));
            else, number = sprintf('%d', value(k)); end
            entries{k} = jsonencode(number);
        else
            number = sprintf('%.17g', double(value(k)));
            if value(k) == 0, number = '0'; end
            entries{k} = jsonencode(number);
        end
    end
    text = ['{"dtype":' jsonencode(class(value)) ',"shape":' shape_json(size(value)) ...
        ',"values":[' strjoin(entries, ',') ']}'];
elseif ischar(value)
    if ~isrow(value) && ~isempty(value)
        error('graphio:InvalidMetadata', 'Character metadata must be a row vector.');
    end
    text = jsonencode(value);
elseif iscell(value)
    entries = cellfun(@gg_io_canonical_json, value(:), 'UniformOutput', false);
    text = ['{"__cell_array__":true,"shape":' shape_json(size(value)) ...
        ',"values":[' strjoin(entries, ',') ']}'];
else
    error('graphio:InvalidMetadata', 'Unsupported metadata class: %s.', class(value));
end
end

function text = shape_json(shape)
text = ['[' strjoin(arrayfun(@(x) sprintf('%d', x), shape, 'UniformOutput', false), ',') ']'];
end
