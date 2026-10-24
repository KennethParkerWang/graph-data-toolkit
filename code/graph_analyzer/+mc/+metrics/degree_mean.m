function r=degree_mean(ctx,p)
%DEGREE_MEAN degree mean
if nargin<2,p=struct;end
d=mc.basic_degree(ctx,mc.param(p,'degree_mode','total'));v=mean(d);
r=mc.basic_result('degree_mean',v,'graph',ctx,'Empty population, or zero mean for heterogeneity, is undefined.');
end
