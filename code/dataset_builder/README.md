# 数据管线模块

先查看[数据管线文档导航](docs/文档导航.md)，按接口交接、验证交付查找文档。

任务 3：沿用任务 1/2 的新格式，按身份整合指标、固定分区、转换可重建 HDF5，并按需读取 PyTorch/PyG batch。

模块版本 `0.2.0`。原交付回归为 **288 项测试通过，无跳过**；后续整理与本轮检查分别见 [公开版架构说明](../../docs/architecture.md)。

已接入任务 1 的正式 `graph-v1` 和任务 2 的 `metric-v1`；交付边界见 [交接记录](docs/interfaces/上游数据接入与当前边界.md)。
训练缓存格式见 [训练缓存格式规范_v1](docs/interfaces/训练缓存格式规范_v1.md)；测试范围见 [数据管线测试设计](docs/validation/数据管线测试设计.md)。
已用 **5 组身份完全匹配的真实图和静态指标**跑通源 MAT→校验/固定划分→HDF5→CPU batch。
攻击 states/sampled 可显式选择并按原 ID 对齐；12 份生产者指标侧 MATLAB 样例通过，
其攻击轨迹使用测试身份；任务2另有一份真实任务1图攻击验证报告，但尚未以正式 metric-v1 attack run
交付给任务3。完整测试结果和边界见 [数据管线历史交付记录_0.2.0](docs/validation/数据管线历史交付记录_0.2.0.md)。

## 环境与独立验证

以下安装与CLI命令从项目根目录执行。运行环境放在 `code/dataset_builder/.venv`；独立module和pytest入口临时切换到code目录运行，再返回项目根。
建议使用独立 venv，不继承 Anaconda site-packages，避免 MKL/PyTorch OpenMP 运行库冲突。

```powershell
uv venv code/dataset_builder/.venv
uv pip install --python code/dataset_builder/.venv/Scripts/python.exe torch --index-url https://download.pytorch.org/whl/cpu
uv pip install --python code/dataset_builder/.venv/Scripts/python.exe -r code/dataset_builder/requirements.txt

& './code/dataset_builder/.venv/Scripts/python.exe' -B './code/run_dataset_builder.py' contract-status
& './code/dataset_builder/.venv/Scripts/python.exe' -B './code/run_dataset_builder.py' framework-smoke --output './code/dataset_builder/artifacts/framework_smoke_NEW_RUN' --workers 2

Push-Location './code'
try {
    & './dataset_builder/.venv/Scripts/python.exe' -B -m pytest './dataset_builder/tests' -q -p no:cacheprovider
    & './dataset_builder/.venv/Scripts/python.exe' -B -m dataset_builder.producer_smoke --workers 2 --warm-passes 3
    & './dataset_builder/.venv/Scripts/python.exe' -B -m dataset_builder.producer_layout_benchmark
    & './dataset_builder/.venv/Scripts/python.exe' -B -m dataset_builder.metric_smoke --output './dataset_builder/artifacts/metric_smoke_NEW_RUN' --workers 2
} finally {
    Pop-Location
}
```

framework-smoke 使用 8 个明确标记的内存测试样本，核对标量/节点/边/曲线、有效 mask、孤立节点、
空边、有向互惠弧、分片回读以及 CPU 多 worker batch。报告为输出目录下的 `report.json`。
这个报告不表示生产者 MATLAB → Python 的正式样本验收已经完成。

`producer_smoke` 使用项目根目录下的 `code/graph_builder/examples/schema_v1/` 和
`code/graph_analyzer/validation/graph_adapter/` 匹配样例，将其复制至唯一 `artifacts/producer_smoke_*` 目录，保留原字节，
只向该副本写 splits/training。报告核对所有输入前后 SHA，记录5图静态全链路及0/2-worker读回。
`metric_smoke` 的输出目录必须尚不存在；它验证 7 份基础和 5 份扩展指标样例、观测投影及缓存，
其中 N=0 样例仅验指标解码，不冒充合法的原始训练图。两个入口均不训练模型。
`producer_layout_benchmark` 对同一5图比较2/8图每片与none/LZF/gzip-1，共6种布局，
逐次校验fingerprint。此样例中8图每片、无压缩体积最小；正式数据规模下需要重新测量。

## 使用自己的正式数据

1. 确认任务 1 已发布图规范与新图样例；任务 2 已发布指标规范、攻击字段和相应小样例。
2. 根据正式 manifest/config 填写 [selection.template.json](examples/selection.template.json)。
   模板中的 REPLACE 占位符必须替换，指标参数需要包含生产者展开后的默认值。
3. 提供自己的 split 配置，选择 random / family / size；本任务不替用户固定正式实验方案。

```powershell
& './code/dataset_builder/.venv/Scripts/python.exe' -B './code/run_dataset_builder.py' validate './datasets/DATASET_ROOT' --selection './path/to/selection.json'
& './code/dataset_builder/.venv/Scripts/python.exe' -B './code/run_dataset_builder.py' split './datasets/DATASET_ROOT' --config './path/to/split_config.json'
& './code/dataset_builder/.venv/Scripts/python.exe' -B './code/run_dataset_builder.py' convert './datasets/DATASET_ROOT' --selection './path/to/selection.json' --split './datasets/DATASET_ROOT/splits/SPLIT_ID.json' --normalization none --shard-size 8 --compression none
```

DATASET_ROOT等是占位符，替换为符合正式图/指标交接条件的数据集目录。命令中的分片/压缩值仅展示语法；实际参数以相同小样例的测量结果为依据。仅有原图的分类入口使用SourceDataset(...,graph_only=True)读取，不直接作为具备标签的训练输入。
数据集必须提供任务 1 的 dataset.json/graphs manifest 和任务 2 的 metrics manifest/configs。
读取器校验保存的身份 JSON 原文、文件 SHA、科学内容摘要、A/边表一致性和指标/协议定义。

## 任务记录与中间存储

`validate`、`split`、`convert` 命令及对应的 `validate_dataset`、`create_split`、`convert_dataset` API 自动按调用建立 `_local/runs/<dataset_folder>/<job_id>/`，保存 `run.json`（`toolkit-run-v1`）、`configs/build.json`、`logs/dataset_builder.jsonl` 和 `reports/dataset_builder.json`；失败时增加 `failures/error.json`。API 校验结果含 `job_directory`，划分与转换继续返回正式 split/cache 路径。

从项目根运行时，CLI 可增加 `--run-root _local/task_runs`，API 可传入 `run_root=`，将任务记录保存到数据集外的指定位置；该根目录不得等于或位于科学数据集内部。任务 job_id 不参与 split_id 或 cache_id 的科学身份，正式分区、缓存及其摘要沿用现有规范。

`run_storage.py` 的 `RunWorkspace.work()` 按需创建 `work/dataset_builder/`。当前投影和转换未自动保存额外的中间 HDF5；最终缓存的临时分片、临时索引和写锁仍留在 `training/<cache_id>/` 供原子提交。完成与失败任务保留原目录，硬中断可能留下 `running`，不表示支持从半个分片恢复。

`contract-status` 和 `framework-smoke` 不创建这种任务记录；`producer_smoke` 的验收副本继续位于固定的 `artifacts/` 范围，其中调用管线的校验、划分、转换会分别记录任务。完整目录与限制见 [文档导航](docs/文档导航.md)。

## 读取一个 CPU batch

```python
from pathlib import Path
import sys
sys.path.insert(0, str(Path.cwd() / 'code')) # 从项目根运行自己的脚本
from dataset_builder.dataset import TrainingDataset, make_pyg_loader

def main():
    with TrainingDataset("datasets/DATASET_ID/training/CACHE_ID/index.json", split="train") as dataset:
        loader = make_pyg_loader(dataset, batch_size=4, num_workers=2, bidirectional=True)
        batch = next(iter(loader))
        graph = batch["graph_batch"]
        target = batch["targets"]["curve_target"]
        values, valid = target["values"], target["valid_mask"]
        # Use only valid entries in a loss; actual positions remain in target["axis_positions"].

if __name__ == "__main__":
    main()
```

`feature_keys` 与 `target_keys` 分开配置；不自动将所有指标装入 x/y。
缺失、失败、数学未定义、不适用、真实 0 和 padding 保持可区分。
唯一静态结果可按图关联；多个独立重复流必须显式配置 run_groups，不能按文件顺序拼接。
mean 只汇总实际轴和定义完全一致的重复；不自动插值或重新计算科学指标。
默认选择 `results`/`summaries`。直接选择攻击观测时，在 selector 中增加
`"observation_source": "states"`（或 `"sampled"`）及 `"alignment": "by_id"`。
变长节点/边/矩阵按原坐标对齐，保留重复请求与实际位置；present_mask 区分结构缺席，
valid_mask 表示数学有效性。详细 shape、状态与来源规则见训练格式规范。

源码、文档和测试均在本目录。模块验收产物保留在本地 `artifacts/`，新任务记录默认位于项目根目录的 `_local/runs/`，历史工作记录保存在 `_local/work_records/dataset_builder/`。生产数据只读，正式派生结果仅写入各数据集的 splits/training。
