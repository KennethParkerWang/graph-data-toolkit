# 有向图生成器

2.0.0 提供 **9 个有向接口**。输出 `A(i,j)=1` 表示 `i→j`，弧数 `M=nnz(A)`；平均入/出度各为 `M/N`，`meta.mean_degree` 是平均总度 `2M/N`。全部返回稀疏 logical 矩阵，保留孤立节点。

```matlab
cd('graph_builder');
setup_generators;
[A, meta] = gen_er_gnm_directed(100, 300, 1);
```

seed 是最后一个参数，默认1。下面的参数表省略 seed；输入顺序与函数定义一致。完整说明、示例和设参公式见[模型手册](../docs/01_使用与接口/图生成模型与参数手册.md)。

| 函数 | 参数 | 范围及核心规则 |
|---|---|---|
| [gen_er_directed](gen_er_directed.m) | N, p | N≥1；0≤p≤1；有序节点对独立采样 |
| [gen_er_gnm_directed](gen_er_gnm_directed.m) | N, M | N≥1；0≤M≤N(N−1)；均匀固定弧数 |
| [gen_sf_directed](gen_sf_directed.m) | N, M, sigma_out, sigma_in | N≥1；M≤N(N−1)；两个指数∈[0,1)，默认0.5；原生出入权重抽弧 |
| [gen_eh_directed](gen_eh_directed.m) | N, M | N≥1；M≤N(N−1)；作者 ER 后接入/出度分别整流 |
| [gen_qs_directed](gen_qs_directed.m) | N, r, q | N≥2；1≤r<N；0≤q≤1；单 r 层链回连 |
| [gen_rt_directed](gen_rt_directed.m) | N, M | N≥3；M≤N(N−1)/2；作者三角形增长 |
| [gen_rr_directed](gen_rr_directed.m) | N, M | N≥5；M≤N(N−1)/2；作者矩形增长和尾部处理 |
| [gen_rh_directed](gen_rh_directed.m) | N, M | N≥7；M≤N(N−1)/2；作者六边形增长和尾部处理 |
| [gen_sbm_directed](gen_sbm_directed.m) | sizes, P | 正整数分组；P元素∈[0,1]且可不对称；分组间独立弧 |

N、M、r 及分组规模为整数，M非负。ER、SF、EH、SBM 允许互惠弧；QS 的 r=1 可以产生互惠弧。RT/RR/RH 成功输出不含互惠弧；没有旧版节点数同余限制。

EH、RT/RR/RH 保留作者抽样过程。作者原版部分种子会报错或返回不符合本项目简单图约束的结果，当前明确失败，不修补或替换种子；参见[原版对照与失败样例](../docs/02_模型与来源/作者图模型与已知边界.md)。QS 保留有向链，因此保证弱连通；其他模型不要默认强连通或弱连通。

以下 7 个入口当前明确拒绝，不生成随机定向替代图：

- [gen_ba_directed](gen_ba_directed.m)
- [gen_ws_directed](gen_ws_directed.m)、[gen_nw_directed](gen_nw_directed.m)
- [gen_rgg_directed](gen_rgg_directed.m)
- [gen_random_regular_directed](gen_random_regular_directed.m)
- [gen_hk_directed](gen_hk_directed.m)
- [gen_chung_lu_directed](gen_chung_lu_directed.m)

来源：[标准模型协议](../docs/02_模型与来源/标准图模型与来源说明.md)、[作者模型协议](../docs/02_模型与来源/作者图模型与已知边界.md)。保存：[统一图存储规范](../docs/graph_schema_v1.md)、[I/O 函数](../io/README.md)。
