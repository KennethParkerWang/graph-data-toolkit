"""In-memory adapter types. These do not define either producer's MAT schema."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import numpy as np


class PipelineError(ValueError):
    """An input violates the requested data contract."""


@dataclass
class GraphRecord:
    graph_id: str
    topology_hash: str
    origin_graph_id: str
    num_nodes: int
    directed: bool
    edge_list: np.ndarray  # Canonical M x 2, original one-based endpoints.
    metadata: dict[str, Any] = field(default_factory=dict)
    source: dict[str, Any] = field(default_factory=dict)
    source_edge_order: np.ndarray | None = None

    @property
    def num_edges(self) -> int:
        return int(self.edge_list.shape[0])

    def validate(self) -> None:
        if isinstance(self.num_nodes, (bool, np.bool_)) or not isinstance(self.num_nodes, (int, np.integer)) or self.num_nodes < 1:
            raise PipelineError("Graph num_nodes must explicitly include all nodes and be positive")
        edges = np.asarray(self.edge_list)
        if edges.ndim != 2 or edges.shape[1] != 2 or edges.dtype.kind not in "iu":
            raise PipelineError("Internal canonical edge_list must be an integer M x 2 array")
        if np.any(edges < 1) or np.any(edges > self.num_nodes):
            raise PipelineError("Graph edge endpoint outside original 1..N IDs")
        if not isinstance(self.directed, (bool, np.bool_)):
            raise PipelineError("Graph directed must be boolean")
        if not self.directed and np.any(edges[:, 0] >= edges[:, 1]):
            raise PipelineError("Undirected canonical edges require source < target")
        if self.source_edge_order is not None:
            order = np.asarray(self.source_edge_order)
            if order.ndim != 1 or order.dtype.kind not in "iu" or not np.array_equal(np.sort(order), np.arange(1, self.num_edges + 1)):
                raise PipelineError("source_edge_order must be a permutation of original edge IDs")

    def model_edges(self, bidirectional: bool = False) -> tuple[np.ndarray, np.ndarray]:
        """Return zero-based 2 x E edges and one-based original edge IDs."""
        edges = np.asarray(self.edge_list, dtype=np.int64).T - 1
        ids = np.arange(1, self.num_edges + 1, dtype=np.int64)
        if bidirectional and not self.directed:
            edges = np.concatenate((edges, edges[::-1]), axis=1)
            ids = np.concatenate((ids, ids))
        return edges, ids


@dataclass
class MetricArray:
    metric_id: str
    metric_version: str
    parameters: dict[str, Any]
    scope: str
    values: np.ndarray
    axis_names: tuple[str, ...]
    valid_mask: np.ndarray
    status: str
    reason: str = ""
    node_ids: np.ndarray | None = None
    edge_ids: np.ndarray | None = None
    axis_positions: dict[str, np.ndarray] = field(default_factory=dict)
    axis_ids: dict[str, np.ndarray] = field(default_factory=dict)
    metadata: dict[str, Any] = field(default_factory=dict)
    present_mask: np.ndarray | None = None

    def validate(self) -> None:
        if self.scope not in {"graph", "node", "edge", "distribution", "matrix", "trajectory"}:
            raise PipelineError(f"Unsupported metric scope: {self.scope}")
        if self.values.shape != self.valid_mask.shape:
            raise PipelineError(f"{self.metric_id}: values/mask shapes differ")
        unavailable_empty = (
            self.values.size == 0 and not self.axis_names
            and self.status in {"failed", "not_applicable", "not_computed", "undefined"}
            and self.metadata.get("shape_unknown", False)
        )
        if len(self.axis_names) != self.values.ndim and not unavailable_empty:
            raise PipelineError(f"{self.metric_id}: axis_names does not describe values")
        if len(set(self.axis_names)) != len(self.axis_names):
            raise PipelineError(f"{self.metric_id}: duplicate axis names")
        if self.valid_mask.dtype != np.bool_:
            raise PipelineError(f"{self.metric_id}: valid_mask must be boolean")
        if self.present_mask is not None:
            if self.present_mask.shape != self.values.shape or self.present_mask.dtype != np.bool_:
                raise PipelineError(f"{self.metric_id}: present_mask must be boolean with values shape")
            if np.any(self.valid_mask & ~self.present_mask):
                raise PipelineError(f"{self.metric_id}: valid values must refer to present observations")
        if self.values.dtype.kind not in "biuf":
            raise PipelineError(f"{self.metric_id}: values must be real numeric data")
        if np.any(self.valid_mask & np.isnan(self.values)):
            raise PipelineError(f"{self.metric_id}: NaN cannot be marked valid")
        if np.any(self.valid_mask & np.isinf(self.values)) and not self.metadata.get("allows_infinity", False):
            raise PipelineError(f"{self.metric_id}: valid infinity requires its source definition")
        for axis, ids in self.axis_ids.items():
            if axis not in self.axis_names or np.asarray(ids).ndim != 1:
                raise PipelineError(f"{self.metric_id}: invalid IDs for axis {axis}")
            if len(ids) != self.values.shape[self.axis_names.index(axis)]:
                raise PipelineError(f"{self.metric_id}: ID length mismatch for {axis}")
        for name in ("node_ids", "edge_ids"):
            ids = getattr(self, name)
            if ids is None:
                continue
            ids = np.asarray(ids)
            if (ids.ndim != 1 or ids.dtype.kind not in "iuf" or not np.all(np.isfinite(ids))
                    or np.any(ids < 1) or np.any(ids != np.floor(ids)) or len(np.unique(ids)) != len(ids)):
                raise PipelineError(f"{self.metric_id}: {name} must contain unique positive integer IDs")
            if self.values.ndim == 1 and len(ids) != self.values.shape[0]:
                raise PipelineError(f"{self.metric_id}: {name} length does not match values")
        for key, positions in self.axis_positions.items():
            positions = np.asarray(positions)
            if positions.ndim != 1 or positions.dtype.kind not in "biuf":
                raise PipelineError(f"{self.metric_id}: {key} positions must be a numeric vector")
            axis = self.metadata.get("axis_position_axes", {}).get(key, key)
            if axis in self.axis_names:
                length = self.values.shape[self.axis_names.index(axis)]
            elif self.values.ndim == 1:
                length = self.values.shape[0]
            else:
                raise PipelineError(f"{self.metric_id}: {key} needs an explicit axis_position_axes mapping")
            if len(positions) != length:
                raise PipelineError(f"{self.metric_id}: {key} positions length does not match values")


@dataclass
class ObservationRecord:
    """One validated state or requested sample with its original logical axes."""

    index: int  # One-based position in states/sampled; repeated requests stay distinct.
    metrics: list[MetricArray]
    positions: dict[str, float | int | bool]
    status: str
    reason: str = ""
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class MetricRun:
    graph_id: str
    topology_hash: str
    metric_set_id: str
    protocol_id: str
    run_id: str
    status: str
    metrics: list[MetricArray]
    source: dict[str, Any] = field(default_factory=dict)
    metadata: dict[str, Any] = field(default_factory=dict)
    observations: dict[str, list[ObservationRecord]] = field(default_factory=dict)


@dataclass
class TrainingSample:
    sample_id: str
    graph: GraphRecord
    features: dict[str, MetricArray]
    targets: dict[str, MetricArray]
    split: str
    provenance: dict[str, Any] = field(default_factory=dict)

    def validate(self) -> None:
        self.graph.validate()
        for metric in (*self.features.values(), *self.targets.values()):
            metric.validate()
            for name, maximum in (("node_ids", self.graph.num_nodes), ("edge_ids", self.graph.num_edges)):
                ids = getattr(metric, name)
                if ids is not None and np.any(np.asarray(ids) > maximum):
                    raise PipelineError(f"{metric.metric_id}: {name} exceeds original graph range")
