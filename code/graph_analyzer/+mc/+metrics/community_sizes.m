function r = community_sizes(ctx,p)
%COMMUNITY_SIZES Counts for a supplied partition in increasing label order.
if nargin<2, p=struct(); end
[labels,ids]=mc.advanced_partition(ctx,p); values=zeros(numel(ids),1);
for i=1:numel(ids), values(i)=sum(labels==ids(i)); end
r=mc.make_result('community_sizes',values,'distribution',{'community_label'},{ids});
end
