function [left_match,right_match,cardinality] = maximum_matching(B)
%MAXIMUM_MATCHING Exact bipartite matching by BFS augmenting paths.
% B(i,j) means left i can match right j. Rectangular B is supported.
% Independent implementation of the augmenting-path theorem; O(V*E).
B=sparse(logical(B)); [nl,nr]=size(B);
left_match=zeros(nl,1); right_match=zeros(nr,1); cardinality=0;
neighbors=cell(nl,1);
for u=1:nl, neighbors{u}=find(B(u,:)); end
for start=1:nl
    parent_right=zeros(nr,1); seen_left=false(nl,1);
    queue=zeros(nl,1); queue(1)=start; seen_left(start)=true;
    head=1; tail=1; finish=0;
    while head<=tail && finish==0
        u=queue(head); head=head+1;
        for v=neighbors{u}
            if parent_right(v)~=0, continue; end
            parent_right(v)=u;
            if right_match(v)==0
                finish=v; break
            end
            next=right_match(v);
            if ~seen_left(next)
                tail=tail+1; queue(tail)=next; seen_left(next)=true;
            end
        end
    end
    if finish~=0
        v=finish;
        while v~=0
            u=parent_right(v); previous=left_match(u);
            left_match(u)=v; right_match(v)=u; v=previous;
        end
        cardinality=cardinality+1;
    end
end
end
