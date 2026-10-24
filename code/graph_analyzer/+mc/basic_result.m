function r=basic_result(id,v,scope,ctx,reason)
%BASIC_RESULT Result with finite-value validity and explicit missing status.
if nargin<5,reason='';end
switch scope
 case 'node', names={'node'}; ids={ctx.node_ids};
 case 'edge', names={'edge'}; ids={ctx.edge_ids};
 otherwise,names={};ids={};
end
mask=isfinite(v);status='ok';
if any(~mask(:)),if any(mask(:)),status='partial';else,status='undefined';end,end

if strcmp(status,'ok'),reason='';end
r=mc.make_result(id,v,scope,names,ids,mask,status,reason);
end

