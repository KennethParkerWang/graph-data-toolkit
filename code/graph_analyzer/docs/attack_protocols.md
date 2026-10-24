# Attack protocols and robustness summaries (1.0.0 / 1.1.0)

This module consumes an in-memory `mc.context` supplied by the common graph reader. It defines an experiment and its results, not another persisted graph format. Graph files remain owned by task 1. All implementations below are original MATLAB code from explicit definitions; no external source code has been copied or relicensed. MATLAB built-ins are invoked through the installed R2024b runtime.

## Calling and saving

```matlab
protocol = struct('target','node','strategy','ranked','ranking','adaptive', ...
    'rank_metric',struct('metric_id','degree','parameters',struct()), ...
    'sample_fractions',[0 .25 .5 .75 1]);
trajectory = mc.attack(ctx,protocol, ...
    {'node_count','edge_count','largest_component_size','global_efficiency'},[],1);
summaries = mc.summarize(ctx,trajectory,{'robustness_schneider'});
```

`mc.attack` executes one repeat only. Random attacks or random ties require an explicit seed in `[0,2^32-1]`. The fifth argument is a positive repeat number; the caller supplies an independent seed for each desired random realization. Reusing a seed reproduces the same path. Deterministic calls explicitly store `randomness.used=false` and `algorithm='none'`. Random calls use a private `RandStream('mt19937ar')`, preserving MATLAB's global RNG. The initial uniformly random permutation is sampled without replacement; adaptive ranking is reserved for ranked attacks.

`mc.summarize` binds `ctx.trajectory` at runtime before invoking `mc.compute`. Only summary definitions and parameters belong in the metric configuration identity. The potentially large trajectory, its NaNs and its per-graph observations do not belong there. Direct summary calls also accept `p.trajectory` for small interactive use; that runtime field is intentionally absent from the configuration registry.

The attack includes `input_context_identity` for an in-memory original-graph/mapping consistency check when summarizing. This is separate from task 1's persisted `topology_hash`, which remains authoritative in the result wrapper.

The root runner saves `attack`, `summaries` and scalar/vector results separately in its documented MAT result wrapper. Each repeat retains its own path; averaging repeats is a separate derived analysis. Source graph IDs and topology hashes remain in that wrapper.

## Fully specified semantics

| Field | Values and meaning |
|---|---|
| `version` | `1.0.0` legacy defaults; explicit `1.1.0` for fraction-grid scheduling |
| `target` | `node` or `edge` |
| `strategy` | `external`, `random`, `ranked`, or `source_order` |
| `external_sequence` | Unique original IDs, never residual MATLAB row numbers. Must cover the selected stop count. JSON-safe integers at most `flintmax`. |
| `rank_metric` | Registered `metric_id` plus `parameters`; defaults are materialized before protocol hashing. It must produce a finite, fully valid vector for the target scope and explicit matching IDs. |
| `rank_metric_version` | Resolved to the installed ranking metric's definition version before hashing. An explicitly supplied mismatch is rejected. Empty for non-ranked strategies. |
| `score_order` | `desc` (largest first) or `asc` |
| `tie_break` | `original_id` ascending, `random` uniform continuous keys, or `source_order` |
| `ranking` | `static`: rank once on original graph. `adaptive`: rank current residual graph. |
| `recompute_interval` | Positive number of deletion rounds between rerankings. Initial ranking is at zero. A batch counts as one round. |
| `deletion_mode` | `single`, fixed-integer `batch`, or v1.1.0 `fraction_grid`; single/grid require `batch_size=1` |
| `attack_fractions` | v1.1.0 only: cumulative nondecreasing grid relative to original target count, ending at `stop_fraction`; positive rounded increments drive actual batches. See [grid definition](fraction_grid_attacks.md). |
| `batch_size` | Positive integer; the final batch is truncated to the stop count. All members are chosen from the same pre-batch ranking. |
| `stop_fraction` | Fraction in `[0,1]`; converted to an integer with `rounding` against the original target count. |
| `sample_fractions` | Requested fractions in `[0,1]`, preserving caller order and repeated positions. Empty means no ratio samples. Sampling does not schedule deletions. |
| `rounding` | `floor`, `ceil`, or `nearest` (MATLAB `round`, half away from zero); applied literally to `fraction * original target count`. |
| `sample_policy` | `exact` requires an observed count; `previous`/`next` select an observed count below/above the requested count and label the actual position. No interpolation. |

All fields are included in `mc.protocol_id`, using root canonical JSON identity version `protocol-v1`. Seeds and repeat indices identify runs and are stored separately. The interval in *rounds* is intentional: adaptive batch size 2 with interval 1 and adaptive single deletion with interval 1 can choose different second objects and have different IDs.

Non-ranked strategies require the unused `tie_break` field to retain `original_id`; `source_order` strategy itself determines deletion order without a tie rule. Formula-version changes to a ranking metric change `rank_metric_version` and therefore change the normalized protocol identity.

Source-order attacks and tie breaks require `ctx.source_edge_order_ids`, a verified permutation of all original edge IDs obtained from the graph reader's source-order mapping. Missing mappings raise `mc:MissingSourceOrder`. Canonical storage order is never substituted. The attack works with supplied `ctx.edge_list` row order and its paired `edge_ids`; MATLAB's internal `G.Edges` ordering has no role in deletion decisions.

Node deletion removes incident edges simultaneously. Its `removed_count` counts explicitly attacked nodes; the same state separately records all lost original edge IDs. Edge deletion keeps every node, including newly isolated ones.

## Observations, samples and limits

`states` contains the initial state and every actual deletion-round state. Each row records:

- `removed_count`, `removed_fraction`, `fraction_valid`, `round_index`;
- ordered attacked IDs in that round, removed node IDs and removed edge IDs;
- remaining original node/edge IDs and original node IDs of each surviving edge endpoint;
- current node/edge counts, selected metric result structs (values, axes, IDs, masks, statuses), and state status.

`deleted_ids` concatenates the actual ordered attacks. `ranking_at_removed_count` identifies each reranking. For v1.1.0, `full_single_object_trajectory` is true only when actual observed counts are exactly `0:T0`; a sufficiently fine fraction grid can meet this condition. Legacy v1.0.0 retains its original `batch_size=1` plus full completion check. Partial stopping and batch gaps are never represented as full trajectories. A full edge path has `M+1` states; a full node path has `N+1` states.

`sampled` separately retains requested fraction/count, actual fraction/count, one-based state index (`0` when unavailable), exact-count match flag, status, and metric observations. Repeated requested positions are retained even if rounding maps them to the same state. The sample lookup always refers to this same attack path. An exact request in a batch gap remains `not_computed`.

State and attack completion statuses describe execution: only `failed` or `not_computed` observations make them `partial`. A fully evaluated metric may legitimately be `undefined`, `not_applicable` or partially valid; those individual values and masks remain explicit without preventing verified run completion and resume.

When the attacked set is empty there is one observed state. Its count is zero, fraction is `NaN`, `fraction_valid=false`, and the attack fraction status is `undefined`; all requested fractions map to that count without pretending their numerical fraction is defined. Metric-level masks preserve their separate mathematical domains. In particular, current-normalized global efficiency is undefined for fewer than two nodes; its retention curve therefore also has invalid final endpoints rather than invented zeros.

Total attack cost includes every selected computation and every reranking. Residual rebuilding costs `O(N+M)` per round. Explicit per-state mappings use up to `O(T(N+M))` storage over `T` rounds, in addition to metric outputs (distance matrices can dominate). Use an explicit small selection and test timings before large jobs. There is no automatic approximation or silent sampling shortcut.

## Registered summaries

| Metric ID | Formula and endpoints | Conditions / unavailable states |
|---|---|---|
| `robustness_schneider` | `sum_{Q=1}^N LCC(Q)/N^2` | Full undirected single-node path; original `N>0`; excludes original state and includes empty endpoint. Requires `largest_component_size`. |
| `connectivity_robustness` | `sum_{q=1}^{T0} L_mode(q)/(T0*N0)` | Full undirected edge or directed node/edge path; original denominators positive; directed weak/strong explicit. See [definition/source boundaries](connectivity_robustness.md). |
| `robustness_control_node` | `(1/N) sum_{i=0}^{N-1} ND(i)/(N-i)` | Every single-node count `0:N-1`, `N>0`; empty endpoint not needed. |
| `robustness_control_edge` | `(1/(M+1)) sum_{i=0}^{M} ND(i)/N` | Complete single-edge path, `N>0`; `M=0` is a valid one-term mean. |
| `sampled_curve_auc` | Trapezoidal integral over actual observed fractions | Explicit scalar metric, source `states`/`sampled`, interval endpoints observed; optional division by initial value. Missing values invalidate selected interval; zero initial normalization is undefined. Identical repeated positions are deduplicated for integration only. |
| `first_threshold_fraction` | First observed fraction with value `<= threshold` or `>= threshold` | Includes original state; no interpolation over batch gaps. Unreached is `undefined`, `reached=false`; unavailable earlier observations make first crossing `not_computed`. |
| `efficiency_retention_curve` | `global_efficiency(Q)/global_efficiency(0)` | Initial value finite and nonzero. Preserves invalid observations; does not clip valid ratios. |

The Schneider formula follows [Schneider et al. (2011), Eq. 1](https://doi.org/10.1073/pnas.1009440108). The finite-size values tested here are `(N-1)/(2N)` for a complete graph and `(N-1)/N^2` for a center-first star; asymptotic bounds must not replace those exact test values. Edge attacks, directed interpretations and trapezoidal samples have separate names and are not registered as this formula.

The two control sums follow [Lou, Wang and Chen (2021), Eqs. 4–7](https://doi.org/10.1016/j.cnsns.2021.105780), cross-checked against the [author preprint](https://arxiv.org/pdf/2008.04414). Lower sums mean lower average input fraction. This library retains the selected control model and uses the independently verified driver-count implementation; it does not adopt the paper's simplified `N-rank(A)` expression as a universal exact controllability rule.

`driver_metric_id` is required and limited to `structural_driver_count` or `exact_numeric_driver_count`. Their count concerns general independent input channels, not the minimum number of dedicated actuated nodes. The result retains the source definition/parameters. A structural count can be recomputed directly by this attack runner on residual directed topology. Fixed numerical systems require a separately specified per-step state matrix and deletion rule. Because no such update policy exists in this version, the attack runner rejects `exact_numeric_driver_count` before computing any node or edge attack state, with error `mc:StateMatrixPolicyRequired`. This applies to observed metrics, ranking metrics, and nested `deletion_impact.base_metric` references. An unchanged matrix during edge deletion would otherwise produce a false constant control curve. Independently computed and auditable numerical-system trajectories can be supplied to summary functions, but this attack runner does not create them.

The AUC invokes MATLAB [`trapz`](https://www.mathworks.com/help/matlab/ref/trapz.html), tested in R2024b. Randomness invokes [`RandStream`](https://www.mathworks.com/help/matlab/ref/randstream.html). Efficiency retention uses the source metric defined from [Latora and Marchiori (2001)](https://doi.org/10.1103/PhysRevLett.87.198701); taking the initial ratio is a project-defined reporting convention. The observed threshold is also a project-defined statistic, not a claimed literature percolation estimator.

## Verification

Run `test_attacks` after adding the library and its `tests` directory to the MATLAB path. It checks analytic star, complete-graph, directed-path and undirected-path values; original ID mappings including shuffled edge rows; fixed-sequence endpoints; repeat sampling; source-order refusal; adaptive single/batch differences; recomputation interval identity; rounding; explicit seeds and preserved global RNG; empty graphs; missing ratios and undefined efficiency endpoints. Assertions use exact integers or `1e-14` for small analytic sums. Root integration additionally verifies result MAT and manifest round trips.

## Follow-up interfaces

`mc.attack_curve` accepts a unique metric ID or exact `{metric_id,parameters[,metric_version]}` selector. AUC and threshold summaries accept `metric_parameters`, so weak/strong versions can coexist in one path. Their registered API versions are 1.1.0; the old formulas remain unchanged.

`mc.aggregate_repeats` checks saved seeded inputs before computing matched-axis statistics. `mc.save_repeat_summary` stores a separate derived MAT with provenance and never replaces raw repeats. See [repeat statistics](repeat_statistics.md) for missingness, sample-size, quantile and confidence-interval conventions.
