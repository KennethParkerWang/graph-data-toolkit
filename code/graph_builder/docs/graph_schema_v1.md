# Graph schema v1

状态：已实现。入口位于 `graph_builder/io/`。MATLAB R2024b 与 Python/SciPy 的五类交接样例已验证，命令见本文末尾。图算法版本与本文件的数据结构版本分别维护。

## 目录和所有权

```text
datasets/<dataset_id>/
  dataset.json
  configs/
    generation.json
    metric_sets/<metric_set_id>.json
    protocols/<protocol_id>.json
  graphs/<prefix>/<graph_id>.mat
  metrics/<metric_set_id>/<prefix>/<graph_id>/<run_id>.mat
  manifests/
    graphs.jsonl
    metrics.jsonl
    parts/graphs_<graph_id>_<uuid>.jsonl
    generation_runs/<batch_id>.jsonl
  splits/<split_id>.json
  training/<cache_id>/
```

`prefix` 为 graph_id 的前两个字符。所有索引路径相对数据集根目录，分隔符固定为 `/`。移动整个数据集不改变身份。

任务1写图、图索引、生成配置和运行记录。任务2写指标结果，任务3写划分及训练缓存。指标不写入图文件。图 I/O 不代替批量入口管理 dataset.json 或配置快照。

## dataset.json 和生成配置

所有数据集描述至少含dataset_id、graph_schema_version、created_utc、graph_root、graph_manifest和description，值均为字符串。graph_schema_version为`graph-v1`，graph_root为`graphs`，graph_manifest为`manifests/graphs.jsonl`。

`generate_graph_batch`产生的数据集另外必须含：

| 字段 | 规则 |
|---|---|
| generation_config | 固定相对路径`configs/generation.json` |
| generation_config_sha256 | 规范生成配置身份的64位小写SHA-256 |
| generation_config_file_sha256 | 配置快照原始文件字节的SHA-256 |
| implementation_sha256 | 生成算法源码快照的SHA-256 |
| implementation_version | 当前为`2.0.0` |

生成配置格式为`schema_version=2`，与图结构版本分别维护。配置身份由`gg_batch_plan`展开默认运行字段、规范网格、递归排序键后，去掉output_dir、resume、on_error、max_graphs，再对MATLAB jsonencode文本做UTF-8 SHA-256。其余字段改变即拒绝混入同一数据集。

快照的output_dir固定为`..`，相对configs目录解析，因此整个数据集移动后可直接使用快照续跑。描述中的文件摘要核验快照是否损坏；它与配置身份摘要用途不同。全部路径都不参与单图graph_id。

`examples/schema_v1`是手工构造的格式夹具，使用基本描述字段和固定测试时间戳；不是由批量配置生成的实验数据集，不通过generate_graph_batch续跑。重建使用`create_graph_io_examples`。

## MAT v7 字段

每张图为独立 MAT v7 文件；顶层字段固定如下，不保存 MATLAB graph/digraph 或 Python 对象。

| 字段 | MATLAB 类型/尺寸 | 规则 |
|---|---|---|
| schema_version | char 行向量 | `graph-v1` |
| graph_id | 64字符 char | 小写 SHA-256；与文件名一致 |
| topology_hash | 64字符 char | 有编号拓扑摘要 |
| origin_graph_id | 64字符 char | 原图等于 graph_id；派生图指向基础图 |
| N | uint32 标量 | N≥1，包含孤立节点 |
| M | uint64 标量 | 无向边数或有向弧数 |
| directed | logical 标量 | 是否有向 |
| A | N×N sparse logical | 无权简单图；对角为0；无向严格对称 |
| edge_list | M×2 uint32 | 规范边表；无边时严格为0×2 |
| meta | 标量 struct | 元数据，见下文 |
| source_edge_order | 可选 M×1 uint64 | 来源最终边顺序对应的规范边ID排列 |

读写器同时核对 A、M、edge_list、方向和所有身份摘要。类型不符或字段不一致直接报错，不猜测如何修正。

MAT v7 的限制通过保守预检执行：整个未压缩 sample 的 MATLAB `whos` 大小必须小于 1,800,000,000 bytes，这也约束单个变量大小。写入后必须完整回读验证。超限或保存失败报错，不切换成 v7.3。

Python 用 `scipy.io.loadmat(..., mat_dtype=True, struct_as_record=False, squeeze_me=False)` 保留维度。N/M/directed分别读为 `(1,1)` 的 uint32/uint64/bool 数组。edge_list保持 `(M,2)`。SciPy不同版本可将MAT稀疏logical读成bool或uint8；读取器验证所有非零值为1后可转bool，不应拒绝合法uint8表示。meta为MATLAB struct容器，char行为单个字符串数组。

## 节点和边ID

- 节点ID为 `1..N`，不能从边表最大值推断N。
- A(i,j)=1表示i→j。
- edge_list按source、target两列升序排序。
- 无向边只保存u<v一次；有向弧不交换端点，互惠弧分别占一行。
- 规范边ID是edge_list的行号 `1..M`。后续删除节点或边时仍使用这些原始ID。
- `source_edge_order(k)`是来源实现第k条最终边对应的规范边ID。没有来源顺序时省略字段，同时设置 `meta.source_edge_order_available=false`。不可自动用规范顺序替代来源顺序。

Python训练读取需要时将节点/边ID减1，并在展开无向双向消息传递边时保存原始边ID映射。图存档本身不展开双向边表。

## meta

| 必需字段 | 含义 |
|---|---|
| model | 批量配置使用的短名，如`ba` |
| generator_id | 具体算法协议标识，如`gen_ba_undirected`；由调用方明确提供 |
| parameters | 标量struct，保存实际使用的全部参数和默认值 |
| rng | 标量struct，至少含algorithm字符行和seed非负uint32范围整数；可保存子种子/子流 |
| implementation_version | 实现版本字符串，如`2.0.0` |
| implementation_sha256 | 具体算法源码集合的摘要，64位小写hex |
| source | 来源字符行或struct，保存出处、版本和许可证记录等 |
| created_utc | UTC生成时间字符行 |
| matlab_version | 生成环境字符串 |
| recipe_json | 规范身份JSON文本，保存后不得重新排版 |
| source_edge_order_available | logical标量 |

模型特有的社区、坐标等放在 `meta.attributes`，通过node_ids或各属性的维度定义与节点对应。自定义元数据保留并参与科学内容校验。支持有限实数数组、logical、char行、struct及由这些类型组成的cell；不接受函数句柄、对象、稀疏元数据、NaN或Inf。A不受此元数据限制。

`gg_io_make_sample`可接收生成器的`directed/seed/rng_algorithm/generator_version`别名，转换后移除它们及num_nodes/num_edges/mean_degree/mean_in_degree/mean_out_degree/density/degree_convention重复统计；顶层N/M/directed为唯一依据。其余自定义字段保留。source_edge_order从meta移动到顶层。

没有generator_id时，底层函数使用`<model>_directed`或`<model>_undirected`；正式批量入口必须传入有来源记录的明确generator_id，避免把算法变体合并。

派生图输入meta.origin_graph_id及meta.transformation。origin_graph_id移到顶层，变换定义留在meta并参与身份。基础图不填写origin_graph_id，封装器将其设为自身ID。

## 四种摘要

### topology_hash

SHA-256输入为以下UTF-8无BOM字节，所有换行均为单字节LF，最后一行也有LF：

```text
topology-v1\n
N\n
directed\n
M\n
u1,v1\n
u2,v2\n
...
```

N/M/u/v为无前导零十进制整数；directed为0或1；无空格。无边时不追加边行。这里只识别相同编号的拓扑，不识别所有同构图。MATLAB实现分块更新SHA-256，不构造完整邻接矩阵字符串。

### graph_id 与 recipe_json

`graph_id = SHA256(UTF8(meta.recipe_json))`。recipe包含schema_version、model、generator_id、directed、parameters、rng、implementation_version、implementation_sha256、topology_hash。派生图另含origin_graph_id与transformation。时间、路径、dataset_id和运行耗时不参与。

本版implementation_sha256由`gg_implementation_digest`计算：枚举common、directed、undirected下全部.m，再加入sources/standard/catalog.json和sources/author_lou/catalog.json；按POSIX相对路径排序。每行是`relative_path:file_sha256`加LF，前缀为`generator-snapshot-v1`加LF，对完整UTF-8文本取SHA-256。它标识整套生成实现快照，不是每个模型独立维护的摘要。文档、I/O、调度代码不在该集合内；来源原文件的独立摘要另存在meta.source。

规范序列化由 `gg_io_canonical_json` 固定：

1. struct键按字符升序；无缩进和额外空格；字符串使用MATLAB jsonencode转义。
2. 所有数值/logical数组（包括标量）使用`{"dtype":"double","shape":[1,2],"values":["1","2"]}`形式。shape保留MATLAB尺寸；values采用列优先顺序。
3. 整数以精确十进制字符串保存；single/double转换为double后用`%.17g`表示；正负零统一为`"0"`；logical值用JSON true/false，不加引号。
4. 数值dtype使用MATLAB类型名。单个struct为JSON对象；非标量struct使用`{"__struct_array__":true,"shape":[...],"values":[...]}`；cell同理，标记为`__cell_array__`。
5. UTF-8无BOM。数组shape、元素类型和行列方向都参与身份，不按语义自动归一化。

任务2/3验证graph_id时直接hash保存的recipe_json原文。无须通过Python JSON解析后重新序列化。测试脚本额外实现了科学内容的跨语言规范化，仅用作校验。

### scientific_sha256

索引中的科学内容摘要包含schema_version、graph_id、origin_graph_id、topology_hash、N、M、directed、meta及可用来源边序。meta排除且仅排除created_utc、matlab_version、elapsed_seconds、duration_seconds、generation_elapsed_seconds、recipe_json。其余新增自定义元数据默认属于科学内容。

同graph_id但属性、出处、来源边序等科学内容不同，是冲突。不同生成时间、运行环境或耗时允许续跑复用已提交文件；既有文件不会重新保存。

### file_sha256

MAT文件实际字节的SHA-256，写在索引，不写回MAT。读图时传入索引记录，先检查文件字节数和file_sha256，再读取MAT及校验科学结构。压缩/头部/时间不同可以导致不同文件hash，不代表拓扑不同。

## 图索引与提交

每行graph-v1索引固定为：graph_id、origin_graph_id、topology_hash、path、N、M、directed、model、generator_id、schema_version、implementation_version、file_sha256、file_bytes、scientific_sha256、created_utc。

`gg_io_write_graph`持有单图目录锁，先在目标目录保存临时MAT并回读校验，再重命名为最终文件。每张提交写独立的 `parts/graphs_<graph_id>_<uuid>.jsonl`，各进程不追加共同文件。已提交分片保留，便于恢复。

`gg_io_merge_manifest`持有单独的合并锁，读取当前总索引和已完整发布的分片，拒绝冲突、重复定义或损坏文件；成功后按graph_id排序，原子替换graphs.jsonl。使用Java NIO ATOMIC_MOVE及REPLACE_EXISTING；文件系统不支持时明确失败，不退化为删除旧索引后再复制。合并开始后新到达的分片由下次合并接收。

读取方只读已发布graphs.jsonl，不递归扫描图文件猜测完成情况。

同ID续跑：先用已提交记录验证旧文件，再比较科学摘要，一致则返回`existing`且保持文件字节不变。记录存在而文件缺失、文件损坏或科学内容冲突都报错。

若上次进程在MAT提交与分片提交之间中断，可能只有完整MAT而无记录；重试时必须通过全部结构/身份校验，且科学摘要与本次候选相同，才补写登记并返回`recovered`。不会根据文件名直接认定成功。锁目录在进程正常退出及异常抛出时自动移除；强制结束进程遗留锁时先确认无写入者，再人工处理该精确锁目录。

## MATLAB API

```matlab
addpath('graph_builder/io');

% prepared_meta由生成入口补齐来源及算法源码摘要。
sample = gg_io_make_sample(A, prepared_meta);
[record, status] = gg_io_write_graph(dataset_root, sample);
records = gg_io_merge_manifest(dataset_root);

records = gg_io_read_manifest(dataset_root);
sample = gg_io_read_graph(fullfile(dataset_root, records(1).path), records(1));
```

独立验证接口：`gg_io_validate_sample`、`gg_io_topology_hash`、`gg_io_sha256`、`gg_io_scientific_hash`。仅传文件路径读图可校验内部身份；有索引时应始终传record，以校验传输和文件损坏。

## 交接样例及测试

[样例目录](../examples/schema_v1)包含五张小图：无向三角形加孤立点（含社区、坐标与来源边序）、有向互惠弧加孤立点、三节点空边图、有向单节点空图、带基础图关系的重标号图。这些是手工构造的结构样例，不是某个随机生成模型的测试结果。

```matlab
addpath('graph_builder/io');
addpath('graph_builder/validation');
test_graph_io;
create_graph_io_examples;
```

```powershell
& 'D:/anaconda/envs/p2_edge/python.exe' 'graph_builder/validation/verify_graph_io.py'
```

MATLAB测试覆盖读写、类型、种子身份、元数据保留、时间差异续跑、科学内容冲突、损坏文件拒绝、孤立点、空边集、边序、孤儿文件恢复、坏索引不覆盖原索引。Python独立验证文件摘要、拓扑摘要、身份摘要、科学摘要、编号、方向、数据类型和模型属性。[最终验证记录](task1_validation.md)。

参考格式文档：MathWorks MAT-File Versions、SciPy loadmat。实际字段及hash规则以本版本为准；后续破坏性变化需要新schema版本。
