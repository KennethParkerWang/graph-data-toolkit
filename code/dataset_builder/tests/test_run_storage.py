"""Task evidence must not change scientific identities or hide failures."""

import hashlib
import json
from pathlib import Path

import pytest

from dataset_builder import pipeline, run_storage
from dataset_builder.models import PipelineError
from dataset_builder.run_storage import RunWorkspace
from dataset_builder.tests.test_pipeline import MemorySource, config, split_config


def records(root):
    return [json.loads(path.read_text(encoding="utf-8")) for path in root.glob("*/*/run.json")]


def test_tasks_preserve_cache_and_split_identity(monkeypatch, tmp_path):
    monkeypatch.setattr(pipeline, "SourceDataset", MemorySource)
    source = tmp_path / "dataset"
    source.mkdir()
    roots = [tmp_path / "runs_a", tmp_path / "runs_b"]
    split_a = pipeline.create_split(source, split_config(), run_root=roots[0])
    split_b = pipeline.create_split(source, split_config(), run_root=roots[1])
    assert split_a == split_b
    indexes = [pipeline.convert_dataset(source, config(), split_a, normalization="none", shard_size=3,
                                       compression=None, run_root=root) for root in roots]
    assert indexes[0] == indexes[1]
    for root in roots:
        jobs = records(root)
        assert len(jobs) == 2 and all(job["status"] == "complete" for job in jobs)
        convert = next(job for job in jobs if "cache_id" in job["outputs"])
        assert convert["outputs"]["cache_id"] == json.loads(indexes[0].read_text())["cache_id"]
        for path in root.glob("*/*/run.json"):
            value = json.loads(path.read_text())
            snapshot = path.parent / value["config_file"]
            assert hashlib.sha256(snapshot.read_bytes()).hexdigest() == value["config_file_sha256"]
            assert not (path.parent / "work").exists()
            assert (path.parent / "reports/dataset_builder.json").exists()


def test_failed_conversion_keeps_evidence_without_index(monkeypatch, tmp_path):
    monkeypatch.setattr(pipeline, "SourceDataset", MemorySource)
    source = tmp_path / "dataset"
    source.mkdir()
    root = tmp_path / "runs"
    split = pipeline.create_split(source, split_config(), run_root=root)
    with pytest.raises(PipelineError, match="normalization"):
        pipeline.convert_dataset(source, config(), split, normalization="bad", shard_size=2,
                                 compression=None, run_root=root)
    assert sorted(job["status"] for job in records(root)) == ["complete", "failed"]
    assert list(root.glob("*/*/failures/error.json"))
    assert not list(source.glob("training/*/index.json"))


def test_recording_failure_does_not_replace_scientific_error(monkeypatch, tmp_path):
    job = RunWorkspace(tmp_path / "dataset", {"task": "validate"}, run_root=tmp_path / "runs")
    original = PipelineError("original scientific failure")
    with pytest.raises(PipelineError, match="original scientific failure") as caught:
        with job:
            monkeypatch.setattr(job, "event", lambda value: (_ for _ in ()).throw(OSError("log unwritable")))
            raise original
    assert caught.value is original
    assert any("log unwritable" in note for note in original.__notes__)


@pytest.mark.parametrize("dataset_id", ["中文数据", "CON", "NUL", "123", "../outside"])
def test_safe_folder_retains_dataset_identity(tmp_path, dataset_id):
    dataset = tmp_path / "dataset"
    dataset.mkdir()
    (dataset / "dataset.json").write_text(json.dumps({"dataset_id": dataset_id}), encoding="utf-8")
    with RunWorkspace(dataset, {"task": "validate"}, run_root=tmp_path / "runs") as job:
        assert job.directory.is_relative_to(tmp_path / "runs")
        assert job.record["dataset_id"] == dataset_id
        assert job.directory.parent.name == job.record["dataset_folder"]
        assert not (job.directory / "work").exists()
        assert job.work().is_dir()


def test_run_root_must_be_outside_dataset(tmp_path):
    with pytest.raises(PipelineError, match="outside"):
        RunWorkspace(tmp_path, {"task": "validate"}, run_root=tmp_path / "runs")
    assert not (tmp_path / "runs").exists()
