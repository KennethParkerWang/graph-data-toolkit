"""Streaming masked feature standardization fitted exclusively on train samples."""

from __future__ import annotations

from copy import deepcopy
from typing import Any, Iterable

import numpy as np

from .config import canonical_json, content_id
from .models import MetricArray, PipelineError, TrainingSample


def _definition(metric: MetricArray) -> dict[str, Any]:
    return {"metric_id": metric.metric_id, "metric_version": metric.metric_version,
            "parameters": metric.parameters, "scope": metric.scope, "axis_names": list(metric.axis_names),
            "units": metric.metadata.get("units"), "method": metric.metadata.get("method"),
            "observation_source": metric.metadata.get("observation_projection", {}).get("source"),
            "alignment": metric.metadata.get("observation_projection", {}).get("alignment")}


def _identity(definition: dict[str, Any]) -> dict[str, Any]:
    """Definitions remain known even when a selected observation has no shape."""
    return {key: definition.get(key) for key in (
        "metric_id", "metric_version", "parameters", "scope", "observation_source", "alignment")}


class FeatureNormalizer:
    """One mean/scale per selected feature alias, pooled over its valid cells.

    Node/edge/trajectory lengths may differ. Targets are always copied unchanged.
    This is a training transform; source physical values/definitions are preserved.
    """

    def __init__(self) -> None:
        self.state: dict[str, Any] | None = None

    def fit(self, samples: Iterable[TrainingSample]) -> "FeatureNormalizer":
        accum: dict[str, dict[str, Any]] = {}
        identities: dict[str, dict[str, Any]] = {}
        sample_ids, graph_ids, selection_ids = set(), set(), set()
        for sample in samples:
            if sample.split != "train":
                raise PipelineError(f"Normalization fit accepts train only: {sample.sample_id} has split={sample.split}")
            if sample.sample_id in sample_ids:
                raise PipelineError(f"Duplicate sample during normalization fit: {sample.sample_id}")
            sample_ids.add(sample.sample_id)
            graph_ids.add(sample.graph.graph_id)
            if sample.provenance.get("selection_id"):
                selection_ids.add(sample.provenance["selection_id"])
            for alias, metric in sample.features.items():
                metric.validate()
                definition = _definition(metric)
                identity = _identity(definition)
                if alias in identities and canonical_json(identities[alias]) != canonical_json(identity):
                    raise PipelineError(f"Feature definition conflict while fitting {alias}")
                identities[alias] = identity
                if np.any(metric.valid_mask & ~np.isfinite(metric.values)):
                    raise PipelineError(f"Feature {alias} contains valid nonfinite values; normalization requires an explicit derived transform")
                if metric.metadata.get("shape_unknown"):
                    continue
                if alias not in accum:
                    accum[alias] = {"definition": definition, "count": 0, "mean": 0.0, "m2": 0.0}
                part = accum[alias]
                if canonical_json(part["definition"]) != canonical_json(definition):
                    raise PipelineError(f"Feature definition conflict while fitting {alias}")
                values = np.asarray(metric.values[metric.valid_mask], dtype=np.float64)
                if not values.size:
                    continue
                count = int(values.size)
                mean = float(np.mean(values))
                m2 = float(np.sum((values - mean) ** 2))
                total = part["count"] + count
                delta = mean - part["mean"]
                part["m2"] += m2 + delta * delta * part["count"] * count / total
                part["mean"] += delta * count / total
                part["count"] = total
        if not sample_ids:
            raise PipelineError("Cannot fit normalization without training samples")
        if not accum:
            raise PipelineError("Cannot fit normalization without features with known shapes")
        if set(identities) - set(accum):
            raise PipelineError(f"Features have no known training values: {sorted(set(identities) - set(accum))}")
        stats = {}
        for alias, part in accum.items():
            if not part["count"]:
                raise PipelineError(f"Feature {alias} has no valid training values")
            variance = max(0.0, part["m2"] / part["count"])
            scale = float(np.sqrt(variance)) if variance > 0 else 1.0
            stats[alias] = {"definition": part["definition"], "count": part["count"],
                            "mean": part["mean"], "variance": variance, "scale": scale}
        body = {"schema_version": "feature-normalizer-v1", "method": "masked_standardize_per_alias",
                "variance_ddof": 0, "fit_split": "train", "features": stats,
                "training_sample_ids": sorted(sample_ids), "training_graph_ids": sorted(graph_ids),
                "selection_ids": sorted(selection_ids)}
        self.state = {"normalizer_id": content_id(body), **body}
        return self

    def transform(self, sample: TrainingSample) -> TrainingSample:
        if self.state is None:
            raise PipelineError("Fit or restore the normalizer before transform")
        result = deepcopy(sample)
        for alias, metric in result.features.items():
            metric.validate()
            if np.any(metric.valid_mask & ~np.isfinite(metric.values)):
                raise PipelineError(f"Feature {alias} contains valid nonfinite values; normalization requires an explicit derived transform")
            if alias not in self.state["features"]:
                raise PipelineError(f"Feature {alias} was not fitted on training data")
            stats = self.state["features"][alias]
            if canonical_json(_identity(stats["definition"])) != canonical_json(_identity(_definition(metric))):
                raise PipelineError(f"Feature definition conflict while transforming {alias}")
            if metric.metadata.get("shape_unknown"):
                continue
            if canonical_json(stats["definition"]) != canonical_json(_definition(metric)):
                raise PipelineError(f"Feature definition conflict while transforming {alias}")
            values = np.asarray(metric.values, dtype=np.float64).copy()
            values[metric.valid_mask] = (values[metric.valid_mask] - stats["mean"]) / stats["scale"]
            metric.values = values
            metric.metadata["training_transform"] = {"normalizer_id": self.state["normalizer_id"],
                                                       "method": self.state["method"], "source_units": stats["definition"]["units"]}
        result.provenance["normalizer_id"] = self.state["normalizer_id"]
        return result

    def to_dict(self) -> dict[str, Any]:
        if self.state is None:
            raise PipelineError("Normalizer is not fitted")
        return deepcopy(self.state)

    @classmethod
    def from_dict(cls, state: dict[str, Any]) -> "FeatureNormalizer":
        state = deepcopy(state)
        body = {key: value for key, value in state.items() if key != "normalizer_id"}
        if state.get("schema_version") != "feature-normalizer-v1" or state.get("fit_split") != "train" or state.get("normalizer_id") != content_id(body):
            raise PipelineError("Invalid or modified normalizer state")
        for stats in state["features"].values():
            if stats["count"] <= 0 or stats["scale"] <= 0 or stats["variance"] < 0:
                raise PipelineError("Invalid normalizer statistics")
        result = cls()
        result.state = state
        return result
