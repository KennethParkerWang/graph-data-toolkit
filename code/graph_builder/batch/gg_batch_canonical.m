function value = gg_batch_canonical(value)
%GG_BATCH_CANONICAL 递归排序结构体键，构造确定的 JSON 校验内容。
if isstruct(value)
    value = orderfields(value);
    names = fieldnames(value);
    for element = 1:numel(value)
        for index = 1:numel(names)
            value(element).(names{index}) = gg_batch_canonical(value(element).(names{index}));
        end
    end
elseif iscell(value)
    for index = 1:numel(value)
        value{index} = gg_batch_canonical(value{index});
    end
end
end
