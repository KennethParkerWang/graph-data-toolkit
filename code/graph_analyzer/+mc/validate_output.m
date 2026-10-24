function validate_output(o)
%VALIDATE_OUTPUT Validate envelope identities and metric mask/axis contracts.
required={'schema_version','graph_id','topology_hash','origin_graph_id','metric_set_id','protocol_id','run_id','metric_version','implementation_sha256','metric_set_identity_json','run_identity_json','selections','summary_selections','seeds','status','results','attack','summaries','created_utc','matlab_version','elapsed_seconds'};
if ~isstruct(o)||~isscalar(o)||~all(isfield(o,required)), error('mc:Schema','Missing output fields.'); end
if ~strcmp(o.schema_version,'metric-v1'), error('mc:Schema','Unsupported result schema.'); end
for f={'graph_id','topology_hash','origin_graph_id','metric_set_id','run_id','implementation_sha256'}
    if isempty(regexp(o.(f{1}),'^[0-9a-f]{64}$','once')), error('mc:Schema','Invalid %s.',f{1}); end
end
if ~strcmp(mc.sha256(unicode2native(o.metric_set_identity_json,'UTF-8')),o.metric_set_id)||~strcmp(mc.sha256(unicode2native(o.run_identity_json,'UTF-8')),o.run_id)
    error('mc:Schema','Identity JSON digest mismatch.');
end
rr=jsondecode(o.run_identity_json); rr=rr.configuration;
if ~strcmp(rr.graph_id,o.graph_id)||~strcmp(rr.topology_hash,o.topology_hash)||~strcmp(rr.metric_set_id,o.metric_set_id)||~strcmp(mc.canonical_json(rr.seeds),mc.canonical_json(o.seeds))
    error('mc:Schema','Run identity fields do not match contents.');
end
mr=jsondecode(o.metric_set_identity_json); mr=mr.configuration;
if ~strcmp(mr.protocol_id,o.protocol_id)||~strcmp(mr.implementation_sha256,o.implementation_sha256), error('mc:Schema','Metric identity fields mismatch.'); end
if numel(mr.selections)~=numel(o.selections), error('mc:Schema','Selection count mismatch.'); end
for i=1:numel(o.selections)
    if ~strcmp(mr.selections(i).metric_id,o.selections(i).metric_id)||~strcmp(mc.canonical_json(mr.selections(i).parameters),mc.canonical_json(o.selections(i).parameters))
        error('mc:Schema','Selection parameters differ from metric-set identity.');
    end
end
if ~ismember(o.status,{'complete','partial','failed'}), error('mc:Schema','Invalid run status.'); end
check_results(o.results);
check_results(o.summaries);
if numel(o.summaries)~=numel(mr.summary_selections), error('mc:Schema','Summary count mismatch.'); end
for i=1:numel(o.summaries)
    if ~strcmp(o.summaries(i).metric_id,mr.summary_selections(i).metric_id)||~strcmp(o.summaries(i).metric_version,mr.summary_selections(i).metric_version)||~strcmp(mc.canonical_json(o.summaries(i).parameters),mc.canonical_json(mr.summary_selections(i).parameters))
        error('mc:Schema','Summary identity differs from definition.');
    end
end
if isempty(o.protocol_id)
    if numel(o.results)~=numel(mr.selections), error('mc:Schema','Static result count mismatch.'); end
    for i=1:numel(o.results)
        if ~strcmp(o.results(i).metric_id,mr.selections(i).metric_id)||~strcmp(o.results(i).metric_version,mr.selections(i).metric_version)||~strcmp(mc.canonical_json(o.results(i).parameters),mc.canonical_json(mr.selections(i).parameters))
            error('mc:Schema','Static metric result identity differs from selected definition.');
        end
    end
end
if ~isempty(o.protocol_id)
    if ~isfield(o.attack,'protocol')||~strcmp(mc.identity(o.attack.protocol,'protocol-v1'),o.protocol_id), error('mc:Schema','Attack protocol mismatch.'); end
    mc.validate_attack_result(o.attack,mr.selections,o.seeds);
    for i=1:numel(o.attack.states), check_results(o.attack.states(i).metrics); end
end
statuses={};
if ~isempty(o.results), statuses=[statuses,{o.results.status}]; end
if ~isempty(o.summaries), statuses=[statuses,{o.summaries.status}]; end
if ~isempty(o.protocol_id), for i=1:numel(o.attack.states), statuses=[statuses,{o.attack.states(i).metrics.status}]; end, end %#ok<AGROW>
if strcmp(o.status,'complete')&&any(ismember(statuses,{'failed','not_computed'})), error('mc:Schema','Complete run contains failed/uncomputed results.'); end
end
function check_results(rs)
for j=1:numel(rs)
    r=rs(j);
    if ~all(isfield(r,{'metric_id','metric_version','parameters','scope','values','axis_names','axis_ids','valid_mask','status','reason'}))||~isequal(size(r.values),size(r.valid_mask))||~islogical(r.valid_mask)
        error('mc:Schema','Metric envelope/mask mismatch.');
    end
    if ~ismember(r.status,{'ok','partial','undefined','not_applicable','not_computed','failed'}), error('mc:Schema','Unknown metric status.'); end
    if any(isnan(r.values(r.valid_mask))), error('mc:Schema','NaN cannot have a true valid_mask.'); end
    if ~iscell(r.axis_names)||~iscell(r.axis_ids)||numel(r.axis_names)~=numel(r.axis_ids), error('mc:Schema','Metric axes mismatch.'); end
    if ~isempty(r.values)
        switch r.scope
            case 'graph'
                if ~isscalar(r.values)||~isempty(r.axis_names), error('mc:Schema','Graph result must be a scalar without axes.'); end
            case {'node','edge','distribution','trajectory'}
                if numel(r.axis_names)~=1||size(r.values,2)~=1, error('mc:Schema','Vector result requires one explicit axis and column values.'); end
            case 'matrix'
                if numel(r.axis_names)~=2, error('mc:Schema','Matrix result requires two explicit axes.'); end
            otherwise
                error('mc:Schema','Unsupported result scope.');
        end
    end
    if strcmp(r.status,'ok')&&any(~r.valid_mask(:)), error('mc:Schema','ok result contains invalid values.'); end
    for k=1:numel(r.axis_ids)
        if numel(r.axis_ids{k})~=size(r.values,k), error('mc:Schema','Axis %d size mismatch in %s.',k,r.metric_id); end
    end
end
end
