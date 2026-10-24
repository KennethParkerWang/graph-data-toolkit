"""Orchestration tests with injected in-memory adapters, not substitute raw formats."""

from copy import deepcopy
import json

import numpy as np
import pytest

from dataset_builder import pipeline
from dataset_builder.config import MetricSelector, SelectionConfig
from dataset_builder.dataset import TrainingDataset
from dataset_builder.examples.framework_records import framework_samples
from dataset_builder.models import MetricRun, PipelineError


class MemorySource:
    """Test double for the source interface; never writes a raw graph/metric."""

    drift = False

    def __init__(self, root):
        self.root = root
        self.records = framework_samples()
        self.graphs = {sample.graph.graph_id: sample.graph for sample in self.records}
        self.snapshots = 0

    def list_graphs(self):
        return [{"graph_id": sample.graph.graph_id,
                 "origin_graph_id": sample.graph.origin_graph_id,
                 "topology_hash": sample.graph.topology_hash,
                 "N": sample.graph.num_nodes,
                 "model": sample.split} for sample in self.records]

    def read_graph(self, graph_id):
        return deepcopy(self.graphs[graph_id])

    def read_runs(self, graph_id, selectors=None):
        sample = next(sample for sample in self.records if sample.graph.graph_id == graph_id)
        return [MetricRun(graph_id, sample.graph.topology_hash, "a" * 64, "", sample.sample_id,
                          "complete", [*deepcopy(sample.features).values(), *deepcopy(sample.targets).values()])]

    def source_snapshot(self):
        self.snapshots += 1
        return {"fixture_snapshot": 2 if self.drift and self.snapshots > 1 else 1}


def config():
    return SelectionConfig(
        {"x": MetricSelector("fixture_node", "fixture-v1", {}, "node", "a" * 64, "")},
        {"y": MetricSelector("fixture_scalar", "fixture-v1", {}, "graph", "a" * 64, "")},
        "keep", "error", "all",
    )


def split_config():
    return {"mode": "family", "conflict": "error", "unassigned": "error",
            "families": {"train": ["train"], "val": ["validation"], "test": ["test"]}}


def test_validate_reads_selected_samples(monkeypatch, tmp_path):
    monkeypatch.setattr(pipeline, "SourceDataset", MemorySource)
    report = pipeline.validate_dataset(tmp_path, config())
    assert report["counts"] == {"graphs": 8, "runs": 8, "samples": 8, "features": 8, "targets": 8, "invalid_values": 8}


def test_convert_train_only_normalizer_and_immutable_split(monkeypatch, tmp_path):
    monkeypatch.setattr(pipeline, "SourceDataset", MemorySource)
    split = pipeline.create_split(tmp_path, split_config())
    assert pipeline.create_split(tmp_path, split_config()) == split
    index = pipeline.convert_dataset(tmp_path, config(), split, normalization="standardize",
                                     shard_size=3, compression=None)
    raw = json.loads(index.read_text())
    state = raw["provenance"]["normalization"]
    train_records = [sample for sample in framework_samples() if sample.split == "train"]
    train_values = np.concatenate([sample.features["node_demo"].values[sample.features["node_demo"].valid_mask]
                                   for sample in train_records])
    assert state["features"]["x"]["mean"] == pytest.approx(train_values.mean())
    assert set(state["training_graph_ids"]) == {sample.graph.graph_id for sample in train_records}
    with TrainingDataset(index) as dataset:
        assert len(dataset) == 8
        assert not dataset._handles
        originals = {sample.graph.graph_id: sample for sample in framework_samples()}
        for sample in dataset:
            original = originals[sample.graph.graph_id]
            np.testing.assert_array_equal(sample.targets["y"].values, original.targets["scalar_demo"].values)
            assert sample.provenance["split_id"] == json.loads(split.read_text())["split_id"]


def test_source_drift_never_publishes_cache(monkeypatch, tmp_path):
    monkeypatch.setattr(pipeline, "SourceDataset", MemorySource)
    split = pipeline.create_split(tmp_path, split_config())
    monkeypatch.setattr(MemorySource, "drift", True)
    with pytest.raises(PipelineError, match="Source metadata changed"):
        pipeline.convert_dataset(tmp_path, config(), split, normalization="none", shard_size=2, compression=None)
    assert not list(tmp_path.glob("training/*/index.json"))
    assert not list(tmp_path.glob("training/*/*.h5"))


def test_changed_split_is_rejected(monkeypatch, tmp_path):
    monkeypatch.setattr(pipeline, "SourceDataset", MemorySource)
    split = pipeline.create_split(tmp_path, split_config())
    value = json.loads(split.read_text())
    value["assignments"][next(iter(value["assignments"]))] = "test"
    split.write_text(json.dumps(value))
    with pytest.raises(PipelineError, match="manifest"):
        pipeline.convert_dataset(tmp_path, config(), split, normalization="none", shard_size=2, compression=None)
