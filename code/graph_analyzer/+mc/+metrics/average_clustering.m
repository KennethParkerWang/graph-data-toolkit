function r=average_clustering(ctx,p)
%AVERAGE_CLUSTERING Arithmetic mean of all local clustering values, including degree <2 zeros
if nargin<2,p=struct;end
q=mc.metrics.clustering(ctx,p);r=mc.basic_result('average_clustering',mean(q.values),'graph',ctx,'Mean of no nodes is undefined.');
end
