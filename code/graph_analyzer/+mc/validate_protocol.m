function p = validate_protocol(p)
%VALIDATE_PROTOCOL Normalize an explicit attack experiment, not graph storage.
if ~isstruct(p) || ~isscalar(p)
    error('mc:InvalidProtocol','Protocol must be a scalar struct.');
end
defaults = struct('version','1.0.0','target','node','strategy','external', ...
    'ranking','static','rank_metric',struct('metric_id','','parameters',struct()), ...
    'rank_metric_version','', ...
    'score_order','desc','tie_break','original_id','deletion_mode','single', ...
    'batch_size',1,'recompute_interval',1,'sample_fractions',[], ...
    'rounding','floor','sample_policy','exact','stop_fraction',1,'external_sequence',[]);
% Do not add fields to v1.0.0: its normalized JSON and IDs remain stable.
version=mc.param(p,'version','1.0.0');
if ~(ischar(version)||(isstring(version)&&isscalar(version))) || ~ismember(char(version),{'1.0.0','1.1.0'})
    error('mc:InvalidProtocol','Unsupported protocol version.');
end
if strcmp(version,'1.1.0'), defaults.attack_fractions=[]; end
names = fieldnames(p);
for j=1:numel(names)
    if ~isfield(defaults,names{j})
        error('mc:InvalidProtocol','Unknown protocol field: %s',names{j});
    end
end
names = fieldnames(defaults);
for j=1:numel(names)
    if ~isfield(p,names{j}), p.(names{j})=defaults.(names{j}); end
end
choices = {'target',{'node','edge'};'strategy',{'random','ranked','external','source_order'}; ...
    'ranking',{'static','adaptive'};'score_order',{'desc','asc'}; ...
    'tie_break',{'original_id','random','source_order'};'deletion_mode',{'single','batch','fraction_grid'}; ...
    'rounding',{'floor','ceil','nearest'};'sample_policy',{'exact','previous','next'}};
for j=1:size(choices,1)
    k=choices{j,1};
    if ~(ischar(p.(k)) || (isstring(p.(k)) && isscalar(p.(k)))) || ~ismember(char(p.(k)),choices{j,2})
        error('mc:InvalidProtocol','Invalid %s.',k);
    end
    p.(k)=char(p.(k));
end
p.version=char(p.version);
for k={'batch_size','recompute_interval'}
    v=p.(k{1});
    if ~isnumeric(v)||~isscalar(v)||~isfinite(v)||v<1||v~=fix(v)
        error('mc:InvalidProtocol','%s must be a positive integer.',k{1});
    end
    p.(k{1})=double(v);
end
if strcmp(p.deletion_mode,'single') && p.batch_size~=1
    error('mc:InvalidProtocol','Single deletion requires batch_size=1.');
end
if ~isnumeric(p.stop_fraction)||~isscalar(p.stop_fraction)||~isfinite(p.stop_fraction)||p.stop_fraction<0||p.stop_fraction>1
    error('mc:InvalidProtocol','stop_fraction must lie in [0,1].');
end
mc.validate_attack_schedule(p);
if strcmp(p.deletion_mode,'fraction_grid'), p.attack_fractions=double(p.attack_fractions(:)); end
if ~isnumeric(p.sample_fractions)||(~isempty(p.sample_fractions)&&~isvector(p.sample_fractions))||any(~isfinite(p.sample_fractions(:)))||any(p.sample_fractions(:)<0|p.sample_fractions(:)>1)
    error('mc:InvalidProtocol','sample_fractions must be a finite vector in [0,1].');
end
p.sample_fractions=double(p.sample_fractions(:));
if ~isnumeric(p.external_sequence)||(~isempty(p.external_sequence)&&~isvector(p.external_sequence))||any(~isfinite(p.external_sequence(:)))||any(p.external_sequence(:)<1|p.external_sequence(:)~=fix(p.external_sequence(:)))||any(p.external_sequence(:)>flintmax)||numel(unique(p.external_sequence))~=numel(p.external_sequence)
    error('mc:InvalidProtocol','external_sequence must contain unique positive original IDs <= flintmax.');
end
p.external_sequence=double(p.external_sequence(:));
if ~strcmp(p.strategy,'external') && ~isempty(p.external_sequence)
    error('mc:InvalidProtocol','external_sequence only applies to external strategy.');
end
if strcmp(p.strategy,'source_order') || strcmp(p.tie_break,'source_order')
    if ~strcmp(p.target,'edge'), error('mc:InvalidProtocol','Source order applies only to edges.'); end
end
if ~isstruct(p.rank_metric)||~isscalar(p.rank_metric)||~all(isfield(p.rank_metric,{'metric_id','parameters'}))||~isempty(setdiff(fieldnames(p.rank_metric),{'metric_id','parameters'}))||~isstruct(p.rank_metric.parameters)||~isscalar(p.rank_metric.parameters)
    error('mc:InvalidProtocol','rank_metric must contain metric_id and scalar parameters.');
end
p.rank_metric.metric_id=char(p.rank_metric.metric_id);
if strcmp(p.strategy,'ranked') && isempty(p.rank_metric.metric_id)
    error('mc:InvalidProtocol','Ranked attack requires rank_metric.metric_id.');
end
if ~(ischar(p.rank_metric_version)||(isstring(p.rank_metric_version)&&isscalar(p.rank_metric_version)))
    error('mc:InvalidProtocol','rank_metric_version must be a string.');
end
p.rank_metric_version=char(p.rank_metric_version);
if strcmp(p.strategy,'ranked')
    p.rank_metric=mc.validate_selection(p.rank_metric);
    registry=mc.registry(); entry=registry(strcmp({registry.metric_id},p.rank_metric.metric_id));
    if isempty(p.rank_metric_version)
        p.rank_metric_version=entry.metric_version;
    elseif ~strcmp(p.rank_metric_version,entry.metric_version)
        error('mc:InvalidProtocol','rank_metric_version does not match the installed metric definition.');
    end
elseif ~isempty(p.rank_metric_version)
    error('mc:InvalidProtocol','Non-ranked strategies require an empty rank_metric_version.');
end
% Reject unused choices instead of recording two seemingly different protocols.
if ~strcmp(p.strategy,'ranked') && ~strcmp(p.tie_break,'original_id')
    error('mc:InvalidProtocol','Non-ranked strategies require tie_break=original_id (unused).');
end
if ~strcmp(p.strategy,'ranked') && ~strcmp(p.ranking,'static')
    error('mc:InvalidProtocol','Adaptive ranking only applies to ranked attacks.');
end
if strcmp(p.ranking,'static') && p.recompute_interval~=1
    error('mc:InvalidProtocol','Static ranking uses recompute_interval=1 (unused).');
end
end
