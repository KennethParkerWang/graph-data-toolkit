"""Independent metric padding and PyTorch/PyG topology batching.

Raw invalid values and original coordinate/ID arrays survive collation.
``values`` is a compute view with invalid/padded elements zeroed; training
losses must use ``valid_mask``. ``present_mask`` distinguishes padding/absence
from stored invalid results, while status/reason retain their meaning.
Textual axis_ids use padded Python strings/None plus a tensor present_mask;
numeric axis_ids and positions use tensors.
"""

from __future__ import annotations

from typing import Any, Sequence

import numpy as np

from .cache import canonical_json
from .models import MetricArray, PipelineError, TrainingSample


def _tensor(array: np.ndarray):
    import torch
    try:
        native = np.asarray(array).astype(array.dtype.newbyteorder("="), copy=False)
        return torch.from_numpy(np.ascontiguousarray(native).copy())
    except (TypeError, ValueError) as exc:
        raise PipelineError(f"Torch cannot represent dtype {array.dtype}; configure an explicit derived cast") from exc


def _pad_arrays(arrays: list[np.ndarray | None], *, rank: int | None = None) -> dict[str, Any]:
    """Pad each dimension only to this batch's maximum; preserve raw dtype."""
    available = [np.asarray(value) for value in arrays if value is not None]
    if rank is None:
        rank = available[0].ndim if available else 1
    if any(value.ndim != rank for value in available):
        raise PipelineError("Cannot pad arrays with inconsistent axis ranks")
    textual = any(value.dtype.kind in "UO" for value in available)
    if textual and not all(value.dtype.kind in "UO" and all(isinstance(item, str) for item in value.flat) for value in available):
        raise PipelineError("Cannot mix textual and numeric axis coordinates in one batch")
    dtype = np.result_type(*(value.dtype for value in available)) if available else np.dtype("float64")
    if dtype.kind == "f":
        for value in available:
            if value.dtype.kind in "iu" and not np.array_equal(value.astype(dtype).astype(object), value.astype(object)):
                raise PipelineError("Padding would make a lossy integer-to-float conversion; configure an explicit derived cast")
    shape = tuple(max((value.shape[axis] for value in available), default=0) for axis in range(rank))
    values = np.full((len(arrays), *shape), None, dtype=object) if textual else np.zeros((len(arrays), *shape), dtype=dtype)
    present = np.zeros(values.shape, dtype=bool)
    shapes: list[tuple[int, ...] | None] = []
    for i, value in enumerate(arrays):
        if value is None:
            shapes.append(None)
            continue
        value = np.asarray(value)
        slot = (i,) + tuple(slice(0, size) for size in value.shape)
        values[slot] = value
        present[slot] = True
        shapes.append(value.shape)
    return {"values": values.tolist() if textual else _tensor(values), "present_mask": _tensor(present), "shapes": shapes,
            "source_dtypes": [None if value is None else np.asarray(value).dtype.str for value in arrays]}


def _is_unknown(metric: MetricArray | None) -> bool:
    return metric is None or bool(metric.metadata.get("shape_unknown", False))


def _is_missing(metric: MetricArray | None) -> bool:
    return metric is None or bool(metric.metadata.get("selection_missing", False))


def _collate_metric(metrics: list[MetricArray | None]) -> dict[str, Any]:
    existing = [metric for metric in metrics if metric is not None]
    if not existing:
        raise PipelineError("Metric batch has no definition")
    for metric in existing:
        metric.validate()
    known = [metric for metric in existing if not _is_unknown(metric)]
    template = known[0] if known else existing[0]
    signature = lambda metric: canonical_json({"metric_id": metric.metric_id, "metric_version": metric.metric_version,
                                               "parameters": metric.parameters, "scope": metric.scope,
                                               "observation_source": metric.metadata.get("observation_projection", {}).get("source"),
                                               "alignment": metric.metadata.get("observation_projection", {}).get("alignment")})
    if any(signature(metric) != signature(template) for metric in existing):
        raise PipelineError("Metric definition conflict within batch")
    numeric_definition = lambda metric: canonical_json({
        "units": metric.metadata.get("units"), "method": metric.metadata.get("method"),
        "training_transform": metric.metadata.get("training_transform") or None,
        "observation_source": metric.metadata.get("observation_projection", {}).get("source"),
        "alignment": metric.metadata.get("observation_projection", {}).get("alignment"),
    })
    if any(numeric_definition(metric) != numeric_definition(template) for metric in known):
        raise PipelineError("Metric units/method/training_transform definition conflict within batch")
    if any(metric.axis_names != template.axis_names for metric in known):
        raise PipelineError(f"{template.metric_id}: axis names/order conflict within batch")
    raw = _pad_arrays([None if _is_unknown(metric) else metric.values for metric in metrics], rank=len(template.axis_names))
    masks = _pad_arrays([None if _is_unknown(metric) else metric.valid_mask for metric in metrics], rank=len(template.axis_names))
    valid = masks["values"].bool() & raw["present_mask"]
    present = raw["present_mask"].clone()
    source_presence = _pad_arrays([
        None if _is_unknown(metric) else
        metric.present_mask if metric.present_mask is not None else np.ones(metric.values.shape, dtype=bool)
        for metric in metrics
    ], rank=len(template.axis_names))
    present &= source_presence["values"].bool()
    valid &= present
    for i, metric in enumerate(metrics):
        if _is_missing(metric):
            present[i] = False
            valid[i] = False
    # NumPy also supports unsigned integer masking, while some torch kernels
    # do not. This is a CPU batch view and preserves the raw numeric dtype.
    values = _tensor(np.where(valid.numpy(), raw["values"].numpy(), 0))
    result = {
        "metric_id": template.metric_id, "metric_version": template.metric_version,
        "parameters": template.parameters, "scope": template.scope, "axis_names": template.axis_names,
        "units": template.metadata.get("units"), "method": template.metadata.get("method"),
        "training_transform": template.metadata.get("training_transform") or None,
        "values": values, "raw_values": raw["values"], "valid_mask": valid,
        "present_mask": present, "shapes": raw["shapes"],
        "source_dtypes": raw["source_dtypes"],
        "status": [metric.status if metric is not None else "not_computed" for metric in metrics],
        "reason": [metric.reason if metric is not None else "Metric absent from sample" for metric in metrics],
        "metadata": [metric.metadata if metric is not None else {} for metric in metrics],
        "source_axis_names": [metric.axis_names if metric is not None else None for metric in metrics],
    }
    for name in ("node_ids", "edge_ids"):
        result[name] = _pad_arrays([getattr(metric, name) if metric is not None else None for metric in metrics])
    for name in ("axis_positions", "axis_ids"):
        keys = sorted({key for metric in existing for key in getattr(metric, name)})
        result[name] = {key: _pad_arrays([getattr(metric, name).get(key) if metric is not None else None for metric in metrics]) for key in keys}
    return result


def collate_samples(samples: Sequence[TrainingSample], *, bidirectional: bool = True) -> dict[str, Any]:
    """Return a CPU tensor batch with one padding shape per selected metric."""
    if not samples:
        raise PipelineError("Cannot collate an empty batch")
    for sample in samples:
        sample.validate()
    node_counts = np.asarray([sample.graph.num_nodes for sample in samples], dtype=np.int64)
    ptr = np.concatenate((np.zeros(1, dtype=np.int64), np.cumsum(node_counts)))
    edges, original_ids, edge_batches = [], [], []
    for i, sample in enumerate(samples):
        edge_index, edge_id = sample.graph.model_edges(bidirectional=bidirectional)
        edges.append(edge_index + ptr[i])
        original_ids.append(edge_id)
        edge_batches.append(np.full(len(edge_id), i, dtype=np.int64))
    result = {
        "sample_id": [sample.sample_id for sample in samples],
        "graph_id": [sample.graph.graph_id for sample in samples],
        "topology_hash": [sample.graph.topology_hash for sample in samples],
        "origin_graph_id": [sample.graph.origin_graph_id for sample in samples],
        "split": [sample.split for sample in samples],
        "num_nodes": _tensor(node_counts), "node_ptr": _tensor(ptr),
        "num_edges": _tensor(np.asarray([sample.graph.num_edges for sample in samples], dtype=np.int64)),
        "directed": _tensor(np.asarray([sample.graph.directed for sample in samples], dtype=bool)),
        "edge_index": _tensor(np.concatenate(edges, axis=1)),
        "original_edge_id": _tensor(np.concatenate(original_ids)),
        "original_node_id": _tensor(np.concatenate([np.arange(1, n + 1, dtype=np.int64) for n in node_counts])),
        "node_batch": _tensor(np.repeat(np.arange(len(samples), dtype=np.int64), node_counts)),
        "edge_batch": _tensor(np.concatenate(edge_batches)),
        "graph_metadata": [sample.graph.metadata for sample in samples],
        "graph_source": [sample.graph.source for sample in samples],
        "source_edge_order": [sample.graph.source_edge_order for sample in samples],
        "provenance": [sample.provenance for sample in samples],
    }
    for role in ("features", "targets"):
        keys = sorted({key for sample in samples for key in getattr(sample, role)})
        result[role] = {key: _collate_metric([getattr(sample, role).get(key) for sample in samples]) for key in keys}
    return result


def to_pyg_data(sample: TrainingSample, *, bidirectional: bool = True):
    """Make a PyG Data with explicit N and a lossless TrainingSample payload.

    PyG's ordinary DataLoader may batch the topology; its ``training_sample``
    field becomes a list. Use make_pyg_loader for padded metric tensor views.
    Original edge IDs remain one-based and local to each graph, including
    both directions of an expanded undirected edge.
    """
    from torch_geometric.data import Data
    sample.validate()
    edges, ids = sample.graph.model_edges(bidirectional=bidirectional)
    return Data(edge_index=_tensor(edges), num_nodes=sample.graph.num_nodes,
                original_edge_id=_tensor(ids),
                original_node_id=_tensor(np.arange(1, sample.graph.num_nodes + 1, dtype=np.int64)),
                graph_id=sample.graph.graph_id, sample_id=sample.sample_id,
                directed=sample.graph.directed, training_sample=sample)


def collate_pyg_samples(samples: Sequence[TrainingSample], *, bidirectional: bool = True) -> dict[str, Any]:
    from torch_geometric.data import Batch
    result = collate_samples(samples, bidirectional=bidirectional)
    result["graph_batch"] = Batch.from_data_list([to_pyg_data(sample, bidirectional=bidirectional) for sample in samples])
    return result
