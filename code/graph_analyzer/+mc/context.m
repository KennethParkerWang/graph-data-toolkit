function ctx = context(A,directed,node_ids,edge_list,edge_ids)
%CONTEXT Validate a simple graph in memory; this is not an on-disk schema.
if nargin<2, error('mc:Input','Specify directed explicitly.'); end
if ~(isnumeric(A)||islogical(A)) || ~ismatrix(A) || size(A,1)~=size(A,2) || ~isreal(A)
    error('mc:Input','A must be a real square numeric/logical matrix.');
end
if ~isscalar(directed) || ~ismember(directed,[0,1]), error('mc:Input','directed must be logical scalar.'); end
if any(~isfinite(nonzeros(A))) || any(nonzeros(A)~=1) || any(diag(A)~=0)
    error('mc:Input','Only unweighted simple graphs without self-loops are supported.');
end
n=size(A,1); A=sparse(double(A)); directed=logical(directed);
if ~directed && ~isequal(A,A'), error('mc:Input','Undirected A must be symmetric.'); end
if nargin<3 || isempty(node_ids), node_ids=uint32((1:n)'); end
if numel(node_ids)~=n || numel(unique(node_ids))~=n || any(node_ids(:)<1) || any(node_ids(:)~=fix(node_ids(:))) || any(node_ids(:)>intmax('uint32'))
    error('mc:Input','node_ids must be unique positive uint32-compatible IDs.');
end
if directed, [u,v]=find(A); else, [u,v]=find(triu(A,1)); end
canonical=sortrows([u(:),v(:)],[1,2]); m=size(canonical,1);
if nargin<4, edge_list=canonical; end
if ~isequal(size(edge_list),[m,2]) || ~isequal(sortrows(double(edge_list),[1,2]),canonical)
    error('mc:Input','edge_list must enumerate every edge once in the supplied local node coordinates.');
end
if nargin<5 || isempty(edge_ids), edge_ids=uint64((1:m)'); end
if numel(edge_ids)~=m || numel(unique(edge_ids))~=m || any(edge_ids(:)<1) || any(edge_ids(:)~=fix(edge_ids(:)))
    error('mc:Input','edge_ids must be unique positive integer IDs.');
end
if directed, G=digraph(A); else, G=graph(A); end
ctx=struct('A',A,'directed',directed,'n',n,'m',m,'node_ids',uint32(node_ids(:)), ...
    'edge_list',uint32(edge_list),'edge_ids',uint64(edge_ids(:)),'G',G,'cache',mc.Cache());
end
