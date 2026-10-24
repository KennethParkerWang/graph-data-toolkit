function values = gg_python_int_set_order(inserted)
%GG_PYTHON_INT_SET_ORDER CPython 3.13 insertion/iteration order of integer sets.
% Input: distinct one-based IDs; the corresponding Python keys are IDs-1.
% Used to retain NetworkX target-set ordering without a Python dependency.
% Adapted from CPython v3.13.7 Objects/setobject.c, PSF License Version 2.
% Only insert-then-iterate/pop is needed. Node IDs are exact positive doubles.
if ~isa(inserted,'double') || ~isreal(inserted) || (~isvector(inserted) && ~isempty(inserted)) || ...
        any(~isfinite(inserted(:))) || any(inserted(:) < 1 | inserted(:) > flintmax | inserted(:) ~= floor(inserted(:))) || ...
        numel(unique(inserted)) ~= numel(inserted)
    error('graphgen:IntegerSetRange','Node IDs must be a distinct finite double integer vector in [1,flintmax].');
end
table = zeros(8,1); used = 0;
for k = 1:numel(inserted)
    table = insert_clean(table,inserted(k));
    used = used+1;
    if used*5 >= (numel(table)-1)*3
        if used > 50000, minimum = used*2; else, minimum = used*4; end
        new_size = 8;
        while new_size <= minimum, new_size = new_size*2; end
        old_values = table(table ~= 0);
        table = zeros(new_size,1);
        for j = 1:numel(old_values)
            table = insert_clean(table,old_values(j));
        end
    end
end
values = table(table ~= 0);
end

function table = insert_clean(table,value)
mask = numel(table)-1;
perturb = value-1;
position = mod(perturb,numel(table));
while true
    probes = 0;
    if position+9 <= mask, probes = 9; end
    for offset = 0:probes
        index = position+offset+1;
        if table(index) == 0
            table(index) = value;
            return
        end
    end
    perturb = floor(perturb/32);
    position = mod(position*5+1+perturb,numel(table));
end
end
