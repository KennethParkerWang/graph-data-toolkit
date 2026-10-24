function value = param(parameters,name,default)
%PARAM Read a parameter without silently changing an explicit empty value.
if isfield(parameters,name), value=parameters.(name); else, value=default; end
end
