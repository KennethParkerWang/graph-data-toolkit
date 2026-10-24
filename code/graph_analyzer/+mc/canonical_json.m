function txt = canonical_json(value)
%CANONICAL_JSON Sorted struct keys; preserve array order and explicit defaults.
% IDs are defined by these UTF-8 bytes; consumers verify saved identity_json.
txt=jsonencode(order(value),'ConvertInfAndNaN',false);
end
function v=order(v)
if isstruct(v)
    v=orderfields(v); names=fieldnames(v);
    for j=1:numel(v), for k=1:numel(names), v(j).(names{k})=order(v(j).(names{k})); end, end
elseif iscell(v)
    for j=1:numel(v), v{j}=order(v{j}); end
elseif isnumeric(v) && any(~isfinite(v(:)))
    error('mc:Identity','Configuration identity cannot contain NaN/Inf.');
elseif isa(v,'function_handle') || isobject(v) && ~isstring(v)
    error('mc:Identity','Configuration cannot contain objects or function handles.');
end
end
