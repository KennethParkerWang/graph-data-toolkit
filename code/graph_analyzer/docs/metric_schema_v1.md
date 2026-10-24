# Metric result schema v1

Published contract: `metric-v1`. Owner: graph_analyzer. Original graphs are owned by task1; no graph format is defined here. Static results and attack results are separate run files. All files use MAT v7 and contain **one top-level variable `output`**, a scalar struct. All identifiers and versions are char row vectors. Numerical arrays, logical masks, simple structs and cell arrays are used; no MATLAB graph objects are persisted.

## Paths and identities

Relative to the existing dataset root:

```
metrics/<metric_set_id>/<graph_id[1:2]>/<graph_id>/<run_id>.mat
configs/metric_sets/<metric_set_id>.json
configs/protocols/<protocol_id>.json
manifests/parts/metrics_<writer_id>.jsonl
manifests/metrics.jsonl
```

graph_id and topology_hash are copied from a validated task1 graph record. IDs for metric sets, protocols and runs are lower-case SHA-256 hex of UTF-8 `identity_json`. `mc.canonical_json` recursively sorts struct keys and preserves array order; explicit defaults are materialized before hashing. Consumers hash the **saved exact JSON**, rather than trying to reproduce MATLAB JSON encoding. Non-finite configuration values are rejected. Source identities are defined by `mc.source_digest` and record all installed .m/registry definition content; runtime/timestamps/paths do not participate.

metric_set identity includes versioned selected metric definitions/default-expanded parameters, optional protocol_id, implementation version and source digest. protocol identity includes the entire normalized attack protocol. run identity includes graph_id, topology_hash, metric_set_id, seeds and repeat_index. Deterministic runs explicitly use `randomness='none'` and seed empty. Repeats of identical deterministic work have different run_id only when repeat_index differs.

The exact JSON envelope is `{"configuration": {...}, "identity_version": "metric-set-v1"}` for metric sets, `metric-run-v1` for runs, and `protocol-v1` for protocols. The metric-set configuration contains `selections`, `summary_selections`, `protocol_id`, `implementation_version`, `implementation_sha256`. Each definition has metric_id, metric_version and parameters. Protocols include the scoring metric's resolved `rank_metric_version`. JSON field order is canonicalized when written; consumers validate the saved bytes.

## Top-level output fields

| Field | Meaning |
|---|---|
| schema_version | `metric-v1` |
| graph_id, topology_hash, origin_graph_id | Identity copied from original graph |
| metric_set_id, protocol_id, run_id | SHA-256 identities; protocol_id is `''` for static results |
| metric_version, implementation_sha256 | Library release `1.0.0` and source snapshot digest |
| metric_set_identity_json, run_identity_json | Exact bytes used for identity checks |
| selections | Default-expanded explicit metric selection array |
| summary_selections, summaries | Explicit summary definitions and independent summary results; empty for static runs |
| seeds | randomness (`none`/`mt19937ar`), attack_seed (empty or scalar), repeat_index |
| status | `complete`, `partial`, or `failed`; mathematical undefined/not_applicable outcomes count as completed computations |
| results | Static result struct column array; empty struct array for attack-only runs |
| attack | Empty scalar struct for static run; attack record below otherwise |
| created_utc, matlab_version, elapsed_seconds | Provenance and timing |

No adjacency or original graph file is copied into the result.

## Per-metric record

Each result has metric_id, metric_version, parameters, scope, values, axis_names, axis_ids, valid_mask, status, reason, units, method, elapsed_seconds, details.

- `scope`: graph, node, edge, distribution, matrix, trajectory. Graph scalar: no axes; a vector has one logical axis even though MATLAB stores it N-by-1. Matrix: two axes. A distribution/spectrum uses explicit bin/rank IDs.
- `values`: numeric or logical array, preserving shape. `valid_mask`: logical array with **exactly the same shape**. False values must be excluded from downstream learning; NaN is the usual undefined marker. Infinity is valid only when the definition explicitly represents an unreachable distance/infinite resistance, as documented for that metric.
- `axis_names`: cell array of names. `axis_ids`: matching cell array of node IDs, edge IDs, component/bin/rank identifiers or other explicitly named coordinates. Node/edge IDs refer to the **original graph**. Matrix node axes both contain original node IDs. Consumers must not use MATLAB internal graph edge order.
- `status`: ok, partial, undefined, not_applicable, not_computed, failed. `reason` explains all unavailable results. An empty vector on the empty graph may legitimately be ok; empty values with failed/not_applicable are unavailable.
- `method`: exact, numerical, heuristic (and a future explicitly registered approximate method). No timeout silently switches the algorithm. `details` holds algorithm-specific witnesses, tolerances, residuals or normalization denominators.

## Attack record

`attack` stores normalized protocol/protocol_id, original object counts, explicit seed/repeat, deletion sequence in original IDs, full observed states, separately requested ratio samples and status. Each state contains the **actual** deletion count/fraction, remaining original node/edge IDs and selected metric records. Single deletion stores every visited count including zero; batch deletion stores only visited batch boundaries and explicitly marks its trajectory resolution. Repeated requested fractions are preserved as separate sample positions, even when they map to the same actual count. A denominator of zero is undefined, never implicit division by zero.

The exact attack field table and runnable protocol examples are in [attack_protocols.md](attack_protocols.md). Summaries are independent metric definitions: original discrete robustness requires the original endpoints/resolution/denominator; sampled trapezoidal area has its own name. Per-repeat records are retained. Aggregation never replaces raw repeats.

## Manifest and atomic publication

Each metrics.jsonl row contains schema_version, graph_id, topology_hash, origin_graph_id, metric_set_id, protocol_id, run_id, status, path (dataset-relative `/`), file_sha256, file_bytes, implementation_sha256, created_utc. The writer first saves a same-directory temporary MAT-v7, loads and validates it, then renames it without replacing an existing result. A conservative 1.8 GB per-variable bound rejects oversized results before save; v7.3 is never selected implicitly.

Each writer owns one part, protected by a lock directory. `mc.merge_manifests` is an explicit single-publisher operation with its own lock. It verifies file checksum, identities and contents, rejects conflicts and atomically publishes the total manifest. It reads only parts named `metrics_*.jsonl` and never modifies graph manifests or other tasks' files.

Resume requires a matching manifest entry, SHA-256/size verification, schema/identity/content validation and a completed status. Existing unindexed files are treated as orphan/conflict and require explicit recovery; an existing filename is not success. Failed/partial runs are retained with reasons and do not silently count as completed. A changed configuration or source snapshot receives a different identity and cannot overwrite prior runs.

## Consumption notes

Read with SciPy `loadmat(..., simplify_cells=True)` for convenient prototypes; singleton squeezing can change array rank, so use axis metadata or `squeeze_me=False` when shapes matter. The MATLAB validation suite and Python round-trip check exercise scalars, node/edge vectors, matrices, empty vectors and mixed valid/invalid data. Task3 may add padding only in derived training storage and must preserve valid_mask and original-ID axes.

Format sources: [MathWorks MAT versions](https://www.mathworks.com/help/matlab/import_export/mat-file-versions.html), [SciPy loadmat](https://docs.scipy.org/doc/scipy/reference/generated/scipy.io.loadmat.html), checked 2026-09-27. Implemented/tested environment is recorded in validation outputs rather than inferred from current online documentation.

## Compatible extensions (2026-09-28 local checkpoint)

The raw-run top-level `metric-v1` wrapper is unchanged. Its nested attack can now be `attack-1.1.0` for an explicitly versioned 1.1.0 protocol. A fraction-grid attack includes the `schedule` request-to-state vectors defined in [fraction_grid_attacks.md](fraction_grid_attacks.md). Version 1.0.0 normalized fields and protocol IDs remain unchanged; old result files are read without rewriting. Result formulas keep their saved metric versions.

Random-repeat derived results have their own `repeat-summary-1.0.0` schema, top-level MAT variable `aggregate`, and `analyses/repeat_statistics/<aggregate_id>.mat` plus `.mat.json` sidecar. They are not raw-run records and must not be inserted into `manifests/metrics.jsonl`. Their exact fields, counts/masks, provenance and statistics options are defined in [repeat_statistics.md](repeat_statistics.md).
