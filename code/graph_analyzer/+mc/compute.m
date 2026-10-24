function results = compute(ctx,selections)
%COMPUTE Explicit selection dispatcher. Isolate per-metric failures.
selections=mc.validate_selection(selections); reg=mc.registry();
results=repmat(mc.make_result('',[],'graph'),numel(selections),1);
for i=1:numel(selections)
    s=selections(i); e=reg(strcmp({reg.metric_id},s.metric_id)); t=tic;
    kind='undirected'; if ctx.directed, kind='directed'; end
    if ~ismember(kind,cellstr(string(e.graph_types)))
        r=mc.make_result(s.metric_id,[],e.scope,{}, {},false(0,0),'not_applicable',['Graph type requires: ',strjoin(cellstr(string(e.graph_types)),', ')]);
    else
        try
            fn=str2func(['mc.metrics.',s.metric_id]); r=fn(ctx,s.parameters);
            if ~isequal(size(r.values),size(r.valid_mask)), error('mc:Result','values/mask size mismatch.'); end
        catch err
            status='failed'; if strcmp(err.identifier,'mc:SizeLimit'), status='not_computed'; end
            r=mc.make_result(s.metric_id,[],e.scope,{}, {},false(0,0),status,[err.identifier,': ',err.message]);
        end
    end
    r.parameters=s.parameters; r.metric_version=e.metric_version; r.method=e.method; r.elapsed_seconds=toc(t);
    results(i)=r;
end
end
