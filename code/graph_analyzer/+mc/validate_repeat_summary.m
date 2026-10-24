function validate_repeat_summary(a)
%VALIDATE_REPEAT_SUMMARY Validate derived identity, provenance and statistics.
required={'schema_version','aggregate_id','identity_json','group','inputs','source','metric_definition', ...
    'axes','statistics','observation_status','summary_implementation_sha256'};
if ~isstruct(a)||~isscalar(a)||~all(isfield(a,required))||~strcmp(a.schema_version,'repeat-summary-1.0.0')
    error('mc:AggregateSchema','Missing or unsupported repeat-summary fields.');
end
recipe=struct('group',a.group,'inputs',a.inputs,'source',a.source,'metric_definition',a.metric_definition, ...
    'statistics_options',a.statistics.options,'summary_implementation_sha256',a.summary_implementation_sha256);
[id,txt]=mc.identity(recipe,'repeat-summary-v1');
if ~strcmp(id,a.aggregate_id)||~strcmp(txt,a.identity_json), error('mc:AggregateSchema','Summary identity mismatch.'); end
s=a.statistics;
if numel(a.inputs)~=s.number_repeats||numel(unique({a.inputs.run_id}))~=numel(a.inputs)||numel(unique([a.inputs.attack_seed]))~=numel(a.inputs)
    error('mc:AggregateSchema','Duplicate or inconsistent repeat provenance.');
end
if ~isequal(size(a.observation_status),size(s.raw_values))||numel(a.axes.observation_index)~=size(s.raw_values,1)
    error('mc:AggregateSchema','Observation axes/status shape mismatch.');
end
if ~strcmp(a.source,'summaries')
    for f={'removed_count','actual_removed_fraction','state_index'}
        if numel(a.axes.(f{1}))~=size(s.raw_values,1), error('mc:AggregateSchema','Curve axis length mismatch.'); end
    end
end
expected=mc.repeat_statistics(s.raw_values,s.raw_valid_mask,s.options);
if ~isequaln(s,expected), error('mc:AggregateSchema','Stored statistics do not match masked raw repeats.'); end
end
