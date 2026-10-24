function r=square_clustering(ctx,p)
%SQUARE_CLUSTERING Square clustering using the Zhang union-neighborhood denominator
if nargin<2,p=struct;end
if ctx.directed,error('mc:NotApplicable','Square clustering uses an undirected definition.');end
k=mc.basic_degree(ctx,'total');v=zeros(ctx.n,1);
for i=1:ctx.n
 nb=find(ctx.A(i,:));num=0;den=0;
 for a=1:numel(nb),for b=a+1:numel(nb)
  u=nb(a);w=nb(b);q=full(ctx.A(u,:)*ctx.A(:,w))-1;theta=full(ctx.A(u,w));
  num=num+q;den=den+k(u)+k(w)-2-2*theta-q;
 end,end
 if den>0,v(i)=num/den;end
end
r=mc.basic_result('square_clustering',v,'node',ctx,'');
end
