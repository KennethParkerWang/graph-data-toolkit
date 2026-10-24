function r = rich_club(ctx,p)
%RICH_CLUB Unnormalized density among nodes of degree strictly greater than k.
if nargin<2, p=struct(); end
if ctx.directed
    r=mc.make_result('rich_club',[],'distribution',{}, {},[],'not_applicable','Undirected graphs only.'); return
end
d=full(sum(ctx.A,2)); k=mc.param(p,'thresholds',[]);
if isempty(k)
    if ctx.n==0, k=zeros(0,1); else, k=(0:max(d)).'; end
else
    validateattributes(k,{'numeric'},{'vector','real','finite','integer','nonnegative'}); k=k(:);
    if numel(unique(k))~=numel(k), error('mc:InvalidParameter','thresholds must be unique.'); end
end
values=nan(numel(k),1); counts=zeros(numel(k),1); edges=zeros(numel(k),1);
for i=1:numel(k)
    chosen=d>k(i); counts(i)=sum(chosen); edges(i)=nnz(ctx.A(chosen,chosen))/2;
    if counts(i)>1, values(i)=2*edges(i)/(counts(i)*(counts(i)-1)); end
end
valid=isfinite(values); status='ok'; reason='';
if any(~valid), status='partial'; reason='Thresholds with fewer than two nodes are undefined.'; end
if ~isempty(k) && ~any(valid), status='undefined'; end
r=mc.make_result('rich_club',values,'distribution',{'degree_threshold'},{k},valid,status,reason);
r.details=struct('node_counts',counts,'edge_counts',edges,'normalized_against_reference',false);
end
