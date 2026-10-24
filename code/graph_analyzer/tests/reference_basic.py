from pathlib import Path
import networkx as nx
import numpy as np
import json
assert nx.__version__=='3.5',nx.__version__
root=Path(__file__).resolve().parents[1]
fixtures=[]
def fixture(name,G):
 n=len(G);A=nx.to_numpy_array(G,nodelist=range(n));directed=G.is_directed();e={};k=np.array([G.degree(i) for i in range(n)],float)
 e.update(node_count=n,edge_count=G.number_of_edges(),isolate_count=sum(k==0),degree=k.tolist())
 if n>1:e['density']=nx.density(G)
 if directed:e.update(indegree=[G.in_degree(i) for i in range(n)],outdegree=[G.out_degree(i) for i in range(n)])
 if n:
  e.update(degree_mean=k.mean(),degree_variance=k.var(),degree_distribution=(np.bincount(k.astype(int),minlength=int(k.max())+1)/n).tolist())
  if k.mean():e['degree_heterogeneity']=np.mean(k*k)/np.mean(k)**2
 cc=list(nx.weakly_connected_components(G) if directed else nx.connected_components(G));sizes=sorted(map(len,cc),reverse=True)
 e.update(component_count=len(cc),largest_component_size=max(sizes,default=0),second_largest_component_size=(sizes+[0,0])[1])
 if n:e['largest_component_fraction']=max(sizes)/n
 e['core_number']=[nx.core_number(G)[i] for i in range(n)]
 if n>1:e.update(node_connectivity=min(nx.node_connectivity(G,s,t) for s in G for t in G if s!=t) if directed else nx.node_connectivity(G),edge_connectivity=nx.edge_connectivity(G))
 D=np.full((n,n),np.inf)
 for s,dist in nx.all_pairs_shortest_path_length(G):
  for t,d in dist.items():D[s,t]=d
 if n>1:
  e['reachable_pair_fraction']=(np.isfinite(D).sum()-n)/(n*(n-1))
  finite=D[~np.eye(n,dtype=bool)]
  if np.isfinite(finite).all():e['average_path_length']=finite.mean()
  e['global_efficiency']=sum(1/d for d in finite if np.isfinite(d))/(n*(n-1))
 if n and np.isfinite(D).all():e.update(eccentricity=D.max(axis=1).tolist(),diameter=D.max(),radius=D.max(axis=1).min(),distance_matrix=D.tolist())
 e['closeness']=list(nx.closeness_centrality(G.reverse(copy=False) if directed else G,wf_improved=True).values())
 H=nx.harmonic_centrality(G.reverse(copy=False) if directed else G);e['harmonic']=[H[i] for i in range(n)]
 bc=nx.betweenness_centrality(G,normalized=False);e['betweenness']=[bc[i] for i in range(n)]
 edges=sorted(G.edges());eb=nx.edge_betweenness_centrality(G,normalized=False);e['edge_betweenness']=[eb[uv] for uv in edges]
 c=nx.clustering(G);e['clustering']=[c[i] for i in range(n)]
 if n:e['average_clustering']=nx.average_clustering(G)
 if not directed:
  tri=nx.triangles(G);e.update(node_triangle_count=[tri[i] for i in range(n)],triangle_count=sum(tri.values())/3)
  if sum(k*(k-1))>0:e['transitivity']=nx.transitivity(G)
  sq=nx.square_clustering(G);e['square_clustering']=[sq[i] for i in range(n)]
  e['local_efficiency']=[nx.global_efficiency(G.subgraph(list(G[i]))) if G.degree(i)>1 else 0 for i in range(n)]
  bridges=set(nx.bridges(G));arts=set(nx.articulation_points(G));e['bridge_mask']=[uv in bridges or uv[::-1] in bridges for uv in edges];e['articulation_mask']=[i in arts for i in range(n)]
 else:
  census=nx.triadic_census(G);e['triad_census']=[census[q] for q in ['003','012','102','021D','021U','021C','111D','111U','030T','030C','201','120D','120U','120C','210','300']]
 if n:
  pr=nx.pagerank(G,alpha=.85,tol=1e-14,max_iter=10000);e['pagerank']=[pr[i] for i in range(n)]
  kat=nx.katz_centrality(G,alpha=.1,beta=1,normalized=True,tol=1e-14,max_iter=10000);e['katz']=[kat[i] for i in range(n)]
  if G.number_of_edges() and (nx.is_strongly_connected(G) if directed else nx.is_connected(G)):
   ev=nx.eigenvector_centrality(G,max_iter=10000,tol=1e-14);e['eigenvector']=[ev[i] for i in range(n)]
 fixtures.append(dict(name=name,n=n,directed=directed,edges=[list(x) for x in edges],expected=e))
for name,G in [('empty0',nx.empty_graph(0)),('singleton',nx.empty_graph(1)),('isolates5',nx.empty_graph(5)),('path4',nx.path_graph(4)),('cycle4',nx.cycle_graph(4)),('star5',nx.star_graph(4)),('complete4',nx.complete_graph(4)),('multi',nx.disjoint_union_all([nx.path_graph(2),nx.cycle_graph(3),nx.empty_graph(1)])),('directedpath4',nx.DiGraph([(0,1),(1,2),(2,3)])),('directedcycle3',nx.DiGraph([(0,1),(1,2),(2,0)])),('directedmix6',nx.DiGraph([(0,1),(1,0),(0,2),(2,3),(3,4),(4,2),(4,5),(5,1)]))]:fixture(name,G)
# Every six-bit directed three-node adjacency pattern, checked by independent nx census.
triads=[]
for bits in range(64):
 G=nx.DiGraph();G.add_nodes_from(range(3));pairs=[(0,1),(1,0),(0,2),(2,0),(1,2),(2,1)];G.add_edges_from(e for b,e in enumerate(pairs) if bits&(1<<b));triads.append(nx.triad_type(G))
payload=dict(reference='NetworkX 3.5; NumPy '+np.__version__,fixtures=fixtures,triad_types_64=triads)
out=root/'validation'/'basic_reference.json';out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps(payload,indent=2,default=lambda x:x.item()),encoding='utf-8')
print('Wrote',len(fixtures),'graph fixtures and 64 exhaustive triads to',out)
