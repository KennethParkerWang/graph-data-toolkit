function r = make_result(id,values,scope,axis_names,axis_ids,valid_mask,status,reason)
%MAKE_RESULT Common result envelope. NaN is never a meaningful zero.
if nargin<4, axis_names={}; end
if nargin<5, axis_ids={}; end
if nargin<6, valid_mask=isfinite(values); end
if nargin<7
    if isempty(values) || all(valid_mask(:)), status='ok';
    elseif any(valid_mask(:)), status='partial'; else, status='undefined'; end
end
if nargin<8, reason=''; end
r=struct('metric_id',id,'metric_version','1.0.0','parameters',struct(), ...
    'scope',scope,'values',values,'axis_names',{axis_names},'axis_ids',{axis_ids}, ...
    'valid_mask',logical(valid_mask),'status',status,'reason',reason,'units','dimensionless', ...
    'method','exact','elapsed_seconds',0,'details',struct());
end
