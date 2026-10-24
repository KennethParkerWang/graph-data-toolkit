# Architecture and data flow

The toolkit is deliberately split into three modules so that graph construction, measurement, and Python data preparation can be audited separately.

```text
parameters / source graph
          |
          v
  graph_builder  ---- graph-v1 ---->  graph_analyzer
          |                              |
          |                              +---- metric-v1
          v                                      |
       manifests                                v
                                  dataset_builder (Python)
                                      |     |     |
                                   split  HDF5  Torch/PyG
```

## `graph_builder`

This module owns model parameters, random seeds, graph identity, sparse adjacency construction, source metadata, manifests, and batch planning. Generators return a graph and metadata; they do not train a model or silently replace a failed sample with another seed.

The graph-v1 contract preserves node count, directedness, canonical edge IDs, source order when available, scientific metadata, and checksums. The I/O helpers are in `code/graph_builder/io/`.

## `graph_analyzer`

This module reads published graph-v1 records and computes explicitly selected metrics. It also contains attack schedules, deletion-impact measures, robustness summaries, repeated-sampling statistics, and metric-v1 result writers. There is no implicit default metric set.

## `dataset_builder`

This module is the Python handoff. It validates graph and metric identities, selects fields, projects variable-shaped observations, creates fixed splits, writes HDF5 caches, and exposes CPU/Torch/PyG readers. It is a data preparation layer; it does not contain a research model-training loop.

## Runtime records

Production calls should keep their configuration, status, logs, reports, and failures in a task directory outside the scientific dataset. The public package only contains the code and small fixtures needed to reproduce the contracts; local run records are intentionally excluded.
