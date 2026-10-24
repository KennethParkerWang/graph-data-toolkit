function r=node_count(ctx,p)
%NODE_COUNT Number of nodes including isolates
if nargin<2,p=struct;end
r=mc.basic_result('node_count',ctx.n,'graph',ctx,'');
end
