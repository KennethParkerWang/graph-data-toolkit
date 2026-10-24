function r=outdegree(ctx,p)
%OUTDEGREE Outgoing degree
if nargin<2,p=struct;end
v=mc.basic_degree(ctx,'out');
r=mc.basic_result('outdegree',v,'node',ctx,'');
end
