function hit=match_metric(results,selection)
%MATCH_METRIC Locate one metric, optionally by exact normalized parameters.
% No installed-registry lookup: saved old definitions remain selectable.
if ischar(selection)||(isstring(selection)&&isscalar(selection))
    id=char(selection); parameters=[]; version='';
elseif isstruct(selection)&&isscalar(selection)&&all(isfield(selection,{'metric_id','parameters'})) ...
        &&isempty(setdiff(fieldnames(selection),{'metric_id','parameters','metric_version'})) ...
        &&isstruct(selection.parameters)&&isscalar(selection.parameters)
    id=char(selection.metric_id); parameters=selection.parameters;
    version=mc.param(selection,'metric_version','');
else
    error('mc:InvalidSelection','Expected metric ID or exact metric_id/parameters selection.');
end
hit=[]; if isempty(results), return; end
hit=find(strcmp({results.metric_id},id));
if isstruct(parameters)
    key=mc.canonical_json(parameters);
    hit=hit(arrayfun(@(k)strcmp(mc.canonical_json(results(k).parameters),key),hit));
end
if ~isempty(version), hit=hit(strcmp({results(hit).metric_version},version)); end
if numel(hit)>1
    error('mc:AmbiguousMetric','Specify exact parameters for metric %s; multiple observations match.',id);
end
end
