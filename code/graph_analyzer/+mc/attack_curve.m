function [x,y,valid,detail] = attack_curve(trajectory,selection,source)
%ATTACK_CURVE Extract scalar observations without interpolation or padding.
% selection: unique metric ID, or exact {metric_id,parameters[,metric_version]}.
if nargin<3, source='states'; end
if isstruct(selection), metric_id=selection.metric_id; else, metric_id=char(selection); end
if ~isstruct(trajectory)||~isscalar(trajectory)||~isfield(trajectory,source)
    error('mc:InvalidTrajectory','A mc.attack trajectory with %s is required.',source);
end
if ~ismember(source,{'states','sampled'}), error('mc:InvalidTrajectory','source must be states or sampled.'); end
rows=trajectory.(source); n=numel(rows);
x=NaN(n,1); y=NaN(n,1); valid=false(n,1);
detail=struct('metric_id',metric_id,'source',source,'removed_count',NaN(n,1), ...
    'status',{cell(n,1)},'normalization_denominator',[],'metric_definition',struct());
for j=1:n
    if strcmp(source,'states')
        x(j)=rows(j).removed_fraction; detail.removed_count(j)=rows(j).removed_count;
    else
        x(j)=rows(j).actual_removed_fraction; detail.removed_count(j)=rows(j).actual_removed_count;
    end
    r=rows(j).metrics;
    if isempty(r), detail.status{j}='not_computed'; continue; end
    hit=mc.match_metric(r,selection);
    if isempty(hit), detail.status{j}='not_computed'; continue; end
    r=r(hit); detail.status{j}=r.status;
    if isempty(fieldnames(detail.metric_definition))
        detail.metric_definition=struct('metric_id',r.metric_id,'metric_version',r.metric_version,'parameters',r.parameters);
    elseif ~strcmp(mc.canonical_json(detail.metric_definition),mc.canonical_json(struct('metric_id',r.metric_id,'metric_version',r.metric_version,'parameters',r.parameters)))
        error('mc:MetricDefinitionMismatch','Metric definition changes between trajectory states.');
    end
    if ~strcmp(r.scope,'graph')
        error('mc:InvalidSummaryMetric','Summary metric %s must return a graph scalar.',metric_id);
    end
    if isempty(r.values)&&ismember(r.status,{'not_computed','failed','not_applicable','undefined'})
        continue; % Preserve an unavailable scalar observation and its reason/status.
    end
    if numel(r.values)~=1
        error('mc:InvalidSummaryMetric','Summary metric %s must return a graph scalar.',metric_id);
    end
    y(j)=r.values;
    valid(j)=isscalar(r.valid_mask)&&r.valid_mask&&isfinite(y(j))&&ismember(r.status,{'ok','partial'});
end
end
