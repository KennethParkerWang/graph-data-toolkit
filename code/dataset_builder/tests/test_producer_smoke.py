"""Acceptance of unchanged producer fixtures, never substitute raw graph data."""

from pathlib import Path
import json
import shutil

import numpy as np
import pytest

import dataset_builder.producer_smoke as producer_smoke
from dataset_builder.batching import collate_pyg_samples, collate_samples
from dataset_builder.cache import sample_fingerprint
from dataset_builder.dataset import TrainingDataset
from dataset_builder.models import PipelineError
from dataset_builder.pipeline import convert_dataset, create_split, validate_dataset
from dataset_builder.producer_smoke import (
    _check_batch, _selection, _verify_sources, copy_producer_inputs,
    default_metric_source, run_producer_smoke,
)
from dataset_builder.selection import select_samples
from dataset_builder.source import PROJECT_ROOT, SourceDataset, read_json_object


@pytest.mark.parametrize("absolute", [False, True])
def test_default_metric_source_resolves_portable_and_legacy_paths(tmp_path, monkeypatch, absolute):
    project_root = tmp_path / "project"
    expected = project_root / "code/graph_analyzer/validation/graph_adapter"
    monkeypatch.setattr(producer_smoke, "PROJECT_ROOT", project_root)

    def read_report(path):
        assert path == project_root / "code/graph_analyzer/validation/graph_adapter_report.json"
        return {"status": "passed", "fixture_root": str(expected) if absolute else "validation/graph_adapter"}

    monkeypatch.setattr(producer_smoke, "read_json_object", read_report)
    assert default_metric_source() == expected.resolve()


@pytest.mark.parametrize("fixture_root", ["../graph_adapter", "validation/../graph_adapter", "outside_absolute"])
def test_default_metric_source_rejects_paths_outside_validation(tmp_path, monkeypatch, fixture_root):
    monkeypatch.setattr(producer_smoke, "PROJECT_ROOT", tmp_path / "project")
    if fixture_root == "outside_absolute":
        fixture_root = str(tmp_path / "outside")
    monkeypatch.setattr(producer_smoke, "read_json_object",
                        lambda path: {"status": "passed", "fixture_root": fixture_root})
    with pytest.raises(PipelineError, match="within its validation directory"):
        default_metric_source()


@pytest.fixture
def producer_roots():
    graph_root = PROJECT_ROOT / "code/graph_builder/examples/schema_v1"
    report = PROJECT_ROOT / "code/graph_analyzer/validation/graph_adapter_report.json"
    if not (graph_root / "dataset.json").is_file() or not report.is_file():
        pytest.skip("Published task 1/task 2 graph adapter fixtures are unavailable")
    return graph_root, default_metric_source()


@pytest.fixture
def staged(tmp_path, producer_roots):
    return copy_producer_inputs(*producer_roots, tmp_path / "dataset")


def test_copy_preserves_producer_bytes_and_tracks_both_sources(staged, producer_roots):
    root = Path(staged["dataset"])
    graph_root, metric_root = producer_roots
    assert (root / "dataset.json").read_bytes() == (graph_root / "dataset.json").read_bytes()
    assert (root / "manifests/graphs.jsonl").read_bytes() == (metric_root / "manifests/graphs.jsonl").read_bytes()
    assert len(list((root / "graphs").rglob("*.mat"))) == 5
    assert len(list((root / "metrics").rglob("*.mat"))) == 5
    integrity = _verify_sources(staged)
    assert integrity["upstream_bytes_unchanged"]
    assert integrity["copied_input_bytes_unchanged"]
    assert str(graph_root / "dataset.json") in staged["inputs_before"]
    assert any(path.endswith(".mat") and str(graph_root) in path for path in staged["inputs_before"])


def test_copy_does_not_overwrite_an_existing_dataset(staged, producer_roots):
    with pytest.raises(FileExistsError):
        copy_producer_inputs(*producer_roots, Path(staged["dataset"]))
    assert _verify_sources(staged)["copied_input_bytes_unchanged"]


def test_copy_refuses_mismatched_producer_graph_manifest(tmp_path, producer_roots):
    graph_root, metric_root = producer_roots
    altered = tmp_path / "altered_producer_copy"
    shutil.copytree(metric_root / "manifests", altered / "manifests")
    path = altered / "manifests/graphs.jsonl"
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
    rows[0]["origin_graph_id"] = "f" * 64
    path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")
    with pytest.raises(PipelineError, match="not byte-identical"):
        copy_producer_inputs(graph_root, altered, tmp_path / "dataset")
    assert not (tmp_path / "dataset").exists()


def test_source_integrity_detects_changed_copied_bytes(staged):
    path = Path(staged["dataset"]) / "dataset.json"
    path.write_bytes(path.read_bytes() + b" ")
    integrity = _verify_sources(staged)
    assert integrity["upstream_bytes_unchanged"]
    assert not integrity["copied_input_bytes_unchanged"]


def test_smoke_output_must_stay_inside_owned_artifacts(tmp_path, producer_roots):
    with pytest.raises(PipelineError, match="within code/dataset_builder/artifacts"):
        run_producer_smoke(tmp_path, graph_source=producer_roots[0], metric_source=producer_roots[1], workers=0)
    assert not list(tmp_path.iterdir())


def test_five_producer_graphs_roundtrip_through_cache_and_both_batches(staged):
    pytest.importorskip("torch")
    pytest.importorskip("torch_geometric")
    dataset = Path(staged["dataset"])
    config = _selection(dataset)
    assert len(config.run_groups) == 5
    validation = validate_dataset(dataset, config)
    assert validation["counts"]["graphs"] == validation["counts"]["samples"] == 5
    split_path = create_split(dataset, {
        "mode": "size", "conflict": "error", "unassigned": "error",
        "size_ranges": {"train": [4, None], "val": [2, 3], "test": [1, 1]},
    })
    split = read_json_object(split_path)
    assert sorted(split["assignments"].values()) == ["test", "train", "train", "train", "val"]
    source = SourceDataset(dataset)
    expected = []
    for graph_id, partition in sorted(split["assignments"].items()):
        graph = source.read_graph(graph_id)
        assert partition == split["assignments"][graph.origin_graph_id]
        samples = select_samples(graph, source.read_runs(graph_id), config, partition)
        assert len(samples) == 1
        sample = samples[0]
        sample.provenance["split_id"] = split["split_id"]
        expected.append(sample)
    index = convert_dataset(dataset, config, split_path, normalization="none", shard_size=2, compression=None)
    with TrainingDataset(index) as reader:
        assert not reader._handles
        loaded = [reader[i] for i in range(len(reader))]
    assert [sample_fingerprint(sample) for sample in loaded] == [sample_fingerprint(sample) for sample in expected]
    assert sum(sample.graph.num_nodes for sample in loaded) == 16
    assert sum(sample.graph.num_edges for sample in loaded) == 9
    assert len([sample for sample in loaded if sample.graph.num_edges == 0]) == 2
    for kind, collator in (("torch", collate_samples), ("pyg", collate_pyg_samples)):
        batch = collator(loaded)
        _check_batch(batch, expected, kind)
        assert batch["edge_index"].shape == (2, 15)
        np.testing.assert_array_equal(batch["num_nodes"].numpy(), [4, 3, 1, 4, 4])
        batch["original_edge_id"][0] = 999
        with pytest.raises(AssertionError):
            _check_batch(batch, expected, kind)
    integrity = _verify_sources(staged)
    assert integrity["upstream_bytes_unchanged"] and integrity["copied_input_bytes_unchanged"]
