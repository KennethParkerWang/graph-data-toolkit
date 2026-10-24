"""Round-trip, immutable publication, corruption and lazy-worker regressions."""

from copy import deepcopy
import json
import pickle

import numpy as np
import pytest

from dataset_builder.cache import build_cache, compute_cache_id, load_index, sample_fingerprint, verify_cache
from dataset_builder.dataset import TrainingDataset
from dataset_builder.models import GraphRecord, MetricArray, PipelineError, TrainingSample


def sample(name="a", split="train"):
    graph = GraphRecord(name * 64, "t" * 64, name * 64, 4, False,
                        np.asarray([[1, 2], [2, 3]], dtype=np.uint32),
                        metadata={"coordinates": np.arange(8).reshape(4, 2)},
                        source={"schema_version": "fixture-graph", "file_sha256": "1" * 64},
                        source_edge_order=np.asarray([2, 1], dtype=np.uint64))
    metric = MetricArray("curve", "v1", {"norm": "none"}, "trajectory",
                         np.asarray([0., np.nan, 4.]), ("step",), np.asarray([True, False, True]),
                         "partial", reason="Middle state undefined",
                         axis_positions={"removed_count": np.asarray([0, 1, 2], dtype=np.uint64),
                                         "requested_fraction": np.asarray([0., .6, 1.])},
                         axis_ids={"step": np.asarray([1, 2, 3])},
                         metadata={"units": "fixture", "raw_denominator": np.float64(np.nan)})
    scalar = MetricArray("scalar", "v1", {}, "graph", np.asarray(0.), (), np.asarray(True), "ok")
    edge = MetricArray("edge", "v1", {}, "edge", np.asarray([9., 2.]), ("edge",),
                       np.ones(2, dtype=bool), "ok", edge_ids=np.asarray([2, 1], dtype=np.uint64))
    return TrainingSample("sample-" + name, graph, {"scalar": scalar, "edge": edge}, {"curve/target": metric}, split,
                          {"run_id": "repeat-1", "protocol_id": "attack-1", "metric_set_id": "set-1"})


def test_roundtrip_preserves_ids_raw_invalid_axes_and_metadata(tmp_path):
    inputs = [sample(), sample("b", "test")]
    provenance = {"sources": ["sha1", "sha2"], "selection": {"targets": ["curve/target"]}}
    path = build_cache(iter(inputs), tmp_path, provenance, shard_size=1, compression="gzip")
    index = verify_cache(path)
    assert len(index["shards"]) == 2
    assert index["cache_id"] == compute_cache_id(provenance, shard_size=1)
    with TrainingDataset(path, expected_provenance=provenance) as dataset:
        assert not dataset._handles
        for i, expected in enumerate(inputs):
            actual = dataset[i]
            assert sample_fingerprint(actual) == sample_fingerprint(expected)
            assert actual.graph.num_nodes == 4
            assert actual.graph.edge_list.dtype == np.uint32
            assert np.isnan(actual.targets["curve/target"].values[1])
            assert actual.targets["curve/target"].axis_positions["removed_count"].tolist() == [0, 1, 2]
    assert not dataset._handles
    assert len(TrainingDataset(path, split="test")) == 1


def test_initialization_opens_no_hdf5_and_pickle_drops_handles(tmp_path, monkeypatch):
    import dataset_builder.dataset as module
    path = build_cache([sample()], tmp_path, {})
    real = module.h5py.File
    monkeypatch.setattr(module.h5py, "File", lambda *_a, **_k: pytest.fail("eager HDF5 read"))
    dataset = TrainingDataset(path)
    assert len(dataset) == 1
    monkeypatch.setattr(module.h5py, "File", real)
    dataset[0]
    assert len(dataset._handles) == 1
    restored = pickle.loads(pickle.dumps(dataset))
    assert not restored._handles
    assert restored[0].sample_id == dataset[0].sample_id
    assert restored._handles["shard_00001.h5"] is not dataset._handles["shard_00001.h5"]
    dataset.close()
    restored.close()


def test_cache_reuse_and_no_overwrite_on_content_or_provenance_change(tmp_path):
    original = sample()
    path = build_cache([original], tmp_path, {"source_sha": "before"})
    before = path.read_bytes()
    assert build_cache([original], tmp_path, {"source_sha": "before"}) == path
    changed = deepcopy(original)
    changed.targets["curve/target"].values[0] = 1
    with pytest.raises(PipelineError, match="Conflicting"):
        build_cache([changed], tmp_path, {"source_sha": "before"})
    with pytest.raises(PipelineError, match="Conflicting"):
        build_cache([original], tmp_path, {"source_sha": "after"})
    with pytest.raises(PipelineError, match="provenance"):
        TrainingDataset(path, expected_provenance={"source_sha": "after"})
    assert path.read_bytes() == before
    verify_cache(path)
    assert not list(tmp_path.glob("*.tmp"))


def test_generator_failure_never_publishes(tmp_path):
    def inputs():
        yield sample()
        raise PipelineError("Sources changed during conversion")
    with pytest.raises(PipelineError, match="Sources changed"):
        build_cache(inputs(), tmp_path, {})
    assert list(tmp_path.iterdir()) == []


def test_duplicate_ids_and_concurrent_writer_are_rejected(tmp_path):
    with pytest.raises(PipelineError, match="duplicate"):
        build_cache([sample(), sample()], tmp_path, {})
    assert list(tmp_path.iterdir()) == []
    (tmp_path / ".writer.lock").write_text("pid=another-writer")
    with pytest.raises(PipelineError, match="writer"):
        build_cache([sample()], tmp_path, {})
    assert (tmp_path / ".writer.lock").read_text() == "pid=another-writer"


def test_corruption_detected_on_lazy_access(tmp_path):
    path = build_cache([sample()], tmp_path, {})
    shard = tmp_path / "shard_00001.h5"
    shard.write_bytes(shard.read_bytes() + b"corruption")
    dataset = TrainingDataset(path)
    assert not dataset._handles
    with pytest.raises(PipelineError, match="checksum"):
        dataset[0]
    with pytest.raises(PipelineError, match="corrupt"):
        verify_cache(path)


def test_index_corruption_and_unindexed_shards_are_rejected(tmp_path):
    path = build_cache([sample()], tmp_path / "good", {})
    index = json.loads(path.read_text(encoding="utf-8"))
    index["samples"][0]["split"] = "test"
    path.write_text(json.dumps(index), encoding="utf-8")
    with pytest.raises(PipelineError, match="checksum"):
        load_index(path)
    target = tmp_path / "partial"
    target.mkdir()
    existing = target / "shard_00001.h5"
    existing.write_bytes(b"unfinished previous publication")
    with pytest.raises(PipelineError, match="Unindexed"):
        build_cache([sample()], target, {})
    assert existing.read_bytes() == b"unfinished previous publication"


@pytest.mark.parametrize("compression", [None, "lzf", "gzip"])
def test_empty_edges_and_scalar_zero_for_all_compressions(tmp_path, compression):
    item = sample()
    item.graph.edge_list = np.empty((0, 2), dtype=np.uint32)
    item.graph.source_edge_order = np.empty((0,), dtype=np.uint64)
    item.features["edge"].values = np.empty((0,))
    item.features["edge"].valid_mask = np.empty((0,), dtype=bool)
    item.features["edge"].edge_ids = np.empty((0,), dtype=np.uint64)
    path = build_cache([item], tmp_path, {}, compression=compression)
    with TrainingDataset(path) as dataset:
        actual = dataset[0]
    assert actual.graph.num_nodes == 4
    assert actual.graph.edge_list.shape == (0, 2)
    assert actual.features["scalar"].values.shape == ()
    assert bool(actual.features["scalar"].valid_mask)
    assert actual.features["scalar"].values == 0


def test_per_worker_handle_limit_closes_least_recent_shard(tmp_path):
    path = build_cache([sample("a"), sample("b"), sample("c")], tmp_path, {}, shard_size=1)
    with TrainingDataset(path, max_open_shards=1) as dataset:
        dataset[0]
        old = next(iter(dataset._handles.values()))
        dataset[1]
        assert len(dataset._handles) == 1
        assert not old.id.valid
        assert dataset[0].sample_id == "sample-a"


def test_matrix_two_original_axes_and_valid_infinity_roundtrip(tmp_path):
    item = sample()
    item.targets["matrix"] = MetricArray("matrix", "v1", {}, "matrix", np.asarray([[0., np.inf], [3., 0.]]),
                                         ("source", "target"), np.ones((2, 2), dtype=bool), "ok",
                                         axis_ids={"source": np.asarray([4, 1]), "target": np.asarray([1, 3])},
                                         metadata={"allows_infinity": True})
    path = build_cache([item], tmp_path, {})
    with TrainingDataset(path) as dataset:
        actual = dataset[0].targets["matrix"]
    assert actual.axis_ids["source"].tolist() == [4, 1]
    assert actual.axis_ids["target"].tolist() == [1, 3]
    assert np.isinf(actual.values[0, 1]) and actual.valid_mask[0, 1]


def test_numpy_provenance_and_nonfinite_metadata_have_stable_identity(tmp_path):
    provenance = {"normalizer": {"mean": np.asarray([1., 2.]), "missing": np.float64(np.nan)},
                  "source_dimensions": np.asarray([[2, 4]], dtype=np.uint32)}
    path = build_cache([sample()], tmp_path, provenance)
    assert load_index(path)["cache_id"] == compute_cache_id(provenance)
    with TrainingDataset(path, expected_provenance=provenance) as dataset:
        assert dataset[0].sample_id == "sample-a"
    assert build_cache([sample()], tmp_path, provenance) == path


@pytest.mark.parametrize("dtype", ["U12", object])
def test_unicode_categorical_axis_ids_roundtrip_without_pointer_hashing(tmp_path, dtype):
    item = sample()
    item.targets["hits"] = MetricArray("hits", "v1", {}, "matrix", np.ones((4, 2)),
                                       ("node", "score"), np.ones((4, 2), dtype=bool), "ok",
                                       axis_ids={"node": np.arange(1, 5),
                                                 "score": np.asarray(["hub", "权威 authority"], dtype=dtype)})
    fingerprint = sample_fingerprint(item)
    assert fingerprint == sample_fingerprint(deepcopy(item))
    path = build_cache([item], tmp_path, {})
    with TrainingDataset(path) as dataset:
        actual = dataset[0]
    assert actual.targets["hits"].axis_ids["score"].dtype == np.dtype(dtype)
    assert actual.targets["hits"].axis_ids["score"].tolist() == ["hub", "权威 authority"]
    assert sample_fingerprint(actual) == fingerprint
