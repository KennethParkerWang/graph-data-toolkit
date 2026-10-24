function selections = validate_selection(selections)
%VALIDATE_SELECTION Require explicit metrics, materialize defaults, reject typos.
if ischar(selections)||isstring(selections), selections=cellstr(selections); end
if iscell(selections)
    names=selections; selections=repmat(struct('metric_id','','parameters',struct()),numel(names),1);
    for i=1:numel(names), selections(i).metric_id=char(names{i}); end
end
if ~isstruct(selections)||isempty(selections)||~all(isfield(selections,{'metric_id','parameters'}))
    error('mc:Config','Select at least one metric explicitly, with metric_id and parameters.');
end
reg=mc.registry(); ids={reg.metric_id}; seen={};
for i=1:numel(selections)
    id=char(selections(i).metric_id); j=find(strcmp(ids,id),1);
    if isempty(j), error('mc:Config','Unknown metric: %s.',id); end
    e=reg(j); p=selections(i).parameters;
    if ~strcmp(e.implementation_status,'implemented'), error('mc:Config','Metric %s is unavailable.',id); end
    if ~isstruct(p)||~isscalar(p), error('mc:Config','Parameters must be a scalar struct.'); end
    allowed=[fieldnames(e.parameter_defaults); cellstr(string(e.required_parameters(:)))];
    unknown=setdiff(fieldnames(p),allowed);
    if ~isempty(unknown), error('mc:Config','Unknown parameter %s for %s.',unknown{1},id); end
    defaults=fieldnames(e.parameter_defaults);
    for k=1:numel(defaults), if ~isfield(p,defaults{k}), p.(defaults{k})=e.parameter_defaults.(defaults{k}); end, end
    required=cellstr(string(e.required_parameters(:)));
    for k=1:numel(required), if ~isfield(p,required{k}), error('mc:Config','%s requires %s.',id,required{k}); end, end
    selections(i).metric_id=id; selections(i).parameters=p;
    key=mc.identity(selections(i),'selection');
    if ismember(key,seen), error('mc:Config','Duplicate metric/parameter selection: %s.',id); end
    seen{end+1}=key; %#ok<AGROW>
end
end
