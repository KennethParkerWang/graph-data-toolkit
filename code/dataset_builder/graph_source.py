"""Strict, lazy consumer of task 1's published graph-v1 files.

The producer's cross-language canonicalizer remains the authority for recipe
and scientific-content serialization.  This adapter adds per-record validation
and never rewrites a source file or infers completion from directory contents.
"""

from __future__ import annotations

from functools import lru_cache
import hashlib
import importlib.util
from pathlib import Path
from types import ModuleType
from typing import Any, Mapping

import numpy as np
from scipy import sparse
from scipy.io.matlab import mat_struct

from .models import GraphRecord, PipelineError


VERIFIER_RELATIVE_PATH = Path("code/graph_builder/validation/verify_graph_io.py")
GRAPH_FIELDS = {
    "schema_version", "graph_id", "topology_hash", "origin_graph_id", "N", "M",
    "directed", "A", "edge_list", "meta",
}
GRAPH_MANIFEST_FIELDS = {
    "graph_id", "origin_graph_id", "topology_hash", "path", "N", "M", "directed",
    "model", "generator_id", "schema_version", "implementation_version",
    "file_sha256", "file_bytes", "scientific_sha256", "created_utc",
}
META_FIELDS = {
    "model", "generator_id", "parameters", "rng", "implementation_version",
    "implementation_sha256", "source", "created_utc", "matlab_version",
    "recipe_json", "source_edge_order_available",
}
NON_SCIENTIFIC_META = {
    "created_utc", "matlab_version", "elapsed_seconds", "duration_seconds",
    "generation_elapsed_seconds", "recipe_json",
}


@lru_cache(maxsize=4)
def _import_producer_verifier(path: str, mtime_ns: int, size: int) -> ModuleType:
    """Import only the installed task-1 verifier; do not invoke its corpus scan."""
    spec = importlib.util.spec_from_file_location("_dataset_builder_graph_v1_verifier", path)
    if spec is None or spec.loader is None:
        raise PipelineError(f"Cannot import the graph-v1 producer verifier: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for name in ("canonical", "numeric", "text", "struct"):
        if not callable(getattr(module, name, None)):
            raise PipelineError(f"Producer verifier is missing its published {name} helper: {path}")
    return module


def producer_verifier(project_root: str | Path) -> ModuleType:
    path = Path(project_root).resolve() / VERIFIER_RELATIVE_PATH
    if not path.is_file():
        raise PipelineError(f"Published graph-v1 Python validator unavailable: {path}")
    stat = path.stat()
    return _import_producer_verifier(str(path), stat.st_mtime_ns, stat.st_size)


def _integer(value: Any, field: str, minimum: int, maximum: int | None = None) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise PipelineError(f"Graph manifest {field} must be an integer >= {minimum}")
    if maximum is not None and value > maximum:
        raise PipelineError(f"Graph manifest {field} exceeds its graph-v1 type range")
    return value


def validate_graph_entry(root: str | Path, row: Mapping[str, Any]) -> None:
    from .source import resolve_source_path, validate_sha256

    missing = GRAPH_MANIFEST_FIELDS - set(row)
    if missing:
        raise PipelineError(f"Graph manifest missing fields: {sorted(missing)}")
    if row["schema_version"] != "graph-v1":
        raise PipelineError(f"Unsupported graph manifest schema: {row['schema_version']}")
    for field in ("graph_id", "origin_graph_id", "topology_hash", "file_sha256", "scientific_sha256"):
        validate_sha256(row[field], field=field)
    _integer(row["N"], "N", 1, np.iinfo(np.uint32).max)
    _integer(row["M"], "M", 0, np.iinfo(np.uint64).max)
    _integer(row["file_bytes"], "file_bytes", 1)
    if not isinstance(row["directed"], bool):
        raise PipelineError("Graph manifest directed must be boolean")
    maximum_edges = row["N"] * (row["N"] - 1)
    if not row["directed"]:
        maximum_edges //= 2
    if row["M"] > maximum_edges:
        raise PipelineError("Graph manifest M exceeds the simple graph edge bound")
    for field in ("model", "generator_id", "implementation_version", "created_utc"):
        if not isinstance(row[field], str) or not row[field]:
            raise PipelineError(f"Graph manifest {field} must be a nonempty string")
    expected = f"graphs/{row['graph_id'][:2]}/{row['graph_id']}.mat"
    if row["path"] != expected:
        raise PipelineError(f"Graph path does not follow graph-v1: {row['path']}")
    if not resolve_source_path(root, row["path"]).is_file():
        raise PipelineError(f"Missing source graph file: {row['path']}")


def read_graph_manifest(root: str | Path) -> list[dict[str, Any]]:
    """Read committed identity metadata only, with no MAT reads or hashes."""
    from .source import read_jsonl

    rows = read_jsonl(Path(root) / "manifests/graphs.jsonl", identity_fields=("graph_id",))
    for row in rows:
        validate_graph_entry(root, row)
    return rows


def read_dataset_description(root: str | Path) -> dict[str, Any]:
    """Use the published descriptor; do not invent a dataset ID for loose MATs."""
    from .source import file_fingerprint, read_json_object, resolve_source_path, validate_sha256

    path = Path(root) / "dataset.json"
    if not path.is_file():
        raise PipelineError(
            f"Missing producer dataset description: {path}. Graph I/O alone does not "
            "publish dataset metadata; provide the producer's dataset.json."
        )
    descriptor = read_json_object(path)
    for field in ("dataset_id", "created_utc", "description"):
        if not isinstance(descriptor.get(field), str) or not descriptor[field]:
            raise PipelineError(f"dataset.json requires a nonempty {field}")
    for field, expected in (
        ("graph_schema_version", "graph-v1"),
        ("graph_root", "graphs"),
        ("graph_manifest", "manifests/graphs.jsonl"),
    ):
        if descriptor.get(field) != expected:
            raise PipelineError(f"dataset.json {field} must be {expected!r} for graph-v1")
    batch_fields = {
        "generation_config", "generation_config_sha256", "generation_config_file_sha256",
        "implementation_sha256", "implementation_version",
    }
    if batch_fields & set(descriptor):
        missing = batch_fields - set(descriptor)
        if missing:
            raise PipelineError(f"Batch dataset.json requires all generation fields; missing: {sorted(missing)}")
        if descriptor["generation_config"] != "configs/generation.json":
            raise PipelineError("dataset.json generation_config must be 'configs/generation.json'")
        for field in ("generation_config_sha256", "generation_config_file_sha256", "implementation_sha256"):
            validate_sha256(descriptor[field], field=f"dataset.json {field}")
        if not isinstance(descriptor["implementation_version"], str) or not descriptor["implementation_version"]:
            raise PipelineError("dataset.json implementation_version must be a nonempty string")
        config_path = resolve_source_path(root, descriptor["generation_config"])
        if not config_path.is_file():
            raise PipelineError(f"Missing generation configuration: {config_path}")
        before = file_fingerprint(config_path)
        if before["file_sha256"] != descriptor["generation_config_file_sha256"]:
            raise PipelineError("Generation configuration file SHA-256 differs from dataset.json")
        configuration = read_json_object(config_path)
        version = configuration.get("schema_version")
        if isinstance(version, bool) or not isinstance(version, (int, float)) or version != 2:
            raise PipelineError("Generation configuration schema_version must be numeric 2")
        if configuration.get("dataset_id") != descriptor["dataset_id"]:
            raise PipelineError("Generation configuration dataset_id differs from dataset.json")
        if configuration.get("output_dir") != "..":
            raise PipelineError("Generation configuration snapshot output_dir must be '..'")
        if file_fingerprint(config_path) != before:
            raise PipelineError("Generation configuration changed while being parsed; reopen SourceDataset")
        # generation_config_sha256 is the producer's normalized MATLAB identity,
        # not a digest of Python-reformatted JSON.  Validate its syntax and keep
        # it verbatim; the independently verified file digest binds the snapshot.
    return descriptor


def _validate_metadata(value: Any, context: str = "meta") -> None:
    """Reject unsupported data before canonicalization or native conversion."""
    if isinstance(value, mat_struct):
        for field in value._fieldnames:
            _validate_metadata(getattr(value, field), f"{context}.{field}")
        return
    if not isinstance(value, np.ndarray) or sparse.issparse(value):
        raise PipelineError(f"{context} must contain only graph-v1 MATLAB metadata types")
    if value.dtype.kind in "US":
        if value.size and (value.size != 1 or value.ndim > 2):
            raise PipelineError(f"{context} must be a MATLAB char row")
        return
    if value.dtype.kind == "O":
        for member in value.ravel(order="F"):
            _validate_metadata(member, context)
        return
    if value.dtype.name not in {
        "bool", "float64", "float32", "uint8", "uint16", "uint32", "uint64",
        "int8", "int16", "int32", "int64",
    } or not np.all(np.isfinite(value)):
        raise PipelineError(f"{context} must contain finite, real, supported MATLAB arrays")


def read_graph_v1(
    root: str | Path, entry: Mapping[str, Any], *, project_root: str | Path,
) -> GraphRecord:
    """Validate every graph-v1 identity and scientific field, then adapt one graph."""
    from .source import (
        _load_mat, _mat_native, file_fingerprint, require_schema, validate_sha256,
        verify_source_file,
    )

    schema = require_schema("graph", project_root)
    validate_graph_entry(root, entry)
    path = verify_source_file(root, entry)
    producer = producer_verifier(project_root)
    saved = {key: value for key, value in _load_mat(path).items() if not key.startswith("__")}
    if not GRAPH_FIELDS <= set(saved) or set(saved) - GRAPH_FIELDS - {"source_edge_order"}:
        raise PipelineError("Graph-v1 MAT has missing or unknown top-level fields")
    try:
        n = int(producer.numeric(saved["N"], "uint32", (1, 1)).item())
        m = int(producer.numeric(saved["M"], "uint64", (1, 1)).item())
        directed = bool(producer.numeric(saved["directed"], "bool", (1, 1)).item())
        edges = producer.numeric(saved["edge_list"], "uint32", (m, 2))
        if n < 1 or (n, m, directed) != (entry["N"], entry["M"], entry["directed"]):
            raise PipelineError("Graph MAT and manifest N/M/directed disagree")
        for field in ("schema_version", "graph_id", "origin_graph_id", "topology_hash"):
            if producer.text(saved[field]) != entry[field]:
                raise PipelineError(f"Graph MAT and manifest {field} disagree")
        if m and (
            np.any(edges < 1) or np.any(edges > n)
            or not np.array_equal(np.lexsort((edges[:, 1], edges[:, 0])), np.arange(m))
            or np.any(np.all(edges[1:] == edges[:-1], axis=1))
            or np.any(edges[:, 0] == edges[:, 1])
        ):
            raise PipelineError("Graph edge_list must be unique, sorted, loop-free original 1..N IDs")
        if not directed and np.any(edges[:, 0] >= edges[:, 1]):
            raise PipelineError("Undirected edge_list must store source < target")
        adjacency = saved["A"]
        if (
            not sparse.issparse(adjacency) or adjacency.shape != (n, n)
            or adjacency.dtype not in (np.dtype("bool"), np.dtype("uint8"))
            or not np.all(adjacency.data == 1) or np.any(adjacency.diagonal())
        ):
            raise PipelineError("Graph A must be N x N sparse logical with zero diagonal")
        u, v = edges.astype(np.int64).T - 1
        expected = sparse.csr_matrix((np.ones(m, dtype=bool), (u, v)), shape=(n, n))
        if not directed:
            expected = expected + expected.T
        if adjacency.nnz != (m if directed else 2 * m) or (adjacency.astype(bool) != expected).nnz:
            raise PipelineError("Graph A and canonical edge_list disagree")
        topology_digest = hashlib.sha256(f"topology-v1\n{n}\n{int(directed)}\n{m}\n".encode("utf-8"))
        for offset in range(0, m, 65536):
            block = "".join(f"{int(left)},{int(right)}\n" for left, right in edges[offset:offset + 65536])
            topology_digest.update(block.encode("utf-8"))
        if topology_digest.hexdigest() != entry["topology_hash"]:
            raise PipelineError("Graph topology_hash disagrees with N/direction/edge_list")

        meta = producer.struct(saved["meta"])
        if not META_FIELDS <= set(meta._fieldnames):
            raise PipelineError(f"Graph meta missing fields: {sorted(META_FIELDS - set(meta._fieldnames))}")
        _validate_metadata(meta)
        for field in ("model", "generator_id", "implementation_version", "created_utc", "matlab_version", "recipe_json"):
            if not producer.text(getattr(meta, field)):
                raise PipelineError(f"Graph meta.{field} must be nonempty")
        for field in ("model", "generator_id", "implementation_version"):
            if producer.text(getattr(meta, field)) != entry[field]:
                raise PipelineError(f"Graph MAT and manifest {field} disagree")
        validate_sha256(producer.text(meta.implementation_sha256), field="meta.implementation_sha256")
        producer.struct(meta.parameters)
        rng = producer.struct(meta.rng)
        if not {"algorithm", "seed"} <= set(rng._fieldnames) or not producer.text(rng.algorithm):
            raise PipelineError("Graph meta.rng requires algorithm and seed")
        seed = np.asarray(rng.seed)
        if (seed.shape != (1, 1) or seed.dtype.kind not in "iuf"
                or seed.item() < 0 or seed.item() > np.iinfo(np.uint32).max or seed.item() != int(seed.item())):
            raise PipelineError("Graph meta.rng.seed must be a scalar nonnegative uint32-range integer")
        source = np.asarray(meta.source)
        if source.dtype.kind in "US":
            if not producer.text(source):
                raise PipelineError("Graph meta.source must be nonempty")
        elif not source.size or not all(isinstance(item, mat_struct) for item in source.ravel()):
            raise PipelineError("Graph meta.source must be a character row or struct")
        available = bool(producer.numeric(meta.source_edge_order_available, "bool", (1, 1)).item())
        if available != ("source_edge_order" in saved):
            raise PipelineError("Graph source_edge_order availability disagrees")
        edge_order = None
        if available:
            edge_order = producer.numeric(saved["source_edge_order"], "uint64", (m, 1)).reshape(-1)
            if not np.array_equal(np.sort(edge_order), np.arange(1, m + 1, dtype=np.uint64)):
                raise PipelineError("Graph source_edge_order must permute original edge IDs")

        recipe_text = producer.text(meta.recipe_json)
        if hashlib.sha256(recipe_text.encode("utf-8")).hexdigest() != entry["graph_id"]:
            raise PipelineError("Graph graph_id disagrees with saved recipe_json bytes")
        recipe = {field: getattr(meta, field) for field in (
            "model", "generator_id", "parameters", "rng", "implementation_version", "implementation_sha256",
        )}
        recipe.update({field: saved[field] for field in ("schema_version", "directed", "topology_hash")})
        if entry["origin_graph_id"] != entry["graph_id"]:
            if "transformation" not in meta._fieldnames:
                raise PipelineError("Derived graph requires meta.transformation")
            recipe["origin_graph_id"] = saved["origin_graph_id"]
            recipe["transformation"] = meta.transformation
        if producer.canonical(recipe) != recipe_text:
            raise PipelineError("Graph saved recipe_json disagrees with scientific identity fields")
        scientific = {field: saved[field] for field in (
            "schema_version", "graph_id", "origin_graph_id", "topology_hash", "N", "M", "directed",
        )}
        scientific["meta"] = {field: getattr(meta, field) for field in meta._fieldnames if field not in NON_SCIENTIFIC_META}
        if available:
            scientific["source_edge_order"] = saved["source_edge_order"]
        digest = hashlib.sha256(producer.canonical(scientific).encode("utf-8")).hexdigest()
        if digest != entry["scientific_sha256"]:
            raise PipelineError("Graph scientific_sha256 disagrees with metadata/source edge order")
    except PipelineError:
        raise
    except (AttributeError, KeyError, ValueError, TypeError, OverflowError) as exc:
        raise PipelineError(f"Invalid graph-v1 source {path}: {exc}") from exc

    graph = GraphRecord(
        graph_id=entry["graph_id"], topology_hash=entry["topology_hash"], origin_graph_id=entry["origin_graph_id"],
        num_nodes=n, directed=directed, edge_list=edges, source_edge_order=edge_order,
        metadata=_mat_native(meta),
        source={**dict(entry), "schema_document_sha256": file_fingerprint(schema)["file_sha256"],
                "producer_validator_sha256": file_fingerprint(Path(project_root) / VERIFIER_RELATIVE_PATH)["file_sha256"]},
    )
    graph.validate()
    return graph
