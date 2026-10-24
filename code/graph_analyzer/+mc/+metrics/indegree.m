function r=indegree(ctx,p)
%INDEGREE Incoming degree
if nargin<2,p=struct;end
v=mc.basic_degree(ctx,'in');
r=mc.basic_result('indegree',v,'node',ctx,'');
end
