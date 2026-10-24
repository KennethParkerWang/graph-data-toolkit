"""Attack projection through HDF5, lazy loading and independent CPU batches."""

from copy import deepcopy
import hashlib
import json

import h5py
import numpy as np
import pytest

from dataset_builder.batching import collate_pyg_samples, collate_samples
from dataset_builder.cache import (
    CONVERSION_VERSION, build_cache, canonical_json, compute_cache_id,
    file_sha256, load_index, sample_fingerprint, verify_cache,
)
from dataset_builder.config import MetricSelector, SelectionConfig
from dataset_builder.dataset import TrainingDataset, make_pyg_loader, make_torch_loader
from dataset_builder.models import GraphRecord, MetricArray, MetricRun, ObservationRecord, PipelineError, TrainingSample
from dataset_builder.normalization import FeatureNormalizer
from dataset_builder.selection import select_samples


def _metric(values, node_ids, labels, *, valid=None, reason=""):
    values = np.asarray(values, dtype=np.float64)
    mask = np.ones(values.shape, dtype=bool) if valid is None else np.asarray(valid, dtype=bool)
    return MetricArray("scores", "v1", {}, "matrix", values, ("node", "score"), mask,
                       "ok" if mask.all() else "partial", reason=reason,
                       axis_ids={"node": np.asarray(node_ids, dtype=np.uint32), "score": np.asarray(labels)},
                       metadata={"units": "ratio", "method": "exact"})


def _positions(index, source):
    if source == "states":
        return {"removed_count": index - 1, "removed_fraction": (index - 1) / 4,
                "fraction_valid": True, "round_index": index - 1, "state_index": index}
    return {"requested_fraction": .1 if index < 3 else .6,
            "requested_removed_count": 0 if index < 3 else 2,
            "actual_removed_count": 0 if index < 3 else 2,
            "actual_removed_fraction": 0. if index < 3 else .5,
            "fraction_valid": True, "state_index": 1 if index < 3 else 3, "exact_count_match": True}


def _sample(name="a", *, source="states", feature=False, smaller=False, unavailable=False):
    directed, nodes = (True, 6) if smaller else (False, 5)
    graph = GraphRecord(name, "topo-" + name, name, nodes, directed,
                        np.asarray([[1, 2], [2, 1]] if directed else [[1, 2], [2, 3]], dtype=np.uint32))
    if unavailable:
        metrics = []
    elif smaller:
        metrics = [_metric([[5.], [6.], [7.]], [6, 1, 2], ["hub"])]
    else:
        metrics = [_metric([[1., 2.], [3., 4.]], [4, 1], ["hub", "权威 authority"]),
                   _metric([[np.nan, 0.]], [1], ["权威 authority", "hub"], valid=[[False, True]],
                           reason="authority normalization is undefined"), None]
    observations = [ObservationRecord(index, [] if value is None else [value], _positions(index, source),
                                      "not_computed" if value is None else "complete",
                                      "requested state unavailable" if value is None else "",
                                      {"remaining_node_ids": np.asarray([1]) if index > 1 else np.asarray([4, 1])})
                    for index, value in enumerate(metrics, start=1)]
    run = MetricRun(name, graph.topology_hash, "set", "attack", "run-" + name, "partial", [],
                    source={"file_sha256": "source-" + name}, observations={source: observations})
    selected = {"signal": MetricSelector("scores", "v1", {}, "matrix", "set", "attack", source, "by_id")}
    config = SelectionConfig(selected if feature else {}, {} if feature else selected, "keep", "mask", "all")
    return select_samples(graph, [run], config, "train")[0]


@pytest.mark.parametrize("compression", [None, "gzip", "lzf"])
def test_projection_hdf5_lazy_roundtrip_preserves_presence_source_rows_and_unicode(tmp_path, monkeypatch, compression):
    inputs = [_sample(), _sample("b", smaller=True)]
    provenance = {"selection_id": inputs[0].provenance["selection_id"], "fixture": "typed-observation-roundtrip"}
    path = build_cache(iter(inputs), tmp_path, provenance, shard_size=1, compression=compression)
    assert len(verify_cache(path)["shards"]) == 2
    import dataset_builder.dataset as module
    with monkeypatch.context() as patch:
        patch.setattr(module.h5py, "File", lambda *_a, **_k: pytest.fail("Dataset opened a shard during initialization"))
        dataset = TrainingDataset(path, expected_provenance=provenance)
        assert len(dataset) == 2 and not dataset._handles
    with dataset:
        restored = dataset[0]
        assert len(dataset._handles) == 1
        assert sample_fingerprint(restored) == sample_fingerprint(inputs[0])
        metric = restored.targets["signal"]
        assert metric.values.shape == (3, 2, 2)
        assert metric.axis_names == ("observation", "node", "score")
        assert metric.scope == "matrix" and metric.values.dtype == np.float64
        np.testing.assert_equal(metric.axis_ids["node"], [4, 1])
        np.testing.assert_equal(metric.axis_ids["score"], ["hub", "权威 authority"])
        # Deleted node 4 is absent; node 1's authority value exists but is invalid.
        assert not metric.present_mask[1, 0].any()
        assert metric.present_mask[1, 1, 1] and not metric.valid_mask[1, 1, 1]
        assert np.isnan(metric.values[1, 1, 1])
        assert metric.values[1, 1, 0] == 0 and metric.valid_mask[1, 1, 0]
        assert not metric.present_mask[2].any()
        np.testing.assert_equal(metric.axis_positions["removed_count"], [0, 1, 2])
        np.testing.assert_equal(metric.axis_positions["removed_fraction"], [0, .25, .5])
        rows = metric.metadata["observation_projection"]["observations"]
        assert rows[1]["metric"]["reason"] == "authority normalization is undefined"
        np.testing.assert_equal(rows[1]["metric"]["axis_ids"]["score"], ["权威 authority", "hub"])
        assert rows[2]["status"] == "not_computed" and rows[2]["reason"] == "requested state unavailable"
        assert sample_fingerprint(dataset[1]) == sample_fingerprint(inputs[1])
    assert not dataset._handles


@pytest.mark.parametrize("kind,workers", [("torch", 0), ("torch", 2), ("pyg", 0), ("pyg", 2)])
def test_projected_ragged_tensor_batches_preserve_mask_axes_and_isolated_nodes(tmp_path, kind, workers):
    torch = pytest.importorskip("torch")
    if kind == "pyg":
        pytest.importorskip("torch_geometric")
    inputs = [_sample(), _sample("b", smaller=True)]
    path = build_cache(inputs, tmp_path, {}, shard_size=1)
    make_loader = make_torch_loader if kind == "torch" else make_pyg_loader
    with TrainingDataset(path) as dataset:
        # An existing parent handle must not be reused by spawned workers.
        dataset[0]
        options = {"multiprocessing_context": "spawn"} if workers else {}
        batch = next(iter(make_loader(dataset, batch_size=2, num_workers=workers, **options)))
        assert len(dataset._handles) == (1 if workers else 2)
    target = batch["targets"]["signal"]
    assert tuple(target["values"].shape) == (2, 3, 3, 2)
    assert target["values"].device.type == "cpu"
    assert target["present_mask"][0].sum().item() == 6
    assert target["valid_mask"][0].sum().item() == 5
    assert target["present_mask"][1].sum().item() == 3
    assert target["valid_mask"][1].sum().item() == 3
    assert not target["present_mask"][0, 1, 0].any()  # Coordinate absent after deletion.
    assert target["present_mask"][0, 1, 1, 1] and not target["valid_mask"][0, 1, 1, 1]
    assert torch.isnan(target["raw_values"][0, 1, 1, 1])
    assert target["values"][0, 1, 1, 1] == 0
    assert target["valid_mask"][0, 1, 1, 0] and target["values"][0, 1, 1, 0] == 0
    assert not target["present_mask"][0, :, 2].any()  # Batch padding beyond this graph's union.
    assert not target["present_mask"][1, 1:].any()  # Missing observation rows in shorter graph.
    assert target["axis_ids"]["score"]["values"] == [["hub", "权威 authority"], ["hub", None]]
    assert target["axis_ids"]["node"]["values"].tolist() == [[4, 1, 0], [6, 1, 2]]
    assert target["axis_positions"]["removed_fraction"]["values"][0].tolist() == [0., .25, .5]
    assert target["axis_positions"]["removed_fraction"]["present_mask"][1].tolist() == [True, False, False]
    row = target["metadata"][0]["observation_projection"]["observations"][1]
    assert row["metric"]["reason"] == "authority normalization is undefined"
    assert batch["num_nodes"].tolist() == [5, 6]
    assert batch["node_ptr"].tolist() == [0, 5, 11]
    assert batch["original_edge_id"].tolist() == [1, 2, 1, 2, 1, 2]
    assert batch["edge_index"].tolist() == [[0, 1, 1, 2, 5, 6], [1, 2, 0, 1, 6, 5]]
    if kind == "pyg":
        assert batch["graph_batch"].num_nodes == 11
        assert batch["graph_batch"].ptr.tolist() == [0, 5, 11]
        for original, restored in zip(inputs, batch["graph_batch"].training_sample):
            assert sample_fingerprint(original) == sample_fingerprint(restored)


def test_sampled_repeated_positions_survive_cache_and_batch(tmp_path):
    pytest.importorskip("torch")
    sample = _sample(source="sampled")
    path = build_cache([sample], tmp_path, {})
    with TrainingDataset(path) as dataset:
        metric = dataset[0].targets["signal"]
        np.testing.assert_equal(metric.axis_positions["requested_fraction"], [.1, .1, .6])
        np.testing.assert_equal(metric.axis_positions["state_index"], [1, 1, 3])
        batch = next(iter(make_torch_loader(dataset, batch_size=1)))
    target = batch["targets"]["signal"]
    assert target["axis_positions"]["requested_fraction"]["values"].tolist() == [[.1, .1, .6]]
    assert target["axis_positions"]["actual_removed_fraction"]["values"].tolist() == [[0., 0., .5]]
    assert target["axis_ids"]["observation"]["values"].tolist() == [[1, 2, 3]]


@pytest.mark.parametrize("kind", ["torch", "pyg"])
def test_different_observation_sources_are_rejected_even_with_same_metric_and_rank(tmp_path, kind):
    pytest.importorskip("torch")
    if kind == "pyg":
        pytest.importorskip("torch_geometric")
    inputs = [_sample("states", source="states"), _sample("sampled", source="sampled")]
    path = build_cache(inputs, tmp_path, {})
    with TrainingDataset(path) as dataset:
        samples = [dataset[0], dataset[1]]
    collate = collate_samples if kind == "torch" else collate_pyg_samples
    with pytest.raises(PipelineError, match="definition conflict"):
        collate(samples)


def test_missing_same_source_is_accepted_while_missing_other_source_is_not():
    pytest.importorskip("torch")
    available = _sample("available", source="states")
    missing_same = _sample("missing-same", source="states", unavailable=True)
    missing_other = _sample("missing-other", source="sampled", unavailable=True)
    target = collate_samples([available, missing_same])["targets"]["signal"]
    assert not target["present_mask"][1].any() and not target["valid_mask"][1].any()
    with pytest.raises(PipelineError, match="definition conflict"):
        collate_samples([available, missing_other])


@pytest.mark.parametrize("operation", ["fit", "transform"])
def test_normalizer_checks_source_identity_even_when_that_source_has_no_values(operation):
    available = _sample("available", source="states", feature=True)
    missing_same = _sample("missing-same", source="states", feature=True, unavailable=True)
    missing_other = _sample("missing-other", source="sampled", feature=True, unavailable=True)
    normalizer = FeatureNormalizer().fit([available, missing_same])
    assert normalizer.to_dict()["features"]["signal"]["count"] == 5
    assert normalizer.transform(missing_same).features["signal"].metadata["shape_unknown"]
    with pytest.raises(PipelineError, match="definition conflict"):
        if operation == "fit":
            FeatureNormalizer().fit([available, missing_other])
        else:
            normalizer.transform(missing_other)


def test_normalizer_excludes_structural_absence_and_invalid_cells_and_rejects_source_mix(tmp_path):
    states = _sample("states", source="states", feature=True)
    sampled = _sample("sampled", source="sampled", feature=True)
    path = build_cache([states, sampled], tmp_path, {})
    with TrainingDataset(path) as dataset:
        states, sampled = dataset[0], dataset[1]
    with pytest.raises(PipelineError, match="definition conflict"):
        FeatureNormalizer().fit([states, sampled])
    normalizer = FeatureNormalizer().fit([states])
    stats = normalizer.to_dict()["features"]["signal"]
    assert stats["count"] == 5 and stats["mean"] == 2
    with pytest.raises(PipelineError, match="definition conflict"):
        normalizer.transform(sampled)
    transformed = normalizer.transform(states).features["signal"]
    original = states.features["signal"]
    np.testing.assert_equal(transformed.present_mask, original.present_mask)
    np.testing.assert_equal(transformed.valid_mask, original.valid_mask)
    np.testing.assert_equal(transformed.values[~original.valid_mask], original.values[~original.valid_mask])


def test_projection_presence_is_part_of_cache_content_identity():
    original = _sample()
    modified = deepcopy(original)
    # A stored mathematically invalid cell becoming absent is a material change.
    modified.targets["signal"].present_mask[1, 1, 1] = False
    assert not modified.targets["signal"].valid_mask[1, 1, 1]
    assert sample_fingerprint(original) != sample_fingerprint(modified)


def test_conversion_version_changes_cache_identity():
    provenance = {"source_sha": "same-source", "selection_id": "same-selection", "split_id": "same-split"}
    assert CONVERSION_VERSION == "data-pipeline-v2"
    assert compute_cache_id(provenance) != compute_cache_id(provenance, conversion_version="data-pipeline-v1")


def test_previous_task_v1_cache_without_presence_dataset_remains_readable(tmp_path):
    """Construct a valid historical-layout fixture without touching user caches."""
    graph = GraphRecord("legacy-task-cache", "topo", "legacy-task-cache", 3, False,
                        np.array([[1, 2]], dtype=np.uint32))
    value = MetricArray("saved_static", "v1", {}, "graph", np.asarray(0.), (), np.asarray(True), "ok")
    original = TrainingSample("legacy-task-sample", graph, {}, {"value": value}, "train")
    provenance = {"fixture": "previous-task-training-v1"}
    path = build_cache([original], tmp_path, provenance)
    index = json.loads(path.read_text(encoding="utf-8"))
    index.pop("index_sha256")
    index["conversion_version"] = "data-pipeline-v1"
    index["cache_id"] = compute_cache_id(provenance, conversion_version="data-pipeline-v1", **index["options"])
    for name in index["shards"]:
        shard = path.parent / name
        with h5py.File(shard, "r+") as handle:
            handle.attrs["cache_id"] = index["cache_id"]
            group = handle[index["samples"][0]["group"]]["targets"]["0"]
            assert "present_mask" not in group
        index["shards"][name] = {"file_sha256": file_sha256(shard), "file_bytes": shard.stat().st_size}
    index["index_sha256"] = hashlib.sha256(canonical_json(index).encode("utf-8")).hexdigest()
    path.write_text(canonical_json(index) + "\n", encoding="utf-8")
    assert load_index(path)["conversion_version"] == "data-pipeline-v1"
    verify_cache(path)
    with TrainingDataset(path) as dataset:
        assert not dataset._handles
        restored = dataset[0]
        assert restored.targets["value"].present_mask is None
        assert sample_fingerprint(restored) == sample_fingerprint(original)
