function report = benchmark_metrics()
%BENCHMARK_METRICS Small deterministic timing only; no production graph reads.
root=setup_metrics(); sizes=[20 100]; names={'path','cycle','star','directed_cycle'};
selected={'node_count','degree','component_count','global_efficiency','clustering','betweenness','pagerank','adjacency_spectral_radius'};
rows=struct([]);
for n=sizes
    for f=1:numel(names)
        switch names{f}
            case 'path', u=1:n-1;v=2:n;directed=false;
            case 'cycle', u=1:n;v=[2:n 1];directed=false;
            case 'star', u=ones(1,n-1);v=2:n;directed=false;
            case 'directed_cycle',u=1:n;v=[2:n 1];directed=true;
        end
        A=sparse(u,v,1,n,n); if ~directed,A=A+A';end
        ctx=mc.context(A,directed); t=tic; results=mc.compute(ctx,selected); total=toc(t);
        for i=1:numel(results)
            r=struct('family',names{f},'n',n,'m',ctx.m,'metric_id',results(i).metric_id,'status',results(i).status,'seconds',results(i).elapsed_seconds,'selection_total_seconds',total);
            if isempty(rows),rows=r;else,rows(end+1)=r;end %#ok<AGROW>
        end
    end
end
report=struct('matlab_version',version,'sizes',sizes,'metric_count',numel(selected),'graph_count',numel(sizes)*numel(names),'observations',rows, ...
    'note','Single small run per family/size; cached shared computations inside a selection, includes interpreter/dispatch overhead; not a production throughput estimate.');
mc.write_text_atomic(fullfile(root,'validation','small_benchmark.json'),jsonencode(report,'PrettyPrint',true),true);
end
