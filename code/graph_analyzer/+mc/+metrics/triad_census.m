function r=triad_census(ctx,p)
%TRIAD_CENSUS Induced directed three-node subgraph counts over all 16 isomorphism classes
if nargin<2,p=struct;end
if ~ctx.directed,error('mc:NotApplicable','Triad census requires a directed graph.');end
lim=mc.param(p,'max_nodes',200);validateattributes(lim,{'numeric'},{'scalar','integer','nonnegative','finite'});if ctx.n>lim,error('mc:SizeLimit','Exact triad census is cubic and exceeds max_nodes.');end
names={'003','012','102','021D','021U','021C','111D','111U','030T','030C','201','120D','120U','120C','210','300'};v=zeros(16,1);
for a=1:ctx.n,for b=a+1:ctx.n,for c=b+1:ctx.n
 B=full(ctx.A([a,b,c],[a,b,c]));out=sum(B,2);in=sum(B,1)';e=sum(out);mut=sum(B.*B','all')/2;
 switch e
 case 0,z=1;
 case 1,z=2;
 case 2
  if mut==1,z=3;elseif max(out)==2,z=4;elseif max(in)==2,z=5;else,z=6;end
 case 3
  if mut==1
   third=find(sum(B.*B',2)==0);if out(third)>0,z=7;else,z=8;end
  elseif all(out==1),z=10;else,z=9;end
 case 4
  if mut==2,z=11;else
   third=find(sum(B.*B',2)==0);if out(third)==2,z=12;elseif in(third)==2,z=13;else,z=14;end
  end
 case 5,z=15;
 case 6,z=16;
 end
 v(z)=v(z)+1;
end,end,end
r=mc.make_result('triad_census',v,'distribution',{'triad_type'},{names(:)});
end
