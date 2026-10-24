# Code layout

The code directory is the only executable part of the public release.

| Directory | Role |
| --- | --- |
| `graph_builder/` | MATLAB graph generators, graph-v1 storage, source catalogs, and batch planning |
| `graph_analyzer/` | MATLAB metric registry, metric computation, attacks, robustness, and metric-v1 output |
| `dataset_builder/` | Python graph/metric readers, selection, projection, splitting, caching, and Torch/PyG batches |
| `run_dataset_builder.py` | Project-root CLI for the Python data pipeline |

Each module has its own README and documentation navigation. Read the root README first, then follow the module README for installation and checks.
