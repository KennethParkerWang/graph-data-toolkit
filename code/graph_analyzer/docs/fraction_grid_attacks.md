# 累计比例网格驱动的批量攻击

协议版本：`1.1.0`；文档核对日期：2026-09-28。

`deletion_mode='fraction_grid'` 用累计攻击比例决定每一批**实际删除多少对象**。`sample_fractions` 仍然只从已经产生的轨迹取样，两者职责不同。此协议定义由项目显式制定，保留原始节点／边 ID，不规定新的图存储格式。

## 1. 数学定义与舍入

令 `T0` 为原始攻击目标数量：删点取原始节点数 `N0`，删边取原始边数 `M0`。给定非递减累计比例

\[
0\le p_1\le\cdots\le p_J=p_{\mathrm{stop}}\le1,
\]

使用同一舍入规则得到

\[
q_j=\rho(p_jT_0),\qquad q_0=0,\qquad\Delta q_j=q_j-q_{j-1}.
\]

`rho` 为 `floor`、`ceil` 或 `nearest`；`nearest` 使用 MATLAB `round`，半整数远离零。代码按浮点乘积直接舍入，不加隐含容差或修正。`p_j` 是**相对于原始总体的累计比例**；不是每轮剩余对象的百分比，也不是各对象独立失效的 Bernoulli 概率。

执行状态的边界为 `unique([0;q_1;...;q_J],'stable')`。每个正增量执行一次删除，零增量不删除、不重算指标、不增加攻击轮数。完整的原请求仍保存在 `schedule` 中，所以重复比例和不同请求舍入到同一整数的情况都能追溯。

固定整数 `batch_size` 不能一般替代这个定义。例如 `T0=7`、`floor`、累计比例 `[.2 .4 .6 1]` 对应累计删除数 `[1 2 4 7]` 和批量 `[1 1 2 3]`，不能简单重复 `floor(.2*7)` 得到同一过程。

## 2. 配置要求

| 字段 | 约束／语义 |
|---|---|
| `version` | 必须显式指定 `'1.1.0'` |
| `deletion_mode` | `'fraction_grid'` |
| `attack_fractions` | 非空、实数、有限向量，位于 `[0,stop_fraction]`，非递减；最后一个值必须严格等于 `stop_fraction` |
| `stop_fraction` | `[0,1]` 内标量，默认 `1`；不会自动补入网格末端 |
| `batch_size` | 此模式不使用固定批量，必须保留 `1`；其他值被拒绝 |
| `rounding` | `'floor'`（默认）、`'ceil'`、`'nearest'` |
| `target` | `'node'` 或 `'edge'`；原始目标数量是全程固定分母 |
| `strategy` | 继续使用 `'external'`、`'random'`、`'ranked'`、`'source_order'` |
| `sample_fractions` | 独立的取样请求，不改变攻击顺序、批量或重排时机 |
| `sample_policy` | `'exact'`、`'previous'`、`'next'`；不插值 |

网格可以不含零，因为初始状态总会记录。网格可以只含 `stop_fraction`，此时最多只有一批。`stop_fraction=0` 时允许 `[0]` 或多个零，只记录初始状态。尾元素的精确相等要求意味着调用方应复用同一个停止值，而非分别计算两个可能存在浮点差异的表达式。

## 3. 可执行小图示例

```matlab
addpath('graph_analyzer');
ctx = mc.context(sparse(1:7,2:8,1,8,8),true); % 8 nodes, 7 directed edges
protocol = struct('version','1.1.0', ...
    'target','edge','strategy','external', ...
    'external_sequence',1:7, ...
    'deletion_mode','fraction_grid', ...
    'attack_fractions',[0 .1 .2 .3 .4 1], ...
    'sample_fractions',[0 .1 .2 .3 .4 .5 1], ...
    'rounding','floor','sample_policy','exact');
trajectory = mc.attack(ctx,protocol,{'node_count','edge_count'});
```

对应映射如下，`state_index` 是 MATLAB 一基索引：

| 请求比例 | 请求累计删除数 | 相邻请求增量 | 实际累计比例 | `state_index` | `round_index` |
|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 0 | 1 | 0 |
| 0.1 | 0 | 0 | 0 | 1 | 0 |
| 0.2 | 1 | 1 | 1/7 | 2 | 1 |
| 0.3 | 2 | 1 | 2/7 | 3 | 2 |
| 0.4 | 2 | 0 | 2/7 | 3 | 2 |
| 1 | 7 | 5 | 1 | 4 | 3 |

实际状态删除数为 `[0 1 2 7]`。`sample_fractions=.5` 请求累计删除 `floor(.5*7)=3`，没有对应状态，因而 `exact` 取样返回 `not_computed`、`state_index=0`。改为 `previous` 会选择删除数 2，改为 `next` 会选择删除数 7，输出仍报告各自真实位置。

## 4. 排序、随机性和轮数

同一批中的全部对象使用**删批前的同一排序**，批内不重排。自适应排序在实际完成 `recompute_interval` 个正增量删除轮之后、下一批删除之前重新计算。重复网格请求和舍入造成的零增量不消耗这个间隔。

例如，实际状态累计删除数为 `[0 1 3 5]`：

- 自适应 `recompute_interval=1` 在累计删除数 `0,1,3` 排序。
- 自适应 `recompute_interval=2` 在累计删除数 `0,3` 排序。
- 把一个大小为 2 的批次拆成两个大小为 1 的批次可能改变后续选中的对象；协议身份因此必须包含整个网格和重排设置。

随机攻击沿用本地 `RandStream('mt19937ar')` 和一次无放回随机排列。随机攻击或随机同分必须提供 `[0,2^32-1]` 内整数种子；相同种子复现同一路径，仅改变 `repeat_index` 不会产生独立随机路径。全局 MATLAB RNG 不被改动。

外部序列提供原始 ID，长度至少覆盖停止删除数。删点时，连带消失的边单独记录，`removed_count` 只计被攻击的节点。删边始终保留所有节点，包括孤立节点。源文件边顺序策略依赖图读入提供并验证的 `source_edge_order_ids`，不会用规范存储顺序替代。

## 5. 结果字段、身份与兼容性

`version='1.1.0'` 生成 `schema_version='attack-1.1.0'`，并保存 `schedule`。比例网格模式中的各向量长度均为原请求数：

- `requested_fraction`、`requested_removed_count`：原请求及其舍入后的累计删除数。
- `increment`：相邻请求的整数增量，重复请求对应零；它不是每个已观察状态的独立列表。
- `state_index`、`round_index`：对应实际状态和实际删除轮数。
- `actual_removed_count`、`actual_removed_fraction`、`fraction_valid`：实际位置及其有效性。

`states` 只含初始状态和不同的实际删除边界；`sampled` 继续独立记录所有取样请求。完整单对象轨迹标记由实际状态是否恰好为 `0:T0` 决定。比例网格只有覆盖所有整数计数时，才能用于要求完整离散求和的鲁棒性指标；粗网格应显式选择 `sampled_curve_auc` 等观察曲线统计。

当 `T0=0`，所有请求累计删除数为零，所有请求指向初始状态；实际比例为 `NaN`，`fraction_valid=false`。不能因为没有可删对象而把比例写成 0 或 1。

版本 `1.0.0` 的默认字段和规范化协议保持原样，不能接受 `attack_fractions` 或 `fraction_grid`。因此原协议 ID 不因新增字段而被悄悄重算。`1.1.0` 的协议身份包含完整网格；种子和重复编号继续保存在各运行身份中。旧结果是否可读由结果验证器和旧样例回读测试验证，而不是通过覆盖旧文件实现。

## 6. 来源、许可与验证

比例网格是项目协议定义 `1.1.0`，于 2026-09-28 固定本页语义，没有把它归因于某篇论文。实现由项目独立编写，未复制外部攻击代码；`round`、`RandStream` 等 MATLAB 内建函数使用本机安装许可。MATLAB 参考入口为 `https://www.mathworks.com/help/matlab/ref/round.html` 和 `https://www.mathworks.com/help/matlab/ref/randstream.html`；本库运行环境为 R2024b。

实现入口为 `graph_analyzer/+mc/validate_protocol.m`、`attack_schedule.m`、`attack.m` 和 `validate_attack_result.m`。测试入口为 `graph_analyzer/tests/test_fraction_grid.m`，应覆盖三种舍入、请求碰撞、零攻击、空目标、提前停止、单次全删、自适应重排、随机种子、取样独立性、原始 ID、旧结果回读和 `schedule` 篡改拒绝。

本文没有宣称本轮测试数量或结果；以验证报告为准。任务 1 已发布 `graph-v1` 图存储规范，见 `graph_builder/docs/graph_schema_v1.md`。`mc.read_graph` 读取其已发布的图 manifest，并调用官方读取器执行校验和与科学字段／身份一致性验证，保留原始节点／边 ID 及存在的来源边顺序映射；本攻击协议继续消费读入后的 `mc.context`。

当前读入联调只使用 `graph_analyzer/validation/` 内的任务 1 手工交接样例副本，不代表任务 3 完整训练集成。攻击范围不含剩余总体百分比攻击、Bernoulli 失效、混合删点删边、恢复、级联或相依网络协议，也不启动正式大批计算。
