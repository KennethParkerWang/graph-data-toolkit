"""Explicit derived alignment of typed attack observations on saved coordinates.

The original metric identity/scope is retained.  The leading observation axis is
the saved request/state order, not an interpolated deletion fraction.  Coordinate
unions contain only actually observed coordinates, including textual labels.
"""

from __future__ import annotations

from copy import deepcopy
from typing import Any

import numpy as np

from .cache import canonical_json as metadata_json
from .config import MetricSelector, canonical_json
from .models import MetricArray, MetricRun, ObservationRecord, PipelineError


PROJECTION_VERSION = "observation-by-id-v1"
_UNAVAILABLE = {"undefined", "not_applicable", "not_computed", "failed"}
_RUNTIME_METADATA = {"details", "elapsed_seconds", "shape_unknown", "selection_missing",
                     "allows_infinity", "infinity_definition", "axis_position_axes"}


def _definition(metric: MetricArray) -> dict[str, Any]:
    return {"metric_id": metric.metric_id, "metric_version": metric.metric_version,
            "parameters": metric.parameters, "scope": metric.scope}


def _match(run: MetricRun, observation: ObservationRecord, selector: MetricSelector) -> MetricArray | None:
    named = [metric for metric in observation.metrics if metric.metric_id == selector.metric_id]
    identity = {"metric_id": selector.metric_id, "metric_version": selector.metric_version,
                "parameters": selector.parameters, "scope": selector.scope}
    matched = [metric for metric in named if canonical_json(_definition(metric)) == canonical_json(identity)]
    context = f"Run {run.run_id}, {selector.observation_source}[{observation.index}], {selector.metric_id}"
    if len(matched) > 1:
        raise PipelineError(f"{context}: duplicate matching metric")
    if named and not matched:
        raise PipelineError(f"{context}: version/parameters/scope conflict")
    if not matched:
        return None
    metric = matched[0]
    metric.validate()
    if metric.metadata.get("shape_unknown") and (metric.values.size or metric.axis_names or metric.status not in _UNAVAILABLE):
        raise PipelineError(f"{context}: shape_unknown must describe an empty unavailable result without axes")
    if metric.status in _UNAVAILABLE and np.any(metric.valid_mask):
        raise PipelineError(f"{context}: {metric.status} result contains valid values")
    if (run.status not in {"ok", "success", "complete", "completed", "partial"}
            or observation.status in {"failed", "not_computed"}) and np.any(metric.valid_mask):
        raise PipelineError(f"{context}: failed run/observation contains valid metric values")
    return metric


def _row(observation: ObservationRecord, metric: MetricArray | None) -> dict[str, Any]:
    row = {"index": observation.index, "status": observation.status, "reason": observation.reason,
           "positions": deepcopy(observation.positions), "metadata": deepcopy(observation.metadata),
           "metric_present": metric is not None}
    if metric is not None:
        row["metric"] = {"status": metric.status, "reason": metric.reason,
                         "shape": list(metric.values.shape), "dtype": metric.values.dtype.str,
                         "axis_names": list(metric.axis_names), "axis_ids": deepcopy(metric.axis_ids),
                         "axis_positions": deepcopy(metric.axis_positions),
                         "node_ids": deepcopy(metric.node_ids), "edge_ids": deepcopy(metric.edge_ids),
                         "metadata": deepcopy(metric.metadata)}
    return row


def _status(metrics: list[MetricArray | None], present: np.ndarray, valid: np.ndarray) -> str:
    statuses = {metric.status if metric is not None else "not_computed" for metric in metrics}
    if statuses == {"ok"} and np.all(present) and np.all(valid):
        return "ok"
    if np.any(valid):
        return "partial"
    if len(statuses) == 1 and statuses <= _UNAVAILABLE:
        return next(iter(statuses))
    return "undefined" if metrics else "not_computed"


def _unknown(selector: MetricSelector, metrics: list[MetricArray | None], projection: dict[str, Any]) -> MetricArray:
    """No record supplies rank/axes, so do not invent a scalar per observation."""
    statuses = {metric.status for metric in metrics if metric is not None}
    status = next(iter(statuses)) if len(statuses) == 1 else "not_computed" if not statuses else "undefined"
    metadata = {"shape_unknown": True, "observation_projection": projection}
    if not any(metric is not None for metric in metrics):
        metadata["selection_missing"] = True
    reason = "Selected observation metric has no saved shape/axes; see observation_projection for source statuses"
    return MetricArray(selector.metric_id, selector.metric_version, deepcopy(selector.parameters),
                       selector.scope, np.empty((0,), dtype=float), (), np.empty((0,), dtype=bool),
                       status, reason=reason, metadata=metadata, present_mask=np.empty((0,), dtype=bool))


def _validate_observations(observations: list[ObservationRecord], source: str) -> dict[str, np.ndarray]:
    if not isinstance(observations, list) or any(not isinstance(item, ObservationRecord) for item in observations):
        raise PipelineError(f"{source}: projection requires typed ObservationRecord entries")
    ids = [item.index for item in observations]
    if any(isinstance(index, (bool, np.bool_)) or not isinstance(index, (int, np.integer)) or index < 1 for index in ids):
        raise PipelineError(f"{source}: observation indices must be positive integers")
    if len(set(ids)) != len(ids):
        raise PipelineError(f"{source}: duplicate observation index; repeated requests need distinct indices")
    if not observations:
        return {}
    keys = set(observations[0].positions)
    if any(set(item.positions) != keys for item in observations):
        raise PipelineError(f"{source}: observation position fields differ")
    positions = {}
    for key in sorted(keys):
        values = [item.positions[key] for item in observations]
        if any(np.asarray(value).ndim != 0 or np.asarray(value).dtype.kind not in "biuf" for value in values):
            raise PipelineError(f"{source}: position {key} must contain numeric/logical scalars")
        positions[key] = np.asarray(values)
    return positions


def _coordinates(metric: MetricArray) -> dict[str, np.ndarray]:
    if set(metric.axis_ids) != set(metric.axis_names):
        raise PipelineError(f"{metric.metric_id}: by_id requires explicit coordinate IDs on every source axis")
    result = {}
    for axis in metric.axis_names:
        ids = np.asarray(metric.axis_ids[axis])
        if ids.dtype.kind in "biuf":
            if not np.all(np.isfinite(ids)):
                raise PipelineError(f"{metric.metric_id}: nonfinite coordinate IDs on {axis}")
        elif ids.dtype.kind not in "UO" or any(not isinstance(item, str) for item in ids):
            raise PipelineError(f"{metric.metric_id}: unsupported coordinate IDs on {axis}")
        if len(set(ids.tolist())) != len(ids):
            raise PipelineError(f"{metric.metric_id}: duplicate coordinate IDs on {axis}")
        result[axis] = ids
    for field in ("node_ids", "edge_ids"):
        ids = getattr(metric, field)
        if ids is not None and (len(metric.axis_names) != 1 or not np.array_equal(ids, result[metric.axis_names[0]])):
            raise PipelineError(f"{metric.metric_id}: {field} disagrees with explicit source axis")
    return result


def project_observations(run: MetricRun, selector: MetricSelector, *, missing: str) -> MetricArray:
    """Stack one exact source metric using coordinate union and separate presence.

    Missing metric records follow ``missing``; identity, dtype and axis conflicts
    always fail.  Absent integer/logical cells carry zero with present_mask false,
    preserving every saved value and dtype without turning padding into data.
    """
    if selector.observation_source not in {"states", "sampled"} or selector.alignment != "by_id":
        raise PipelineError("Observation projection requires explicit states/sampled and alignment='by_id'")
    if missing not in {"error", "mask"}:
        raise PipelineError("Observation projection missing policy must be error or mask")
    source = selector.observation_source
    available = source in run.observations
    observations = run.observations.get(source, [])
    positions = _validate_observations(observations, source)
    metrics = [_match(run, observation, selector) for observation in observations]
    absent = [observation.index for observation, metric in zip(observations, metrics) if metric is None]
    projection = {"transform_version": PROJECTION_VERSION, "source": source,
                  "alignment": "by_id", "leading_axis": "observation", "source_available": available,
                  "observations": [_row(observation, metric) for observation, metric in zip(observations, metrics)]}
    if missing == "error" and (not observations or absent):
        detail = f"missing selected metric at observations {absent}" if absent else f"no {source} observations"
        raise PipelineError(f"Run {run.run_id}, {selector.metric_id}: {detail}")
    known = [metric for metric in metrics if metric is not None and not metric.metadata.get("shape_unknown")]
    if not known:
        return _unknown(selector, metrics, projection)
    first = known[0]
    if "observation" in first.axis_names:
        raise PipelineError(f"{selector.metric_id}: source axis conflicts with derived observation axis")
    source_metadata = {key: deepcopy(value) for key, value in first.metadata.items() if key not in _RUNTIME_METADATA}
    coordinate_sets = []
    for metric in known:
        if metric.axis_names != first.axis_names:
            raise PipelineError(f"{selector.metric_id}: source axis names/ranks differ across observations")
        if metric.values.dtype != first.values.dtype:
            raise PipelineError(f"{selector.metric_id}: source value dtypes differ; an explicit derived cast is required")
        definition_metadata = {key: value for key, value in metric.metadata.items() if key not in _RUNTIME_METADATA}
        if metadata_json(definition_metadata) != metadata_json(source_metadata):
            raise PipelineError(f"{selector.metric_id}: metric metadata/definitions differ across observations")
        coordinate_sets.append(_coordinates(metric))
    unions: dict[str, np.ndarray] = {}
    maps: dict[str, dict[Any, int]] = {}
    for axis in first.axis_names:
        arrays = [coordinates[axis] for coordinates in coordinate_sets]
        numeric = all(array.dtype.kind in "biuf" for array in arrays)
        text = all(array.dtype.kind in "UO" for array in arrays)
        if not (numeric or text) or (numeric and len({array.dtype.str for array in arrays}) != 1):
            raise PipelineError(f"{selector.metric_id}: coordinate dtypes differ on {axis}; explicit conversion required")
        ordered = list(dict.fromkeys(item for array in arrays for item in array.tolist()))
        unions[axis] = np.asarray(ordered, dtype=np.result_type(*(array.dtype for array in arrays)))
        maps[axis] = {coordinate: index for index, coordinate in enumerate(ordered)}
    shape = (len(observations), *(len(unions[axis]) for axis in first.axis_names))
    fill = np.nan if first.values.dtype.kind == "f" else 0
    values = np.full(shape, fill, dtype=first.values.dtype)
    valid = np.zeros(shape, dtype=bool)
    present = np.zeros(shape, dtype=bool)
    for index, metric in enumerate(metrics):
        if metric is None or metric.metadata.get("shape_unknown"):
            continue
        if not first.axis_names:
            values[index], valid[index] = metric.values, metric.valid_mask
            present[index] = True if metric.present_mask is None else metric.present_mask
            continue
        target = np.ix_(*(np.asarray([maps[axis][coordinate] for coordinate in metric.axis_ids[axis].tolist()], dtype=np.intp)
                          for axis in first.axis_names))
        values[index][target] = metric.values
        valid[index][target] = metric.valid_mask
        present[index][target] = True if metric.present_mask is None else metric.present_mask
    axes = ("observation", *first.axis_names)
    axis_ids = {"observation": np.asarray([item.index for item in observations], dtype=np.int64), **unions}
    position_axes = {key: "observation" for key in positions}
    # Preserve secondary saved axis positions only when they are already exact;
    # regridding a trajectory within each observation is a distinct transform.
    for metric in known:
        if metadata_json(metric.axis_positions) != metadata_json(first.axis_positions):
            raise PipelineError(f"{selector.metric_id}: source axis positions differ; explicit derived alignment required")
    for key, vector in first.axis_positions.items():
        if key in positions:
            raise PipelineError(f"{selector.metric_id}: source/observation position name conflict: {key}")
        axis = first.metadata.get("axis_position_axes", {}).get(key, key)
        if axis not in first.axis_names and len(first.axis_names) == 1:
            axis = first.axis_names[0]
        if axis not in unions or len(vector) != len(unions[axis]):
            raise PipelineError(f"{selector.metric_id}: source position {key} cannot follow coordinate union without regridding")
        positions[key], position_axes[key] = np.asarray(vector).copy(), axis
    metadata = {**source_metadata, "axis_position_axes": position_axes, "observation_projection": projection}
    infinity_definitions = [metric.metadata["infinity_definition"] for metric in known if "infinity_definition" in metric.metadata]
    if infinity_definitions:
        if any(metadata_json(value) != metadata_json(infinity_definitions[0]) for value in infinity_definitions):
            raise PipelineError(f"{selector.metric_id}: infinity definitions differ")
        metadata["infinity_definition"] = deepcopy(infinity_definitions[0])
    if any(metric.metadata.get("allows_infinity") for metric in known):
        metadata["allows_infinity"] = True
    projected = MetricArray(selector.metric_id, selector.metric_version, deepcopy(selector.parameters), selector.scope,
                            values, axes, valid, _status(metrics, present, valid),
                            reason="Derived observation coordinate alignment; source statuses/reasons retained per observation",
                            axis_positions=positions, axis_ids=axis_ids, metadata=metadata, present_mask=present)
    for field in ("node_ids", "edge_ids"):
        flags = [getattr(metric, field) is not None for metric in known]
        if any(flags):
            if not all(flags):
                raise PipelineError(f"{selector.metric_id}: {field} missing on some source observations")
            setattr(projected, field, unions[first.axis_names[0]].copy())
    projected.validate()
    return projected
