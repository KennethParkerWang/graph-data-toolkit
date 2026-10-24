# 图生成模块

先查看[图生成文档导航](docs/文档导航.md)，按使用接口、模型来源、验证记录查找文档。

当前算法版本 **2.1.0**，存储规范 **graph-v1**，批量配置版本 **2**。提供 **23个命名模型、27个可用方向接口：17个无向、10个有向**。另12个缺乏独立来源的旧方向入口保留明确报错；公共 `gen_*.m` 入口共39个。

生成器返回稀疏logical邻接矩阵，保持节点编号，遵循各模型规定的生成与连通规则，不按实验目标额外筛选、不自动换种子补成功样本。运行只需基础MATLAB和默认JVM。历史扩展验收的证据边界见[验证说明](../../docs/validation.md)。这里生成原始图；指标与攻击协议由指标模块处理，训练数据准备由数据管线处理。

## 入口

- [参数与生成规则](docs/usage/图生成模型与参数手册.md)：23个命名模型的方向、参数范围、核心规则和例子。
- [合成网络扩展模型与验证说明](docs/models/合成网络扩展模型与验证说明.md)：新增LFR、指定度序列、DC-SBM、Waxman、复制—分化、RHG、Forest Fire的来源、适用条件和验证入口。
- [标准模型来源](docs/models/标准图模型与来源说明.md)与[EH/多边形作者实现](docs/models/作者图模型与已知边界.md)：固定版本、原始源码、保留行为和已知问题。
- [图存储规范](docs/graph_schema_v1.md)：MAT字段、ID、hash、索引、续跑与并行写入。
- [批量生成](docs/usage/批量图生成与任务存储.md)：范围、配置、预览、失败与恢复。
- [任务2/3交接](docs/usage/原始图交接与读写示例.md)：正式接口及小样本路径。
- [本轮验证记录](docs/validation/图生成历史验收记录_20260927.md)：实际执行结果及限制。

## 生成单张图

```matlab
cd('code/graph_builder'); % 从项目根目录执行
setup_generators;
[A, meta] = gen_ba_undirected(500, 4, 20260927);
% A(i,j)=1：无向边；有向接口则表示i到j的弧。
% BA默认星形种子，此例M=4*(500-4)=1984。
```

所有支持的函数都遵循 `[A,meta]=gen_<model>_<direction>(...,seed)`，seed最后、默认1，调用后恢复外部随机数状态。`demo_generators`用于小图接口示例，不写正式数据；扩展模型示例见参数手册。新增模型不会自动加入此前的正式8,000张合成图库。

## 按配置批量保存

```matlab
preview = generate_graph_batch('configs/smoke.json', 'DryRun', true);
% 预览12张；检查preview.plan后再执行：
result = generate_graph_batch('configs/smoke.json');
disp([result.generated, result.skipped, result.recovered, result.failed]);
disp(result.job_directory); % 本次任务参数、日志、状态与报告的位置
```

图保存到项目的`datasets/<dataset_id>/graphs/<prefix>/<graph_id>.mat`。正式索引是`manifests/graphs.jsonl`；各次运行另记`manifests/generation_runs/<batch_id>.jsonl`。相同配置重跑时先验证文件hash、图身份、参数与种子，再跳过已完成样本。

`smoke.json`是12张小图配置；`pilot.json`是ER-Gnm、BA、WS的135张先导配置。它们不是已替用户确定的正式实验设计，本轮没有运行这两个配置来生产数据。

非 DryRun 调用另建 `_local/runs/<dataset_folder>/<job_id>/` 任务目录，保存 `run.json`（`toolkit-run-v1`）、`configs/generation.json`、`logs/graph_builder.jsonl` 和 `reports/graph_builder.json`；失败时增加 `failures/error.json`。`job_id` 是独立任务标识，与配置计划中的数字 job_id、正式 batch_id 不同。DryRun 不创建任务目录。可传入 `'RunRoot','_local/task_runs'` 指定相对于项目根的任务目录，也可显式指定外部绝对路径；该位置必须在科学数据集外。

`io/gg_run_record.m` 提供按需 `work/graph_builder/` 目录；当前生成器仍在内存中生成、校验图，不自动保存候选图，也不支持从单图生成中途恢复。正式提交临时 MAT 与写锁仍位于数据集目标目录。状态与完整布局见 [文档导航](docs/文档导航.md)。

## 扩展验收（2026-10-07）

当前23模型、27接口的历史回归记录保留在原项目中；本公开副本只携带小型互操作夹具和验证入口，不携带完整验证图库。实际运行边界见[验证说明](../../docs/validation.md)。

## 目录

```text
code/graph_builder/
  directed/             10个可用接口，7个明确拒绝入口
  undirected/           17个可用接口，5个明确拒绝入口
  common/               RNG、校验、出处和实现摘要
  io/                   graph-v1读写、身份、提交、索引与独立任务记录
  batch/                配置预检和续跑
  configs/              示例配置
  sources/              固定版本的原始参考文件、hash及许可证
  examples/schema_v1/   5张交接样例；不属于训练样本
  validation/           验证入口、固定样例和当前报告
  docs/                 参数、来源、存储与交接说明
```

作者EH/多边形源码存在异常路径；整理版完整保留随机过程，再对最终结果执行简单图校验。失败会写明模型、参数、seed和错误，不偷偷修补。作者包未发现通用开源许可证，许可证状态随来源记录保存；不能把“公开下载”写成MIT/BSD授权。

旧版审计、性能日志及运行产物保存在项目根目录的 `_local/history/graph_builder/`；日常入口保留在本模块。2.0已更换若干生成规则，因此旧版逐样本等价与速度倍数不适用于本版。
