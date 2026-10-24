"""Select exact metric definitions; preserve masks and original sampling positions."""

from __future__ import annotations

from copy import deepcopy
from typing import Any, Iterable

import numpy as np

from .cache import canonical_json as metadata_json
from .config import MetricSelector, SelectionConfig, canonical_json, content_id
from .models import GraphRecord, MetricArray, MetricRun, PipelineError, TrainingSample
from .projection import PROJECTION_VERSION, project_observations


def _identity(metric: MetricArray) -> dict[str, Any]:
    return {"metric_id": metric.metric_id, "metric_version": metric.metric_version,
            "parameters": metric.parameters, "scope": metric.scope}


def _run_provenance(run: MetricRun) -> dict[str, Any]:
    """Preserve run definitions/randomness once, excluding observation payloads."""
    metadata = deepcopy({key: value for key, value in run.metadata.items() if key != "attack"})
    if "attack" in run.metadata:
        attack = run.metadata["attack"]
        if not isinstance(attack, dict):
            raise PipelineError(f"Run {run.run_id}: normalized attack metadata must be a mapping")
        metadata["attack"] = deepcopy({key: value for key, value in attack.items() if key not in {"states", "sampled"}})
    return {"graph_id": run.graph_id, "topology_hash": run.topology_hash,
            "metric_set_id": run.metric_set_id, "protocol_id": run.protocol_id,
            "run_id": run.run_id, "status": run.status,
            "source": deepcopy(run.source), "metadata": metadata}


def _lookup(run: MetricRun, selector: MetricSelector, *, missing: str) -> MetricArray | None:
    if selector.observation_source != "results":
        return project_observations(run, selector, missing=missing)
    named = [metric for metric in run.metrics if metric.metric_id == selector.metric_id]
    expected = {"metric_id": selector.metric_id, "metric_version": selector.metric_version,
                "parameters": selector.parameters, "scope": selector.scope}
    matched = [metric for metric in named if canonical_json(_identity(metric)) == canonical_json(expected)]
    if len(matched) > 1:
        raise PipelineError(f"Run {run.run_id} contains duplicate matching metric {selector.metric_id}")
    if not matched and named:
        raise PipelineError(f"Run {run.run_id}: version/parameters/scope conflict for {selector.metric_id}")
    if not matched:
        if any(metric.metric_id == selector.metric_id for observations in run.observations.values()
               for observation in observations for metric in observation.metrics):
            raise PipelineError(
                f"Run {run.run_id}, {selector.metric_id}: Explicit observation projection required; "
                "set observation_source='states' or 'sampled' and alignment='by_id'"
            )
        attack = run.metadata.get("attack", {})
        if isinstance(attack, dict):
            for source in ("states", "sampled"):
                observations = attack.get(source, [])
                if isinstance(observations, dict):
                    observations = [observations]
                for observation in observations:
                    if not isinstance(observation, dict):
                        continue
                    records = observation.get("metrics", [])
                    if isinstance(records, dict):
                        records = [records]
                    for record in records:
                        if not isinstance(record, dict):
                            continue
                        if (record.get("metric_id") == selector.metric_id
                                and record.get("metric_version") == selector.metric_version
                                # MAT numerical scalars can decode as 10000.0
                                # while identity JSON stores 10000; this check
                                # only detects an unsupported observation source.
                                and record.get("parameters") == selector.parameters):
                            raise PipelineError(
                                f"Run {run.run_id}, {selector.metric_id}: Explicit observation projection required; "
                                "this adapter only selects producer results/summaries"
                            )
        return None
    metric = matched[0]
    metric.validate()
    if run.status not in {"ok", "success", "complete", "completed", "partial"} and np.any(metric.valid_mask):
        raise PipelineError(f"Failed run {run.run_id} contains valid metric values")
    if metric.status in {"failed", "not_computed", "not_applicable", "undefined"} and np.any(metric.valid_mask):
        raise PipelineError(f"{metric.metric_id}: {metric.status} result contains valid values")
    return deepcopy(metric)


def _missing(selector: MetricSelector, template: MetricArray | None = None) -> MetricArray:
    if selector.observation_source != "results":
        # A different repeat cannot supply this missing run's actual positions.
        return MetricArray(selector.metric_id, selector.metric_version, deepcopy(selector.parameters),
                           selector.scope, np.empty((0,), dtype=float), (), np.empty((0,), dtype=bool),
                           "not_computed", reason="Selected observation source is absent; axes and positions are unknown",
                           metadata={"selection_missing": True, "shape_unknown": True,
                                     "observation_projection": {"transform_version": PROJECTION_VERSION,
                                     "source": selector.observation_source, "alignment": selector.alignment,
                                     "leading_axis": "observation", "source_available": False, "observations": []}},
                           present_mask=np.empty((0,), dtype=bool))
    if template is not None:
        result = deepcopy(template)
        result.values = np.full(template.values.shape, np.nan)
        result.valid_mask = np.zeros(template.values.shape, dtype=bool)
        result.present_mask = np.zeros(template.values.shape, dtype=bool)
        result.status = "not_computed"
        result.reason = "Selected metric is absent from this run"
        result.metadata = {**result.metadata, "selection_missing": True}
        return result
    # An absent result has no inferable shape/axes. An empty array records absence;
    # it is never populated with a plausible node count or invented trajectory.
    return MetricArray(selector.metric_id, selector.metric_version, deepcopy(selector.parameters),
                       selector.scope, np.empty((0,), dtype=float), (),
                       np.empty((0,), dtype=bool), "not_computed",
                       reason="Selected metric is absent; original axes and shape are unknown",
                       metadata={"selection_missing": True, "shape_unknown": True})


def _array_equal(left: np.ndarray | None, right: np.ndarray | None) -> bool:
    if left is None or right is None:
        return left is None and right is None
    left, right = np.asarray(left), np.asarray(right)
    numeric = left.dtype.kind in "biufc" and right.dtype.kind in "biufc"
    return np.array_equal(left, right, equal_nan=numeric)


def _same_axes(first: MetricArray, metric: MetricArray) -> bool:
    if first.values.shape != metric.values.shape or first.axis_names != metric.axis_names:
        return False
    if not _array_equal(first.node_ids, metric.node_ids) or not _array_equal(first.edge_ids, metric.edge_ids):
        return False
    for name in ("axis_positions", "axis_ids"):
        left, right = getattr(first, name), getattr(metric, name)
        if left.keys() != right.keys() or any(not _array_equal(left[key], right[key]) for key in left):
            return False
    return True


def _mean(entries: list[tuple[MetricRun, MetricArray]], selector: MetricSelector) -> MetricArray:
    if not entries:
        return _missing(selector)
    known = [metric for _, metric in entries if not metric.metadata.get("shape_unknown")]
    first = known[0] if known else entries[0][1]
    def definition_metadata(metric: MetricArray) -> dict:
        metadata = {key: value for key, value in metric.metadata.items()
                    if key not in {"selection_missing", "shape_unknown", "elapsed_seconds", "details"}}
        if "observation_projection" in metadata:
            metadata["observation_projection"] = {
                key: value for key, value in metadata["observation_projection"].items() if key != "observations"}
        return metadata
    for metric in known:
        if np.any(metric.valid_mask & ~np.isfinite(metric.values)):
            raise PipelineError(f"Cannot average {selector.metric_id}: valid nonfinite values require an explicit derived transform")
        if not _same_axes(first, metric):
            raise PipelineError(f"Cannot average {selector.metric_id}: actual axes/IDs/shapes differ; explicit derived alignment is required")
        if metadata_json(definition_metadata(first)) != metadata_json(definition_metadata(metric)):
            raise PipelineError(f"Cannot average {selector.metric_id}: metric metadata/definitions differ")
    count = np.zeros(first.values.shape, dtype=np.int64)
    present_count = np.zeros(first.values.shape, dtype=np.int64)
    mean = np.zeros(first.values.shape, dtype=np.float64)
    m2 = np.zeros_like(mean)
    for _, metric in entries:
        if metric.metadata.get("shape_unknown"):
            continue
        mask = metric.valid_mask
        present_count += np.ones(metric.values.shape, dtype=bool) if metric.present_mask is None else metric.present_mask
        new_count = count + mask
        delta = np.where(mask, metric.values, 0) - mean
        new_mean = mean + np.divide(delta * mask, new_count, out=np.zeros_like(mean), where=new_count > 0)
        m2 += np.where(mask, delta * (np.where(mask, metric.values, 0) - new_mean), 0)
        mean, count = new_mean, new_count
    valid = count > 0
    values = np.where(valid, mean, np.nan)
    variance = np.divide(m2, count, out=np.full_like(mean, np.nan), where=valid)
    result = deepcopy(first)
    result.values, result.valid_mask = values, valid
    if any(metric.present_mask is not None for _, metric in entries):
        result.present_mask = present_count > 0
    if valid.size and np.all(valid):
        result.status = "ok"
    elif np.any(valid):
        result.status = "partial"
    elif not valid.size and any(metric.status == "ok" for metric in known):
        # The metric-v1 contract explicitly permits a successful empty result
        # (for example, an edge vector on an edgeless graph).
        result.status = "ok"
    else:
        source_statuses = {metric.status for _, metric in entries}
        unavailable = {"not_computed", "not_applicable", "undefined", "failed"}
        result.status = next(iter(source_statuses)) if len(source_statuses) == 1 and source_statuses <= unavailable else "undefined"
    result.reason = "Derived masked repeat mean; source statuses retained in repeat_summary"
    result.metadata = {**result.metadata, "repeat_summary": {
        "transform_version": "masked-repeat-mean-v1", "variance_ddof": 0,
        "count": count.tolist(), "present_count": present_count.tolist(), "variance": np.where(valid, variance, None).tolist(),
        "runs": [{"run_id": run.run_id, "metric_set_id": run.metric_set_id,
                  "protocol_id": run.protocol_id, "run_status": run.status,
                  "status": metric.status, "reason": metric.reason, "source": run.source,
                  "valid_mask": metric.valid_mask.tolist(),
                  "present_mask": None if metric.present_mask is None else metric.present_mask.tolist(),
                  "metric_metadata": metric.metadata}
                 for run, metric in entries]}}
    return result


def select_samples(graph: GraphRecord, runs: Iterable[MetricRun], config: SelectionConfig | dict,
                   split: str) -> list[TrainingSample]:
    """Keep repeats by run_id, or average matching actual axes without interpolation.

    A sole static (protocol_id='') run may be broadcast to selected attack runs.
    Unique static metric sets compose once per graph, despite different run IDs.
    Independent repeated streams require run_groups, mapping graph_id to sample
    keys and explicit metric_set_id -> run_id bindings. No ordinal joins occur.
    Missing results are errors unless explicitly configured as masked absence.
    """
    if isinstance(config, dict):
        config = SelectionConfig.from_dict(config)
    if split not in {"train", "val", "test"}:
        raise PipelineError(f"Unsupported split: {split}")
    selectors = [(role, alias, selector) for role, values in (("features", config.feature_keys), ("targets", config.target_keys))
                 for alias, selector in values.items()]
    contexts = {(selector.metric_set_id, selector.protocol_id) for _, _, selector in selectors}
    attack_contexts = [context for context in contexts if context[1]]
    has_attack = bool(attack_contexts)
    explicit_groups = config.run_groups.get(graph.graph_id, {})
    if config.run_groups and not explicit_groups:
        raise PipelineError(f"Graph {graph.graph_id} has no explicit run_groups bindings")
    driver = attack_contexts[0] if len(attack_contexts) == 1 else next(iter(contexts)) if len(contexts) == 1 else None
    requested: dict[tuple[str, str], set[str] | None] = {}
    for context in contexts:
        if explicit_groups:
            requested[context] = {bindings[context[0]] for bindings in explicit_groups.values()}
        elif config.run_ids != "all" and context == driver:
            requested[context] = set(config.run_ids)
        else:
            requested[context] = None
    selected: dict[tuple[str, str], dict[str, MetricRun]] = {key: {} for key in contexts}
    for run in runs:
        context = (run.metric_set_id, run.protocol_id)
        if context not in contexts:
            continue
        if run.graph_id != graph.graph_id or run.topology_hash != graph.topology_hash:
            raise PipelineError(f"Run {run.run_id}: graph_id/topology_hash does not match requested graph")
        if requested[context] is not None and run.run_id not in requested[context]:
            continue
        if run.run_id in selected[context]:
            raise PipelineError(f"Duplicate run identity {context}/{run.run_id}")
        selected[context][run.run_id] = run
    for context, by_id in selected.items():
        for run_id in sorted(requested[context] or set()):
            if run_id not in by_id:
                if config.missing == "error":
                    raise PipelineError(f"Graph {graph.graph_id}: requested run {run_id} is absent for metric set {context[0]}")
                by_id[run_id] = MetricRun(graph.graph_id, graph.topology_hash, context[0], context[1],
                                          run_id, "not_computed", [])
    if not explicit_groups:
        if has_attack:
            ambiguous = [context for context in contexts if not context[1] and len(selected[context]) > 1]
        elif len(contexts) > 1:
            ambiguous = [context for context in contexts if len(selected[context]) > 1]
        else:
            ambiguous = []
        if ambiguous:
            raise PipelineError("Independent repeated metric streams require explicit run_groups; cannot infer corresponding run IDs")
    slots: dict[str, dict[tuple[str, str], str]] = {}
    if explicit_groups:
        slots = {key: {context: bindings[context[0]] for context in contexts}
                 for key, bindings in sorted(explicit_groups.items())}
    elif driver is not None:
        for run_id in sorted(selected[driver]):
            bindings = {driver: run_id}
            for context in contexts - {driver}:
                if len(selected[context]) == 1:
                    bindings[context] = next(iter(selected[context]))
            slots[run_id] = bindings
    else:
        # Each available static context has exactly one independent run; produce
        # one graph sample, not one duplicate sample per metric-set-specific ID.
        slots["static"] = {context: next(iter(selected[context])) for context in contexts if selected[context]}
    if not slots:
        if config.missing == "error":
            raise PipelineError(f"Graph {graph.graph_id}: no selected metric runs")
        slots["missing"] = {}
    looked_up: dict[tuple[str, str], list[tuple[MetricRun, MetricArray]]] = {}
    for role, alias, selector in selectors:
        entries = []
        context_runs = selected[(selector.metric_set_id, selector.protocol_id)]
        for run in sorted(context_runs.values(), key=lambda item: item.run_id):
            metric = _lookup(run, selector, missing=config.missing)
            if metric is None:
                if config.missing == "error":
                    raise PipelineError(f"Run {run.run_id} is missing selected {role} {alias}")
            entries.append((run, metric))
        template = next((metric for _, metric in entries if metric is not None), None)
        looked_up[(role, alias)] = [(run, metric if metric is not None else _missing(selector, template))
                                    for run, metric in entries]
    active_ids = ["mean"] if config.repeat_mode == "mean" else list(slots)
    results = []
    for active in active_ids:
        parts: dict[str, dict[str, MetricArray]] = {"features": {}, "targets": {}}
        sources = []
        source_runs = {}
        for role, alias, selector in selectors:
            entries = looked_up[(role, alias)]
            if config.repeat_mode == "mean":
                chosen = entries
                if not chosen and config.missing == "error":
                    raise PipelineError(f"Graph {graph.graph_id} is missing selected {role} {alias}")
                value = _mean(chosen, selector)
            else:
                bound_run_id = slots[active].get((selector.metric_set_id, selector.protocol_id))
                chosen = [(run, metric) for run, metric in entries if run.run_id == bound_run_id]
                if not chosen:
                    if config.missing == "error":
                        raise PipelineError(f"Graph {graph.graph_id}, run {active}: missing selected {role} {alias}")
                    value = _missing(selector, entries[0][1] if entries else None)
                else:
                    value = deepcopy(chosen[0][1])
            parts[role][alias] = value
            for run, _ in chosen:
                source_runs[(run.metric_set_id, run.protocol_id, run.run_id)] = _run_provenance(run)
            sources.extend({"role": role, "key": alias, "run_id": run.run_id,
                            "metric_set_id": run.metric_set_id, "protocol_id": run.protocol_id,
                            "run_status": run.status, "source": deepcopy(run.source)} for run, _ in chosen)
        identity = {"graph_id": graph.graph_id, "selection_id": config.config_id,
                    "repeat": active, "sources": [{key: item[key] for key in ("role", "key", "run_id", "metric_set_id", "protocol_id")} for item in sources]}
        results.append(TrainingSample(content_id(identity), graph, parts["features"], parts["targets"], split,
                                      {"selection_id": config.config_id, "selection_config": config.to_dict(),
                                       "repeat_mode": config.repeat_mode, "repeat_id": active,
                                       "metric_sources": sources,
                                       "source_runs": [source_runs[key] for key in sorted(source_runs)]}))
    return results
