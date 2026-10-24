function r = deletion_impact(ctx,p)
%DELETION_IMPACT Exact one-object marginal change of an explicit graph metric.
% delta_i = baseline - f(G without i); optional division by baseline.
if nargin<2, p=struct(); end
base=mc.param(p,'base_metric',[]); target=mc.param(p,'target','node'); relative=mc.param(p,'relative',false);
max_objects=mc.param(p,'max_objects',200);
if ~ismember(target,{'node','edge'}), error('mc:Config','target must be node or edge.'); end
validateattributes(relative,{'logical'},{'scalar'}); validateattributes(max_objects,{'numeric'},{'scalar','integer','nonnegative','finite'});
base=mc.validate_selection(base);
if numel(base)~=1||strcmp(base.metric_id,'deletion_impact'), error('mc:Config','Select one nonrecursive base metric.'); end
if strcmp(base.metric_id,'exact_numeric_driver_count'), error('mc:StateMatrixPolicyRequired','Fixed numerical state matrices need an explicit deletion/update rule; this generic impact function cannot infer it.'); end
reg=mc.registry(); e=reg(strcmp({reg.metric_id},base.metric_id));
if ~strcmp(e.scope,'graph')||strcmp(e.category,'robustness'), error('mc:Config','base_metric must be a scalar static graph metric.'); end
if strcmp(target,'node'), ids=ctx.node_ids; else, ids=ctx.edge_ids; end
if numel(ids)>max_objects, error('mc:SizeLimit','Exact deletion impact exceeds max_objects.'); end
b=mc.compute(ctx,base);
if ~isscalar(b.values)||~isscalar(b.valid_mask)||~b.valid_mask||~isfinite(b.values)
    r=mc.make_result('deletion_impact',[],target,{}, {},[],'undefined','Base metric must be a valid finite scalar.'); return
end
values=nan(numel(ids),1); residual=values; reasons=cell(numel(ids),1);
for i=1:numel(ids)
    keep_nodes=true(ctx.n,1); keep_edges=true(ctx.m,1);
    if strcmp(target,'node')
        keep_nodes(i)=false; keep_edges=all(ctx.edge_list~=i,2);
    else, keep_edges(i)=false;
    end
    mapping=zeros(ctx.n,1); mapping(keep_nodes)=1:nnz(keep_nodes);
    el=mapping(double(ctx.edge_list(keep_edges,:))); el=reshape(el,[],2);
    A=sparse(double(el(:,1)),double(el(:,2)),1,nnz(keep_nodes),nnz(keep_nodes)); if ~ctx.directed, A=A+A'; end
    c=mc.context(A,ctx.directed,ctx.node_ids(keep_nodes),el,ctx.edge_ids(keep_edges)); x=mc.compute(c,base);
    if isscalar(x.values)&&x.valid_mask&&isfinite(x.values), residual(i)=x.values; values(i)=b.values-x.values;
    else, reasons{i}=[x.status,': ',x.reason]; end
end
if relative
    if b.values==0, values(:)=NaN; reasons(:)={'Relative impact undefined for zero baseline.'};
    else, values=values/b.values; end
end
r=mc.make_result('deletion_impact',values,target,{[target,'_id']},{ids});
r.details=struct('baseline',b.values,'remaining_values',residual,'per_object_reason',{reasons}, ...
    'difference','baseline minus remaining metric','relative',relative,'base_definition',base);
end
