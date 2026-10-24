function r=closeness(ctx,p)
%CLOSENESS Reachability-corrected closeness, with explicit incoming/outgoing direction
if nargin<2,p=struct;end
D=mc.distances(ctx,p);direction=validatestring(mc.param(p,'direction','out'),{'out','in'});if strcmp(direction,'in'),D=D';end
n=ctx.n;k=sum(isfinite(D),2)-1;D(~isfinite(D))=0;s=sum(D,2);v=zeros(n,1);ix=k>0;v(ix)=k(ix)./s(ix);wf=mc.param(p,'wf_improved',true);validateattributes(wf,{'logical'},{'scalar'});if wf&&n>1,v=v.*k/(n-1);end
r=mc.basic_result('closeness',v,'node',ctx,'');
end
