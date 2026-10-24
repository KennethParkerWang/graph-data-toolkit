# 无向图生成器

2.0.0 提供 **11 个无向接口**。全部返回对称稀疏 logical 邻接矩阵及 meta；边数 `M=nnz(A)/2`，平均度 `2M/N`。不删孤立节点，不添加自环，不自动筛选连通图。

```matlab
cd('graph_builder');
setup_generators;
[A, meta] = gen_er_gnm_undirected(100, 300, 1);
```

seed 是最后一个参数，默认1。下面省略 seed；完整定义和例子见[模型手册](../docs/01_使用与接口/图生成模型与参数手册.md)。

| 函数 | 参数 | 范围及核心规则 |
|---|---|---|
| [gen_er_undirected](gen_er_undirected.m) | N, p | N≥1；0≤p≤1；无序节点对独立采样 |
| [gen_er_gnm_undirected](gen_er_gnm_undirected.m) | N, M | N≥1；0≤M≤N(N−1)/2；均匀固定边数 |
| [gen_ba_undirected](gen_ba_undirected.m) | N, m | 1≤m<N；m+1节点星形种子；按度连接；M=m(N−m) |
| [gen_sf_undirected](gen_sf_undirected.m) | N, M, sigma | N≥1；M≤N(N−1)/2；sigma∈[0,1)，默认0.5；按排名权重抽边 |
| [gen_ws_undirected](gen_ws_undirected.m) | N, K, beta | N≥3；1≤K<N/2；beta∈[0,1]；环格重连；M=NK |
| [gen_nw_undirected](gen_nw_undirected.m) | N, K, beta | 范围同WS；保留环格、增加捷径；M随样本变化 |
| [gen_sbm_undirected](gen_sbm_undirected.m) | sizes, P | 正整数分组；P严格对称，元素∈[0,1] |
| [gen_rgg_undirected](gen_rgg_undirected.m) | N, radius, dim | N≥1；radius≥0；dim≥1，默认2；开放单位立方体与欧氏距离 |
| [gen_random_regular_undirected](gen_random_regular_undirected.m) | N, d | 0≤d<N，Nd偶数；stub配对及重启；M=Nd/2 |
| [gen_hk_undirected](gen_hk_undirected.m) | N, m, triad_probability | 1≤m≤N；闭合概率∈[0,1]；m个孤立种子；实际M可能低于m(N−m) |
| [gen_chung_lu_undirected](gen_chung_lu_undirected.m) | w | 有限非负权重；无自环独立边；概率截为min(1,w_i w_j/sum(w)) |

节点数、边数、度数和维度参数为整数，M非负。K 是每侧环格邻居数，不是总度。当前 RGG 没有 periodic 参数，SF 没有 offset 参数，随机正则没有 num_swaps 参数。

BA 从星形图开始；HK 从孤立种子开始，完整保留来源的三角闭合及重复回退行为，重复次数见 `meta.duplicate_fallbacks`。随机正则采用来源配对算法，不是旧版有限换边；来源的渐近均匀条件不能写成有限图完全均匀保证。

以下 5 个入口当前明确拒绝，不返回自行均衡或去方向投影的替代图：

- [gen_eh_undirected](gen_eh_undirected.m)
- [gen_qs_undirected](gen_qs_undirected.m)
- [gen_rt_undirected](gen_rt_undirected.m)、[gen_rr_undirected](gen_rr_undirected.m)、[gen_rh_undirected](gen_rh_undirected.m)

来源：[标准模型协议](../docs/02_模型与来源/标准图模型与来源说明.md)、[作者模型协议](../docs/02_模型与来源/作者图模型与已知边界.md)。保存：[统一图存储规范](../docs/graph_schema_v1.md)、[I/O 函数](../io/README.md)。
