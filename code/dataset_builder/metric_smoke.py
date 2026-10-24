"""Read actual producer metric fixtures without claiming task-1 graph linkage.

The graph context below comes only from the producer's explicit test descriptions.
It is not an original graph format and never supplies a graph-v1 acceptance claim.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np

from .cache import build_cache, sample_fingerprint, verify_cache
from .config import MetricSelector, SelectionConfig, content_id
from .dataset import TrainingDataset, make_pyg_loader, make_torch_loader
from .models import GraphRecord, MetricArray, MetricRun, PipelineError
from .selection import select_samples
from .source import PROJECT_ROOT, _read_metric_run, file_fingerprint, read_json_object, read_jsonl


def _snapshot(roots: list[Path]) -> dict:
    return {str(path): file_fingerprint(path) for root in roots for path in sorted(root.rglob("*"))
            if path.is_file() and path.suffix in {".json", ".jsonl", ".mat"}}


def _selectors(run: MetricRun) -> dict[str, MetricSelector]:
    selectors = {}
    for source, metrics in [("results", run.metrics), *[(source, [metric for row in rows for metric in row.metrics])
                                                       for source, rows in run.observations.items() if rows]]:
        for metric in metrics:
            selector = MetricSelector(metric.metric_id, metric.metric_version, metric.parameters, metric.scope,
                                      run.metric_set_id, run.protocol_id, observation_source=source,
                                      alignment="by_id" if source != "results" else None)
            signature = {**selector.__dict__}
            alias = f"{source}_{metric.metric_id}_{content_id(signature)[:12]}"
            selectors[alias] = selector
    return selectors


def _verify_projection(run: MetricRun, selector: MetricSelector, projected: MetricArray) -> int:
    """Compare each original logical cell to its derived coordinate, including NaN."""
    if selector.observation_source == "results":
        return 0
    checks = 0
    for index, row in enumerate(run.observations[selector.observation_source]):
        matched = [metric for metric in row.metrics if metric.metric_id == selector.metric_id
                   and metric.metric_version == selector.metric_version and metric.parameters == selector.parameters
                   and metric.scope == selector.scope]
        if not matched or matched[0].metadata.get("shape_unknown"):
            if projected.values.size and np.any(projected.present_mask[index]):
                raise PipelineError("Unobserved metric was filled as a present value")
            continue
        source = matched[0]
        axes = [np.asarray([list(projected.axis_ids[axis]).index(value) for value in source.axis_ids[axis]], dtype=int)
                for axis in source.axis_names]
        selected = np.ix_(*axes) if axes else ()
        values = projected.values[index][selected] if axes else projected.values[index]
        valid = projected.valid_mask[index][selected] if axes else projected.valid_mask[index]
        if not np.array_equal(values, source.values, equal_nan=True) or not np.array_equal(valid, source.valid_mask):
            raise PipelineError("Observation alignment changed a source value or valid_mask")
        checks += source.values.size
    return checks


def run_metric_smoke(output: str | Path, *, workers: int = 2, project_root: Path = PROJECT_ROOT) -> dict:
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    roots = [project_root / "code/graph_analyzer/examples/result_fixtures",
             project_root / "code/graph_analyzer/examples/extension_result_fixtures"]
    before = _snapshot(roots)
    descriptions = read_json_object(roots[0] / "fixture_descriptions.json")
    if descriptions.get("purpose") != "test-only in-memory fixtures; no original graph files":
        raise PipelineError("Metric smoke requires producer-labelled metric-only test fixtures")
    contexts = {fixture["test_identity"]["graph_id"]: fixture for fixture in descriptions["fixtures"]}
    extension = read_json_object(roots[1] / "fixture_description.json")
    if extension.get("purpose") != "Synthetic small in-memory graph; identities are not task1 graph identities":
        raise PipelineError("Extension samples are not marked as synthetic identity fixtures")
    # Direction is explicit in the producer's new example, not inferred from arcs.
    extension_source = project_root / "code/graph_analyzer/examples/robustness_extensions_demo.m"
    expected = "ctx=mc.context(sparse([1 2 3 3 4],[2 3 1 4 2],1,4,4),true);"
    if expected not in extension_source.read_text(encoding="utf-8"):
        raise PipelineError("Extension fixture context changed; update the explicit test description check")
    before[str(extension_source)] = file_fingerprint(extension_source)
    records, samples, counts = [], [], {"compared_observation_values": 0}
    started = time.perf_counter()
    for root in roots:
        rows = read_jsonl(root / "manifests/metrics.jsonl", identity_fields=("graph_id", "metric_set_id", "protocol_id", "run_id"))
        for entry in rows:
            fixture = contexts[entry["graph_id"]] if root == roots[0] else {**extension, "directed": True, "fixture_name": "directed4_followup"}
            directed = fixture["directed"]
            arcs = np.asarray(fixture["arcs_one_based"], dtype=np.uint32).reshape(-1, 2)
            edges = arcs if directed else arcs[arcs[:, 0] < arcs[:, 1]]
            edges = edges[np.lexsort((edges[:, 1], edges[:, 0]))]
            graph = {key: entry[key] for key in ("graph_id", "topology_hash", "origin_graph_id")}
            graph.update(N=fixture["node_count"], M=len(edges), directed=directed, edge_list=edges)
            run = _read_metric_run(root, entry, graph, project_root)
            for metric in [*run.metrics, *[metric for rows in run.observations.values() for row in rows for metric in row.metrics]]:
                metric.validate()
            record = {"fixture_name": fixture["fixture_name"], "run_id": run.run_id, "graph_id": run.graph_id,
                      "protocol_id": run.protocol_id, "status": "passed", "source": entry,
                      "states": len(run.observations.get("states", [])), "sampled": len(run.observations.get("sampled", []))}
            if graph["N"] == 0:
                record["cache_scope"] = "metric decode only; graph-v1 requires N>=1"
            else:
                context_graph = GraphRecord(graph["graph_id"], graph["topology_hash"], graph["origin_graph_id"],
                                            graph["N"], directed, edges, metadata={"metric_only_fixture": True},
                                            source={"fixture_description": str(root), "graph_v1_verified": False})
                selectors = _selectors(run)
                config = SelectionConfig({}, selectors, "keep", "mask", "all")
                sample = select_samples(context_graph, [run], config, "train")[0]
                for alias, selector in selectors.items():
                    counts["compared_observation_values"] += _verify_projection(run, selector, sample.targets[alias])
                samples.append(sample)
                record.update(cache_scope="metric-only described context", sample_id=sample.sample_id,
                              target_count=len(sample.targets))
            records.append(record)
    parse_seconds = time.perf_counter() - started
    provenance = {"fixture_only": True, "scope": "metric-only producer MAT + explicit synthetic graph context",
                  "source_files": before, "graph_v1_verified": False}
    started = time.perf_counter()
    index = build_cache(samples, output / "training", provenance, shard_size=8, compression=None, compression_opts=None)
    write_seconds = time.perf_counter() - started
    verify_cache(index)
    expected_samples = {sample.sample_id: sample for sample in samples}
    loaders = []
    with TrainingDataset(index) as dataset:
        if dataset._handles:
            raise PipelineError("Lazy Dataset opened shards during initialization")
        for sample in dataset:
            if sample_fingerprint(sample) != sample_fingerprint(expected_samples[sample.sample_id]):
                raise PipelineError("Metric cache roundtrip lost source information")
        for name, make_loader in (("torch", make_torch_loader), ("pyg", make_pyg_loader)):
            for worker_count in sorted({0, workers}):
                seen = []
                started = time.perf_counter()
                for batch in make_loader(dataset, batch_size=3, num_workers=worker_count, shuffle=False):
                    for alias, tensor in batch["targets"].items():
                        for i, sample_id in enumerate(batch["sample_id"]):
                            metric = expected_samples[sample_id].targets.get(alias)
                            if metric is None or metric.metadata.get("shape_unknown"):
                                if tensor["present_mask"][i].any():
                                    raise PipelineError("Batch fabricated an absent metric")
                                continue
                            slot = (i, *[slice(0, size) for size in metric.values.shape])
                            if not np.array_equal(tensor["raw_values"][slot].numpy(), metric.values, equal_nan=True):
                                raise PipelineError("Batch changed raw metric values")
                            if not np.array_equal(tensor["valid_mask"][slot].numpy(), metric.valid_mask):
                                raise PipelineError("Batch changed valid_mask")
                            presence = np.ones_like(metric.valid_mask) if metric.present_mask is None else metric.present_mask
                            if not np.array_equal(tensor["present_mask"][slot].numpy(), presence):
                                raise PipelineError("Batch changed source presence")
                    seen.extend(batch["sample_id"])
                if sorted(seen) != sorted(expected_samples):
                    raise PipelineError("Worker loading duplicated or omitted samples")
                loaders.append({"backend": name, "workers": worker_count, "sample_count": len(seen),
                                "elapsed_seconds_including_startup": time.perf_counter() - started})
    after = _snapshot(roots)
    after[str(extension_source)] = file_fingerprint(extension_source)
    if before != after:
        raise PipelineError("Producer inputs changed during metric smoke")
    report = {"status": "passed", "scope": provenance["scope"], "graph_v1_verified": False,
              "input_files_unchanged": True, "source_files": before, "passed": len(records), "rejected": 0,
              "cached_samples": len(samples), **counts, "records": records, "loaders": loaders,
              "parse_and_select_seconds": parse_seconds, "cache_write_seconds": write_seconds,
              "index": str(index), "limits": "Test contexts have synthetic IDs and are not task-1 original graph files; no training."}
    (output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--workers", type=int, default=2)
    args = parser.parse_args()
    report = run_metric_smoke(args.output, workers=args.workers)
    print(json.dumps({key: value for key, value in report.items() if key not in {"source_files", "records"}}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
