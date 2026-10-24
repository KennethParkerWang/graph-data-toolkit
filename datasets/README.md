# Dataset boundary

The public code repository does not bundle the large synthetic and real-network collections used by the local research workspace.

For a user-provided dataset, keep the scientific data separate from the source checkout and expose a stable root containing:

```text
dataset-root/
├── dataset.json
├── manifests/graphs.jsonl
├── graphs/<prefix>/<graph_id>.mat
├── configs/
├── metrics/                 optional metric-v1 output
├── splits/                  optional fixed splits
└── training/                optional HDF5/Torch cache
```

`code/graph_builder` writes and reads `graph-v1` records. `code/graph_analyzer` writes `metric-v1` records. `code/dataset_builder` validates the two contracts before creating splits or training caches.

Downloaded archives, provider terms, source URLs, and node-remapping decisions belong in a separate provenance record. A downloaded archive is not automatically a graph-v1 input or a labeled training sample.
