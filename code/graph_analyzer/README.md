# 指标计算模块

先查看[指标计算文档导航](docs/文档导航.md)，按指标定义、攻击统计、开发交接查找文档。

General-purpose functions for simple, unweighted directed and undirected graphs. Select metrics explicitly; there is no default production metric set. No historical data/code or production dataset is needed by the examples.

Implemented: **70 independent metrics** (45 basic, 17 advanced, 7 robustness/curve summaries, 1 single-object deletion impact), plus reusable attacks and a versioned MAT-v7 result writer. Definitions and applicability differ by metric; the catalog is not a claim every function supports both graph types. Exact algorithms, numerical methods and greedy heuristics are identified separately.

## Quick start

```matlab
cd('code/graph_analyzer'); % Run from the project root
setup_metrics;
A = sparse([1 2 2 3],[2 1 3 2],1,3,3); % path on 3 nodes
ctx = mc.context(A,false);
r = mc.compute(ctx, {'degree','global_efficiency','edge_betweenness'});
disp(r(2).values); % 5/6
one = mc.metrics.clustering(ctx,struct()); % independent function
reg = mc.registry();                       % definitions, sources and parameters
```

Use `A(source,target)=1` for directed graphs. `mc.context` validates symmetry where necessary, rejects weights/loops and preserves supplied original node/edge IDs. This is an in-memory function API, not a new graph file format. Vector/matrix axes are explicit; unreachable distance `Inf` differs from invalid `NaN`.

To pass parameters:

```matlab
selection = struct('metric_id','closeness', ...
    'parameters',struct('direction','in','wf_improved',true));
r = mc.compute(mc.context(sparse([1 2],[2 3],1,3,3),true),selection);
```

## Attacks and separate summaries

```matlab
protocol = struct('target','node','strategy','external', ...
    'external_sequence',[2;1;3], 'sample_fractions',[0;.1;.5;1]);
a = mc.attack(ctx,protocol,{'largest_component_size','global_efficiency'});
summary = mc.summarize(ctx,a,{'robustness_schneider'});
```

Node/edge, static/adaptive ranking, single/batch deletion, seeded random attacks, tie rules, recomputation intervals and ratio rounding are explicit. Actual original deletion IDs and all remaining mappings are retained. Batch states are never presented as an observed full single-deletion trajectory. Repeated sampling positions are preserved. See [attack protocols](docs/attack_protocols.md).

New additions: [edge/directed connectivity robustness](docs/attacks/删点删边与连通性鲁棒性.md), [cumulative fraction-grid batches](docs/fraction_grid_attacks.md), and [random-repeat statistics](docs/repeat_statistics.md). Proportional deletion requires protocol `version=1.1.0`, `deletion_mode=fraction_grid`, and `attack_fractions`; `sample_fractions` alone still only samples a path. Statistics retain raw repeats and report valid counts, sample SD, type-7 quantiles, and optionally pointwise Student-t mean CIs. Run `addpath('examples'); robustness_extensions_demo()` for a tiny complete example.

## Definitions and sources

- [Basic metrics](docs/metrics/基础图指标定义与验证.md): state/degree, components/cuts/core, distances/efficiency, clustering/motifs and centralities.
- [Advanced metrics](docs/metrics/相关性社区谱与可控性指标.md): correlations/community, spectra/resistance, structural versus numerical controllability.
- [Result schema](docs/metric_schema_v1.md): statuses, ID axes, random settings, MAT files and manifests.
- [Extensions and missing inputs](docs/metrics/指标扩展条件与未支持情形.md): precise unsupported cases.
- [Machine-readable registry](registry): one definition/source/method/parameter/validation entry per independent metric.

`deletion_impact` requires a scalar `base_metric` selection. It returns baseline minus the metric after independently deleting each node/edge; `relative=true` divides by the baseline. Baseline zero is invalid for relative differences. It follows the vulnerability idea of [Latora & Marchiori (2005)](https://journals.aps.org/pre/abstract/10.1103/PhysRevE.71.015103), with an explicitly generalized choice of base metric. Each deletion starts from the same original graph; this is distinct from an attack path. Fixed numeric-control matrices require an explicit update policy and are rejected.

## Original graph integration

Task1's schema is published at `code/graph_builder/docs/graph_schema_v1.md` relative to the project root. `mc.read_graph` uses its official `gg_io_read_manifest` and `gg_io_read_graph` APIs. It reads only published graph records, validates file/scientific checksums and identities, retains nodes `1..N`, canonical edge IDs `1..M`, and preserves optional verified source edge order. No alternate graph format or topology identity is defined here.

`compute_graph_metrics` and `compute_metric_batch` default to preview. Explicit non-preview calls write metric results separately, with checksummed identities, manifest parts and resume verification. Partial/failed runs require a new explicit repeat index.

Non-preview entry calls also save task evidence under `_local/runs/<dataset_folder>/<job_id>/`: `run.json` (`toolkit-run-v1`), `configs/analysis.json`, `logs/graph_analyzer.jsonl`, and `reports/graph_analyzer.json`. Failed tasks add `failures/error.json`. A batch shares one task directory, reported as `job_directory`; preview creates none. `options.run_root` can select an absolute task root outside the scientific dataset. This scheduling job_id is independent of the scientific run_id, metric_set_id and protocol_id.

Task evidence uses `code/graph_builder/io/gg_run_record.m`. Its `work` action creates `work/graph_analyzer/` only on demand; current attacks keep intermediate state in memory and save the final result through the existing writer. Recording a task does not add disk checkpoints or resume-from-round support. Commit temporary MAT files and locks stay beside the final metric target. Completed and failed task directories remain in place; hard interruption may leave a `running` status that requires inspection. See the [文档导航](docs/文档导航.md).

The public release keeps small reference fixtures under `validation/`; large measured reports and local history are omitted.

Integration tests copy task1's five tiny hand-crafted graph-v1 examples into this module's validation directory, then test formal reads, metric-only saves, preview, resume, source-order mappings and corruption refusal. Source graph files remain byte-for-byte unchanged. This confirms the task1-to-task2 file contract; task3's full training pipeline and production throughput are not claimed tested.

## Verification and small fixtures

```matlab
report = run_validation();
addpath('examples'); records = small_graph_demo();
```

Run these Python checks from `code/graph_analyzer/`:

```powershell
python tests/reference_basic.py
python validation/generate_advanced_reference.py
python tests/check_result_roundtrip.py
python tests/check_repeat_statistics.py
python tests/check_extension_roundtrip.py
python tests/check_graph_adapter.py
```

The Python references use installed NetworkX 3.5, NumPy and SciPy. MATLAB does not depend on Python at runtime. Test code covers analytic path/cycle/star/complete/isolated/multicomponent/directed graphs, all 64 directed three-node patterns, formula values, independent references, reordering, masks, explicit failures, fixed attack paths and file integrity. Numerical comparisons use documented tolerances 1e-8 or 1e-9.

Measured validation reports are generated locally and are intentionally omitted from this source release; see `../../docs/validation.md` for the evidence boundary.
