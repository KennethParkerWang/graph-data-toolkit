"""Read-only producer adapters and strict, format-independent source validation.

Only published producer schemas may be wired into this module. The helpers below
do not prescribe the layout of either producer's MAT files.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping, Sequence

import numpy as np

from .models import GraphRecord, MetricArray, MetricRun, ObservationRecord, PipelineError
from .graph_source import (
    VERIFIER_RELATIVE_PATH, read_dataset_description, read_graph_manifest, read_graph_v1,
)


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATHS = {
    "graph": Path("code/graph_builder/docs/graph_schema_v1.md"),
    "metric": Path("code/graph_analyzer/docs/metric_schema_v1.md"),
}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class SchemaUnavailable(PipelineError):
    """The responsible producer has not published a usable formal schema."""


def require_schema(kind: str, project_root: str | Path = PROJECT_ROOT) -> Path:
    """Find the producer's formal schema without substituting the design draft."""
    if kind not in SCHEMA_PATHS:
        raise ValueError(f"Unknown schema kind: {kind}")
    path = Path(project_root) / SCHEMA_PATHS[kind]
    if not path.is_file() or not path.read_text(encoding="utf-8-sig").strip():
        owner = "task 1" if kind == "graph" else "task 2"
        raise SchemaUnavailable(
            f"Formal {kind} schema unavailable: {path}. Await {owner}'s published "
            "schema and samples; the design draft is not a raw-file adapter contract."
        )
    return path


def _unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise PipelineError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise PipelineError(f"Non-finite JSON constant: {value}")


def _finite_float(value: str) -> float:
    result = float(value)
    if not math.isfinite(result):
        raise PipelineError(f"Non-finite JSON number: {value}")
    return result


def parse_json(text: str, *, context: str = "JSON") -> Any:
    try:
        return json.loads(
            text, object_pairs_hook=_unique_pairs, parse_constant=_reject_constant,
            parse_float=_finite_float,
        )
    except (ValueError, TypeError) as exc:
        raise PipelineError(f"Invalid {context}: {exc}") from exc


def read_json_object(path: str | Path) -> dict[str, Any]:
    path = Path(path)
    try:
        value = parse_json(path.read_text(encoding="utf-8-sig"), context=str(path))
    except (OSError, UnicodeError) as exc:
        raise PipelineError(f"Cannot read JSON file {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise PipelineError(f"Expected a JSON object: {path}")
    return value


def read_jsonl(
    path: str | Path, *, identity_fields: Sequence[str]
) -> list[dict[str, Any]]:
    """Read metadata only; reject duplicate identities, including exact repeats."""
    path = Path(path)
    if not identity_fields:
        raise ValueError("At least one identity field is required")
    rows: list[dict[str, Any]] = []
    seen: dict[tuple[Any, ...], tuple[int, dict[str, Any]]] = {}
    try:
        with path.open("r", encoding="utf-8-sig") as handle:
            for line_number, line in enumerate(handle, 1):
                if not line.strip():
                    raise PipelineError(f"Blank JSONL record at {path}:{line_number}")
                row = parse_json(line, context=f"{path}:{line_number}")
                if not isinstance(row, dict):
                    raise PipelineError(f"Expected a JSON object at {path}:{line_number}")
                missing = [field for field in identity_fields if field not in row]
                if missing:
                    raise PipelineError(f"Missing identity fields {missing} at {path}:{line_number}")
                identity = tuple(row[field] for field in identity_fields)
                if any(not isinstance(value, str) for value in identity):
                    raise PipelineError(f"Identity fields must be strings at {path}:{line_number}")
                if identity in seen:
                    first_line, previous = seen[identity]
                    conflict = "conflicting" if row != previous else "duplicate"
                    raise PipelineError(
                        f"{conflict.capitalize()} manifest identity {identity} at "
                        f"{path}:{line_number}; first seen on line {first_line}"
                    )
                seen[identity] = (line_number, row)
                rows.append(row)
    except (OSError, UnicodeError) as exc:
        raise PipelineError(f"Cannot read manifest {path}: {exc}") from exc
    return rows


def validate_sha256(value: Any, *, field: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise PipelineError(f"{field} must be 64 lowercase hexadecimal characters")
    return value


def resolve_source_path(root: str | Path, relative: Any) -> Path:
    """Resolve a manifest path and reject escape through syntax or symlinks."""
    if not isinstance(relative, str) or not relative or any(char in relative for char in ("\\", ":", "\x00")):
        raise PipelineError(f"Expected a relative POSIX source path: {relative!r}")
    pieces = relative.split("/")
    pure = PurePosixPath(relative)
    if pure.is_absolute() or any(part in {"", ".", ".."} for part in pieces):
        raise PipelineError(f"Unsafe source path: {relative!r}")
    root = Path(root).resolve()
    path = (root / Path(*pure.parts)).resolve()
    if not path.is_relative_to(root):
        raise PipelineError(f"Source path escapes dataset root: {relative!r}")
    return path


def verify_source_file(root: str | Path, entry: Mapping[str, Any]) -> Path:
    """Validate committed byte count and SHA-256 before parsing a source file."""
    for name in ("path", "file_bytes", "file_sha256"):
        if name not in entry:
            raise PipelineError(f"Source manifest entry is missing {name}")
    expected_bytes = entry["file_bytes"]
    if isinstance(expected_bytes, bool) or not isinstance(expected_bytes, int) or expected_bytes < 0:
        raise PipelineError("file_bytes must be a nonnegative integer")
    expected_hash = validate_sha256(entry["file_sha256"], field="file_sha256")
    path = resolve_source_path(root, entry["path"])
    if not path.is_file():
        raise PipelineError(f"Missing source file: {path}")
    digest = hashlib.sha256()
    count = 0
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                count += len(chunk)
                digest.update(chunk)
    except OSError as exc:
        raise PipelineError(f"Cannot read source file {path}: {exc}") from exc
    if count != expected_bytes:
        raise PipelineError(f"Source byte count mismatch: {path}: expected {expected_bytes}, got {count}")
    if digest.hexdigest() != expected_hash:
        raise PipelineError(f"Source SHA-256 mismatch: {path}")
    return path


def file_fingerprint(path: str | Path) -> dict[str, Any]:
    """Hash a metadata document without interpreting its producer-owned format."""
    path = Path(path)
    digest = hashlib.sha256()
    count = 0
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                count += len(chunk)
                digest.update(chunk)
    except OSError as exc:
        raise PipelineError(f"Cannot fingerprint source metadata {path}: {exc}") from exc
    return {"file_sha256": digest.hexdigest(), "file_bytes": count}


def _mat_struct(value: Any, context: str) -> dict[str, Any]:
    if isinstance(value, np.ndarray):
        if value.size != 1:
            raise PipelineError(f"{context} must be a scalar MATLAB struct")
        value = value.reshape(-1)[0]
    fields = getattr(value, "_fieldnames", None)
    if fields is None:
        raise PipelineError(f"{context} must be a MATLAB struct")
    return {name: getattr(value, name) for name in fields}


def _mat_text(value: Any, context: str) -> str:
    array = np.asarray(value)
    if array.dtype.kind not in "US":
        raise PipelineError(f"{context} must be a MATLAB char row")
    if array.size == 0:
        return ""
    if array.ndim > 2 or (array.ndim == 2 and array.shape[0] != 1):
        raise PipelineError(f"{context} must be a MATLAB char row")
    return "".join(str(part) for part in array.reshape(-1))


def _mat_native(value: Any) -> Any:
    """Translate provenance/parameter structs, never metric value arrays."""
    if getattr(value, "_fieldnames", None) is not None:
        return {key: _mat_native(getattr(value, key)) for key in value._fieldnames}
    if isinstance(value, np.ndarray):
        if value.dtype.kind in "US":
            return _mat_text(value, "metadata text")
        if value.size == 0:
            return []
        if value.dtype.kind == "O":
            values = [_mat_native(item) for item in value.reshape(-1)]
            return values[0] if value.size == 1 and getattr(value.reshape(-1)[0], "_fieldnames", None) is not None else values
        if value.size == 1:
            return value.reshape(-1)[0].item()
        if value.ndim == 2 and 1 in value.shape:
            return value.reshape(-1).tolist()
        return value.tolist()
    if isinstance(value, np.generic):
        return value.item()
    return value


def _load_mat(path: Path) -> dict[str, Any]:
    try:
        from scipy.io import loadmat

        return loadmat(path, struct_as_record=False, squeeze_me=False, mat_dtype=True)
    except (OSError, ValueError, TypeError, NotImplementedError) as exc:
        raise PipelineError(f"Cannot parse MAT v7 source {path}: {exc}") from exc


def _required(record: Mapping[str, Any], fields: Iterable[str], context: str) -> None:
    missing = set(fields) - set(record)
    if missing:
        raise PipelineError(f"{context} missing fields: {sorted(missing)}")


def _cell_items(value: Any, context: str) -> list[Any]:
    array = np.asarray(value)
    if array.size == 0:
        return []
    if array.dtype.kind != "O":
        raise PipelineError(f"{context} must be a MATLAB cell array")
    return list(array.reshape(-1, order="F"))


def _axis_coordinate(value: Any, context: str) -> np.ndarray:
    array = np.asarray(value)
    if array.ndim > 2 or (array.size and array.ndim == 2 and min(array.shape) != 1):
        raise PipelineError(f"{context} must be a coordinate vector")
    if array.dtype.kind == "O":
        # Producer HITS has a cellstr score axis, e.g. {'hub','authority'}.
        # Mixed numeric/text cells or nested cell arrays are not coordinate types.
        return np.asarray([_mat_text(item, context) for item in array.reshape(-1, order="F")], dtype=str)
    if array.dtype.kind in "biuf":
        return array.reshape(-1)
    if array.dtype.kind in "US":
        return np.asarray([_mat_text(array, context)], dtype=str)
    raise PipelineError(f"{context} contains unsupported coordinate values")


def _mat_equal(left: Any, right: Any) -> bool:
    """MATLAB isequaln semantics for copied nested result records."""
    left_fields, right_fields = getattr(left, "_fieldnames", None), getattr(right, "_fieldnames", None)
    if left_fields is not None or right_fields is not None:
        return (left_fields is not None and right_fields is not None and set(left_fields) == set(right_fields)
                and all(_mat_equal(getattr(left, key), getattr(right, key)) for key in left_fields))
    a, b = np.asarray(left), np.asarray(right)
    if a.shape != b.shape:
        return False
    if a.dtype.kind == "O" or b.dtype.kind == "O":
        return a.dtype.kind == b.dtype.kind and all(_mat_equal(x, y) for x, y in zip(a.flat, b.flat))
    if a.dtype.kind in "biuf" and b.dtype.kind in "biuf":
        return bool(np.array_equal(a, b, equal_nan=True))
    return bool(np.array_equal(a, b))


def _infinity_definition(metric_id: str, version: str, project_root: Path) -> dict[str, Any] | None:
    # Explicit clauses read from the producer's v1 registries, not a generic
    # substring inference: efficiency formulas also mention Inf but yield finite values.
    definitions = {
        "distance_matrix": ("basic", "formula", "D_ij=min number of arcs from i to j; D_ii=0, unreachable Inf"),
        "eccentricity": ("basic", "definition", "eccentricity with unreachable distances equal to Inf"),
        "diameter": ("basic", "formula", "max node eccentricity, Inf allowed"),
        "radius": ("basic", "formula", "min node eccentricity, Inf allowed"),
        "effective_resistance": ("advanced", "conditions", "Every undirected edge is a unit resistor; diagonal zero; disconnected +Inf is valid extended-real resistance; axes preserve node IDs."),
        "kirchhoff_index": ("advanced", "conditions", "N=0 undefined; N=1 zero; disconnected N>1 gives valid +Inf; this is the unordered-pair total."),
    }
    if version != "1.0.0" or metric_id not in definitions:
        return None
    group, field, clause = definitions[metric_id]
    relative = f"code/graph_analyzer/registry/{group}.json"
    path = project_root / relative
    if not path.is_file():
        return None
    rows = parse_json(path.read_text(encoding="utf-8-sig"), context=str(path))
    if not isinstance(rows, list):
        raise PipelineError(f"Metric registry must contain an array: {path}")
    matches = [row for row in rows if row.get("metric_id") == metric_id and row.get("metric_version") == version]
    if len(matches) != 1 or matches[0].get(field) != clause:
        return None
    return {"path": relative, **file_fingerprint(path), "metric_id": metric_id, "metric_version": version, field: clause}


def _read_metric(
    record: Mapping[str, Any], *, num_nodes: int, num_edges: int, project_root: Path = PROJECT_ROOT,
) -> MetricArray:
    _required(record, (
        "metric_id", "metric_version", "parameters", "scope", "values", "axis_names",
        "axis_ids", "valid_mask", "status", "reason", "units", "method", "elapsed_seconds", "details",
    ), "metric result")
    metric_id = _mat_text(record["metric_id"], "metric_id")
    version = _mat_text(record["metric_version"], "metric_version")
    status = _mat_text(record["status"], f"{metric_id}.status")
    scope = _mat_text(record["scope"], f"{metric_id}.scope")
    if scope not in {"graph", "node", "edge", "distribution", "matrix", "trajectory"}:
        raise PipelineError(f"{metric_id}: unsupported source scope {scope}")
    axes = tuple(_mat_text(item, f"{metric_id}.axis_names") for item in _cell_items(record["axis_names"], "axis_names"))
    if len(set(axes)) != len(axes):
        raise PipelineError(f"{metric_id}: duplicate axis names")
    source_values = np.asarray(record["values"])
    source_mask = np.asarray(record["valid_mask"])
    if source_values.dtype.kind not in "biuf" or source_mask.dtype != np.bool_:
        raise PipelineError(f"{metric_id}: values must be real numeric and valid_mask logical")
    if source_values.shape != source_mask.shape:
        raise PipelineError(f"{metric_id}: source values/mask shape mismatch")
    shape_unknown = not axes and source_values.size == 0 and status in {"undefined", "not_applicable", "not_computed", "failed"}
    expected_rank = {"graph": 0, "node": 1, "edge": 1, "distribution": 1, "trajectory": 1, "matrix": 2}[scope]
    if not shape_unknown and len(axes) != expected_rank:
        raise PipelineError(f"{metric_id}: source {scope} scope requires {expected_rank} logical axes")
    if not axes:
        if shape_unknown:
            values, mask = source_values, source_mask
        elif source_values.size != 1:
            raise PipelineError(f"{metric_id}: no axes but result is not scalar; producer must define unavailable shape")
        else:
            values, mask = source_values.reshape(()), source_mask.reshape(())
    elif len(axes) == 1:
        if source_values.ndim > 2 or (source_values.size and min(source_values.shape) != 1):
            raise PipelineError(f"{metric_id}: a one-axis metric must be a vector")
        values, mask = source_values.reshape(-1), source_mask.reshape(-1)
    else:
        if source_values.ndim != len(axes):
            raise PipelineError(f"{metric_id}: axes do not describe values shape")
        values, mask = source_values, source_mask
    coordinates = _cell_items(record["axis_ids"], "axis_ids")
    if len(coordinates) != len(axes):
        raise PipelineError(f"{metric_id}: axis_ids does not match axis_names")
    axis_ids = {axis: _axis_coordinate(ids, f"{metric_id}.{axis}") for axis, ids in zip(axes, coordinates)}
    node_ids = None
    edge_ids = None
    for index, axis in enumerate(axes):
        ids = axis_ids[axis]
        if len(ids) != values.shape[index]:
            raise PipelineError(f"{metric_id}: IDs length mismatch on axis {axis}")
        node_axis = axis in {"node", "node_id", "node_ids", "source_node", "target_node", "source_node_id", "target_node_id"}
        edge_axis = axis in {"edge", "edge_id", "edge_ids"}
        if scope == "node" and len(axes) == 1:
            node_axis = True
        if scope == "edge" and len(axes) == 1:
            edge_axis = True
        if node_axis or edge_axis:
            count = num_nodes if node_axis else num_edges
            if (ids.dtype.kind not in "iuf" or not np.all(np.isfinite(ids))
                    or np.any(ids != np.floor(ids)) or len(np.unique(ids)) != len(ids)
                    or np.any(ids < 1) or np.any(ids > count)):
                raise PipelineError(f"{metric_id}: invalid original {'node' if node_axis else 'edge'} IDs")
            if node_axis and len(axes) == 1:
                node_ids = ids
            if edge_axis and len(axes) == 1:
                edge_ids = ids
    if status not in {"ok", "partial", "undefined", "not_applicable", "not_computed", "failed"}:
        raise PipelineError(f"{metric_id}: invalid metric status {status}")
    reason = _mat_text(record["reason"], f"{metric_id}.reason")
    if status == "ok" and not np.all(mask):
        raise PipelineError(f"{metric_id}: status ok requires all values valid")
    if status in {"undefined", "not_applicable", "not_computed", "failed"} and (np.any(mask) or not reason):
        raise PipelineError(f"{metric_id}: unavailable result needs reason and no valid values")
    if np.any(mask & np.isnan(values)):
        raise PipelineError(f"{metric_id}: NaN marked valid")
    infinity_definition = None
    if np.any(mask & np.isinf(values)):
        infinity_definition = _infinity_definition(metric_id, version, project_root)
    if np.any(mask & np.isneginf(values)) or (np.any(mask & np.isinf(values)) and infinity_definition is None):
        raise PipelineError(
            f"{metric_id}: valid infinity needs the producer's explicit metric definition; "
            "metric-v1 alone does not authorize treating infinity as a training value"
        )
    parameters = _mat_native(record["parameters"])
    if not isinstance(parameters, dict):
        raise PipelineError(f"{metric_id}: parameters must be a scalar struct")
    positions = {}
    if scope == "trajectory":
        positions = {axis: ids.copy() for axis, ids in axis_ids.items()}
        detail_fields = _mat_struct(record["details"], "trajectory details")
        if metric_id == "efficiency_retention_curve" and version == "1.0.0" and "actual_fraction" in detail_fields:
            actual_fraction = np.asarray(detail_fields["actual_fraction"]).reshape(-1)
            if len(axes) != 1 or len(actual_fraction) != values.size:
                raise PipelineError("efficiency_retention_curve actual fraction length mismatch")
            positions["actual_fraction"] = actual_fraction
    return MetricArray(
        metric_id=metric_id, metric_version=version,
        parameters=parameters, scope=scope, values=values, axis_names=axes, valid_mask=mask,
        status=status, reason=reason, node_ids=node_ids, edge_ids=edge_ids, axis_ids=axis_ids, axis_positions=positions,
        metadata={
            **{key: _mat_native(record[key]) for key in ("units", "method", "elapsed_seconds", "details")},
            **({"shape_unknown": True} if shape_unknown else {}),
            **({"allows_infinity": True, "infinity_definition": infinity_definition} if infinity_definition else {}),
        },
    )


def _selection_rows(value: Any, context: str) -> list[dict[str, Any]]:
    if isinstance(value, dict):
        return [value]
    if isinstance(value, list) and all(isinstance(item, dict) for item in value):
        return value
    raise PipelineError(f"{context} must describe metric selection structs")


def _verify_result_definitions(metrics: list[MetricArray], definitions: Any, context: str) -> None:
    selections = _selection_rows(definitions, context)
    if len(metrics) != len(selections):
        raise PipelineError(f"{context}: result/selection count differs")
    for result, selection in zip(metrics, selections):
        _required(selection, ("metric_id", "metric_version", "parameters"), context)
        if (result.metric_id != selection["metric_id"] or result.metric_version != selection["metric_version"]
                or result.parameters != selection["parameters"]):
            raise PipelineError(f"{context}: result metric version or parameters disagree with saved identity")
        # Preserve the producer's exact JSON number representation for config matching.
        result.parameters = selection["parameters"]


def _numeric_scalar(value: Any, context: str) -> float:
    array = np.asarray(value)
    if array.size != 1 or array.dtype.kind not in "biuf":
        raise PipelineError(f"{context} must be a numeric scalar")
    return float(array.item())


def _original_ids(value: Any, limit: int, context: str) -> np.ndarray:
    ids = np.asarray(value).reshape(-1)
    if (ids.dtype.kind not in "iuf" or not np.all(np.isfinite(ids)) or np.any(ids != np.floor(ids))
            or np.any(ids < 1) or np.any(ids > limit) or len(np.unique(ids)) != len(ids)):
        raise PipelineError(f"{context}: invalid original IDs")
    return ids.astype(np.int64)


def _round_attack_counts(fractions: Any, total: int, rounding: str) -> np.ndarray:
    """Match positive MATLAB round without rounding x+0.5 prematurely."""
    scaled = np.asarray(fractions, dtype=np.float64) * total
    if rounding == "nearest":
        lower = np.floor(scaled)
        result = lower + (scaled - lower >= 0.5)
    else:
        result = {"floor": np.floor, "ceil": np.ceil}[rounding](scaled)
    return np.clip(result, 0, total).astype(np.int64)


def _attack_boundaries(attack: Mapping[str, Any], protocol: Mapping[str, Any], total: int) -> list[int]:
    """Validate the producer's discrete schedule; never interpolate observations."""
    version = protocol.get("version")
    if version not in {"1.0.0", "1.1.0"} or _mat_text(attack["schema_version"], "attack schema") != f"attack-{version}":
        raise PipelineError("Unsupported attack schema or protocol version mismatch")
    _required(protocol, ("stop_fraction", "batch_size", "rounding", "sample_policy", "deletion_mode"), "attack protocol")
    stop, batch = protocol["stop_fraction"], protocol["batch_size"]
    if isinstance(stop, bool) or not isinstance(stop, (int, float)) or not np.isfinite(stop) or not 0 <= stop <= 1:
        raise PipelineError("Attack stop_fraction must be in [0, 1]")
    if isinstance(batch, bool) or not isinstance(batch, (int, float)) or not np.isfinite(batch) or batch != int(batch) or batch < 1:
        raise PipelineError("Attack batch_size must be a positive integer")
    if protocol["rounding"] not in {"floor", "ceil", "nearest"} or protocol["sample_policy"] not in {"exact", "previous", "next"}:
        raise PipelineError("Attack rounding/sample policy unsupported")
    mode = protocol["deletion_mode"]
    if mode not in {"single", "batch", "fraction_grid"} or (mode in {"single", "fraction_grid"} and batch != 1):
        raise PipelineError("Attack deletion_mode/batch_size mismatch")
    if version == "1.0.0" and (mode == "fraction_grid" or "attack_fractions" in protocol):
        raise PipelineError("Fraction-grid requests require protocol version 1.1.0")
    if version == "1.1.0":
        _required(protocol, ("attack_fractions",), "normalized protocol 1.1.0")
        if mode != "fraction_grid" and np.asarray(protocol["attack_fractions"]).size:
            raise PipelineError("Attack attack_fractions applies only to fraction_grid")

    def rounded(fractions: Any) -> np.ndarray:
        return _round_attack_counts(fractions, total, protocol["rounding"])

    expected_schedule: dict[str, np.ndarray] = {}
    if mode == "fraction_grid":
        requested = np.asarray(protocol.get("attack_fractions", []))
        if (requested.dtype.kind not in "iuf" or requested.ndim > 1 or not requested.size
                or not np.all(np.isfinite(requested)) or np.any(requested < 0) or np.any(requested > stop)
                or np.any(np.diff(requested.reshape(-1)) < 0) or requested.reshape(-1)[-1] != stop):
            raise PipelineError("Attack fraction-grid requests must be nondecreasing and end at stop_fraction")
        requested = requested.reshape(-1)
        q = rounded(requested)
        counts = np.unique(np.concatenate(([0], q)))
        indices = np.searchsorted(counts, q) + 1
        expected_schedule = {
            "requested_fraction": requested, "requested_removed_count": q,
            "increment": np.diff(np.concatenate(([0], q))), "state_index": indices,
            "round_index": indices - 1, "actual_removed_count": q,
            "actual_removed_fraction": q / total if total else np.full(len(q), np.nan),
            "fraction_valid": np.full(len(q), total > 0, dtype=bool),
        }
    else:
        limit = int(rounded(stop))
        counts = np.arange(0, limit + 1, int(batch), dtype=np.int64)
        if counts[-1] != limit:
            counts = np.append(counts, limit)
    if version == "1.1.0":
        _required(attack, ("schedule",), "attack-1.1.0")
        schedule = _mat_struct(attack["schedule"], "attack schedule")
        if set(schedule) != set(expected_schedule):
            raise PipelineError("Attack schedule fields disagree with configured deletion mode")
        for name, expected in expected_schedule.items():
            saved = np.asarray(schedule[name])
            if (saved.ndim > 2 or (saved.ndim == 2 and saved.shape[1] != 1)
                    or saved.dtype.kind not in "biuf"
                    or (name == "fraction_valid" and saved.dtype != np.bool_)
                    or not np.array_equal(saved.reshape(-1), expected, equal_nan=True)):
                raise PipelineError(f"Attack schedule.{name} differs from configured fraction-grid boundaries")
    full = np.array_equal(counts, np.arange(total + 1)) if version == "1.1.0" else batch == 1 and counts[-1] == total
    if _numeric_scalar(attack["full_single_object_trajectory"], "full_single_object_trajectory") != full:
        raise PipelineError("Attack states do not cover configured stop/batch boundaries: full trajectory flag differs")
    return counts.tolist()


def _read_attack(
    attack: Mapping[str, Any], graph: Mapping[str, Any], protocol_id: str,
    definitions: Any, project_root: Path, seeds: Mapping[str, Any] | None = None,
    observations: dict[str, list[ObservationRecord]] | None = None,
) -> dict[str, Any]:
    attack_schema = project_root / "code/graph_analyzer/docs/attack_protocols.md"
    if not attack_schema.is_file():
        raise SchemaUnavailable(f"Attack field specification unavailable: {attack_schema}; request task 2 publication")
    _required(attack, (
        "schema_version", "protocol_id", "protocol", "original_node_count", "original_edge_count",
        "original_node_ids", "original_edge_ids", "directed", "target_count", "deleted_ids",
        "states", "sampled", "status", "fraction_status", "attack_seed", "repeat_index",
        "randomness", "full_single_object_trajectory",
    ), "attack")
    if _mat_text(attack["protocol_id"], "attack protocol_id") != protocol_id:
        raise PipelineError("Attack/output protocol_id mismatch")
    protocol = _mat_native(attack["protocol"])
    if not isinstance(protocol, dict) or protocol.get("target") not in {"node", "edge"}:
        raise PipelineError("Invalid attack protocol target")
    if seeds is not None:
        randomness = _mat_native(attack["randomness"])
        if (not isinstance(randomness, dict)
                or _mat_native(attack["attack_seed"]) != seeds.get("attack_seed")
                or _mat_native(attack["repeat_index"]) != seeds.get("repeat_index")
                or randomness.get("algorithm") != seeds.get("randomness")
                or randomness.get("seed") != seeds.get("attack_seed")
                or randomness.get("used") != (seeds.get("randomness") != "none")):
            raise PipelineError("Attack seed/repeat/randomness differs from run envelope")
    for field, expected in (("original_node_count", graph["N"]), ("original_edge_count", graph["M"]), ("directed", graph["directed"])):
        if _numeric_scalar(attack[field], field) != expected:
            raise PipelineError(f"Attack/graph {field} mismatch")
    for field, count in (("original_node_ids", graph["N"]), ("original_edge_ids", graph["M"])):
        if not np.array_equal(_original_ids(attack[field], count, field), np.arange(1, count + 1)):
            raise PipelineError(f"Attack {field} must preserve canonical original IDs")
    total = graph["N"] if protocol["target"] == "node" else graph["M"]
    if _numeric_scalar(attack["target_count"], "target_count") != total:
        raise PipelineError("Attack target count disagrees with graph")
    deleted = _original_ids(attack["deleted_ids"], total, "deleted_ids")
    states = [_mat_struct(item, "attack state") for item in np.asarray(attack["states"]).reshape(-1, order="F")]
    if not states:
        raise PipelineError("Attack must include its initial observed state")
    expected_counts = _attack_boundaries(attack, protocol, total)
    if len(deleted) != expected_counts[-1] or len(states) != len(expected_counts):
        raise PipelineError("Attack states do not cover configured stop/batch boundaries")
    initial_endpoints = np.asarray(states[0].get("remaining_edge_endpoints_original"))
    if (initial_endpoints.shape != (graph["M"], 2) or initial_endpoints.dtype.kind not in "iuf"
            or not np.all(np.isfinite(initial_endpoints)) or np.any(initial_endpoints != np.floor(initial_endpoints))
            or np.any(initial_endpoints < 1) or np.any(initial_endpoints > graph["N"])
            or np.any(initial_endpoints[:, 0] == initial_endpoints[:, 1])):
        raise PipelineError("Attack initial original edge endpoints are invalid")
    canonical_pairs = initial_endpoints if graph["directed"] else np.sort(initial_endpoints, axis=1)
    if len(np.unique(canonical_pairs, axis=0)) != graph["M"]:
        raise PipelineError("Attack initial original edge endpoints contain duplicate edges")
    if "edge_list" in graph and not np.array_equal(initial_endpoints, graph["edge_list"]):
        raise PipelineError("Attack initial endpoints disagree with source graph edge IDs")
    counts = []
    attacked = []
    state_records: list[ObservationRecord] = []
    for index, state in enumerate(states):
        _required(state, (
            "removed_count", "removed_fraction", "fraction_valid", "removed_ids", "remaining_node_ids",
            "remaining_edge_ids", "remaining_edge_endpoints_original", "node_count", "edge_count", "metrics", "status",
            "round_index", "removed_node_ids", "removed_edge_ids",
        ), "attack state")
        removed = _original_ids(state["removed_ids"], total, "state.removed_ids")
        attacked.extend(removed.tolist())
        count = _numeric_scalar(state["removed_count"], "removed_count")
        if count != len(attacked) or count != expected_counts[index] or _numeric_scalar(state["round_index"], "round_index") != index:
            raise PipelineError("Attack observed counts/deletion IDs disagree")
        counts.append(count)
        fraction = _numeric_scalar(state["removed_fraction"], "removed_fraction")
        fraction_valid = _numeric_scalar(state["fraction_valid"], "fraction_valid")
        if (total > 0 and (fraction_valid != 1 or fraction != count / total)) or (total == 0 and (fraction_valid != 0 or not np.isnan(fraction))):
            raise PipelineError("Attack actual fraction or fraction validity mismatch")
        nodes = _original_ids(state["remaining_node_ids"], graph["N"], "remaining_node_ids")
        edges = _original_ids(state["remaining_edge_ids"], graph["M"], "remaining_edge_ids")
        if _numeric_scalar(state["node_count"], "node_count") != len(nodes) or _numeric_scalar(state["edge_count"], "edge_count") != len(edges):
            raise PipelineError("Attack remaining ID counts disagree")
        endpoints = np.asarray(state["remaining_edge_endpoints_original"])
        if endpoints.shape != (len(edges), 2) or not np.all(np.isin(endpoints, nodes)):
            raise PipelineError("Attack remaining endpoints do not refer to surviving original nodes")
        expected_survivors = np.setdiff1d(np.arange(1, total + 1), attacked)
        if not np.array_equal(np.sort(nodes if protocol["target"] == "node" else edges), expected_survivors):
            raise PipelineError("Attack remaining IDs disagree with deletion sequence")
        if protocol["target"] == "edge" and not np.array_equal(nodes, np.arange(1, graph["N"] + 1)):
            raise PipelineError("Edge attacks must retain all nodes, including isolates")
        original_nodes, original_edges = np.arange(1, graph["N"] + 1), np.arange(1, graph["M"] + 1)
        expected_nodes = original_nodes[~np.isin(original_nodes, attacked)] if protocol["target"] == "node" else original_nodes
        keep_edges = np.all(~np.isin(initial_endpoints, attacked), axis=1) if protocol["target"] == "node" else ~np.isin(original_edges, attacked)
        expected_edges = original_edges[keep_edges]
        if not np.array_equal(nodes, expected_nodes) or not np.array_equal(edges, expected_edges) or not np.array_equal(endpoints, initial_endpoints[keep_edges]):
            raise PipelineError("Attack residual original-ID endpoints disagree with initial edge table")
        previous_edges = original_edges if index == 0 else _original_ids(states[index - 1]["remaining_edge_ids"], graph["M"], "previous edges")
        expected_removed_edges = previous_edges[~np.isin(previous_edges, expected_edges)]
        expected_removed_nodes = removed if protocol["target"] == "node" else np.empty(0, dtype=np.int64)
        if (not np.array_equal(_original_ids(state["removed_node_ids"], graph["N"], "removed_node_ids"), expected_removed_nodes)
                or not np.array_equal(_original_ids(state["removed_edge_ids"], graph["M"], "removed_edge_ids"), expected_removed_edges)):
            raise PipelineError("Attack per-state removed node/edge IDs disagree")
        metrics = [_read_metric(_mat_struct(item, "state metric"), num_nodes=graph["N"], num_edges=graph["M"], project_root=project_root)
                   for item in np.asarray(state["metrics"]).reshape(-1, order="F")]
        _verify_result_definitions(metrics, definitions, "attack state")
        for metric in metrics:
            metric.validate()
            if metric.values.size and metric.scope in {"node", "edge"}:
                expected_axis = nodes if metric.scope == "node" else edges
                if len(metric.axis_names) != 1 or not np.array_equal(metric.axis_ids[metric.axis_names[0]], expected_axis):
                    raise PipelineError("Attack state metric axis disagrees with surviving original IDs")
            for axis, ids in metric.axis_ids.items():
                expected_axis = (nodes if axis in {"node", "node_id", "node_ids", "source_node", "target_node", "source_node_id", "target_node_id"}
                                 else edges if axis in {"edge", "edge_id", "edge_ids"} else None)
                if metric.values.size and expected_axis is not None and not np.array_equal(ids, expected_axis):
                    raise PipelineError("Attack state metric axis disagrees with surviving original IDs")
        state_status = _mat_text(state["status"], "state status")
        expected_status = "partial" if any(metric.status in {"failed", "not_computed"} for metric in metrics) else "ok"
        if state_status != expected_status:
            raise PipelineError("Attack state status disagrees with metric execution statuses")
        state_records.append(ObservationRecord(
            index=index + 1, metrics=metrics,
            positions={"removed_count": int(count), "removed_fraction": fraction,
                       "fraction_valid": bool(fraction_valid), "round_index": index, "state_index": index + 1},
            status=state_status, reason=_mat_text(state["reason"], "state reason") if "reason" in state else "",
            metadata={key: _mat_native(value) for key, value in state.items()
                      if key not in {"metrics", "status", "reason", "removed_count", "removed_fraction", "fraction_valid", "round_index"}},
        ))
    if not np.array_equal(deleted, attacked):
        raise PipelineError("Attack deleted_ids differs from concatenated observed attacks")
    samples = [_mat_struct(item, "attack sample") for item in np.asarray(attack["sampled"]).reshape(-1, order="F")]
    sample_records: list[ObservationRecord] = []
    for index, sample in enumerate(samples):
        _required(sample, ("state_index", "requested_fraction", "requested_removed_count", "actual_removed_count", "actual_removed_fraction", "fraction_valid", "exact_count_match", "status", "metrics"), "attack sample")
        state_index = _numeric_scalar(sample["state_index"], "state_index")
        requested_fraction = _numeric_scalar(sample["requested_fraction"], "requested_fraction")
        requested_count = _numeric_scalar(sample["requested_removed_count"], "requested_removed_count")
        if not np.isfinite(requested_fraction) or not 0 <= requested_fraction <= 1:
            raise PipelineError("Attack requested fraction must be in [0, 1]")
        rounding = protocol.get("rounding")
        if rounding not in {"floor", "ceil", "nearest"}:
            raise PipelineError("Attack protocol has unsupported rounding")
        expected_count = int(_round_attack_counts(requested_fraction, total, rounding))
        if requested_count != expected_count:
            raise PipelineError("Attack requested_removed_count disagrees with protocol rounding")
        if not np.isfinite(state_index) or state_index != int(state_index) or state_index < 0 or state_index > len(states):
            raise PipelineError("Attack sample refers to nonexistent observed state")
        if protocol["sample_policy"] == "exact":
            eligible = [i for i, value in enumerate(counts, 1) if value == requested_count]
        elif protocol["sample_policy"] == "previous":
            eligible = [i for i, value in enumerate(counts, 1) if value <= requested_count][-1:]
        else:
            eligible = [i for i, value in enumerate(counts, 1) if value >= requested_count][:1]
        if state_index != (eligible[0] if eligible else 0):
            raise PipelineError("Attack sample state_index disagrees with protocol sample_policy")
        metrics = []
        if state_index:
            state = states[int(state_index) - 1]
            for sample_name, state_name in (("actual_removed_count", "removed_count"), ("actual_removed_fraction", "removed_fraction"), ("fraction_valid", "fraction_valid")):
                actual = _numeric_scalar(sample[sample_name], sample_name)
                expected = _numeric_scalar(state[state_name], state_name)
                if actual != expected and not (np.isnan(actual) and np.isnan(expected)):
                    raise PipelineError(f"Attack sampled {sample_name} disagrees with observed state")
            metrics = [_read_metric(_mat_struct(item, "sampled metric"), num_nodes=graph["N"], num_edges=graph["M"], project_root=project_root)
                       for item in np.asarray(sample["metrics"]).reshape(-1, order="F")]
            _verify_result_definitions(metrics, definitions, "attack sampled")
            if not _mat_equal(sample["metrics"], state["metrics"]) or _mat_text(sample["status"], "sample status") != _mat_text(state["status"], "state status"):
                raise PipelineError("Attack sampled metric values/axes/masks/status differ from referenced state")
            if _numeric_scalar(sample["exact_count_match"], "exact_count_match") != (counts[int(state_index) - 1] == requested_count):
                raise PipelineError("Attack exact_count_match flag disagrees with actual observation")
        else:
            if _mat_text(sample["status"], "sample status") != "not_computed" or np.asarray(sample["metrics"]).size:
                raise PipelineError("Unobserved sample must remain not_computed with no metric observations")
            if (not np.isnan(_numeric_scalar(sample["actual_removed_count"], "actual_removed_count"))
                    or not np.isnan(_numeric_scalar(sample["actual_removed_fraction"], "actual_removed_fraction"))
                    or _numeric_scalar(sample["fraction_valid"], "fraction_valid") != 0
                    or _numeric_scalar(sample["exact_count_match"], "exact_count_match") != 0):
                raise PipelineError("Unobserved sample must retain undefined actual positions and false validity flags")
        positions = {name: _numeric_scalar(sample[name], name) for name in (
            "requested_fraction", "requested_removed_count", "actual_removed_count", "actual_removed_fraction",
            "fraction_valid", "state_index", "exact_count_match")}
        for name in ("fraction_valid", "exact_count_match"):
            positions[name] = bool(positions[name])
        positions["state_index"] = int(state_index)
        positions["requested_removed_count"] = int(requested_count)
        sample_records.append(ObservationRecord(
            index=index + 1, metrics=metrics, positions=positions,
            status=_mat_text(sample["status"], "sample status"),
            reason=_mat_text(sample["reason"], "sample reason") if "reason" in sample else "",
            metadata={**({"referenced_state": state_records[int(state_index) - 1].metadata} if state_index else {}),
                      **{key: _mat_native(value) for key, value in sample.items()
                         if key not in {"metrics", "status", "reason", *positions}}},
        ))
    requested = np.asarray(protocol.get("sample_fractions", [])).reshape(-1)
    if not np.array_equal(requested, [_numeric_scalar(row["requested_fraction"], "requested_fraction") for row in samples]):
        raise PipelineError("Attack sampled requests do not preserve protocol order and repeats")
    expected_status = "partial" if any(row.status == "partial" for row in state_records) else "ok"
    if _mat_text(attack["status"], "attack status") != expected_status:
        raise PipelineError("Attack status disagrees with state execution statuses")
    if _mat_text(attack["fraction_status"], "fraction_status") != ("ok" if total else "undefined"):
        raise PipelineError("Attack fraction_status disagrees with original target population")
    if observations is not None:
        observations.update(states=state_records, sampled=sample_records)
    return {key: _mat_native(value) for key, value in attack.items()}


def _read_metric_run(
    root: Path, entry: Mapping[str, Any], graph: Mapping[str, Any], project_root: Path,
) -> MetricRun:
    schema = require_schema("metric", project_root)
    path = verify_source_file(root, entry)
    raw = _load_mat(path)
    if set(raw) - {"__header__", "__version__", "__globals__"} != {"output"}:
        raise PipelineError(f"metric-v1 requires one top-level output struct: {path}")
    output = _mat_struct(raw["output"], "output")
    _required(output, (
        "schema_version", "graph_id", "topology_hash", "origin_graph_id", "metric_set_id",
        "protocol_id", "run_id", "metric_version", "implementation_sha256", "metric_set_identity_json",
        "run_identity_json", "selections", "seeds", "status", "results", "attack", "created_utc",
        "matlab_version", "elapsed_seconds", "summary_selections", "summaries",
    ), "metric output")
    text_fields = (
        "schema_version", "graph_id", "topology_hash", "origin_graph_id", "metric_set_id",
        "protocol_id", "run_id", "metric_version", "implementation_sha256", "status",
    )


    labels = {field: _mat_text(output[field], field) for field in text_fields}
    if labels["schema_version"] != "metric-v1":
        raise PipelineError(f"Unsupported metric schema: {labels['schema_version']}")
    for field in ("graph_id", "topology_hash", "origin_graph_id"):
        if labels[field] != graph[field]:
            raise PipelineError(f"Metric/graph {field} mismatch: {path}")
    for field in set(text_fields) & set(entry):
        if labels[field] != entry[field]:
            raise PipelineError(f"Metric/manifest {field} mismatch: {path}")
    for field in ("graph_id", "topology_hash", "origin_graph_id", "metric_set_id", "run_id", "implementation_sha256"):
        validate_sha256(labels[field], field=field)
    if labels["protocol_id"]:
        validate_sha256(labels["protocol_id"], field="protocol_id")
    if labels["status"] not in {"complete", "partial", "failed"}:
        raise PipelineError(f"Unsupported run status: {labels['status']}")
    identities: dict[str, Any] = {}
    configurations: dict[str, Any] = {}
    for field, identifier in (("metric_set_identity_json", "metric_set_id"), ("run_identity_json", "run_id")):
        saved_json = _mat_text(output[field], field)
        if hashlib.sha256(saved_json.encode("utf-8")).hexdigest() != labels[identifier]:
            raise PipelineError(f"{identifier} does not match saved exact identity JSON: {path}")
        identity = parse_json(saved_json, context=field)
        if not isinstance(identity, dict) or not isinstance(identity.get("configuration"), dict):
            raise PipelineError(f"{field} must describe a JSON object")
        expected_version = "metric-set-v1" if identifier == "metric_set_id" else "metric-run-v1"
        if identity.get("identity_version") != expected_version:
            raise PipelineError(f"{field} has unexpected identity_version")
        configuration = identity["configuration"]
        for key in ("graph_id", "topology_hash", "metric_set_id", "protocol_id"):
            if key in configuration and configuration[key] != labels[key]:
                raise PipelineError(f"{field} {key} disagrees with metric output")
        identities[field] = saved_json
        configurations[identifier] = configuration
    metric_configuration = configurations["metric_set_id"]
    run_configuration = configurations["run_id"]
    _required(metric_configuration, ("selections", "summary_selections", "protocol_id", "implementation_sha256"), "metric identity")
    _required(run_configuration, ("graph_id", "topology_hash", "metric_set_id", "seeds"), "run identity")
    if metric_configuration["implementation_sha256"] != labels["implementation_sha256"]:
        raise PipelineError("Implementation digest disagrees with metric identity")
    if run_configuration["seeds"] != _mat_native(output["seeds"]):
        raise PipelineError("Seeds disagree with saved run identity")
    for field in ("selections", "summary_selections"):
        saved_selections = _selection_rows(_mat_native(output[field]), field)
        defined_selections = _selection_rows(metric_configuration[field], f"identity {field}")
        if len(saved_selections) != len(defined_selections):
            raise PipelineError(f"{field} count disagrees with saved metric-set identity")
        for saved, defined in zip(saved_selections, defined_selections):
            if saved.get("metric_id") != defined.get("metric_id") or saved.get("parameters") != defined.get("parameters"):
                raise PipelineError(f"{field} parameters disagree with saved metric-set identity")
    set_config = root / "configs/metric_sets" / f"{labels['metric_set_id']}.json"
    if not set_config.is_file() or set_config.read_text(encoding="utf-8") != identities["metric_set_identity_json"]:
        raise PipelineError(f"Metric-set config missing or differs from exact identity JSON: {set_config}")
    result_array = np.asarray(output["results"])
    metrics = [
        _read_metric(_mat_struct(item, "results record"), num_nodes=graph["N"], num_edges=graph["M"], project_root=project_root)
        for item in result_array.reshape(-1, order="F")
    ]
    summaries = [_read_metric(_mat_struct(item, "summary result"), num_nodes=graph["N"], num_edges=graph["M"], project_root=project_root)
                 for item in np.asarray(output["summaries"]).reshape(-1, order="F")]
    _verify_result_definitions(summaries, metric_configuration["summary_selections"], "summaries")
    attack_metadata = {}
    observations: dict[str, list[ObservationRecord]] = {}
    attack = _mat_struct(output["attack"], "attack")
    if labels["protocol_id"]:
        if metrics:
            raise PipelineError("Attack run has unexpected static result records")
        protocol_config = root / "configs/protocols" / f"{labels['protocol_id']}.json"
        if not protocol_config.is_file() or file_fingerprint(protocol_config)["file_sha256"] != labels["protocol_id"]:
            raise PipelineError(f"Protocol config missing or exact JSON hash mismatch: {protocol_config}")
        protocol_identity = read_json_object(protocol_config)
        if protocol_identity.get("identity_version") != "protocol-v1" or protocol_identity.get("configuration") != _mat_native(attack.get("protocol")):
            raise PipelineError("Saved protocol configuration disagrees with attack")
        attack_metadata = _read_attack(
            attack, graph, labels["protocol_id"], metric_configuration["selections"], project_root,
            seeds=run_configuration["seeds"], observations=observations,
        )
    else:
        if attack:
            raise PipelineError("Static metric run has nonempty attack data")
        _verify_result_definitions(metrics, metric_configuration["selections"], "static results")
    metrics.extend(summaries)
    execution_metrics = [*metrics, *[metric for row in observations.get("states", []) for metric in row.metrics]]
    if labels["status"] == "complete" and any(metric.status in {"failed", "not_computed"} for metric in execution_metrics):
        raise PipelineError("Complete run contains failed or not_computed metric results")
    seen = set()
    for metric in metrics:
        identity = (metric.metric_id, metric.metric_version, metric.scope,
                    json.dumps(metric.parameters, sort_keys=True, allow_nan=False))
        if identity in seen:
            raise PipelineError(f"Duplicate metric identity inside run: {identity}")
        seen.add(identity)
    return MetricRun(
        graph_id=labels["graph_id"], topology_hash=labels["topology_hash"],
        metric_set_id=labels["metric_set_id"], protocol_id=labels["protocol_id"], run_id=labels["run_id"],
        status=labels["status"], metrics=metrics, observations=observations,
        source={**dict(entry), "schema_document_sha256": file_fingerprint(schema)["file_sha256"]},
        metadata={**identities, "attack": attack_metadata, **{key: _mat_native(output[key]) for key in (
            "selections", "summary_selections", "seeds", "metric_version", "implementation_sha256", "created_utc", "matlab_version", "elapsed_seconds",
        )}},
    )


def _read_metric_manifest(
    root: Path, graphs: Mapping[str, Mapping[str, Any]], project_root: Path,
) -> list[dict[str, Any]]:
    require_schema("metric", project_root)
    rows = read_jsonl(root / "manifests/metrics.jsonl", identity_fields=(
        "graph_id", "topology_hash", "metric_set_id", "protocol_id", "run_id",
    ))
    for row in rows:
        _required(row, (
            "schema_version", "graph_id", "topology_hash", "origin_graph_id", "metric_set_id",
            "protocol_id", "run_id", "status", "path", "file_sha256", "file_bytes",
            "implementation_sha256", "created_utc",
        ), "metrics manifest")
        if row["schema_version"] != "metric-v1":
            raise PipelineError(f"Unsupported metric manifest schema: {row['schema_version']}")
        for field in ("graph_id", "topology_hash", "origin_graph_id", "metric_set_id", "run_id", "file_sha256", "implementation_sha256"):
            validate_sha256(row[field], field=field)
        if row["protocol_id"]:
            validate_sha256(row["protocol_id"], field="protocol_id")
        if row["graph_id"] not in graphs:
            raise PipelineError(f"Metric references unknown graph_id: {row['graph_id']}")
        graph = graphs[row["graph_id"]]
        for field in ("topology_hash", "origin_graph_id"):
            if row[field] != graph[field]:
                raise PipelineError(f"Metric/graph manifest {field} mismatch: {row['graph_id']}")
        if row["status"] not in {"complete", "partial", "failed"}:
            raise PipelineError(f"Unknown metric run status: {row['status']}")
        if isinstance(row["file_bytes"], bool) or not isinstance(row["file_bytes"], int) or row["file_bytes"] < 0:
            raise PipelineError("Metric file_bytes must be a nonnegative integer")
        expected_path = f"metrics/{row['metric_set_id']}/{row['graph_id'][:2]}/{row['graph_id']}/{row['run_id']}.mat"
        if row["path"] != expected_path:
            raise PipelineError(f"Metric path does not follow metric-v1: {row['path']}")
        if not resolve_source_path(root, row["path"]).is_file():
            raise PipelineError(f"Missing source metric file: {row['path']}")
    return rows

class SourceDataset:
    """Producer-aware source reader; initialization must remain metadata-only.

    Graph MATs and metric MATs are validated when requested.  ``graph_only=True``
    explicitly opens task-1 fixtures without claiming they have metric results.
    A missing dataset descriptor is always reported rather than synthesized.
    """

    def __init__(
        self, root: str | Path, *, project_root: str | Path = PROJECT_ROOT,
        graph_only: bool = False,
    ):
        self.root = Path(root).resolve()
        self.project_root = Path(project_root).resolve()
        if not isinstance(graph_only, bool):
            raise PipelineError("graph_only must be boolean")
        self.graph_only = graph_only
        self.graph_schema_path = require_schema("graph", self.project_root)
        self._indexed_documents = ("dataset.json", "manifests/graphs.jsonl")
        if not graph_only:
            self._indexed_documents += ("manifests/metrics.jsonl",)
        self._metadata_fingerprints, self._metadata_tokens = self._capture_metadata()
        self.dataset_metadata = read_dataset_description(self.root)
        if "generation_config" in self.dataset_metadata:
            relative = self.dataset_metadata["generation_config"]
            self._indexed_documents += (relative,)
            current, tokens = self._capture_metadata()
            fingerprint = current[relative]
            if (fingerprint is None
                    or fingerprint["file_sha256"] != self.dataset_metadata["generation_config_file_sha256"]):
                raise PipelineError("Generation configuration changed since descriptor validation; reopen SourceDataset")
            self._metadata_fingerprints[relative] = fingerprint
            self._metadata_tokens[relative] = tokens[relative]
        self._graphs = {row["graph_id"]: row for row in read_graph_manifest(self.root)}
        self._last_graph: GraphRecord | None = None
        self._metric_entries: list[dict[str, Any]] = []
        self._runs_by_graph: dict[str, list[dict[str, Any]]] = {}
        self.has_metric_manifest = self._metadata_fingerprints.get("manifests/metrics.jsonl") is not None
        if not graph_only and self.has_metric_manifest:
            self._metric_entries = _read_metric_manifest(self.root, self._graphs, self.project_root)
            for row in self._metric_entries:
                self._runs_by_graph.setdefault(row["graph_id"], []).append(row)
        # Bind the parsed identities to exactly the bytes observed before the
        # reads, including an absent optional metric index.  An atomic producer
        # publication during parsing must not become the first snapshot's hash.
        self._assert_metadata_unchanged(force_hash=True)

    def _current_metadata_tokens(self) -> dict[str, tuple[int, ...] | None]:
        tokens = {}
        for relative in self._indexed_documents:
            path = self.root / relative
            try:
                info = path.stat()
            except FileNotFoundError:
                tokens[relative] = None
                continue
            except OSError as exc:
                raise PipelineError(f"Cannot inspect source metadata {path}: {exc}") from exc
            # File identity catches atomic replacement even when the producer
            # preserves size/timestamps; ctime also catches ordinary rewrites.
            tokens[relative] = (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)
        return tokens

    def _capture_metadata(self) -> tuple[dict[str, Any], dict[str, tuple[int, ...] | None]]:
        before = self._current_metadata_tokens()
        fingerprints = {
            relative: None if before[relative] is None else file_fingerprint(self.root / relative)
            for relative in self._indexed_documents
        }
        after = self._current_metadata_tokens()
        if before != after:
            raise PipelineError("Source metadata changed while being fingerprinted; reopen SourceDataset")
        return fingerprints, after

    def _assert_metadata_unchanged(self, *, force_hash: bool = False) -> None:
        # Hash all index bytes for snapshots and at construction.  Per-graph
        # calls take the stat fast path so a corpus conversion is not quadratic
        # in manifest length; any file token change triggers full comparison.
        if not force_hash and self._current_metadata_tokens() == self._metadata_tokens:
            return
        current, tokens = self._capture_metadata()
        changed = [relative for relative in self._indexed_documents
                   if current[relative] != self._metadata_fingerprints[relative]]
        if changed:
            raise PipelineError(
                f"Source metadata changed since initialization: {', '.join(changed)}; reopen SourceDataset"
            )
        self._metadata_tokens = tokens

    def list_graphs(self) -> list[dict[str, Any]]:
        self._assert_metadata_unchanged()
        return [dict(row) for row in self._graphs.values()]

    def graph_entry(self, graph_id: str) -> dict[str, Any]:
        self._assert_metadata_unchanged()
        if graph_id not in self._graphs:
            raise PipelineError(f"Unknown graph_id: {graph_id}")
        return dict(self._graphs[graph_id])

    def read_graph(self, graph_id: str) -> GraphRecord:
        graph = read_graph_v1(self.root, self.graph_entry(graph_id), project_root=self.project_root)
        self._assert_metadata_unchanged()
        self._last_graph = graph
        return graph

    def read_runs(self, graph_id: str, selectors: Iterable[Any] | None = None) -> list[MetricRun]:
        graph = self.graph_entry(graph_id)
        selectors = None if selectors is None else list(selectors)
        if self.graph_only:
            if selectors:
                raise PipelineError("This SourceDataset is explicitly graph-only; metric selection is unavailable")
            self._assert_metadata_unchanged()
            return []
        if not self.has_metric_manifest:
            raise PipelineError(
                f"No published metric manifest: {self.root / 'manifests/metrics.jsonl'}. "
                "Use graph_only=True for graph fixtures; metric training requires producer results."
            )
        choices = None if selectors is None else {(selector.metric_set_id, selector.protocol_id) for selector in selectors}
        rows = [row for row in self._runs_by_graph.get(graph_id, ())
                if choices is None or (row["metric_set_id"], row["protocol_id"]) in choices]
        if rows:
            loaded = self._last_graph
            if loaded is None or loaded.graph_id != graph_id:
                loaded = self.read_graph(graph_id)
            graph["edge_list"] = loaded.edge_list
        runs = [_read_metric_run(self.root, row, graph, self.project_root) for row in rows]
        self._assert_metadata_unchanged()
        return runs

    def source_snapshot(self) -> dict[str, Any]:
        """Recompute small metadata hashes for source-change detection.

        Payload entries are manifest declarations, not newly read MAT arrays.
        Their bytes are verified only when the corresponding record is loaded.
        """
        self._assert_metadata_unchanged(force_hash=True)
        documents = {relative: dict(fingerprint) for relative, fingerprint in self._metadata_fingerprints.items()
                     if fingerprint is not None}
        # Include generation snapshots as well as every published configuration;
        # the graph I/O schema does not prescribe a descriptor key for them.
        config_root = self.root / "configs"
        if config_root.is_dir():
            for path in sorted(config_root.rglob("*.json")):
                relative = path.relative_to(self.root).as_posix()
                if relative not in documents:
                    documents[relative] = file_fingerprint(resolve_source_path(self.root, relative))
        for row in self._metric_entries:
            paths = [f"configs/metric_sets/{row['metric_set_id']}.json"]
            if row["protocol_id"]:
                paths.append(f"configs/protocols/{row['protocol_id']}.json")
            for relative in paths:
                if relative not in documents:
                    documents[relative] = file_fingerprint(resolve_source_path(self.root, relative))
        schemas = {
            kind: file_fingerprint(self.project_root / relative)
            for kind, relative in SCHEMA_PATHS.items()
            if (self.project_root / relative).is_file()
        }
        for relative in (
            VERIFIER_RELATIVE_PATH.as_posix(),
            "code/graph_analyzer/docs/attack_protocols.md",
            "code/graph_analyzer/docs/fraction_grid_attacks.md",
            "code/graph_analyzer/docs/repeat_statistics.md",
            "code/graph_analyzer/registry/basic.json",
            "code/graph_analyzer/registry/advanced.json",
        ):
            path = self.project_root / relative
            if path.is_file():
                schemas[relative] = file_fingerprint(path)
        self._assert_metadata_unchanged(force_hash=True)
        return {
            "dataset_id": self.dataset_metadata["dataset_id"],
            "mode": "graph-only" if self.graph_only else "graphs-and-metrics",
            "documents": documents,
            "schemas": schemas,
            "source_files": [
                {key: row[key] for key in ("path", "file_bytes", "file_sha256")}
                for row in (*self._graphs.values(), *self._metric_entries)
            ],
        }
