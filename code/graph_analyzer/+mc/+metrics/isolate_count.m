function r=isolate_count(ctx,p)
%ISOLATE_COUNT Number of nodes with no incident edges
if nargin<2,p=struct;end
r=mc.basic_result('isolate_count',sum(mc.basic_degree(ctx,'total')==0),'graph',ctx,'');
end
