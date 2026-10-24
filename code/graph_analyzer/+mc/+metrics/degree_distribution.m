function r=degree_distribution(ctx,p)
%DEGREE_DISTRIBUTION Empirical degree probability mass, including zero-degree bin
if nargin<2,p=struct;end
d=mc.basic_degree(ctx,mc.param(p,'degree_mode','total'));
if isempty(d),v=zeros(0,1);k=zeros(0,1);else,k=(0:max(d))';v=accumarray(d+1,1,[numel(k),1])/ctx.n;end
r=mc.make_result('degree_distribution',v,'distribution',{'degree'},{k});if ctx.n==0,r.status='undefined';r.reason='No nodes to define an empirical distribution.';end
end
