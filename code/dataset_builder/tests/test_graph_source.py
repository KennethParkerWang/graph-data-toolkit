"""Producer graph-v1 interoperability plus content-corruption regression tests."""

from copy import deepcopy
import json
import os
from pathlib import Path
import shutil
from types import SimpleNamespace

import numpy as np
import pytest
from scipy import sparse
from scipy.io import loadmat, savemat
from scipy.io.matlab import mat_struct

from dataset_builder.graph_source import read_graph_manifest
from dataset_builder.models import MetricRun, PipelineError
from dataset_builder.source import PROJECT_ROOT, SourceDataset, file_fingerprint, read_jsonl
import dataset_builder.source as source_module


PRODUCER_ROOT = PROJECT_ROOT / "code/graph_builder/examples/schema_v1"


@pytest.fixture
def dataset(tmp_path):
    target = tmp_path / "schema_v1"
    shutil.copytree(PRODUCER_ROOT, target)
    return target


def _rows(root):
    return read_jsonl(root / "manifests/graphs.jsonl", identity_fields=("graph_id",))


def _save_rows(root, rows):
    (root / "manifests/graphs.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows), encoding="utf-8",
    )


def _fixture_row(root, fixture):
    source = SourceDataset(root, graph_only=True)
    for row in source.list_graphs():
        if source.read_graph(row["graph_id"]).metadata["parameters"]["fixture"] == fixture:
            return row
    raise AssertionError(f"Missing published producer fixture: {fixture}")


def _rewrite_mat(root, row, mutate):
    """Mutate only a test copy, then update byte hash so content checks must run."""
    path = root / row["path"]
    saved = {name: value for name, value in loadmat(
        path, mat_dtype=True, struct_as_record=False, squeeze_me=False,
    ).items() if not name.startswith("__")}
    mutate(saved)
    # SciPy's mat_struct read containers need unwrapping before reserialization;
    # saving the object ndarray directly would accidentally turn structs into cells.
    def for_savemat(value):
        if isinstance(value, mat_struct):
            return {name: for_savemat(getattr(value, name)) for name in value._fieldnames}
        if isinstance(value, np.ndarray) and value.dtype.kind == "O":
            if value.size == 1 and isinstance(value.item(), mat_struct):
                return for_savemat(value.item())
            result = np.empty(value.shape, dtype=object)
            for index in np.ndindex(value.shape):
                result[index] = for_savemat(value[index])
            return result
        return value

    savemat(path, {key: for_savemat(value) for key, value in saved.items()}, do_compression=True)
    rows = _rows(root)
    for item in rows:
        if item["graph_id"] == row["graph_id"]:
            item.update(file_fingerprint(path))
    _save_rows(root, rows)


def _meta(saved):
    return saved["meta"].item()


def test_all_five_published_matlab_graphs_read_back():
    source = SourceDataset(PRODUCER_ROOT, graph_only=True)
    graphs = [source.read_graph(row["graph_id"]) for row in source.list_graphs()]
    assert len(graphs) == 5
    fixtures = {graph.metadata["parameters"]["fixture"]: graph for graph in graphs}
    undirected = fixtures["undirected_triangle_isolate"]
    assert (undirected.num_nodes, undirected.num_edges, undirected.directed) == (4, 3, False)
    assert undirected.source_edge_order.tolist() == [3, 1, 2]
    assert undirected.metadata["attributes"]["community"] == [1, 1, 1, 2]
    assert undirected.metadata["attributes"]["coordinates"] == [[0, 0], [1, 0], [0, 1], [2, 2]]
    assert undirected.metadata["custom_note"] == "社区与坐标保持节点顺序"
    edge_index, edge_ids = undirected.model_edges(bidirectional=True)
    assert edge_index.shape == (2, 6)
    assert edge_ids.tolist() == [1, 2, 3, 1, 2, 3]
    assert edge_index.max() == 2  # Node 4 remains an isolated node via num_nodes.
    directed = fixtures["directed_reciprocal_isolate"]
    assert (directed.num_nodes, directed.num_edges, directed.directed) == (4, 3, True)
    assert [1, 2] in directed.edge_list.tolist() and [2, 1] in directed.edge_list.tolist()
    assert directed.model_edges(bidirectional=True)[0].shape == (2, 3)
    empty = fixtures["edgeless_three"]
    assert empty.num_nodes == 3 and empty.edge_list.shape == (0, 2)
    assert empty.model_edges(bidirectional=True)[0].shape == (2, 0)
    assert empty.source_edge_order is None
    singleton = fixtures["directed_singleton"]
    assert singleton.num_nodes == 1 and singleton.source_edge_order.shape == (0,)
    assert fixtures["derived_relabeling"].origin_graph_id == undirected.graph_id
    assert all(graph.source["scientific_sha256"] and graph.source["producer_validator_sha256"] for graph in graphs)


def test_initialization_only_reads_metadata_and_does_not_hash_mat(monkeypatch):
    def forbidden(*args, **kwargs):
        raise AssertionError("Initialization must not load or checksum MAT payloads")

    monkeypatch.setattr(source_module, "_load_mat", forbidden)
    monkeypatch.setattr(source_module, "verify_source_file", forbidden)
    source = SourceDataset(PRODUCER_ROOT, graph_only=True)
    assert len(source.list_graphs()) == 5
    assert len(source.source_snapshot()["source_files"]) == 5
    rows = source.list_graphs()
    rows[0]["N"] = 999
    assert source.graph_entry(rows[0]["graph_id"])["N"] != 999


def test_graph_only_is_explicit_and_never_claims_metric_results():
    source = SourceDataset(PRODUCER_ROOT, graph_only=True)
    identity = source.list_graphs()[0]["graph_id"]
    assert source.read_runs(identity) == []
    with pytest.raises(PipelineError, match="graph-only"):
        source.read_runs(identity, [SimpleNamespace(metric_set_id="a", protocol_id="")])
    with pytest.raises(PipelineError, match="No published metric manifest"):
        SourceDataset(PRODUCER_ROOT).read_runs(identity)
    with pytest.raises(PipelineError, match="Unknown graph_id"):
        source.read_graph("0" * 64)


def test_missing_dataset_description_is_reported_without_fabrication(dataset):
    (dataset / "dataset.json").unlink()
    with pytest.raises(PipelineError, match="Missing producer dataset description"):
        SourceDataset(dataset, graph_only=True)


@pytest.mark.parametrize("field,value", [
    ("N", True), ("N", 0), ("N", 2**32), ("M", -1), ("M", 999),
    ("directed", 0), ("file_bytes", 0), ("scientific_sha256", "A" * 64),
    ("schema_version", "graph-v2"), ("model", ""), ("path", "../outside.mat"),
])
def test_manifest_rejects_invalid_types_and_identities(dataset, field, value):
    rows = _rows(dataset)
    rows[0][field] = value
    _save_rows(dataset, rows)
    with pytest.raises(PipelineError):
        SourceDataset(dataset, graph_only=True)


def test_duplicate_graph_identity_rejected(dataset):
    rows = _rows(dataset)
    _save_rows(dataset, [*rows, deepcopy(rows[0])])
    with pytest.raises(PipelineError, match="Duplicate"):
        read_graph_manifest(dataset)


def test_missing_and_corrupted_committed_files_rejected(dataset):
    source = SourceDataset(dataset, graph_only=True)
    row = source.list_graphs()[0]
    path = dataset / row["path"]
    payload = path.read_bytes()
    path.write_bytes(bytes([payload[0] ^ 1]) + payload[1:])
    with pytest.raises(PipelineError, match="SHA-256 mismatch"):
        source.read_graph(row["graph_id"])
    path.unlink()
    with pytest.raises(PipelineError, match="Missing source graph"):
        SourceDataset(dataset, graph_only=True)


@pytest.mark.parametrize("mutate,match", [
    (lambda value: value.update(N=np.array([[4]], dtype=np.uint64)), "uint32"),
    (lambda value: value.update(edge_list=value["edge_list"][::-1]), "sorted"),
    (lambda value: value.update(A=sparse.csc_matrix((4, 4), dtype=bool)), "A and canonical"),
    (lambda value: value.update(A=value["A"].astype(np.float64)), "sparse logical"),
    (lambda value: value.update(extra=np.array([[1]])), "unknown top-level"),
    (lambda value: value.update(source_edge_order=np.array([[1], [1], [3]], dtype=np.uint64)), "permute"),
    (lambda value: setattr(_meta(value), "source_edge_order_available", np.array([[False]])), "availability"),
    (lambda value: setattr(_meta(value), "parameters", np.array([[1.0]])), "scalar MATLAB struct"),
    (lambda value: setattr(_meta(value).rng.item(), "seed", np.array([[12.0]])), "recipe_json disagrees"),
    (lambda value: setattr(_meta(value).rng.item(), "seed", np.array([[-1.0]])), "rng.seed"),
    (lambda value: setattr(_meta(value), "custom_note", np.array(["tampered metadata"])), "scientific_sha256"),
    (lambda value: setattr(_meta(value), "custom_note", np.array([[np.nan]])), "finite"),
    (lambda value: setattr(_meta(value), "recipe_json", np.array([str(_meta(value).recipe_json.item()) + " "])), "saved recipe_json bytes"),
])
def test_content_corruption_rejected_even_after_file_hash_is_updated(dataset, mutate, match):
    row = _fixture_row(dataset, "undirected_triangle_isolate")
    _rewrite_mat(dataset, row, mutate)
    with pytest.raises(PipelineError, match=match):
        SourceDataset(dataset, graph_only=True).read_graph(row["graph_id"])


def test_wrong_scientific_manifest_digest_rejected(dataset):
    rows = _rows(dataset)
    rows[0]["scientific_sha256"] = "0" * 64
    _save_rows(dataset, rows)
    with pytest.raises(PipelineError, match="scientific_sha256"):
        SourceDataset(dataset, graph_only=True).read_graph(rows[0]["graph_id"])


def test_missing_derived_transformation_rejected(dataset):
    row = _fixture_row(dataset, "derived_relabeling")

    def remove_transformation(saved):
        meta = _meta(saved)
        meta._fieldnames.remove("transformation")
        delattr(meta, "transformation")

    _rewrite_mat(dataset, row, remove_transformation)
    with pytest.raises(PipelineError, match="Derived graph requires"):
        SourceDataset(dataset, graph_only=True).read_graph(row["graph_id"])


def test_read_runs_filters_context_and_passes_verified_canonical_edges(dataset, monkeypatch):
    row = _fixture_row(dataset, "undirected_triangle_isolate")
    (dataset / "manifests/metrics.jsonl").write_text("", encoding="utf-8")
    entries = [
        {"graph_id": row["graph_id"], "metric_set_id": set_id, "protocol_id": protocol, "run_id": run}
        for set_id, protocol, run in (("a", "", "1"), ("b", "p", "2"), ("b", "p", "3"))
    ]
    manifest_calls, payload_calls = [], []

    def manifest(*args):
        manifest_calls.append(True)
        return entries

    def read_run(root, entry, graph, project_root):
        payload_calls.append(entry["run_id"])
        np.testing.assert_array_equal(graph["edge_list"], [[1, 2], [1, 3], [2, 3]])
        assert graph["N"] == 4
        return MetricRun(row["graph_id"], row["topology_hash"], entry["metric_set_id"],
                         entry["protocol_id"], entry["run_id"], "complete", [])

    monkeypatch.setattr(source_module, "_read_metric_manifest", manifest)
    monkeypatch.setattr(source_module, "_read_metric_run", read_run)
    source = SourceDataset(dataset)
    assert len(manifest_calls) == 1 and payload_calls == []
    source.read_graph(row["graph_id"])
    monkeypatch.setattr(source, "read_graph", lambda graph_id: pytest.fail("Do not load the same graph twice"))
    runs = source.read_runs(row["graph_id"], [SimpleNamespace(metric_set_id="b", protocol_id="p")])
    assert [run.run_id for run in runs] == ["2", "3"]
    assert payload_calls == ["2", "3"] and len(manifest_calls) == 1
    assert source.read_runs(row["graph_id"], []) == []


def test_snapshot_covers_generation_config_schema_and_manifests(dataset):
    config = dataset / "configs/generation.json"
    config.parent.mkdir()
    config.write_text('{"source":"fixture"}', encoding="utf-8")
    source = SourceDataset(dataset, graph_only=True)
    before = source.source_snapshot()
    assert before["dataset_id"] == "schema_v1_examples"
    assert "configs/generation.json" in before["documents"]
    assert "graph" in before["schemas"]
    assert "code/graph_builder/validation/verify_graph_io.py" in before["schemas"]
    config.write_text('{"source":"changed"}', encoding="utf-8")
    assert before["documents"] != source.source_snapshot()["documents"]
    (dataset / "manifests/graphs.jsonl").write_text(
        (dataset / "manifests/graphs.jsonl").read_text(encoding="utf-8") + "\n", encoding="utf-8",
    )
    with pytest.raises(PipelineError, match="Source metadata changed.*graphs.jsonl"):
        source.source_snapshot()


def test_constructor_rejects_publication_between_manifest_parse_and_first_snapshot(dataset, monkeypatch):
    full = _rows(dataset)
    _save_rows(dataset, full[:-1])
    original = source_module.read_graph_manifest

    def publish_after_read(root):
        previous = original(root)
        assert len(previous) == 4
        _save_rows(dataset, full)
        return previous

    monkeypatch.setattr(source_module, "read_graph_manifest", publish_after_read)
    with pytest.raises(PipelineError, match="Source metadata changed.*graphs.jsonl"):
        SourceDataset(dataset, graph_only=True)
    assert len(_rows(dataset)) == 5


def test_constructor_rejects_dataset_descriptor_replacement_during_parse(dataset, monkeypatch):
    original = source_module.read_dataset_description

    def publish_after_read(root):
        descriptor = original(root)
        replacement = {**descriptor, "dataset_id": "changed_dataset"}
        (dataset / "dataset.json").write_text(json.dumps(replacement), encoding="utf-8")
        return descriptor

    monkeypatch.setattr(source_module, "read_dataset_description", publish_after_read)
    with pytest.raises(PipelineError, match="Source metadata changed.*dataset.json"):
        SourceDataset(dataset)


def test_constructor_pins_absence_of_metric_manifest(dataset, monkeypatch):
    original = source_module.read_graph_manifest

    def publish_metrics_after_read(root):
        rows = original(root)
        (dataset / "manifests/metrics.jsonl").write_text("", encoding="utf-8")
        return rows

    monkeypatch.setattr(source_module, "read_graph_manifest", publish_metrics_after_read)
    with pytest.raises(PipelineError, match="Source metadata changed.*metrics.jsonl"):
        SourceDataset(dataset)


def test_constructor_rejects_metric_manifest_change_during_parse(dataset, monkeypatch):
    path = dataset / "manifests/metrics.jsonl"
    path.write_text("", encoding="utf-8")

    def publish_after_read(*args):
        path.write_text("\n", encoding="utf-8")
        return []

    monkeypatch.setattr(source_module, "_read_metric_manifest", publish_after_read)
    with pytest.raises(PipelineError, match="Source metadata changed.*metrics.jsonl"):
        SourceDataset(dataset)


@pytest.mark.parametrize("change", ["dataset", "graphs", "metric_create", "metric_remove", "metric_replace"])
@pytest.mark.parametrize("method", ["source_snapshot", "read_graph", "read_runs"])
def test_indexed_metadata_changes_are_rejected_before_source_access(dataset, change, method):
    metric_path = dataset / "manifests/metrics.jsonl"
    if change in {"metric_remove", "metric_replace"}:
        metric_path.write_text("", encoding="utf-8")
    source = SourceDataset(dataset)
    identity = source.list_graphs()[0]["graph_id"]
    if change == "dataset":
        path = dataset / "dataset.json"
        path.write_text(path.read_text(encoding="utf-8") + "\n", encoding="utf-8")
    elif change == "graphs":
        _save_rows(dataset, _rows(dataset)[:-1])
    elif change == "metric_remove":
        metric_path.unlink()
    else:
        metric_path.write_text("" if change == "metric_create" else "\n", encoding="utf-8")
    with pytest.raises(PipelineError, match="Source metadata changed.*reopen SourceDataset"):
        if method == "source_snapshot":
            source.source_snapshot()
        else:
            getattr(source, method)(identity)


def test_graph_only_reader_does_not_pin_unused_metric_manifest(dataset):
    source = SourceDataset(dataset, graph_only=True)
    before = source.source_snapshot()
    (dataset / "manifests/metrics.jsonl").write_text("", encoding="utf-8")
    assert source.source_snapshot() == before
    assert source.read_runs(source.list_graphs()[0]["graph_id"]) == []


def test_read_graph_rejects_manifest_publication_while_payload_is_read(dataset, monkeypatch):
    source = SourceDataset(dataset, graph_only=True)
    identity = source.list_graphs()[0]["graph_id"]
    original = source_module.read_graph_v1

    def read_then_publish(*args, **kwargs):
        graph = original(*args, **kwargs)
        _save_rows(dataset, _rows(dataset)[:-1])
        return graph

    monkeypatch.setattr(source_module, "read_graph_v1", read_then_publish)
    with pytest.raises(PipelineError, match="Source metadata changed.*graphs.jsonl"):
        source.read_graph(identity)
    assert source._last_graph is None


def test_read_runs_rejects_descriptor_change_while_metric_payload_is_read(dataset, monkeypatch):
    row = _rows(dataset)[0]
    (dataset / "manifests/metrics.jsonl").write_text("", encoding="utf-8")
    entry = {"graph_id": row["graph_id"], "metric_set_id": "a", "protocol_id": "", "run_id": "1"}
    monkeypatch.setattr(source_module, "_read_metric_manifest", lambda *args: [entry])
    source = SourceDataset(dataset)

    def read_then_publish(*args):
        path = dataset / "dataset.json"
        path.write_text(path.read_text(encoding="utf-8") + "\n", encoding="utf-8")
        return MetricRun(row["graph_id"], row["topology_hash"], "a", "", "1", "complete", [])

    monkeypatch.setattr(source_module, "_read_metric_run", read_then_publish)
    with pytest.raises(PipelineError, match="Source metadata changed.*dataset.json"):
        source.read_runs(row["graph_id"])


def test_snapshot_rejects_publication_during_configuration_hashing(dataset, monkeypatch):
    config = dataset / "configs/generation.json"
    config.parent.mkdir()
    config.write_text("{}", encoding="utf-8")
    source = SourceDataset(dataset, graph_only=True)
    original = source_module.file_fingerprint

    def fingerprint_then_publish(path):
        value = original(path)
        if Path(path) == config:
            _save_rows(dataset, _rows(dataset)[:-1])
        return value

    monkeypatch.setattr(source_module, "file_fingerprint", fingerprint_then_publish)
    with pytest.raises(PipelineError, match="Source metadata changed.*graphs.jsonl"):
        source.source_snapshot()


def test_atomic_replacement_with_preserved_size_and_mtime_is_detected(dataset):
    source = SourceDataset(dataset, graph_only=True)
    identity = source.list_graphs()[0]["graph_id"]
    path = dataset / "dataset.json"
    prior = path.stat()
    replacement = dataset / "descriptor.replacement.json"
    replacement.write_bytes(path.read_bytes().replace(b"schema_v1_examples", b"schema_v1_examplez"))
    os.utime(replacement, ns=(prior.st_atime_ns, prior.st_mtime_ns))
    os.replace(replacement, path)
    assert path.stat().st_size == prior.st_size and path.stat().st_mtime_ns == prior.st_mtime_ns
    with pytest.raises(PipelineError, match="Source metadata changed.*dataset.json"):
        source.read_graph(identity)


def test_per_graph_reads_do_not_rehash_entire_unchanged_indexes(dataset, monkeypatch):
    source = SourceDataset(dataset, graph_only=True)
    identities = [row["graph_id"] for row in source.list_graphs()]
    original = source_module.file_fingerprint
    indexed_paths = {dataset / relative for relative in ("dataset.json", "manifests/graphs.jsonl")}
    calls = []

    def count_index_hashes(path):
        if Path(path) in indexed_paths:
            calls.append(Path(path))
        return original(path)

    monkeypatch.setattr(source_module, "file_fingerprint", count_index_hashes)
    for graph_id in identities:
        source.read_graph(graph_id)
        source.read_runs(graph_id)
    assert calls == []
    source.source_snapshot()
    assert set(calls) == indexed_paths


def _batch_descriptor(root):
    """Add a test-only batch descriptor; do not create or alter producer graphs."""
    path = root / "dataset.json"
    descriptor = json.loads(path.read_text(encoding="utf-8"))
    configuration = {"schema_version": 2, "dataset_id": descriptor["dataset_id"], "output_dir": ".."}
    config_path = root / "configs/generation.json"
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(json.dumps(configuration), encoding="utf-8")
    descriptor.update(
        generation_config="configs/generation.json", generation_config_sha256="a" * 64,
        generation_config_file_sha256=file_fingerprint(config_path)["file_sha256"],
        implementation_sha256="b" * 64, implementation_version="2.0.0",
    )
    path.write_text(json.dumps(descriptor), encoding="utf-8")
    return descriptor, config_path


def _replace_batch_config(root, value):
    path = root / "configs/generation.json"
    path.write_text(json.dumps(value), encoding="utf-8")
    descriptor_path = root / "dataset.json"
    descriptor = json.loads(descriptor_path.read_text(encoding="utf-8"))
    descriptor["generation_config_file_sha256"] = file_fingerprint(path)["file_sha256"]
    descriptor_path.write_text(json.dumps(descriptor), encoding="utf-8")


def test_batch_descriptor_validates_file_digest_but_preserves_producer_identity(dataset, monkeypatch):
    descriptor, config_path = _batch_descriptor(dataset)
    descriptor["implementation_version"] = "2.1.0"
    (dataset / "dataset.json").write_text(json.dumps(descriptor), encoding="utf-8")
    monkeypatch.setattr(source_module, "_load_mat", lambda *args: pytest.fail("Initialization cannot read MATs"))
    source = SourceDataset(dataset, graph_only=True)
    assert source.dataset_metadata == descriptor
    assert source.dataset_metadata["generation_config_sha256"] == "a" * 64
    assert source.source_snapshot()["documents"]["configs/generation.json"] == file_fingerprint(config_path)
    assert "configs/generation.json" in source._indexed_documents


@pytest.mark.parametrize("field", [
    "generation_config", "generation_config_sha256", "generation_config_file_sha256",
    "implementation_sha256", "implementation_version",
])
def test_batch_descriptor_requires_generation_fields_together(dataset, field):
    descriptor, _ = _batch_descriptor(dataset)
    del descriptor[field]
    (dataset / "dataset.json").write_text(json.dumps(descriptor), encoding="utf-8")
    with pytest.raises(PipelineError, match="requires all generation fields"):
        SourceDataset(dataset, graph_only=True)


@pytest.mark.parametrize("field,value,match", [
    ("generation_config", "../generation.json", "generation_config must"),
    ("generation_config", "configs/other.json", "generation_config must"),
    ("generation_config_sha256", "A" * 64, "lowercase hexadecimal"),
    ("generation_config_file_sha256", "not-a-hash", "lowercase hexadecimal"),
    ("implementation_sha256", 123, "lowercase hexadecimal"),
    ("implementation_version", "", "nonempty string"),
    ("implementation_version", 2, "nonempty string"),
])
def test_batch_descriptor_rejects_invalid_declared_fields(dataset, field, value, match):
    descriptor, _ = _batch_descriptor(dataset)
    descriptor[field] = value
    (dataset / "dataset.json").write_text(json.dumps(descriptor), encoding="utf-8")
    with pytest.raises(PipelineError, match=match):
        SourceDataset(dataset, graph_only=True)


@pytest.mark.parametrize("mode", ["missing", "corrupt"])
def test_batch_descriptor_requires_intact_configuration_file(dataset, mode):
    _, path = _batch_descriptor(dataset)
    if mode == "missing":
        path.unlink()
    else:
        path.write_text(path.read_text(encoding="utf-8") + " ", encoding="utf-8")
    with pytest.raises(PipelineError, match="Missing generation|file SHA-256"):
        SourceDataset(dataset, graph_only=True)


@pytest.mark.parametrize("field,value,match", [
    ("schema_version", 1, "schema_version must be numeric 2"),
    ("schema_version", True, "schema_version must be numeric 2"),
    ("schema_version", "2", "schema_version must be numeric 2"),
    ("dataset_id", "different_dataset", "dataset_id differs"),
    ("output_dir", "F:/elsewhere", "output_dir must"),
])
def test_batch_configuration_semantics_checked_after_file_digest(dataset, field, value, match):
    _, path = _batch_descriptor(dataset)
    configuration = json.loads(path.read_text(encoding="utf-8"))
    configuration[field] = value
    _replace_batch_config(dataset, configuration)
    with pytest.raises(PipelineError, match=match):
        SourceDataset(dataset, graph_only=True)


def test_batch_configuration_must_be_json_object(dataset):
    _batch_descriptor(dataset)
    _replace_batch_config(dataset, [])
    with pytest.raises(PipelineError, match="Expected a JSON object"):
        SourceDataset(dataset, graph_only=True)


@pytest.mark.parametrize("method", ["source_snapshot", "read_graph", "read_runs"])
def test_declared_generation_config_is_pinned_for_all_source_reads(dataset, method):
    _, path = _batch_descriptor(dataset)
    source = SourceDataset(dataset, graph_only=True)
    graph_id = source.list_graphs()[0]["graph_id"]
    path.write_text(path.read_text(encoding="utf-8") + "\n", encoding="utf-8")
    with pytest.raises(PipelineError, match="Source metadata changed.*generation.json"):
        if method == "source_snapshot":
            source.source_snapshot()
        else:
            getattr(source, method)(graph_id)


def test_generation_config_change_during_its_parse_is_rejected(dataset, monkeypatch):
    _, path = _batch_descriptor(dataset)
    original = source_module.read_json_object

    def read_then_replace(value):
        result = original(value)
        if Path(value) == path:
            path.write_text(path.read_text(encoding="utf-8") + "\n", encoding="utf-8")
        return result

    monkeypatch.setattr(source_module, "read_json_object", read_then_replace)
    with pytest.raises(PipelineError, match="Generation configuration changed while being parsed"):
        SourceDataset(dataset, graph_only=True)


def test_generation_config_change_after_descriptor_validation_is_rejected(dataset, monkeypatch):
    _, path = _batch_descriptor(dataset)
    original = source_module.read_dataset_description

    def validate_then_replace(root):
        result = original(root)
        path.write_text(path.read_text(encoding="utf-8") + "\n", encoding="utf-8")
        return result

    monkeypatch.setattr(source_module, "read_dataset_description", validate_then_replace)
    with pytest.raises(PipelineError, match="Generation configuration changed since descriptor validation"):
        SourceDataset(dataset, graph_only=True)


def test_generation_config_change_while_graph_manifest_is_parsed_is_rejected(dataset, monkeypatch):
    _, path = _batch_descriptor(dataset)
    original = source_module.read_graph_manifest

    def read_then_replace(root):
        result = original(root)
        path.write_text(path.read_text(encoding="utf-8") + "\n", encoding="utf-8")
        return result

    monkeypatch.setattr(source_module, "read_graph_manifest", read_then_replace)
    with pytest.raises(PipelineError, match="Source metadata changed.*generation.json"):
        SourceDataset(dataset, graph_only=True)
