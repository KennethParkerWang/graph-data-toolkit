"""Compare six cache layouts using the same five accepted producer samples.

This is a small static-fixture measurement, not a production throughput claim.
All files written by this entrypoint live under artifacts/producer_layouts_v2.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import importlib.metadata
import json
from pathlib import Path, PurePosixPath
import platform
import sys
import time
from typing import Any
import uuid

import numpy as np

from .cache import build_cache, load_index, sample_fingerprint
from .config import canonical_json
from .dataset import TrainingDataset
from .models import PipelineError, TrainingSample
from .pipeline import load_selection
from .selection import select_samples
from .source import PROJECT_ROOT, SourceDataset, file_fingerprint, read_json_object
from .splits import build_split_manifest, validate_split_manifest


ARTIFACT_ROOT = PROJECT_ROOT / "code/dataset_builder/artifacts"


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise PipelineError(message)


def latest_smoke_report() -> Path:
    candidates = [*ARTIFACT_ROOT.glob("producer_smoke_*/report.json"),
                  *(ARTIFACT_ROOT / "producer_layouts_v2").glob("producer_smoke_*/report.json")]
    reports = sorted(candidates,
                     key=lambda path: path.stat().st_mtime_ns, reverse=True)
    for path in reports:
        report = read_json_object(path)
        if report.get("status") == "passed" and report.get("acceptance_level") == "producer_graph_v1_static_metric_v1":
            return path.resolve()
    raise PipelineError("No passed producer static smoke report was found")


def _smoke_path(value: str, report_path: Path, smoke: dict[str, Any]) -> Path:
    """Locate copied project files without changing the accepted report bytes.

    The report's output must match its current artifacts-relative directory.
    Only that recorded project prefix and the three known module names may be
    relocated. User-provided external sources retain their original paths.
    """
    tail = report_path.resolve().relative_to(ARTIFACT_ROOT.resolve()).parent.parts
    recorded_output = PurePosixPath(str(smoke["output"]).replace("\\", "/"))
    suffix_length = len(tail) + 2
    output_parts = recorded_output.parts
    if (len(output_parts) > suffix_length
            and output_parts[-suffix_length] in {"data_pipeline", "dataset_builder"}
            and output_parts[-suffix_length + 1] == "artifacts"
            and output_parts[-len(tail):] == tail):
        old_root = PurePosixPath(*output_parts[:-suffix_length])
        reference = PurePosixPath(str(value).replace("\\", "/"))
        if reference.is_relative_to(old_root):
            relative = reference.relative_to(old_root)
            names = {"data_pipeline": "dataset_builder", "dataset_builder": "dataset_builder",
                     "graph_generation": "graph_builder", "graph_builder": "graph_builder",
                     "metric_computation": "graph_analyzer", "graph_analyzer": "graph_analyzer"}
            if relative.parts and relative.parts[0] in names:
                module_root = PROJECT_ROOT / "code" / names[relative.parts[0]]
                path = module_root.joinpath(*relative.parts[1:]).resolve()
                _require(path.is_relative_to(module_root.resolve()), "Recorded smoke path escapes its module root")
                return path
    path = Path(value)
    return (path if path.is_absolute() else PROJECT_ROOT / path).resolve()


def _collect_inputs(report_path: Path, smoke: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Check raw producer/copy bytes against the accepted smoke report first."""
    expected = {}
    for path, fingerprint in smoke["staging"]["inputs_before"].items():
        relocated = str(_smoke_path(path, report_path, smoke))
        _require(relocated not in expected or expected[relocated] == fingerprint,
                 "Conflicting accepted fingerprints for a relocated producer input")
        expected[relocated] = fingerprint
    dataset = _smoke_path(smoke["staging"]["dataset"], report_path, smoke)
    for row in smoke["staging"]["copied_files"]:
        path = (dataset / row["relative_path"]).resolve()
        _require(path.is_relative_to(dataset), "Copied producer input escapes its dataset root")
        expected[str(path)] = {key: row[key] for key in ("file_sha256", "file_bytes")}
    for path, fingerprint in expected.items():
        _require(file_fingerprint(path) == fingerprint, f"Producer input changed since smoke acceptance: {path}")
    for path in (report_path, report_path.parent / "selection.json", _smoke_path(smoke["split_manifest"], report_path, smoke),
                 _smoke_path(smoke["cache_index"], report_path, smoke)):
        expected[str(path.resolve())] = file_fingerprint(path)
    return expected


def _read_samples(smoke: dict[str, Any], report_path: Path) -> tuple[list[TrainingSample], dict[str, Any], SourceDataset]:
    dataset = _smoke_path(smoke["staging"]["dataset"], report_path, smoke)
    source = SourceDataset(dataset)
    selection = load_selection(report_path.parent / "selection.json")
    split = read_json_object(_smoke_path(smoke["split_manifest"], report_path, smoke))
    validate_split_manifest(split)
    _require(canonical_json(build_split_manifest(source.list_graphs(), split["config"])) == canonical_json(split),
             "Recorded split does not match the producer dataset")
    snapshot = source.source_snapshot()
    selectors = [*selection.feature_keys.values(), *selection.target_keys.values()]
    samples = []
    for graph_id, partition in sorted(split["assignments"].items()):
        graph = source.read_graph(graph_id)
        runs = source.read_runs(graph_id, selectors=selectors)
        for sample in select_samples(graph, runs, selection, partition):
            sample.provenance["split_id"] = split["split_id"]
            samples.append(sample)
    _require(len(samples) == 5 and len({sample.graph.graph_id for sample in samples}) == 5,
             "Layout comparison requires the five accepted producer graphs")
    baseline = load_index(_smoke_path(smoke["cache_index"], report_path, smoke))
    recorded = {row["sample_id"]: row["fingerprint"] for row in baseline["samples"]}
    fingerprints = {sample.sample_id: sample_fingerprint(sample) for sample in samples}
    _require(fingerprints == recorded, "Source samples differ from the accepted smoke cache fingerprints")
    provenance = {
        "benchmark_version": "producer-layouts-v2", "source_snapshot": snapshot,
        "selection": selection.to_dict(), "selection_id": selection.config_id,
        "split_manifest": split, "normalization": {"method": "none"},
        "accepted_smoke_report": str(report_path), "accepted_smoke_report_fingerprint": file_fingerprint(report_path),
        "accepted_sample_fingerprints": fingerprints,
    }
    return samples, provenance, source


def _measure_layout(samples: list[TrainingSample], provenance: dict[str, Any], output: Path, *,
                    shard_size: int, compression: str | None) -> dict[str, Any]:
    label = f"shards_{shard_size}_{compression or 'none'}"
    start = time.perf_counter()
    index_path = build_cache(iter(samples), output / label, provenance,
                             shard_size=shard_size, compression=compression,
                             compression_opts=1 if compression == "gzip" else None)
    write_seconds = time.perf_counter() - start
    expected = [sample_fingerprint(sample) for sample in samples]
    warm = []
    start = time.perf_counter()
    with TrainingDataset(index_path) as reader:
        _require(not reader._handles and len(reader) == len(samples), "Reader must initialize lazily with all samples")
        for i, fingerprint in enumerate(expected):
            _require(sample_fingerprint(reader[i]) == fingerprint, f"Cold roundtrip mismatch in {label}")
        cold_seconds = time.perf_counter() - start
        for _ in range(3):
            start = time.perf_counter()
            for i, fingerprint in enumerate(expected):
                _require(sample_fingerprint(reader[i]) == fingerprint, f"Warm roundtrip mismatch in {label}")
            warm.append(time.perf_counter() - start)
        cache_id, content_id = reader.index["cache_id"], reader.index["content_id"]
    shard_paths = sorted(index_path.parent.glob("shard_*.h5"))
    shard_bytes = sum(path.stat().st_size for path in shard_paths)
    index_bytes = index_path.stat().st_size
    return {
        "layout": label, "shard_size": shard_size, "compression": compression,
        "compression_opts": 1 if compression == "gzip" else None,
        "sample_count": len(samples), "shard_count": len(shard_paths),
        "shard_bytes": shard_bytes, "index_bytes": index_bytes, "total_cache_bytes": shard_bytes + index_bytes,
        "write_seconds": write_seconds, "cold_new_reader_seconds": cold_seconds,
        "warm_reused_reader_seconds": warm, "warm_median_seconds": float(np.median(warm)),
        "index": str(index_path), "cache_id": cache_id, "content_id": content_id,
        "fingerprints_verified": True,
    }


def run_benchmark(smoke_report: str | Path | None = None) -> dict[str, Any]:
    report_path = Path(smoke_report).resolve() if smoke_report is not None else latest_smoke_report()
    smoke = read_json_object(report_path)
    _require(smoke.get("status") == "passed" and smoke.get("acceptance_level") == "producer_graph_v1_static_metric_v1",
             "Provide a passed producer graph/static-metric smoke report")
    _require(report_path.is_relative_to(ARTIFACT_ROOT.resolve()), "Smoke report must be within code/dataset_builder/artifacts")
    inputs_before = _collect_inputs(report_path, smoke)
    samples, provenance, source = _read_samples(smoke, report_path)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
    output = ARTIFACT_ROOT / "producer_layouts_v2" / f"run_{stamp}_{uuid.uuid4().hex[:8]}"
    output.mkdir(parents=True, exist_ok=False)
    result: dict[str, Any] = {
        "status": "running", "benchmark_version": "producer-layouts-v2", "output": str(output),
        "accepted_smoke_report": str(report_path), "dataset": str(source.root),
        "sample_count": len(samples), "node_count": sum(sample.graph.num_nodes for sample in samples),
        "original_edge_count": sum(sample.graph.num_edges for sample in samples),
        "sample_fingerprints": provenance["accepted_sample_fingerprints"], "inputs_before": inputs_before,
        "measurement_limit": "One write and one new-reader pass per layout, followed by three passes through the same reader. Cold does not evict the OS page cache. Timings include source-derived sample fingerprint verification and cache checksum/content validation. Five tiny static graphs cannot determine production settings.",
        "attack_trajectories_matched_to_task1_graphs": False, "layouts": [],
        "environment": {"python": platform.python_version(), "platform": platform.platform(),
                        **{name: importlib.metadata.version(name) for name in ("numpy", "scipy", "h5py")}},
    }
    failure: Exception | None = None
    try:
        for shard_size in (2, 8):
            for compression in (None, "lzf", "gzip"):
                result["layouts"].append(_measure_layout(samples, provenance, output,
                                                         shard_size=shard_size, compression=compression))
        _require(len({row["content_id"] for row in result["layouts"]}) == 1,
                 "Cache content identity differs between layouts")
        choice = min(result["layouts"], key=lambda row: (row["total_cache_bytes"], row["warm_median_seconds"], row["write_seconds"]))
        fastest_write = min(result["layouts"], key=lambda row: row["write_seconds"])
        fastest_warm = min(result["layouts"], key=lambda row: row["warm_median_seconds"])
        result["recommendation"] = {
            "scope": "Only this five-graph static producer sample; rerun representative large graphs and trajectories before production decisions.",
            "rule": "Choose smallest total cache bytes, breaking ties by warm-read median then write time; expose speed winners separately.",
            "selected_layout": choice["layout"], "shard_size": choice["shard_size"],
            "compression": choice["compression"], "compression_opts": choice["compression_opts"],
            "total_cache_bytes": choice["total_cache_bytes"], "write_seconds": choice["write_seconds"],
            "cold_new_reader_seconds": choice["cold_new_reader_seconds"],
            "warm_median_seconds": choice["warm_median_seconds"],
            "fastest_measured_write_layout": fastest_write["layout"],
            "fastest_measured_warm_layout": fastest_warm["layout"],
        }
        _require(canonical_json(source.source_snapshot()) == canonical_json(provenance["source_snapshot"]),
                 "Source dataset/schema snapshot changed during layout comparison")
        result["status"] = "passed"
    except Exception as exc:
        failure = exc
        result["status"] = "failed"
        result["error"] = f"{type(exc).__name__}: {exc}"
    finally:
        try:
            after = {path: file_fingerprint(path) for path in inputs_before}
            result["inputs_after"] = after
            result["source_bytes_unchanged"] = after == inputs_before
            _require(result["source_bytes_unchanged"], "Input files changed during layout comparison")
        except Exception as exc:
            failure = failure or exc
            result["status"] = "failed"
            result["integrity_error"] = f"{type(exc).__name__}: {exc}"
        output_report = output / "report.json"
        output_report.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    if failure is not None:
        raise PipelineError(f"Producer layout benchmark failed; inspect {output_report}: {failure}") from failure
    return {"report": str(output_report), **result}


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--smoke-report", type=Path, help="Passed static producer report; defaults to the newest passed report")
    args = parser.parse_args(argv)
    try:
        result = run_benchmark(args.smoke_report)
    except (PipelineError, OSError, KeyError, ImportError) as exc:
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        return 2
    print(json.dumps({key: result[key] for key in ("status", "report", "layouts", "recommendation", "source_bytes_unchanged")},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
