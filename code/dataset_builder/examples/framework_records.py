"""Small in-memory fixtures; not a producer format or scientific metric library."""

from __future__ import annotations

import hashlib

import numpy as np

from dataset_builder.models import GraphRecord, MetricArray, TrainingSample


def _id(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def framework_samples() -> list[TrainingSample]:
    """Exercise ragged axes, missing values, directed arcs and isolated nodes."""
    samples: list[TrainingSample] = []
    for i in range(8):
        n = (3, 5, 1, 7, 4, 6, 2, 8)[i]
        directed = i % 2 == 1
        edge_list = np.array([[1, 2], [2, 1]] if directed else [[1, 2]], dtype=np.uint32)
        if i in (2, 6):
            edge_list = np.empty((0, 2), dtype=np.uint32)
        graph_id = _id(f"framework-only-graph-{i}")
        graph = GraphRecord(
            graph_id, _id(f"framework-only-topology-{i}"), graph_id,
            n, directed, edge_list,
            metadata={"model": "framework_fixture", "fixture_only": True},
            source={"schema_version": "in-memory-fixture", "fixture_only": True},
        )
        m = graph.num_edges
        node_values = np.arange(n, dtype=np.float64)
        node_mask = np.ones(n, dtype=bool)
        node_mask[-1] = False
        node_values[-1] = np.nan
        features = {
            "node_demo": MetricArray(
                "fixture_node", "fixture-v1", {}, "node", node_values,
                ("node",), node_mask, "partial", "Synthetic invalid final node",
                node_ids=np.arange(1, n + 1), axis_ids={"node": np.arange(1, n + 1)},
            ),
            "edge_demo": MetricArray(
                "fixture_edge", "fixture-v1", {}, "edge", np.arange(m, dtype=np.float64),
                ("edge",), np.ones(m, dtype=bool), "ok",
                edge_ids=np.arange(1, m + 1), axis_ids={"edge": np.arange(1, m + 1)},
            ),
        }
        curve_len = i + 1
        positions = np.arange(curve_len, dtype=np.float64) ** 2
        curve = np.arange(curve_len, dtype=np.float64)
        curve_mask = np.ones(curve_len, dtype=bool)
        if i == 3:
            curve_mask[-1] = False
            curve[-1] = np.nan
        targets = {
            "scalar_demo": MetricArray(
                "fixture_scalar", "fixture-v1", {}, "graph", np.asarray(float(i)),
                (), np.asarray(True), "ok",
            ),
            "curve_demo": MetricArray(
                "fixture_curve", "fixture-v1", {}, "trajectory", curve,
                ("step",), curve_mask, "partial" if i == 3 else "ok",
                axis_positions={"removed_count": positions, "actual_fraction": positions / max(1.0, positions[-1])},
                metadata={"fixture_only": True, "units": "fixture_unit"},
            ),
        }
        samples.append(TrainingSample(
            _id(f"fixture-sample-{i}"), graph, features, targets,
            ("train" if i < 4 else "validation" if i < 6 else "test"),
            {"fixture_only": True, "run_ids": [f"fixture-run-{i}"], "protocol_id": "fixture-protocol"},
        ))
    return samples
