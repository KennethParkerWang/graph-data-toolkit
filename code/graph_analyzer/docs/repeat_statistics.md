# 随机攻击重复的派生统计

派生结果模式：`repeat-summary-1.0.0`；定义核对日期：2026-09-28。

`mc.aggregate_repeats` 从**已经保存且校验通过**的随机攻击运行提取同一定义、同一实际观察位置的数值，计算逐位置均值、样本标准差和分位数，可选 Student-t 均值置信区间。每个原始运行继续保留，聚合结果单独保存；聚合函数不会生成新攻击、重新采样、合并不同图或插值缺失位置。

## 1. API 分层与输入边界

```matlab
aggregate = mc.aggregate_repeats(root,records,selection,options);
[record,resumed] = mc.save_repeat_summary(root,aggregate);
```

`root` 是已有结果目录；`records` 是 `mc.save_run` 返回的 manifest 记录结构数组。调用方先按研究问题选择记录，不把未知 MAT 文件路径直接作为合格重复输入。

每个记录先经 `mc.verify_record` 核对文件大小、SHA-256、MAT 内容与运行身份。组合规则如下：

| 必须一致 | 必须区分／其他约束 |
|---|---|
| `graph_id`、`topology_hash`、`origin_graph_id` | `run_id` 必须唯一 |
| `metric_set_id`、`protocol_id`、运行实现摘要 | 攻击种子必须唯一 |
| 原始 `input_context_identity` | 输入必须是显式使用 `mt19937ar` 的随机攻击或随机同分运行 |
| 源指标 ID、规范化参数、指标版本 | 确定性运行不能作为随机重复输入 |
| 实际观察轴及请求映射 | 输入先按 `run_id` 排序，使列顺序与身份可重现 |

同一图拓扑但不同原始 ID 映射、不同弱／强分量含义、不同攻击网格、不同指标实现，都不会被静默合并。不同种子是避免同路径复用的必要检查，**不是随机样本独立性的数学证明**。调用者仍需确认种子生成和实验设计合理；也不应为了增加重复次数而把同一运行换名。

### 支持的三个来源

| `options.source` | 观察对象 | 对齐要求 |
|---|---|---|
| `'states'`（默认） | 每个实际攻击状态的图级标量 | 删除数、实际删除比例、状态索引一致 |
| `'sampled'` | 独立取样表中的图级标量 | 还要求请求比例、请求删除数和对应状态索引完全一致 |
| `'summaries'` | 每次运行已保存的单个图级标量汇总 | 同一汇总定义，无攻击横轴 |

只支持图级标量。节点／边向量、矩阵和整条 `scope='trajectory'` 汇总不能被假装成同一标量。`selection` 可为无歧义的名称，或精确的 `struct('metric_id',...,'parameters',...)`；可另加 `metric_version`。同名指标的弱／强参数必须明确选择。

对 `sampled` 中舍入后重合的不同请求，本接口保留每一请求行。它们是同一重复内的不同观察标签，不是额外的独立重复。重复次数始终等于输入运行数。

## 2. 有效样本与缺失策略

设数据矩阵 `Y` 的行为匹配观察位置，列为重复运行。源观测必须是有限标量、`valid_mask=true`，且指标状态为 `ok` 或 `partial`，才进入该位置的统计。`failed`、`not_computed`、`undefined`、`not_applicable` 及无效掩码都保留为无效观测。数学上可成立的无穷值也不进入这里的有限均值统计。

| `missing_policy` | 行内存在不可用重复时的行为 |
|---|---|
| `'propagate'`（默认） | 该行全部统计无效，`count_used=0`；`count_valid` 仍报告实际有效数量 |
| `'available_case'` | 仅使用该行有效重复，`count_used=count_valid`；不补零、不从邻点插值 |

`count_valid` 与 `count_used` 必须伴随统计展示，尤其是不同位置的有效重复数不同时。`available_case` 可能因失败或失效事件具有选择性而产生偏差；它不自动解决缺失机制问题。一次运行整体为 `partial` 不会被整列删除：每个所选指标的有效性仍独立判断。

## 3. 统计定义

以下 `n` 是某行按照缺失策略实际使用的重复数。

### 均值与样本标准差

\[
\bar y=\frac{1}{n}\sum_{i=1}^{n}y_i,\qquad
s=\sqrt{\frac{1}{n-1}\sum_{i=1}^{n}(y_i-\bar y)^2}.
\]

均值需要 `n>=1`；标准差使用 `n-1` 分母，需要 `n>=2`。只有一个有效重复时，标准差保持 `NaN` 且掩码为假，不输出人为的零。实现分别使用 MATLAB `mean` 与 `std(x,0)`。

### 分位数：Hyndman–Fan type 7

令排序后的样本为 `y_(1)<=...<=y_(n)`。对请求概率 `p∈[0,1]`，

\[
h=1+(n-1)p,\quad j=\lfloor h\rfloor,\quad k=\lceil h\rceil,
\qquad Q(p)=y_{(j)}+(h-j)[y_{(k)}-y_{(j)}].
\]

因此 `Q(0)` 是最小值、`Q(1)` 是最大值；`n=1` 时所有分位数等于该唯一数值。概率必须是非空、严格递增且位于 `[0,1]` 的有限实数向量。默认 `[.025 .5 .975]`。明确固定 type 7，避免不同软件默认分位数定义造成偏差。数值实现采用凸组合，并限制在相邻样本端点之间，避免异号极大值作差溢出；`[-realmax,realmax]` 的中位数保持为零。

### 可选的逐位置均值置信区间

`confidence_method='none'` 为默认值，保留无效的 CI 字段，不自动画置信带。显式选择 `'student_t'` 后，对于 `n>=2` 和置信水平 `c∈(0,1)`，

\[
CI_c=\bar y\pm t_{(1+c)/2,n-1}\frac{s}{\sqrt n}.
\]

实现通过 MATLAB 基础函数 `betaincinv` 取得临界值，不依赖 Statistics and Machine Learning Toolbox：

\[
\nu=n-1,\quad b=I^{-1}_{1-c}(\nu/2,1/2),\quad
t=\sqrt{\nu(1/b-1)}.
\]

默认置信水平为 `0.95`。`n<2` 时 CI 不可用。`n>=2` 且样本方差为零时，区间退化为样本均值；这不证明所有可能随机路径都相同。区间不截断到 `[0,1]` 或其他指标边界，以免悄悄改变统计方法。数值溢出或非有限结果由各自有效掩码显式标记。

Student-t 区间在独立、同分布正态样本条件下具有通常的精确覆盖解释；对一般攻击结果分布，适用性需要评估，尤其是少量重复、离散或偏态分布。每个攻击位置分别计算的区间是 **pointwise mean CI**，不是整条曲线的同时置信带。不同位置通常在同一路径内相关，本实现不对它们作独立性假设或同时覆盖保证。

分位数带描述所观察随机路径数值的分布；均值 CI 描述均值估计的不确定性。两者必须使用不同标签，不能把 2.5%–97.5% 分位区间标作“95% 均值置信区间”。

## 4. 调用示例

### 已保存随机运行的统计

下面假定 `root` 和 `records` 已由调用者选择，并指向同一图和同一协议的已保存随机重复；本示例不创建正式数据或伪造原始图身份。

```matlab
selection = struct('metric_id','largest_component_size', ...
    'parameters',struct('component_mode','weak'));
options = struct('source','states', ...
    'missing_policy','propagate', ...
    'quantile_probabilities',[.025 .5 .975], ...
    'confidence_method','student_t','confidence_level',.95);
aggregate = mc.aggregate_repeats(root,records,selection,options);
[summary_record,resumed] = mc.save_repeat_summary(root,aggregate);
```

若输入是每次运行保存的完整路径鲁棒性标量，使用精确参数选择器，并把 `source` 改为 `'summaries'`：

```matlab
selection = struct('metric_id','connectivity_robustness', ...
    'parameters',struct('component_mode','strong'));
options.source = 'summaries';
aggregate = mc.aggregate_repeats(root,records,selection,options);
```

### 独立数值核心的小测试

`mc.repeat_statistics` 可直接验证统计公式，但它不具备已保存记录的身份、校验和与种子审核功能，不能替代上层聚合入口的可追溯性。

```matlab
values = [1 2 3; 4 NaN 8];
valid = logical([1 1 1; 1 0 1]);
options = struct('missing_policy','available_case', ...
    'quantile_probabilities',[0 .25 .5 .75 1], ...
    'confidence_method','student_t','confidence_level',.95);
stats = mc.repeat_statistics(values,valid,options);
% mean = [2;6]; count_valid = count_used = [3;2].
% sample_std = [1;sqrt(8)].
% quantiles row 1 = [1 1.5 2 2.5 3]; row 2 = [4 5 6 7 8].
```

## 5. 输出、保存与身份

`aggregate.statistics` 包括：`raw_values`、`raw_valid_mask`、`number_repeats`、`count_valid`、`count_used`、`mean`、`sample_std`、`quantiles`、`ci_lower`、`ci_upper`、`degrees_of_freedom`，以及各统计对应的有效掩码和完整选项。

`aggregate.inputs` 保留各输入的运行 ID、路径、SHA-256、文件大小、种子、重复编号及运行状态。`observation_status` 保存每个位置每次重复的源指标状态；`axes` 保存匹配位置。聚合身份包含输入来源、源指标定义、统计选项和统计实现摘要，避免更换方法后继续使用旧身份。

保存位置相对于 `root`：

```text
analyses/repeat_statistics/<aggregate_id>.mat
analyses/repeat_statistics/<aggregate_id>.mat.json
```

MAT-v7 顶层变量名为 `aggregate`，不是原始运行的 `output`。JSON sidecar 保存聚合标识、路径、文件 SHA-256、大小和重复数量等索引信息；完整来源在 MAT 中。保存前重新读取并验证源运行文件，再提取源指标，逐项核对定义、实际轴、原始数值、掩码和观测状态；随后进行 MAT 回读和内容验证。`validate_repeat_summary` 单独调用时只负责内部一致性，来源绑定由保存入口额外完成。已有同身份、同内容结果返回 `resumed=true`；冲突、缺失配对文件或校验失败会被拒绝。原始运行文件及 raw-run manifest 不被聚合器覆盖。

## 6. 来源、版本与许可

| 来源 | 固定信息／核对日期 | 用途与许可边界 |
|---|---|---|
| NIST/SEMATECH e-Handbook §1.3.5.2, `https://www.itl.nist.gov/div898/handbook/eda/section3/eda352.htm` | 页面未提供单独算法版号；2026-09-28 保存并核对 | 双侧 Student-t 均值 CI 公式；独立实现，未复制示例代码 |
| R `stats::quantile` 手册，`https://stat.ethz.ch/R-manual/R-devel/library/stats/html/quantile.html` | 本地快照显示 stats 4.6.0；2026-09-28 核对 type 7 | 分位数定义参照；未复制 R 源码，不将 R 软件许可移植给本 MATLAB 实现 |
| Hyndman 与 Fan，1996，*Sample Quantiles in Statistical Packages*，DOI `10.1080/00031305.1996.10473566` | 文献信息来自已核对的 R 官方手册 | type 7 的方法来源；不声称本轮另行核对了论文全文 |
| MATLAB `betaincinv`、`mean`、`std` | 本库运行环境 R2024b | 内建数值函数，遵循安装的 MATLAB 许可；不复制其实现 |

保存的参考文本为 项目根目录的 `_local/history/graph_analyzer/validation/followup_sources/mean_ci.txt`、同目录 `quantile.txt` 及 `sources.json`。文献和文档引用不等于获得其全文或代码的再分发许可；库内统计核心为项目原创实现。

## 7. 验证与剩余限制

应验证已知样本的均值、`n-1` 标准差、type 7 分位数、Student-t 临界值、`n=0/1/2`、常数重复、两种缺失策略、精确参数选择、轴不匹配、重复种子和运行 ID 拒绝、文件篡改及 MAT/sidecar 回读。可使用独立数值库交叉核对临界值和分位数，并在验证报告记录版本与容差。本文不预先宣称这些检查的通过数量。

本接口没有实现 bootstrap、同时置信带、跨图层次统计、加权重复、配对协议差异检验、缺失插补或随机种子独立性证明。正式分析应先明确重复设计和统计对象。

任务 1 已发布 `graph-v1` 图存储规范，见 [图存储规范](../../graph_builder/docs/graph_schema_v1.md)。上游 `mc.read_graph` 读取其已发布的图 manifest，并调用官方读取器完成校验和与科学字段／身份一致性验证；原始节点／边 ID 以及存在的来源边顺序映射均予保留。本聚合接口继续只处理由这些身份约束的已保存指标运行，不重新定义图格式。当前读入联调范围是 `code/graph_analyzer/validation/graph_adapter/` 内的任务 1 手工交接样例副本，本页不宣称测试通过数量或任务 3 完整训练集成，不启动生产批量计算。
