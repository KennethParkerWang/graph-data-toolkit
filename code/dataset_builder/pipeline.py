"""Explicit, streaming orchestration of the producer adapters and training cache."""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Any, Iterator

from .cache import build_cache, compute_cache_id
from .config import SelectionConfig, canonical_json
from .models import PipelineError, TrainingSample
from .normalization import FeatureNormalizer
from .run_storage import RunWorkspace, file_reference
from .selection import select_samples
from .source import SourceDataset, read_json_object
from .splits import build_split_manifest, validate_split_manifest, write_split_manifest


def load_selection(path: str | Path) -> SelectionConfig:
    return SelectionConfig.from_dict(read_json_object(path))


def _create_split(dataset_root: str | Path, config: dict[str, Any]) -> Path:
    source = SourceDataset(dataset_root)
    manifest = build_split_manifest(source.list_graphs(), config)
    return write_split_manifest(source.root / "splits" / f"{manifest['split_id']}.json", manifest)


def _check_split(source: SourceDataset, manifest: dict[str, Any]) -> None:
    validate_split_manifest(manifest)
    current = build_split_manifest(source.list_graphs(), manifest["config"])
    if canonical_json(current) != canonical_json(manifest):
        raise PipelineError("Split manifest does not match the current graph identities; create a new fixed split")


def _samples(
    source: SourceDataset, config: SelectionConfig, manifest: dict[str, Any],
    *, split: str | None = None,
) -> Iterator[TrainingSample]:
    selectors = [*config.feature_keys.values(), *config.target_keys.values()]
    for graph_id, partition in sorted(manifest["assignments"].items()):
        if split is not None and split != partition:
            continue
        graph = source.read_graph(graph_id)
        runs = source.read_runs(graph_id, selectors=selectors)
        yield from select_samples(graph, runs, config, partition)


def _validate_dataset(dataset_root: str | Path, config: SelectionConfig) -> dict[str, Any]:
    """Read selected values, masks and axes; do not merely check file existence."""
    source = SourceDataset(dataset_root)
    counts = {"graphs": 0, "runs": 0, "samples": 0, "features": 0, "targets": 0, "invalid_values": 0}
    selectors = [*config.feature_keys.values(), *config.target_keys.values()]
    initial = source.source_snapshot()
    for identity in source.list_graphs():
        graph = source.read_graph(identity["graph_id"])
        runs = source.read_runs(graph.graph_id, selectors=selectors)
        counts["graphs"] += 1
        counts["runs"] += len(runs)
        for sample in select_samples(graph, runs, config, "val"):
            counts["samples"] += 1
            for kind in ("features", "targets"):
                metrics = getattr(sample, kind)
                counts[kind] += len(metrics)
                for metric in metrics.values():
                    metric.validate()
                    counts["invalid_values"] += int((~metric.valid_mask).sum())
    if canonical_json(source.source_snapshot()) != canonical_json(initial):
        raise PipelineError("Source metadata changed during validation; retry against a committed snapshot")
    if not counts["graphs"] or not counts["samples"]:
        raise PipelineError("Validation requires at least one graph and selected sample")
    return {"selection_id": config.config_id, "counts": counts, "source_snapshot": initial}


def _convert_dataset(
    dataset_root: str | Path, config: SelectionConfig, split_path: str | Path, *,
    normalization: str, shard_size: int, compression: str | None, compression_opts: int | None = None,
) -> Path:
    """Two passes only when fitting is requested; no graph corpus in memory."""
    if normalization not in {"none", "standardize"}:
        raise PipelineError("normalization must explicitly be none or standardize")
    source = SourceDataset(dataset_root)
    manifest = read_json_object(split_path)
    _check_split(source, manifest)
    snapshot = source.source_snapshot()
    normalizer = None
    if normalization == "standardize":
        normalizer = FeatureNormalizer().fit(_samples(source, config, manifest, split="train"))
    provenance = {
        "source_snapshot": snapshot,
        "selection": config.to_dict(),
        "selection_id": config.config_id,
        "split_manifest": manifest,
        "normalization": normalizer.to_dict() if normalizer is not None else {"method": "none"},
        "pipeline_version": "0.2.0",
    }
    options = {"shard_size": shard_size, "compression": compression, "compression_opts": compression_opts}
    cache_id = compute_cache_id(provenance, **options)

    def stream() -> Iterator[TrainingSample]:
        count = 0
        for sample in _samples(source, config, manifest):
            count += 1
            sample.provenance["split_id"] = manifest["split_id"]
            yield normalizer.transform(sample) if normalizer is not None else sample
        if not count:
            raise PipelineError("No samples remain after explicit selection and split exclusion")
        if canonical_json(source.source_snapshot()) != canonical_json(snapshot):
            raise PipelineError("Source metadata changed during conversion; no cache index may be committed")

    return build_cache(stream(), source.root / "training" / cache_id, provenance, cache_id=cache_id, **options)


def create_split(dataset_root: str | Path, config: dict[str, Any], *, run_root: str | Path | None = None) -> Path:
    """Publish a fixed split and record the task separately from its identity."""
    with RunWorkspace(dataset_root, {"task": "split", "split": config}, run_root=run_root) as job:
        path = _create_split(dataset_root, config)
        job.result({"split_manifest": file_reference(path), "split_id": read_json_object(path)["split_id"]})
        return path


def validate_dataset(dataset_root: str | Path, config: SelectionConfig, *,
                     run_root: str | Path | None = None) -> dict[str, Any]:
    """Validate selected data and save a task report with source identities."""
    with RunWorkspace(dataset_root, {"task": "validate", "selection": config.to_dict()}, run_root=run_root) as job:
        result = _validate_dataset(dataset_root, config)
        job.result({}, {"counts": result["counts"], "selection_id": result["selection_id"],
                       "source_snapshot_sha256": hashlib.sha256(canonical_json(result['source_snapshot']).encode('utf-8')).hexdigest()})
        return {**result, "job_directory": str(job.directory)}


def convert_dataset(
    dataset_root: str | Path, config: SelectionConfig, split_path: str | Path, *,
    normalization: str, shard_size: int, compression: str | None, compression_opts: int | None = None,
    run_root: str | Path | None = None,
) -> Path:
    """Build the authoritative training cache and retain per-task evidence."""
    parameters = {"task": "convert", "selection": config.to_dict(), "normalization": normalization,
                  "shard_size": shard_size, "compression": compression, "compression_opts": compression_opts}
    with RunWorkspace(dataset_root, parameters, inputs=(split_path,), run_root=run_root) as job:
        index = _convert_dataset(dataset_root, config, split_path, normalization=normalization,
                                 shard_size=shard_size, compression=compression, compression_opts=compression_opts)
        metadata = read_json_object(index)
        job.result({"cache_index": file_reference(index), "cache_id": metadata["cache_id"],
                    "split_id": metadata["provenance"]["split_manifest"]["split_id"]},
                   {"sample_count": metadata["sample_count"]})
        return index
