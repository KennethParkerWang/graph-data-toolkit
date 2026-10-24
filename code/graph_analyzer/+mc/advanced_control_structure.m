function s = advanced_control_structure(ctx)
%ADVANCED_CONTROL_STRUCTURE Directed matching and source SCC information.
key='advanced_control_structure';
if isfield(ctx.cache.data,key), s=ctx.cache.data.(key); return; end
[left,right,count]=mc.maximum_matching(ctx.A);
if ctx.n==0
    component=zeros(0,1); sources=zeros(0,1); representatives=zeros(0,1);
else
    component=conncomp(ctx.G,'Type','strong').';
    incoming=false(max(component),1);
    [u,v]=find(ctx.A); cross=component(u)~=component(v);
    incoming(component(v(cross)))=true; sources=find(~incoming);
    representatives=zeros(numel(sources),1);
    for k=1:numel(sources)
        candidates=find(component==sources(k));
        [~,first]=min(ctx.node_ids(candidates)); representatives(k)=candidates(first);
    end
end
s=struct('left_match',left,'right_match',right,'matching_size',count,...
    'unmatched',find(right==0),'component',component,...
    'source_components',sources,'representatives',representatives);
ctx.cache.data.(key)=s;
end
