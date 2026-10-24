function r=degree_variance(ctx,p)
%DEGREE_VARIANCE degree variance
if nargin<2,p=struct;end
d=mc.basic_degree(ctx,mc.param(p,'degree_mode','total'));v=mean((d-mean(d)).^2);
r=mc.basic_result('degree_variance',v,'graph',ctx,'Empty population, or zero mean for heterogeneity, is undefined.');
end
