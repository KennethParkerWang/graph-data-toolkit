function r=degree(ctx,p)
%DEGREE Degree; directed total degree is in plus out
if nargin<2,p=struct;end
v=mc.basic_degree(ctx,'total');
r=mc.basic_result('degree',v,'node',ctx,'');
end
