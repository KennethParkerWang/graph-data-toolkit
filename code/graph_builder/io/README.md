# Graph I/O API

Root integration API:
- `sample = gg_io_make_sample(A, meta)`; requires model, directed, parameters, seed (or rng), generator_version (or implementation_version), implementation_sha256, source; accepts generator_id or derives model_direction. Keeps custom meta, attributes, optional meta.source_edge_order (moves mapping to top-level).
- `[record,status] = gg_io_write_graph(dataset_root,sample)`; status `created`, `existing`, or `recovered`; commits per-graph independent `manifests/parts/graphs_<graph_id>_<uuid>.jsonl`; graph lock avoids concurrent same-ID writes. Does not create dataset.json/config snapshots.
- `sample = gg_io_read_graph(path,expected_record)`; expected_record optional; file checksum checked first if supplied, complete scientific structure validated.
- `records = gg_io_read_manifest(dataset_root)` reads published graphs.jsonl only; no implicit merge.
- `records = gg_io_merge_manifest(dataset_root)` reads existing published index and graph part files, validates files, publishes sorted deduplicated index under a merge lock. Leaves immutable parts in place for audit/recovery.
- `hash = gg_io_topology_hash(N,directed,edge_list)` and `gg_io_sha256(value,mode)` with modes `text` (default), `file`, `bytes`.
- `gg_io_validate_sample(sample)` and `gg_io_scientific_hash(sample)` available for integration checks.

Integration uses `gg_io_make_sample` directly after source metadata has been added; no second legacy-metadata converter is needed. Formal batches should pass explicit `generator_id` such as `gen_ba_undirected`, with `model='ba'`.

The schema is `docs/graph_schema_v1.md`. MATLAB tests: add `io` and `validation` to the path, run `test_graph_io`, then `create_graph_io_examples`. Run `validation/verify_graph_io.py` with NumPy/SciPy for independent checks. MATLAB R2024b and Python validation have both passed the five stored examples.
