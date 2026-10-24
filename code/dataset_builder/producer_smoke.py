"""Small, byte-preserving graph-v1/metric-v1 interoperability acceptance.

Run ``python -m dataset_builder.producer_smoke`` from the code directory. Inputs
are copied from the two producers into a unique owned artifact directory;
only the copied dataset receives split manifests and training caches.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.metadata
import json
from pathlib import Path
import platform
import shutil
import sys
import time
from typing import Any
import uuid

import numpy as np

from .cache import sample_fingerprint
from .config import MetricSelector, SelectionConfig
from .dataset import TrainingDataset, make_pyg_loader, make_torch_loader
from .models import PipelineError, TrainingSample
from .pipeline import convert_dataset, create_split, validate_dataset
from .selection import select_samples
from .source import PROJECT_ROOT, SourceDataset, file_fingerprint, read_json_object, read_jsonl


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise PipelineError(message)


def default_metric_source() -> Path:
    """Resolve task 2's recorded fixtures relative to its module root."""
    module_root = PROJECT_ROOT / "code/graph_analyzer"
    report = read_json_object(module_root / "validation/graph_adapter_report.json")
    _require(report.get("status") == "passed", "Task 2 graph adapter report is not passed")
    path = Path(report["fixture_root"])
    path = (path if path.is_absolute() else module_root / path).resolve()
    _require(path.is_relative_to((module_root / "validation").resolve()),
             "Task 2 graph adapter fixtures must be within its validation directory")
    return path


def _input_files(graph_source: Path, metric_source: Path) -> tuple[list[tuple[Path, str]], list[Path]]:
    """Choose published inputs only; never copy corruption fixtures or caches."""
    graphs = read_jsonl(graph_source / "manifests/graphs.jsonl", identity_fields=("graph_id",))
    copied_graphs = read_jsonl(metric_source / "manifests/graphs.jsonl", identity_fields=("graph_id",))
    metrics = read_jsonl(metric_source / "manifests/metrics.jsonl",
                         identity_fields=("graph_id", "metric_set_id", "protocol_id", "run_id"))
    _require(bool(graphs), "Producer graph manifest is empty")
    _require((graph_source / "manifests/graphs.jsonl").read_bytes()
             == (metric_source / "manifests/graphs.jsonl").read_bytes(),
             "Producer graph manifests are not byte-identical")
    by_id = {row["graph_id"]: row for row in copied_graphs}
    _require(set(by_id) == {row["graph_id"] for row in metrics},
             "Producer graph and metric ID sets differ")
    for row in metrics:
        _require(all(row[key] == by_id[row["graph_id"]][key]
                     for key in ("graph_id", "topology_hash", "origin_graph_id")),
                 "Producer metric and graph identities differ")
        _require(row["status"] == "complete" and row["protocol_id"] == "",
                 "This smoke entrypoint requires complete static producer results")
    files = [(graph_source / "dataset.json", "dataset.json")]
    for name in ("graphs", "metrics", "configs", "manifests"):
        directory = metric_source / name
        _require(directory.is_dir(), f"Missing producer input directory: {directory}")
        for path in sorted(directory.rglob("*")):
            _require(not path.is_symlink() and path.resolve().is_relative_to(metric_source),
                     f"Producer input escapes its root: {path}")
            if path.is_file():
                files.append((path, path.relative_to(metric_source).as_posix()))
    originals = [graph_source / "manifests/graphs.jsonl"]
    for row in graphs:
        original = (graph_source / row["path"]).resolve()
        copied = (metric_source / row["path"]).resolve()
        _require(original.is_relative_to(graph_source) and copied.is_relative_to(metric_source),
                 "Producer graph path escapes its root")
        expected = {key: row[key] for key in ("file_bytes", "file_sha256")}
        _require(file_fingerprint(original) == expected and file_fingerprint(copied) == expected,
                 f"Producer graph bytes disagree with their manifest: {row['graph_id']}")
        originals.append(original)
    return files, originals


def copy_producer_inputs(graph_source: Path, metric_source: Path, target: Path) -> dict[str, Any]:
    """Copy immutable producer files once and record before/after checksums."""
    graph_source, metric_source, target = (Path(path).resolve() for path in (graph_source, metric_source, target))
    _require(not target.is_relative_to(graph_source) and not target.is_relative_to(metric_source),
             "Smoke output must not be inside a producer input directory")
    files, originals = _input_files(graph_source, metric_source)
    input_paths = sorted({path for path, _ in files} | set(originals))
    inputs_before = {str(path): file_fingerprint(path) for path in input_paths}
    target.mkdir(parents=True, exist_ok=False)
    copied = []
    for source, relative in files:
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        expected = inputs_before[str(source)]
        _require(file_fingerprint(source) == expected and file_fingerprint(destination) == expected,
                 f"Source changed or copy verification failed: {source}")
        copied.append({"source": str(source), "relative_path": relative, **expected})
    return {"graph_source": str(graph_source), "metric_source": str(metric_source),
            "dataset": str(target), "copied_files": copied, "inputs_before": inputs_before}


def _selection(dataset: Path) -> SelectionConfig:
    rows = read_jsonl(dataset / "manifests/metrics.jsonl",
                     identity_fields=("graph_id", "metric_set_id", "protocol_id", "run_id"))
    sets = {row["metric_set_id"] for row in rows}
    _require(len(sets) == 1, "Smoke fixtures must publish one static metric set")
    _require(len({row["graph_id"] for row in rows}) == len(rows),
             "Smoke fixtures must publish exactly one static run per graph")
    metric_set = next(iter(sets))
    published = read_json_object(dataset / f"configs/metric_sets/{metric_set}.json")["configuration"]
    definitions = {item["metric_id"]: item for item in published["selections"]}

    def selector(metric_id: str, scope: str) -> MetricSelector:
        item = definitions[metric_id]
        return MetricSelector(metric_id, item["metric_version"], item["parameters"], scope, metric_set, "")

    return SelectionConfig(
        {"degree": selector("degree", "node"), "node_count": selector("node_count", "graph")},
        {name: selector(name, "graph") for name in
         ("edge_count", "largest_component_size", "global_efficiency")},
        "keep", "error", "all",
        {row["graph_id"]: {"published_static": {metric_set: row["run_id"]}} for row in rows},
    )


def _check_batch(batch: dict[str, Any], expected: list[TrainingSample], kind: str) -> None:
    _require(batch["sample_id"] == [sample.sample_id for sample in expected], "Batch sample order changed")
    _require(batch["graph_id"] == [sample.graph.graph_id for sample in expected], "Batch graph IDs changed")
    sizes = np.asarray([sample.graph.num_nodes for sample in expected], dtype=np.int64)
    offsets = np.concatenate(([0], np.cumsum(sizes)))
    np.testing.assert_array_equal(batch["num_nodes"].numpy(), sizes)
    np.testing.assert_array_equal(batch["node_ptr"].numpy(), offsets)
    np.testing.assert_array_equal(batch["directed"].numpy(), [sample.graph.directed for sample in expected])
    np.testing.assert_array_equal(batch["original_node_id"].numpy(),
                                  np.concatenate([np.arange(1, n + 1) for n in sizes]))
    edges, edge_ids = [], []
    for i, sample in enumerate(expected):
        graph = sample.graph
        canonical = graph.edge_list.astype(np.int64).T - 1
        original_ids = np.arange(1, graph.num_edges + 1, dtype=np.int64)
        if not graph.directed:
            canonical = np.concatenate((canonical, canonical[::-1]), axis=1)
            original_ids = np.concatenate((original_ids, original_ids))
        edges.append(canonical + offsets[i])
        edge_ids.append(original_ids)
        for role in ("features", "targets"):
            for alias, metric in getattr(sample, role).items():
                actual = batch[role][alias]
                slot = (i, *(slice(0, size) for size in metric.values.shape))
                np.testing.assert_array_equal(actual["raw_values"][slot].numpy(), metric.values)
                np.testing.assert_array_equal(actual["valid_mask"][slot].numpy(), metric.valid_mask)
                expected_present = (metric.present_mask if metric.present_mask is not None
                                    else np.ones(metric.values.shape, dtype=bool))
                np.testing.assert_array_equal(actual["present_mask"][slot].numpy(), expected_present)
                outside = actual["valid_mask"][i].numpy().copy()
                outside[tuple(slice(0, size) for size in metric.values.shape)] = False
                _require(not bool(outside.any()), f"Padded elements marked valid in {alias}")
                _require(actual["status"][i] == metric.status and actual["reason"][i] == metric.reason,
                         f"Metric status or reason changed in {alias}")
                for id_name in ("node_ids", "edge_ids"):
                    ids = getattr(metric, id_name)
                    if ids is not None:
                        np.testing.assert_array_equal(actual[id_name]["values"][i, :len(ids)].numpy(), ids)
    np.testing.assert_array_equal(batch["edge_index"].numpy(), np.concatenate(edges, axis=1))
    np.testing.assert_array_equal(batch["original_edge_id"].numpy(), np.concatenate(edge_ids))
    _require(batch["edge_index"].device.type == "cpu", "Smoke loader unexpectedly moved data to a GPU")
    if kind == "pyg":
        pyg = batch["graph_batch"]
        _require(pyg.num_nodes == int(sizes.sum()), "PyG dropped explicit isolated nodes")
        np.testing.assert_array_equal(pyg.ptr.numpy(), offsets)
        np.testing.assert_array_equal(pyg.edge_index.numpy(), batch["edge_index"].numpy())
        np.testing.assert_array_equal(pyg.original_edge_id.numpy(), batch["original_edge_id"].numpy())


def _loader_measurement(index: Path, expected: list[TrainingSample], *, kind: str,
                        workers: int, warm_passes: int) -> dict[str, Any]:
    factory = make_pyg_loader if kind == "pyg" else make_torch_loader
    seconds = []
    batches = 0
    with TrainingDataset(index) as dataset:
        started = time.perf_counter()
        loader = factory(dataset, batch_size=3, num_workers=workers, shuffle=False,
                         persistent_workers=workers > 0)
        try:
            for epoch in range(warm_passes + 1):
                if epoch:
                    started = time.perf_counter()
                seen = 0
                batches = 0
                for batch in loader:
                    count = len(batch["sample_id"])
                    _check_batch(batch, expected[seen:seen + count], kind)
                    seen += count
                    batches += 1
                _require(seen == len(expected), "Loader did not visit each sample exactly once")
                seconds.append(time.perf_counter() - started)
        finally:
            # Releasing the DataLoader closes its persistent worker iterator.
            del loader
    median = float(np.median(seconds[1:]))
    return {"kind": kind, "workers": workers, "batch_size": 3, "samples": len(expected),
            "batches_per_pass": batches, "cold_new_loader_seconds": seconds[0],
            "warm_reused_loader_seconds": seconds[1:], "warm_median_seconds": median,
            "warm_samples_per_second": len(expected) / median,
            "warm_nodes_per_second": sum(sample.graph.num_nodes for sample in expected) / median,
            "warm_original_edges_per_second": sum(sample.graph.num_edges for sample in expected) / median,
            "persistent_workers": workers > 0}


def _verify_sources(staging: dict[str, Any]) -> dict[str, Any]:
    after = {path: file_fingerprint(Path(path)) for path in staging["inputs_before"]}
    copies_after = {row["relative_path"]: file_fingerprint(Path(staging["dataset"]) / row["relative_path"])
                    for row in staging["copied_files"]}
    sources_unchanged = after == staging["inputs_before"]
    copies_unchanged = all(copies_after[row["relative_path"]]
                           == {key: row[key] for key in ("file_bytes", "file_sha256")}
                           for row in staging["copied_files"])
    return {"inputs_after": after, "copied_inputs_after": copies_after,
            "upstream_bytes_unchanged": sources_unchanged, "copied_input_bytes_unchanged": copies_unchanged}


def run_producer_smoke(output_root: str | Path, *, graph_source: str | Path | None = None,
                       metric_source: str | Path | None = None, workers: int = 2,
                       warm_passes: int = 3) -> dict[str, Any]:
    """Run five producer graphs through selection, split, cache and CPU loaders."""
    _require(isinstance(workers, int) and not isinstance(workers, bool) and workers >= 0,
             "workers must be a nonnegative integer")
    _require(isinstance(warm_passes, int) and not isinstance(warm_passes, bool) and warm_passes >= 1,
             "warm_passes must be a positive integer")
    graph_source = Path(graph_source or PROJECT_ROOT / "code/graph_builder/examples/schema_v1").resolve()
    metric_source = Path(metric_source).resolve() if metric_source is not None else default_metric_source()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
    output = Path(output_root).resolve() / f"producer_smoke_{stamp}_{uuid.uuid4().hex[:8]}"
    _require(output.is_relative_to((PROJECT_ROOT / "code/dataset_builder/artifacts").resolve()),
             "Producer smoke artifacts must stay within code/dataset_builder/artifacts")
    dataset = output / "dataset"
    staging = copy_producer_inputs(graph_source, metric_source, dataset)
    report: dict[str, Any] = {
        "status": "running", "acceptance_level": "producer_graph_v1_static_metric_v1",
        "created_utc": datetime.now(timezone.utc).isoformat(), "output": str(output),
        "staging": staging, "attack_trajectories_matched_to_task1_graphs": False,
        "limitation": "Five tiny producer fixtures only. Attack result fixtures retain synthetic graph IDs and are not joined to these graphs.",
        "measurement_limit": "Cold means a new reader or loader, not an evicted OS page cache. Timings include checksum/content validation and batch assertions; warm loader passes reuse workers. These are not large-dataset throughput measurements.",
    }
    failure: Exception | None = None
    try:
        config = _selection(dataset)
        (output / "selection.json").write_text(json.dumps(config.to_dict(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        start = time.perf_counter()
        report["validation"] = validate_dataset(dataset, config)
        report["validation_seconds"] = time.perf_counter() - start
        _require(report["validation"]["counts"]["graphs"] == 5
                 and report["validation"]["counts"]["samples"] == 5,
                 "Expected the five published graph-v1 sample graphs")
        split_path = create_split(dataset, {
            "mode": "size", "conflict": "error", "unassigned": "error",
            "size_ranges": {"train": [4, None], "val": [2, 3], "test": [1, 1]},
        })
        split = read_json_object(split_path)
        source = SourceDataset(dataset)
        expected = []
        graph_checks = []
        selectors = [*config.feature_keys.values(), *config.target_keys.values()]
        for graph_id, partition in sorted(split["assignments"].items()):
            graph = source.read_graph(graph_id)
            runs = source.read_runs(graph_id, selectors=selectors)
            selected = select_samples(graph, runs, config, partition)
            _require(len(selected) == 1, f"Expected one static sample for {graph_id}")
            sample = selected[0]
            sample.provenance["split_id"] = split["split_id"]
            _require(float(sample.features["node_count"].values.item()) == graph.num_nodes,
                     "Stored node_count disagrees with explicit graph N")
            _require(float(sample.targets["edge_count"].values.item()) == graph.num_edges,
                     "Stored edge_count disagrees with graph M")
            np.testing.assert_array_equal(sample.features["degree"].node_ids, np.arange(1, graph.num_nodes + 1))
            if graph.origin_graph_id in split["assignments"]:
                _require(partition == split["assignments"][graph.origin_graph_id],
                         "A derived graph and its original were assigned to different splits")
            expected.append(sample)
            graph_checks.append({"graph_id": graph_id, "origin_graph_id": graph.origin_graph_id,
                                 "topology_hash": graph.topology_hash, "N": graph.num_nodes,
                                 "M": graph.num_edges, "directed": graph.directed, "split": partition,
                                 "isolated_nodes": graph.num_nodes - int(np.unique(graph.edge_list).size),
                                 "source_edge_order": None if graph.source_edge_order is None else graph.source_edge_order.tolist()})
        _require(any(row["M"] == 0 for row in graph_checks) and any(row["isolated_nodes"] for row in graph_checks),
                 "Producer acceptance fixtures must include empty edges and isolated nodes")
        _require({row["directed"] for row in graph_checks} == {False, True},
                 "Producer acceptance fixtures must include both graph directions")
        report.update({"graphs": graph_checks, "split_manifest": str(split_path), "split_id": split["split_id"],
                       "partition_counts": {name: list(split["assignments"].values()).count(name) for name in ("train", "val", "test")}})
        start = time.perf_counter()
        index = convert_dataset(dataset, config, split_path, normalization="none", shard_size=2, compression=None)
        report["conversion_seconds"] = time.perf_counter() - start
        report["cache_index"] = str(index)
        report["cache_file_bytes"] = sum(path.stat().st_size for path in index.parent.glob("shard_*.h5"))
        reads = []
        with TrainingDataset(index) as reader:
            _require(not reader._handles, "TrainingDataset initialization opened an HDF5 shard")
            _require(len(reader) == len(expected), "Cache sample count changed")
            for _ in range(warm_passes + 1):
                start = time.perf_counter()
                for i, wanted in enumerate(expected):
                    actual = reader[i]
                    _require(sample_fingerprint(actual) == sample_fingerprint(wanted),
                             f"Cache roundtrip changed a selected sample: {wanted.sample_id}")
                reads.append(time.perf_counter() - start)
        report["direct_read"] = {"cold_new_reader_seconds": reads[0], "warm_reused_reader_seconds": reads[1:],
                                 "warm_median_seconds": float(np.median(reads[1:]))}
        report["loaders"] = [_loader_measurement(index, expected, kind=kind, workers=count, warm_passes=warm_passes)
                             for kind in ("torch", "pyg") for count in sorted({0, workers})]
        report["environment"] = {"python": platform.python_version(), "platform": platform.platform(),
                                  **{name: importlib.metadata.version(name) for name in
                                     ("numpy", "scipy", "h5py", "torch", "torch-geometric")}}
        report["status"] = "passed"
    except Exception as exc:
        failure = exc
        report["status"] = "failed"
        report["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        try:
            report["source_integrity"] = _verify_sources(staging)
            if not (report["source_integrity"]["upstream_bytes_unchanged"]
                    and report["source_integrity"]["copied_input_bytes_unchanged"]):
                raise PipelineError("Producer input bytes changed during the smoke run")
        except Exception as exc:
            failure = failure or exc
            report["status"] = "failed"
            report["source_integrity_error"] = f"{type(exc).__name__}: {exc}"
        report_path = output / "report.json"
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    if failure is not None:
        raise PipelineError(f"Producer smoke failed; inspect {report_path}: {failure}") from failure
    return {"report": str(report_path), **report}


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--graph-source", type=Path)
    parser.add_argument("--metric-source", type=Path)
    parser.add_argument("--output-root", type=Path, default=PROJECT_ROOT / "code/dataset_builder/artifacts")
    parser.add_argument("--workers", type=int, default=2)
    parser.add_argument("--warm-passes", type=int, default=3)
    args = parser.parse_args(argv)
    try:
        report = run_producer_smoke(args.output_root, graph_source=args.graph_source,
                                    metric_source=args.metric_source, workers=args.workers,
                                    warm_passes=args.warm_passes)
    except (PipelineError, OSError, KeyError, ImportError) as exc:
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    print(json.dumps({key: report[key] for key in
                      ("status", "report", "cache_index", "partition_counts", "loaders")},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
