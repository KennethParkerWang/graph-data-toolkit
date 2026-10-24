function r = reciprocity(ctx,~)
%RECIPROCITY Fraction of directed arcs whose reverse arc exists.
if ~ctx.directed
    r=mc.make_result('reciprocity',[],'graph',{}, {},[],'not_applicable','Directed graphs only.'); return
end
if ctx.m==0
    r=mc.make_result('reciprocity',NaN,'graph',{}, {},false,'undefined','No arcs.'); return
end
r=mc.make_result('reciprocity',nnz(ctx.A.*ctx.A.')/ctx.m,'graph',{});
end
