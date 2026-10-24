# Graph Data Toolkit

Graph Data Toolkit is a reproducible toolkit for building graph datasets, computing graph metrics, and preparing graph data for Python and PyTorch Geometric workflows.

The repository is organized around one explicit pipeline:

```text
graph_builder  ->  graph_analyzer  ->  dataset_builder
     graphs          metrics            Python-ready data
```

It contains source code, small interoperability fixtures, configuration examples, and documentation. Large graph collections, downloaded source archives, local run logs, virtual environments, and private research notes are intentionally kept outside this public code package.

## What is included

| Module | Purpose | Main language |
| --- | --- | --- |
| `code/graph_builder/` | Synthetic graph generators, graph-v1 I/O, manifests, source metadata, and batch generation | MATLAB |
| `code/graph_analyzer/` | Static metrics, controllability-related metrics, deletion/attack protocols, robustness curves, and metric-v1 output | MATLAB |
| `code/dataset_builder/` | Dataset validation, selection, splitting, projection, normalization, HDF5 caching, and Torch/PyG batch reading | Python |
| `datasets/` | Public data layout and acquisition boundary; raw datasets are not bundled | Markdown |
| `docs/` | Architecture, source policy, validation boundaries, and design notes | Markdown / LaTeX |

The graph generator currently documents 23 named models and 27 usable direction-specific interfaces. The metric registry contains 70 independent metric definitions grouped into basic, advanced, robustness, and deletion-impact families.

## Quick start

### MATLAB graph generation

From the repository root:

```matlab
addpath('code/graph_builder');
setup_generators;
[A, meta] = gen_ba_undirected(500, 4, 20260927);
```

For a batch plan, inspect a configuration before writing data:

```matlab
preview = generate_graph_batch('code/graph_builder/configs/smoke.json', 'DryRun', true);
disp(preview.plan);
```

### MATLAB metric computation

```matlab
addpath('code/graph_analyzer');
setup_metrics;
A = sparse([1 2 2 3], [2 1 3 2], 1, 3, 3);
ctx = mc.context(A, false);
result = mc.compute(ctx, {'degree', 'global_efficiency'});
```

### Python data pipeline

Create an isolated environment and install the module requirements:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r code/dataset_builder/requirements.txt
```

The Python package reads published `graph-v1` and `metric-v1` records. A complete dataset needs its own manifest, selection configuration, and split configuration; this repository does not silently treat downloaded files or test fixtures as training data.

## Where to read next

- [Architecture and data flow](docs/architecture.md)
- [Data sources and provenance](docs/data-sources.md)
- [Validation and evidence boundaries](docs/validation.md)
- [Graph builder README](code/graph_builder/README.md)
- [Metric analyzer README](code/graph_analyzer/README.md)
- [Python dataset builder README](code/dataset_builder/README.md)
- [Graph-v1 storage schema](code/graph_builder/docs/graph_schema_v1.md)
- [Metric-v1 storage schema](code/graph_analyzer/docs/metric_schema_v1.md)

Chinese module documentation remains next to the implementation. The repository root is intentionally short; detailed model, metric, attack, and interface documentation stays with the code it describes.

## Validation status

The package includes small graph-v1 interoperability fixtures and module-level tests. Validation is separated from scientific production: a smoke test confirms an interface or file contract, but it does not claim a full dataset, a completed attack-label run, or a trained model. See [Validation and evidence boundaries](docs/validation.md).

## Data and licensing boundary

Raw network downloads and large generated graph collections are not committed here. Their provider URLs, checksums, citations, and import rules belong in an external dataset archive; [datasets/README.md](datasets/README.md) describes the expected layout.

The repository does not declare a single blanket license yet. See [NOTICE.md](NOTICE.md) before redistributing the source or adding third-party material. NetworkX and CPython reference files retain their upstream notices. Author-provided archives with unresolved redistribution terms are intentionally excluded from this release.

## Project status

This is a cleaned source release of the existing toolkit. It is suitable for code review, extension, and reproducible small fixtures. It is not a copy of the local research workspace and does not include private task records, large data archives, or unfinished end-to-end experiments.
