function r=degree_heterogeneity(ctx,p)
%DEGREE_HETEROGENEITY degree heterogeneity
if nargin<2,p=struct;end
d=mc.basic_degree(ctx,mc.param(p,'degree_mode','total'));v=mean(d.^2)/mean(d)^2;
r=mc.basic_result('degree_heterogeneity',v,'graph',ctx,'Empty population, or zero mean for heterogeneity, is undefined.');
end
