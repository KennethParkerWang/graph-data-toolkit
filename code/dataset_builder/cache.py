"""Immutable, content-addressed HDF5 training cache (no raw MAT interpretation)."""

from __future__ import annotations

import hashlib
import json
import math
import os
import uuid
from pathlib import Path
from typing import Any, Iterable

import h5py
import numpy as np

from .models import GraphRecord, MetricArray, PipelineError, TrainingSample

TRAINING_SCHEMA = "training-v1"
CONVERSION_VERSION = "data-pipeline-v2"


def _jsonable(value: Any) -> Any:
    if isinstance(value, np.ndarray):
        return {"__array__": _jsonable(value.tolist()), "dtype": value.dtype.str, "shape": list(value.shape)}
    if isinstance(value, np.generic):
        return _jsonable(value.item())
    if isinstance(value, float) and not math.isfinite(value):
        return {"__nonfinite__": repr(value)}
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, dict):
        if not all(isinstance(key, str) for key in value):
            raise PipelineError("Metadata JSON keys must be strings")
        return {key: _jsonable(item) for key, item in value.items()}
    if isinstance(value, (tuple, list)):
        return [_jsonable(item) for item in value]
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    raise PipelineError(f"Metadata cannot serialize {type(value).__name__}")


def _restore(value: Any) -> Any:
    if isinstance(value, list):
        return [_restore(item) for item in value]
    if isinstance(value, dict):
        if set(value) == {"__array__", "dtype", "shape"}:
            return np.asarray(_restore(value["__array__"]), dtype=value["dtype"]).reshape(value["shape"])
        if set(value) == {"__nonfinite__"}:
            return float(value["__nonfinite__"])
        return {key: _restore(item) for key, item in value.items()}
    return value


def canonical_json(value: Any) -> str:
    return json.dumps(_jsonable(value), ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def _digest(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def compute_cache_id(provenance: dict[str, Any], *, shard_size: int = 128,
                     compression: str | None = "gzip", compression_opts: Any = 1,
                     conversion_version: str = CONVERSION_VERSION) -> str:
    """Identity from source SHA/config/split/transform provenance and layout.

    Callers must include their complete source snapshots and configuration in
    provenance. A separate content_id also binds actual sample fingerprints.
    """
    return _digest({"schema_version": TRAINING_SCHEMA, "conversion_version": conversion_version,
                    "provenance": provenance, "options": {"shard_size": shard_size,
                    "compression": compression, "compression_opts": compression_opts if compression == "gzip" else None}})


def file_sha256(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _array_identity(value: np.ndarray | None) -> Any:
    if value is None:
        return None
    value = np.ascontiguousarray(value)
    # Object arrays contain process-local pointers, not reproducible values.
    content = canonical_json(value.tolist()).encode("utf-8") if value.dtype.hasobject else value.tobytes()
    return {"dtype": value.dtype.str, "shape": list(value.shape), "sha256": hashlib.sha256(content).hexdigest()}


def _metric_identity(metric: MetricArray) -> dict[str, Any]:
    metric.validate()
    result = {
        "metric_id": metric.metric_id, "metric_version": metric.metric_version,
        "parameters": metric.parameters, "scope": metric.scope, "axis_names": metric.axis_names,
        "status": metric.status, "reason": metric.reason, "metadata": metric.metadata,
        "values": _array_identity(metric.values), "valid_mask": _array_identity(metric.valid_mask),
        "node_ids": _array_identity(metric.node_ids), "edge_ids": _array_identity(metric.edge_ids),
        "axis_positions": {key: _array_identity(value) for key, value in metric.axis_positions.items()},
        "axis_ids": {key: _array_identity(value) for key, value in metric.axis_ids.items()},
    }
    if metric.present_mask is not None:
        result["present_mask"] = _array_identity(metric.present_mask)
    return result


def sample_fingerprint(sample: TrainingSample) -> str:
    """Hash all scientific content, definitions, transforms and source provenance."""
    sample.validate()
    graph = sample.graph
    return _digest({
        "sample_id": sample.sample_id, "split": sample.split, "provenance": sample.provenance,
        "graph": {"graph_id": graph.graph_id, "topology_hash": graph.topology_hash,
                  "origin_graph_id": graph.origin_graph_id, "num_nodes": graph.num_nodes,
                  "directed": graph.directed, "edge_list": _array_identity(graph.edge_list),
                  "metadata": graph.metadata, "source": graph.source,
                  "source_edge_order": _array_identity(graph.source_edge_order)},
        "features": {key: _metric_identity(value) for key, value in sample.features.items()},
        "targets": {key: _metric_identity(value) for key, value in sample.targets.items()},
    })


def _write_json(group: h5py.Group, key: str, value: Any) -> None:
    group.create_dataset(key, data=canonical_json(value), dtype=h5py.string_dtype("utf-8"))


def _read_json(group: h5py.Group, key: str) -> Any:
    return _restore(json.loads(group[key].asstr()[()]))


def _write_array(group: h5py.Group, key: str, value: np.ndarray, compression: str | None, compression_opts: Any,
                 *, allow_text: bool = False) -> None:
    value = np.asarray(value)
    if allow_text and value.dtype.kind in "UO" and all(isinstance(item, str) for item in value.flat):
        dataset = group.create_dataset(key, data=value.astype(object), dtype=h5py.string_dtype("utf-8"))
        dataset.attrs["numpy_dtype"] = value.dtype.str
        return
    if value.dtype.kind not in "biuf":
        raise PipelineError(f"{key}: cache arrays must be real numeric data")
    options = {}
    if value.ndim and value.size and compression is not None:
        options = {"compression": compression, "shuffle": True}
        if compression_opts is not None:
            options["compression_opts"] = compression_opts
    group.create_dataset(key, data=value, **options)


def _read_array(dataset: h5py.Dataset) -> np.ndarray:
    if "numpy_dtype" in dataset.attrs:
        dtype = np.dtype(dataset.attrs["numpy_dtype"])
        if dtype.kind not in "UO":
            raise PipelineError("Text coordinate dataset has an invalid numpy_dtype")
        return np.asarray(dataset.asstr()[()], dtype=dtype)
    return np.asarray(dataset[()])


def _write_metric(group: h5py.Group, key: str, metric: MetricArray, compression: str | None, compression_opts: Any) -> None:
    _write_json(group, "definition", {
        "key": key, "metric_id": metric.metric_id, "metric_version": metric.metric_version,
        "parameters": metric.parameters, "scope": metric.scope, "axis_names": metric.axis_names,
        "status": metric.status, "reason": metric.reason, "metadata": metric.metadata,
    })
    for name in ("values", "valid_mask", "present_mask", "node_ids", "edge_ids"):
        value = getattr(metric, name)
        if value is not None:
            _write_array(group, name, value, compression, compression_opts)
    for name in ("axis_positions", "axis_ids"):
        axis_group = group.create_group(name)
        for i, (axis, value) in enumerate(sorted(getattr(metric, name).items())):
            entry = axis_group.create_group(str(i))
            _write_json(entry, "name", axis)
            _write_array(entry, "values", value, compression, compression_opts, allow_text=name == "axis_ids")


def _read_metric(group: h5py.Group) -> tuple[str, MetricArray]:
    definition = _read_json(group, "definition")
    key = definition.pop("key")
    definition["axis_names"] = tuple(definition["axis_names"])
    for name in ("values", "valid_mask", "present_mask", "node_ids", "edge_ids"):
        definition[name] = _read_array(group[name]) if name in group else None
    for name in ("axis_positions", "axis_ids"):
        definition[name] = {_read_json(entry, "name"): _read_array(entry["values"]) for entry in group[name].values()}
    metric = MetricArray(**definition)
    metric.validate()
    return key, metric


def _write_sample(group: h5py.Group, sample: TrainingSample, compression: str | None, compression_opts: Any) -> None:
    graph = sample.graph
    _write_json(group, "record", {
        "sample_id": sample.sample_id, "split": sample.split, "provenance": sample.provenance,
        "graph_id": graph.graph_id, "topology_hash": graph.topology_hash,
        "origin_graph_id": graph.origin_graph_id, "num_nodes": graph.num_nodes,
        "directed": graph.directed, "metadata": graph.metadata, "source": graph.source,
    })
    _write_array(group, "edge_list", graph.edge_list, compression, compression_opts)
    if graph.source_edge_order is not None:
        _write_array(group, "source_edge_order", graph.source_edge_order, compression, compression_opts)
    for name in ("features", "targets"):
        metric_group = group.create_group(name)
        for i, (key, metric) in enumerate(sorted(getattr(sample, name).items())):
            _write_metric(metric_group.create_group(str(i)), key, metric, compression, compression_opts)


def read_sample(group: h5py.Group) -> TrainingSample:
    record = _read_json(group, "record")
    sample_fields = {key: record.pop(key) for key in ("sample_id", "split", "provenance")}
    record["edge_list"] = group["edge_list"][()]
    record["source_edge_order"] = group["source_edge_order"][()] if "source_edge_order" in group else None
    return TrainingSample(graph=GraphRecord(**record), **sample_fields,
                          **{name: dict(_read_metric(entry) for entry in group[name].values()) for name in ("features", "targets")})


def load_index(path: str | Path, expected_provenance: dict[str, Any] | None = None) -> dict[str, Any]:
    """Read only index metadata, without opening any shard."""
    try:
        index = json.loads(Path(path).read_text(encoding="utf-8"))
        checksum = index.pop("index_sha256")
        if checksum != _digest(index):
            raise PipelineError("Training index checksum mismatch")
        if index["schema_version"] != TRAINING_SCHEMA or index["conversion_version"] not in {"data-pipeline-v1", CONVERSION_VERSION}:
            raise PipelineError("Unsupported training cache version")
        if expected_provenance is not None and canonical_json(expected_provenance) != canonical_json(_restore(index["provenance"])):
            raise PipelineError("Cache provenance mismatch: sources, selection or split changed")
        ids = [row["sample_id"] for row in index["samples"]]
        if len(ids) != len(set(ids)):
            raise PipelineError("Duplicate sample IDs in training index")
        if index["sample_count"] != len(ids) or not ids:
            raise PipelineError("Training index sample_count is invalid")
        if any(row["shard"] not in index["shards"] for row in index["samples"]):
            raise PipelineError("Training index refers to an unknown shard")
        expected_id = compute_cache_id(index["provenance"], conversion_version=index["conversion_version"], **index["options"])
        if index["cache_id"] != expected_id:
            raise PipelineError("Training cache identity mismatch")
        if index["content_id"] != _digest(sorted((row["sample_id"], row["fingerprint"]) for row in index["samples"])):
            raise PipelineError("Training content identity mismatch")
        return index
    except (OSError, ValueError, KeyError, TypeError) as exc:
        if isinstance(exc, PipelineError):
            raise
        raise PipelineError(f"Cannot read training index {path}: {exc}") from exc


def _safe_shard_path(root: Path, relative: str) -> Path:
    path = (root / relative).resolve()
    if path.parent != root.resolve() or not relative.startswith("shard_") or path.suffix != ".h5":
        raise PipelineError(f"Invalid shard path: {relative}")
    return path


def verify_cache(index_path: str | Path) -> dict[str, Any]:
    index_path = Path(index_path)
    index = load_index(index_path)
    for relative, info in index["shards"].items():
        path = _safe_shard_path(index_path.parent, relative)
        if not path.is_file() or path.stat().st_size != info["file_bytes"] or file_sha256(path) != info["file_sha256"]:
            raise PipelineError(f"Missing or corrupt cache shard: {path}")
        with h5py.File(path, "r") as handle:
            if handle.attrs.get("schema_version") != TRAINING_SCHEMA or handle.attrs.get("cache_id") != index["cache_id"]:
                raise PipelineError(f"Shard identity mismatch: {path}")
    return index


def build_cache(samples: Iterable[TrainingSample], output_dir: str | Path, provenance: dict[str, Any], *,
                shard_size: int = 128, compression: str | None = "gzip", compression_opts: Any = 1,
                cache_id: str | None = None) -> Path:
    """Stream samples to shards; validate every round trip before publishing index.

    ``output_dir`` is one cache directory. Its existing index is immutable: a
    repeated identical build verifies and reuses it; a conflicting build fails.
    Cache IDs include options and caller-supplied source, selection,
    normalization and split provenance; content_id binds full sample content.
    The input iterable is never
    materialized as a graph list.
    """
    if isinstance(shard_size, bool) or not isinstance(shard_size, int) or shard_size < 1:
        raise PipelineError("shard_size must be a positive integer")
    if compression not in (None, "gzip", "lzf"):
        raise PipelineError("compression must be None, gzip or lzf")
    if compression != "gzip":
        compression_opts = None
    root = Path(output_dir).resolve()
    root.mkdir(parents=True, exist_ok=True)
    lock = root / ".writer.lock"
    try:
        descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError as exc:
        raise PipelineError(f"Cache already has a writer: {lock}") from exc
    temporary: list[Path] = []
    handle: h5py.File | None = None
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(f"pid={os.getpid()}\n")
        options = {"shard_size": shard_size, "compression": compression, "compression_opts": compression_opts}
        rows, ids, shard_names = [], set(), []
        token = uuid.uuid4().hex
        for i, sample in enumerate(samples):
            if not sample.sample_id or sample.sample_id in ids:
                raise PipelineError(f"Empty or duplicate sample_id: {sample.sample_id}")
            ids.add(sample.sample_id)
            fingerprint = sample_fingerprint(sample)
            if i % shard_size == 0:
                if handle is not None:
                    handle.close()
                name = f"shard_{i // shard_size + 1:05d}.h5"
                shard_names.append(name)
                temp = root / f".{name}.{token}.tmp"
                temporary.append(temp)
                handle = h5py.File(temp, "w")
                handle.attrs["schema_version"] = TRAINING_SCHEMA
                handle.create_group("samples")
            group_name = f"samples/{i:09d}"
            _write_sample(handle.create_group(group_name), sample, compression, compression_opts)
            rows.append({"sample_id": sample.sample_id, "graph_id": sample.graph.graph_id, "split": sample.split,
                         "shard": name, "group": group_name, "fingerprint": fingerprint})
        if handle is not None:
            handle.close()
            handle = None
        if not rows:
            raise PipelineError("Cannot publish an empty training cache")
        derived_id = compute_cache_id(provenance, **options)
        content_id = _digest(sorted((row["sample_id"], row["fingerprint"]) for row in rows))
        if cache_id is not None and cache_id != derived_id:
            raise PipelineError("Requested cache_id does not match source/config/content identity")
        shard_info = {}
        shard_rows: dict[str, list[dict[str, Any]]] = {name: [] for name in shard_names}
        for row in rows:
            shard_rows[row["shard"]].append(row)
        for name, temp in zip(shard_names, temporary):
            with h5py.File(temp, "r+") as stream:
                stream.attrs["cache_id"] = derived_id
                for row in shard_rows[name]:
                    if sample_fingerprint(read_sample(stream[row["group"]])) != row["fingerprint"]:
                        raise PipelineError(f"Cache round-trip mismatch: {row['sample_id']}")
                stream.flush()
            shard_info[name] = {"file_sha256": file_sha256(temp), "file_bytes": temp.stat().st_size}
        index_path = root / "index.json"
        if index_path.exists():
            existing = verify_cache(index_path)
            if existing["cache_id"] != derived_id or existing["content_id"] != content_id:
                raise PipelineError(f"Conflicting cache exists at {root}; choose a new directory")
            return index_path
        if any((root / name).exists() for name in shard_names):
            raise PipelineError(f"Unindexed shard files exist at {root}; refusing to overwrite")
        index = {"schema_version": TRAINING_SCHEMA, "conversion_version": CONVERSION_VERSION,
                 "cache_id": derived_id, "content_id": content_id, "provenance": provenance, "options": options,
                 "sample_count": len(rows), "samples": rows, "shards": shard_info}
        index["index_sha256"] = _digest(index)
        temp_index = root / f".index.{token}.tmp"
        temporary.append(temp_index)
        temp_index.write_text(canonical_json(index) + "\n", encoding="utf-8")
        load_index(temp_index)
        for name, temp in zip(shard_names, temporary):
            os.replace(temp, root / name)
        os.replace(temp_index, index_path)
        return index_path
    finally:
        if handle is not None:
            handle.close()
        for path in temporary:
            if path.parent == root and path.exists():
                path.unlink()
        lock.unlink(missing_ok=True)
