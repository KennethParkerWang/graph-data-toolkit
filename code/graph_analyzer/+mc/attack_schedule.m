function [counts,schedule] = attack_schedule(p,total)
%ATTACK_SCHEDULE Actual round boundaries and cumulative-grid request mapping.
% p is a normalized protocol. Original target population is the denominator.
mc.validate_attack_schedule(p);
limit=rounded(p.stop_fraction,total,p.rounding);
schedule=struct();
if strcmp(p.deletion_mode,'fraction_grid')
    requested=p.attack_fractions(:);
    q=rounded(requested,total,p.rounding);
    counts=unique([0;q],'stable');
    [~,ix]=ismember(q,counts);
    actual=NaN(size(q));
    if total>0, actual=q/total; end
    increment=diff([0;q]);
    schedule=struct('requested_fraction',requested,'requested_removed_count',q, ...
        'state_index',ix,'round_index',ix-1,'increment',increment, ...
        'actual_removed_count',q,'actual_removed_fraction',actual, ...
        'fraction_valid',repmat(total>0,size(q)));
else
    counts=(0:p.batch_size:limit)';
    if counts(end)~=limit, counts(end+1,1)=limit; end
end
end
function q=rounded(f,n,mode)
switch mode
    case 'floor', q=floor(f*n);
    case 'ceil', q=ceil(f*n);
    case 'nearest', q=round(f*n);
    otherwise, error('mc:InvalidProtocol','Unknown rounding mode.');
end
q=max(0,min(n,q));
end
