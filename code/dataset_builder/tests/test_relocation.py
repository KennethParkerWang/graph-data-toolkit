"""Relocate report references while retaining exact producer-byte checks."""

from pathlib import Path

import pytest

from dataset_builder import producer_layout_benchmark as benchmark
from dataset_builder.models import PipelineError
from dataset_builder.source import file_fingerprint


@pytest.mark.parametrize("module", ["data_pipeline", "dataset_builder", "code/dataset_builder"])
def test_copied_smoke_report_uses_new_root_and_keeps_byte_checks(tmp_path, monkeypatch, module):
    root = tmp_path / "迁移后的 项目"
    artifacts = root / "code/dataset_builder/artifacts"
    monkeypatch.setattr(benchmark, "PROJECT_ROOT", root)
    monkeypatch.setattr(benchmark, "ARTIFACT_ROOT", artifacts)
    report = artifacts / "producer_smoke_copy/report.json"
    inputs = root / "code/graph_builder/examples/fixture.bin"
    dataset = report.parent / "dataset"
    for path in (report, inputs, report.parent / "selection.json", dataset / "split.json", dataset / "index.json"):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"unchanged accepted bytes")
    old_root = "Z:/original project"
    old_source_root = f"{old_root}/code" if module.startswith("code/") else old_root
    smoke = {
        "output": f"{old_root}/{module}/artifacts/producer_smoke_copy",
        "staging": {
            "dataset": f"{old_root}/{module}/artifacts/producer_smoke_copy/dataset",
            "inputs_before": {f"{old_source_root}/graph_generation/examples/fixture.bin": file_fingerprint(inputs)},
            "copied_files": [],
        },
        "split_manifest": f"{old_root}/{module}/artifacts/producer_smoke_copy/dataset/split.json",
        "cache_index": f"{old_root}/{module}/artifacts/producer_smoke_copy/dataset/index.json",
    }
    expected = benchmark._collect_inputs(report, smoke)
    assert str(inputs.resolve()) in expected
    assert all(Path(path).is_relative_to(root) for path in expected)
    inputs.write_bytes(b"changed__ accepted bytes")
    with pytest.raises(PipelineError, match="changed since smoke acceptance"):
        benchmark._collect_inputs(report, smoke)


def test_report_path_relocation_rejects_module_escape_and_preserves_external_input(tmp_path, monkeypatch):
    artifacts = tmp_path / "project/code/dataset_builder/artifacts"
    monkeypatch.setattr(benchmark, "PROJECT_ROOT", tmp_path / "project")
    monkeypatch.setattr(benchmark, "ARTIFACT_ROOT", artifacts)
    report = artifacts / "producer_smoke_copy/report.json"
    smoke = {"output": "Z:/original/data_pipeline/artifacts/producer_smoke_copy"}
    with pytest.raises(PipelineError, match="escapes its module root"):
        benchmark._smoke_path("Z:/original/data_pipeline/../../outside.bin", report, smoke)
    external = tmp_path / "explicit_external.bin"
    assert benchmark._smoke_path(str(external), report, smoke) == external.resolve()
