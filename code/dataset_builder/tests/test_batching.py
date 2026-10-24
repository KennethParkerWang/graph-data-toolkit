"""Variable-size CPU batches, original IDs, invalid states and PyG workers."""

from copy import deepcopy

import numpy as np
import pytest

torch = pytest.importorskip("torch")

from dataset_builder.batching import collate_samples, collate_pyg_samples, to_pyg_data
from dataset_builder.cache import build_cache
from dataset_builder.dataset import TrainingDataset, PyGTrainingDataset, make_torch_loader, make_pyg_loader
from dataset_builder.models import GraphRecord, MetricArray, PipelineError, TrainingSample


def make_sample(name, nodes=4, directed=False, length=3):
    graph = GraphRecord(name, "topo-" + name, name, nodes, directed,
                        np.asarray([[1, 2], [2, 1]] if directed else [[1, 2]], dtype=np.uint32))
    values = np.arange(length, dtype=float)
    mask = np.ones(length, dtype=bool)
    if length > 1:
        values[1], mask[1] = np.nan, False
    curve = MetricArray("curve", "v1", {}, "trajectory", values, ("step",), mask, "partial",
                        axis_positions={"actual_fraction": np.arange(length) / max(length - 1, 1)},
                        axis_ids={"step": np.arange(1, length + 1)})
    nodes_metric = MetricArray("node", "v1", {}, "node", np.asarray([9., 3.]), ("node",),
                               np.ones(2, dtype=bool), "ok", node_ids=np.asarray([nodes, 1]))
    edge = MetricArray("edge", "v1", {}, "edge", np.arange(graph.num_edges, dtype=float), ("edge",),
                       np.ones(graph.num_edges, dtype=bool), "ok", edge_ids=np.arange(1, graph.num_edges + 1))
    scalar = MetricArray("scalar", "v1", {}, "graph", np.asarray(0.), (), np.asarray(True), "ok")
    return TrainingSample(name, graph, {"node": nodes_metric, "edge": edge}, {"curve": curve, "scalar": scalar}, "train")


def test_padding_is_metric_specific_and_keeps_raw_mask_axes_ids():
    a, b = make_sample("a"), make_sample("b", nodes=6, directed=True, length=5)
    batch = collate_samples([a, b])
    assert batch["edge_index"].tolist() == [[0, 1, 4, 5], [1, 0, 5, 4]]
    assert batch["original_edge_id"].tolist() == [1, 1, 1, 2]
    assert batch["node_ptr"].tolist() == [0, 4, 10]
    assert batch["num_nodes"].tolist() == [4, 6]
    curve = batch["targets"]["curve"]
    assert curve["values"].shape == (2, 5)
    assert curve["values"][0].tolist() == [0, 0, 2, 0, 0]
    assert torch.isnan(curve["raw_values"][0, 1])
    assert curve["valid_mask"][0].tolist() == [True, False, True, False, False]
    assert curve["present_mask"][0].tolist() == [True, True, True, False, False]
    assert curve["axis_positions"]["actual_fraction"]["values"][0].tolist() == [0, .5, 1, 0, 0]
    assert curve["axis_ids"]["step"]["values"][0].tolist() == [1, 2, 3, 0, 0]
    assert batch["features"]["node"]["node_ids"]["values"].tolist() == [[4, 1], [6, 1]]
    assert batch["features"]["edge"]["values"].shape == (2, 2)
    assert batch["targets"]["scalar"]["values"].shape == (2,)
    assert batch["targets"]["scalar"]["valid_mask"].all()


def test_missing_failed_not_applicable_undefined_and_zero_remain_distinct():
    samples = [make_sample(str(i)) for i in range(5)]
    for item, status in zip(samples, ["ok", "failed", "not_applicable", "undefined", "not_computed"]):
        scalar = item.targets["scalar"]
        scalar.status = status
        if status != "ok":
            scalar.values = np.asarray(np.nan)
            scalar.valid_mask = np.asarray(False)
    samples[-1].targets["scalar"] = MetricArray("scalar", "v1", {}, "graph", np.empty((0,)), ("missing",),
                                               np.empty((0,), dtype=bool), "not_computed", metadata={"shape_unknown": True, "selection_missing": True})
    scalar = collate_samples(samples)["targets"]["scalar"]
    assert scalar["values"].tolist() == [0, 0, 0, 0, 0]
    assert scalar["valid_mask"].tolist() == [True, False, False, False, False]
    assert scalar["present_mask"].tolist() == [True, True, True, True, False]
    assert scalar["status"] == ["ok", "failed", "not_applicable", "undefined", "not_computed"]
    assert torch.isnan(scalar["raw_values"][1:4]).all()


def test_empty_edges_isolated_nodes_and_definition_conflict():
    item = make_sample("empty")
    item.graph.edge_list = np.empty((0, 2), dtype=np.uint32)
    item.features["edge"].values = np.empty((0,))
    item.features["edge"].valid_mask = np.empty((0,), dtype=bool)
    item.features["edge"].edge_ids = np.empty((0,), dtype=np.int64)
    batch = collate_samples([item])
    assert batch["edge_index"].shape == (2, 0)
    assert batch["node_batch"].tolist() == [0, 0, 0, 0]
    other = deepcopy(item)
    other.targets["curve"].metric_version = "v2"
    with pytest.raises(PipelineError, match="definition"):
        collate_samples([item, other])


def test_pyg_explicit_node_count_edge_mapping_and_ragged_safe_payload():
    pytest.importorskip("torch_geometric")
    from torch_geometric.loader import DataLoader
    a, b = make_sample("a"), make_sample("b", nodes=6, directed=True, length=5)
    data = to_pyg_data(a)
    assert data.num_nodes == 4
    assert data.original_edge_id.tolist() == [1, 1]
    batch = collate_pyg_samples([a, b])
    assert batch["graph_batch"].num_nodes == 10
    assert batch["graph_batch"].ptr.tolist() == [0, 4, 10]
    assert batch["graph_batch"].original_edge_id.tolist() == [1, 1, 1, 2]
    assert batch["graph_batch"].training_sample[1].targets["curve"].values.shape == (5,)
    ordinary = next(iter(DataLoader([to_pyg_data(a), to_pyg_data(b)], batch_size=2)))
    assert ordinary.num_nodes == 10
    assert len(ordinary.training_sample) == 2


@pytest.mark.parametrize("workers", [0, 2])
def test_cpu_loader_and_independent_spawn_workers(tmp_path, workers):
    path = build_cache([make_sample("a"), make_sample("b", length=5)], tmp_path, {}, shard_size=1)
    with TrainingDataset(path) as dataset:
        # Open a parent handle deliberately: spawn must not pickle/reuse it.
        dataset[0]
        options = {"multiprocessing_context": "spawn"} if workers else {}
        loader = make_torch_loader(dataset, batch_size=2, num_workers=workers, **options)
        batch = next(iter(loader))
        assert batch["targets"]["curve"]["values"].shape == (2, 5)
        assert batch["edge_index"].device.type == "cpu"
        assert len(dataset._handles) == (1 if workers else 2)
        valid = batch["targets"]["curve"]["valid_mask"]
        target = batch["targets"]["curve"]["values"]
        prediction = torch.zeros_like(target, requires_grad=True)
        loss = ((prediction[valid] - target[valid]) ** 2).mean()
        loss.backward()
        assert torch.isfinite(loss)
        assert torch.isfinite(prediction.grad).all()


def test_pyg_loader_padding(tmp_path):
    pytest.importorskip("torch_geometric")
    path = build_cache([make_sample("a"), make_sample("b", length=7)], tmp_path, {})
    with TrainingDataset(path) as dataset:
        batch = next(iter(make_pyg_loader(dataset, batch_size=2)))
        assert batch["graph_batch"].num_graphs == 2
        assert batch["targets"]["curve"]["values"].shape == (2, 7)


def test_native_pyg_loader_reads_lazy_dataset(tmp_path):
    pytest.importorskip("torch_geometric")
    from torch_geometric.loader import DataLoader
    path = build_cache([make_sample("a"), make_sample("b", nodes=6, length=7)], tmp_path, {}, shard_size=1)
    with PyGTrainingDataset(path) as dataset:
        assert not dataset._handles
        batch = next(iter(DataLoader(dataset, batch_size=2, num_workers=0)))
        assert batch.num_nodes == 10
        assert batch.original_edge_id.tolist() == [1, 1, 1, 1]
        assert batch.training_sample[0].targets["curve"].values.shape == (3,)
        assert batch.training_sample[1].targets["curve"].values.shape == (7,)
        assert len(dataset._handles) == 2


def test_matrix_independent_axes_and_valid_infinity_preserved():
    a, b = make_sample("a"), make_sample("b", nodes=6)
    for item, size in ((a, 2), (b, 3)):
        values = np.arange(size * 2, dtype=float).reshape(size, 2)
        values[0, 1] = np.inf
        item.targets["matrix"] = MetricArray("matrix", "v1", {}, "matrix", values,
                                               ("source", "target"), np.ones(values.shape, dtype=bool), "ok",
                                               axis_ids={"source": np.arange(1, size + 1), "target": np.asarray([4, 1])},
                                               metadata={"allows_infinity": True})
    matrix = collate_samples([a, b])["targets"]["matrix"]
    assert matrix["values"].shape == (2, 3, 2)
    assert torch.isinf(matrix["values"][:, 0, 1]).all()
    assert matrix["valid_mask"][:, 0, 1].all()
    assert not matrix["present_mask"][0, 2].any()
    assert matrix["axis_ids"]["source"]["values"].tolist() == [[1, 2, 0], [1, 2, 3]]
    assert matrix["axis_ids"]["target"]["values"].tolist() == [[4, 1], [4, 1]]


def test_unsigned_integer_raw_values_remain_exact_and_lossy_promotion_fails():
    a, b = make_sample("a"), make_sample("b")
    a.targets["scalar"].values = np.asarray(2 ** 63 + 1, dtype=np.uint64)
    scalar = collate_samples([a])["targets"]["scalar"]
    assert scalar["values"].numpy()[0] == 2 ** 63 + 1
    assert scalar["raw_values"].numpy()[0] == 2 ** 63 + 1
    with pytest.raises(PipelineError, match="lossy"):
        collate_samples([a, b])


@pytest.mark.parametrize("field,value", [
    ("units", "seconds"), ("method", "approximate"),
    ("training_transform", {"normalizer_id": "another-fit", "method": "standardize"}),
])
def test_incompatible_numeric_definitions_cannot_share_a_batch(field, value):
    a, b = make_sample("a"), make_sample("b")
    b.targets["scalar"].metadata[field] = value
    with pytest.raises(PipelineError, match="definition conflict"):
        collate_samples([a, b])


def test_dynamic_details_do_not_change_metric_definition():
    a, b = make_sample("a"), make_sample("b")
    a.targets["scalar"].metadata.update({"elapsed_seconds": 1, "details": {"iterations": 2}})
    b.targets["scalar"].metadata.update({"elapsed_seconds": 4, "details": {"iterations": 5}})
    assert collate_samples([a, b])["targets"]["scalar"]["valid_mask"].all()


def test_categorical_unicode_axis_ids_are_lossless_padded_strings():
    a, b = make_sample("a"), make_sample("b", nodes=6)
    for item, labels in ((a, ["hub", "权威 authority"]), (b, ["hub"])):
        shape = (item.graph.num_nodes, len(labels))
        item.targets["hits"] = MetricArray("hits", "v1", {}, "matrix", np.ones(shape),
                                           ("node", "score"), np.ones(shape, dtype=bool), "ok",
                                           axis_ids={"node": np.arange(1, shape[0] + 1), "score": np.asarray(labels)})
    hits = collate_samples([a, b])["targets"]["hits"]
    assert hits["values"].shape == (2, 6, 2)
    assert hits["axis_ids"]["score"]["values"] == [["hub", "权威 authority"], ["hub", None]]
    assert hits["axis_ids"]["score"]["present_mask"].tolist() == [[True, True], [True, False]]
    assert hits["axis_ids"]["node"]["values"].shape == (2, 6)
