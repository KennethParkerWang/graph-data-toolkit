"""Explicit, producer-independent selection configuration."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
import hashlib
import json
from typing import Any, Mapping

from .models import PipelineError


def canonical_json(value: Any) -> str:
    try:
        return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)
    except (TypeError, ValueError) as exc:
        raise PipelineError(f"Configuration must contain finite JSON data: {exc}") from exc


def content_id(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class MetricSelector:
    metric_id: str
    metric_version: str
    parameters: dict[str, Any]
    scope: str
    metric_set_id: str
    protocol_id: str
    observation_source: str = "results"
    alignment: str | None = None

    def __post_init__(self) -> None:
        for key in ("metric_id", "metric_version", "metric_set_id"):
            if not isinstance(getattr(self, key), str) or not getattr(self, key):
                raise PipelineError(f"{key} must be an explicit nonempty string")
        if not isinstance(self.protocol_id, str):
            raise PipelineError("protocol_id must be a string; use an empty string for static metrics")
        if self.observation_source not in {"results", "states", "sampled"}:
            raise PipelineError("observation_source must be results, states or sampled")
        if self.observation_source == "results":
            if self.alignment is not None:
                raise PipelineError("alignment applies only to explicit states/sampled observation selection")
        else:
            if not self.protocol_id:
                raise PipelineError("states/sampled observation selection requires an explicit attack protocol_id")
            if self.alignment != "by_id":
                raise PipelineError("states/sampled observation selection requires explicit alignment='by_id'")
        if self.scope not in {"graph", "node", "edge", "trajectory", "distribution", "matrix"}:
            raise PipelineError(f"Unknown scope: {self.scope}")
        if not isinstance(self.parameters, dict):
            raise PipelineError("parameters must be an explicit mapping, including when empty")
        canonical_json(self.parameters)

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "MetricSelector":
        required = {"metric_id", "metric_version", "parameters", "scope", "metric_set_id", "protocol_id"}
        optional = {"observation_source", "alignment"}
        if not required <= set(value) or set(value) - required - optional:
            raise PipelineError(f"Metric selector requires exactly {sorted(required)} plus optional {sorted(optional)}; received {sorted(value)}")
        return cls(**dict(value))


@dataclass(frozen=True)
class SelectionConfig:
    feature_keys: dict[str, MetricSelector]
    target_keys: dict[str, MetricSelector]
    repeat_mode: str
    missing: str
    run_ids: tuple[str, ...] | str
    run_groups: dict[str, dict[str, dict[str, str]]] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if self.repeat_mode not in {"keep", "mean"}:
            raise PipelineError("repeat_mode must explicitly be keep or mean")
        if self.missing not in {"error", "mask"}:
            raise PipelineError("missing must explicitly be error or mask")
        if not self.feature_keys and not self.target_keys:
            raise PipelineError("Select at least one feature or target")
        for values in (self.feature_keys, self.target_keys):
            for alias, selector in values.items():
                if not isinstance(alias, str) or not alias or "/" in alias:
                    raise PipelineError("Metric aliases must be nonempty strings without '/' ")
                if not isinstance(selector, MetricSelector):
                    raise PipelineError("Construct selectors with MetricSelector or SelectionConfig.from_dict")
        protocols = {selector.protocol_id for values in (self.feature_keys, self.target_keys)
                     for selector in values.values() if selector.protocol_id}
        if len(protocols) > 1:
            raise PipelineError("Select one attack protocol per configuration; independent protocols cannot share a sample")
        contexts = {(selector.metric_set_id, selector.protocol_id) for values in (self.feature_keys, self.target_keys)
                    for selector in values.values()}
        sets = {set_id for set_id, _ in contexts}
        if len(sets) != len(contexts):
            raise PipelineError("One metric_set_id cannot identify both static and attack contexts")
        if not isinstance(self.run_groups, dict):
            raise PipelineError("run_groups must map graph_id -> sample_key -> metric_set_id -> run_id")
        for graph_id, groups in self.run_groups.items():
            if not isinstance(graph_id, str) or not graph_id or not isinstance(groups, dict) or not groups:
                raise PipelineError("run_groups requires explicit graph IDs and nonempty sample groups")
            for sample_key, bindings in groups.items():
                if not isinstance(sample_key, str) or not sample_key or not isinstance(bindings, dict) or set(bindings) != sets:
                    raise PipelineError("Each run group must bind every selected metric_set_id exactly once")
                if any(not isinstance(run_id, str) or not run_id for run_id in bindings.values()):
                    raise PipelineError("run_groups bindings require nonempty run IDs")
            serialized = [canonical_json(bindings) for bindings in groups.values()]
            if len(set(serialized)) != len(serialized):
                raise PipelineError("Duplicate run group bindings would duplicate the same sample")
        if self.run_groups and self.run_ids != "all":
            raise PipelineError("Use run_ids='all' with explicit run_groups; bindings perform run selection")
        if len([context for context in contexts if context[1]]) > 1 and not self.run_groups:
            raise PipelineError("Independent attack metric sets require explicit run_groups; run_id includes metric_set_id")
        if not protocols and len(contexts) > 1 and self.run_ids != "all" and not self.run_groups:
            raise PipelineError("Independent static metric sets require run_groups for explicit run selection")
        if isinstance(self.run_ids, str):
            if self.run_ids != "all":
                raise PipelineError("run_ids must be 'all' or an explicit nonempty sequence")
        elif (not isinstance(self.run_ids, tuple) or not self.run_ids
              or any(not isinstance(x, str) or not x for x in self.run_ids)
              or len(set(self.run_ids)) != len(self.run_ids)):
            raise PipelineError("run_ids must contain unique nonempty string IDs")

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "SelectionConfig":
        required = {"feature_keys", "target_keys", "repeat_mode", "missing", "run_ids"}
        if not required <= set(value) or set(value) - required - {"run_groups"}:
            raise PipelineError(f"Selection config requires exactly {sorted(required)} plus optional run_groups; received {sorted(value)}")
        result = dict(value)
        for key in ("feature_keys", "target_keys"):
            if not isinstance(value[key], Mapping):
                raise PipelineError(f"{key} must map user aliases to explicit selectors")
            result[key] = {alias: MetricSelector.from_dict(selector) for alias, selector in value[key].items()}
        if not isinstance(result["run_ids"], str):
            result["run_ids"] = tuple(result["run_ids"])
        return cls(**result)

    def to_dict(self) -> dict[str, Any]:
        result = asdict(self)
        if isinstance(result["run_ids"], tuple):
            result["run_ids"] = list(result["run_ids"])
        return result

    @property
    def config_id(self) -> str:
        return content_id(self.to_dict())


# This type describes metric selection; split/cache settings stay independently explicit.
PipelineConfig = SelectionConfig
