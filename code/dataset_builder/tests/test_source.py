"""Independent source checks; no prior datasets or guessed MAT schemas."""

import hashlib
import json
from copy import deepcopy
from pathlib import Path

import numpy as np
import pytest
from scipy.io import loadmat, savemat

from dataset_builder.models import PipelineError
from dataset_builder.source import (
    SchemaUnavailable,
    SourceDataset,
    file_fingerprint,
    parse_json,
    read_jsonl,
    resolve_source_path,
    verify_source_file,
    _mat_struct,
    _read_metric,
    _read_metric_run,
    _read_attack,
    read_json_object,
    PROJECT_ROOT,
)


def test_formal_schema_required(tmp_path):
    with pytest.raises(SchemaUnavailable, match="task 1"):
        SourceDataset(tmp_path / "dataset", project_root=tmp_path)


def test_duplicate_and_conflicting_manifest_rows_rejected(tmp_path):
    path = tmp_path / "manifest.jsonl"
    row = {"graph_id": "a", "path": "graphs/a.mat"}
    path.write_text(json.dumps(row) + "\n" + json.dumps(row) + "\n", encoding="utf-8")
    with pytest.raises(PipelineError, match="Duplicate"):
        read_jsonl(path, identity_fields=("graph_id",))
    path.write_text(json.dumps(row) + "\n" + json.dumps(dict(row, path="graphs/b.mat")), encoding="utf-8")
    with pytest.raises(PipelineError, match="Conflicting"):
        read_jsonl(path, identity_fields=("graph_id",))


def test_compound_identity_keeps_repeated_runs(tmp_path):
    path = tmp_path / "manifest.jsonl"
    rows = [
        {"graph_id": "a", "metric_set_id": "m", "protocol_id": "", "run_id": "r1"},
        {"graph_id": "a", "metric_set_id": "m", "protocol_id": "", "run_id": "r2"},
    ]
    path.write_text("\n".join(map(json.dumps, rows)), encoding="utf-8")
    assert read_jsonl(path, identity_fields=("graph_id", "metric_set_id", "protocol_id", "run_id")) == rows


@pytest.mark.parametrize("text", ['{"a":1,"a":2}', '{"a":NaN}', '{"a":Infinity}', '{"a":1e999}'])
def test_ambiguous_json_rejected(text):
    with pytest.raises(PipelineError):
        parse_json(text)


@pytest.mark.parametrize("path", ["../a", "/a", "C:/a", "a\\b", "a/../b", "a//b", "./a", ""])
def test_path_escape_rejected(tmp_path, path):
    with pytest.raises(PipelineError):
        resolve_source_path(tmp_path, path)


def test_file_bytes_and_digest_checked(tmp_path):
    path = tmp_path / "sample.bin"
    path.write_bytes(b"source data")
    entry = {"path": "sample.bin", "file_bytes": 11, "file_sha256": hashlib.sha256(b"source data").hexdigest()}
    assert verify_source_file(tmp_path, entry) == path
    path.write_bytes(b"source edit")
    with pytest.raises(PipelineError, match="SHA-256 mismatch"):
        verify_source_file(tmp_path, entry)
    path.write_bytes(b"truncated")
    with pytest.raises(PipelineError, match="byte count mismatch"):
        verify_source_file(tmp_path, entry)
    path.unlink()
    with pytest.raises(PipelineError, match="Missing source file"):
        verify_source_file(tmp_path, entry)


def test_fingerprint_detects_metadata_mutation(tmp_path):
    path = tmp_path / "document.json"
    path.write_bytes(b'{"value":1}')
    before = file_fingerprint(path)
    assert before["file_bytes"] == path.stat().st_size
    path.write_bytes(b'{"value":2}')
    assert file_fingerprint(path)["file_sha256"] != before["file_sha256"]


def _metric_record(tmp_path, *, values, mask, scope="node", axes=("node",), ids=None, status="ok", reason="", details=None):
    names = np.empty((1, len(axes)), dtype=object)
    coordinates = np.empty((1, len(axes)), dtype=object)
    for index, axis in enumerate(axes):
        names[0, index] = axis
        if all(isinstance(item, str) for item in ids[index]) and len(ids[index]):
            labels = np.empty((len(ids[index]), 1), dtype=object)
            for position, label in enumerate(ids[index]):
                labels[position, 0] = label
            coordinates[0, index] = labels
        else:
            coordinates[0, index] = np.asarray(ids[index], dtype=np.uint32).reshape(-1, 1)
    record = {
        "metric_id": "test_metric", "metric_version": "1.0.0", "parameters": {}, "scope": scope,
        "values": np.asarray(values), "valid_mask": np.asarray(mask, dtype=bool),
        "axis_names": names, "axis_ids": coordinates, "status": status, "reason": reason,
        "units": "count", "method": "exact", "elapsed_seconds": 0.0, "details": details or {},
    }
    path = tmp_path / "metric.mat"
    savemat(path, {"record": record}, do_compression=True)
    data = loadmat(path, struct_as_record=False, squeeze_me=False, mat_dtype=True)
    return _mat_struct(data["record"], "record")


def test_metric_scalar_and_singleton_axis_are_distinct(tmp_path):
    scalar = _read_metric(_metric_record(tmp_path, values=[[0.0]], mask=[[True]], scope="graph", axes=()), num_nodes=1, num_edges=0)
    vector = _read_metric(_metric_record(tmp_path, values=[[0.0]], mask=[[True]], ids=([1],)), num_nodes=1, num_edges=0)
    assert scalar.values.shape == ()
    assert vector.values.shape == (1,)
    assert vector.node_ids.tolist() == [1]
    assert scalar.valid_mask.item() is True


def test_metric_original_ids_and_invalid_values_preserved(tmp_path):
    metric = _read_metric(_metric_record(
        tmp_path, values=[[3.0], [np.nan], [0.0]], mask=[[True], [False], [True]],
        scope="edge", axes=("edge",), ids=([3, 1, 2],), status="partial", reason="one undefined entry",
    ), num_nodes=4, num_edges=3)
    assert metric.edge_ids.tolist() == [3, 1, 2]
    assert np.isnan(metric.values[1])
    assert metric.valid_mask.tolist() == [True, False, True]
    assert metric.values[2] == 0.0


def test_metric_original_id_out_of_range_rejected(tmp_path):
    record = _metric_record(tmp_path, values=[[1.0]], mask=[[True]], ids=([5],))
    with pytest.raises(PipelineError, match="original node IDs"):
        _read_metric(record, num_nodes=4, num_edges=0)


@pytest.mark.parametrize("scope", ["graph", "matrix"])
def test_metric_scope_axis_rank_conflict_rejected(tmp_path, scope):
    record = _metric_record(tmp_path, values=[[1.0]], mask=[[True]], scope=scope, ids=([1],))
    with pytest.raises(PipelineError, match="scope requires"):
        _read_metric(record, num_nodes=1, num_edges=0)


def test_metric_matrix_node_axes_preserved(tmp_path):
    record = _metric_record(tmp_path, values=[[0, 1], [1, 0]], mask=[[True, True], [True, True]],
                            scope="matrix", axes=("source_node", "target_node"), ids=([1, 3], [1, 3]))
    metric = _read_metric(record, num_nodes=3, num_edges=1)
    assert metric.values.shape == (2, 2)
    assert metric.axis_ids["source_node"].tolist() == [1, 3]


def test_valid_infinity_requires_explicit_definition(tmp_path):
    record = _metric_record(tmp_path, values=[[np.inf]], mask=[[True]], scope="graph", axes=())
    with pytest.raises(PipelineError, match="explicit metric definition"):
        _read_metric(record, num_nodes=1, num_edges=0)


def test_unavailable_empty_retains_source_shape(tmp_path):
    record = _metric_record(tmp_path, values=np.empty((0, 0)), mask=np.empty((0, 0)),
                            scope="graph", axes=(), status="failed", reason="computation failed")
    metric = _read_metric(record, num_nodes=1, num_edges=0)
    assert metric.values.shape == (0, 0)
    assert metric.axis_names == ()
    assert metric.metadata["shape_unknown"] is True
    metric.validate()


def test_documented_positive_infinity_preserves_definition_proof(tmp_path):
    path = tmp_path / "code/graph_analyzer/registry/advanced.json"
    path.parent.mkdir(parents=True)
    path.write_text(json.dumps([{
        "metric_id": "kirchhoff_index", "metric_version": "1.0.0",
        "conditions": "N=0 undefined; N=1 zero; disconnected N>1 gives valid +Inf; this is the unordered-pair total.",
    }]), encoding="utf-8")
    record = _metric_record(tmp_path, values=[[np.inf]], mask=[[True]], scope="graph", axes=())
    record["metric_id"] = np.array(["kirchhoff_index"])
    metric = _read_metric(record, num_nodes=2, num_edges=0, project_root=tmp_path)
    assert metric.metadata["allows_infinity"] is True
    assert metric.metadata["infinity_definition"]["file_sha256"] == file_fingerprint(path)["file_sha256"]
    metric.validate()
    record["values"] = np.array([[-np.inf]])
    with pytest.raises(PipelineError, match="explicit metric definition"):
        _read_metric(record, num_nodes=2, num_edges=0, project_root=tmp_path)


def test_static_run_exact_identity_and_source_hash(tmp_path):
    schema = tmp_path / "code/graph_analyzer/docs/metric_schema_v1.md"
    schema.parent.mkdir(parents=True)
    schema.write_text("metric-v1 test fixture", encoding="utf-8")
    graph = {"graph_id": "a" * 64, "topology_hash": "b" * 64, "origin_graph_id": "a" * 64, "N": 1, "M": 0}
    selection = {"metric_id": "test_metric", "metric_version": "1.0.0", "parameters": {}}
    seeds = {"randomness": "none", "attack_seed": [], "repeat_index": 1}
    metric_json = json.dumps({"identity_version": "metric-set-v1", "configuration": {
        "protocol_id": "", "implementation_sha256": "c" * 64, "selections": [selection], "summary_selections": [],
    }})
    metric_id = hashlib.sha256(metric_json.encode()).hexdigest()
    run_json = json.dumps({"identity_version": "metric-run-v1", "configuration": {
        "graph_id": graph["graph_id"], "topology_hash": graph["topology_hash"], "metric_set_id": metric_id, "seeds": seeds,
    }})
    run_id = hashlib.sha256(run_json.encode()).hexdigest()
    record = _metric_record(tmp_path, values=[[0.0]], mask=[[True]], scope="graph", axes=())
    record["parameters"] = {}
    record["details"] = {}
    output = {
        **{key: graph[key] for key in ("graph_id", "topology_hash", "origin_graph_id")},
        "schema_version": "metric-v1", "metric_set_id": metric_id, "protocol_id": "", "run_id": run_id,
        "metric_version": "1.0.0", "implementation_sha256": "c" * 64,
        "metric_set_identity_json": metric_json, "run_identity_json": run_json,
        "selections": selection, "summary_selections": np.empty((0, 0)), "summaries": np.empty((0, 0)), "seeds": seeds,
        "status": "complete", "results": record, "attack": {}, "created_utc": "2026-09-27T00:00:00Z",
        "matlab_version": "test", "elapsed_seconds": 0.0,
    }
    path = tmp_path / "result.mat"
    config_path = tmp_path / "configs/metric_sets" / f"{metric_id}.json"
    config_path.parent.mkdir(parents=True)
    config_path.write_text(metric_json, encoding="utf-8")
    savemat(path, {"output": output}, do_compression=True)
    entry = {"path": "result.mat", **file_fingerprint(path), "run_id": run_id, "metric_set_id": metric_id}
    run = _read_metric_run(tmp_path, entry, graph, tmp_path)
    assert run.run_id == run_id
    assert run.metrics[0].values.item() == 0.0
    output["run_identity_json"] += " "
    savemat(path, {"output": output}, do_compression=True)
    entry.update(file_fingerprint(path))
    with pytest.raises(PipelineError, match="saved exact identity JSON"):
        _read_metric_run(tmp_path, entry, graph, tmp_path)
    output["run_identity_json"] = run_json
    output["results"].update(status="failed", reason="calculation failed",
                              values=np.asarray([[np.nan]]), valid_mask=np.asarray([[False]]))
    savemat(path, {"output": output}, do_compression=True)
    entry.update(file_fingerprint(path))
    with pytest.raises(PipelineError, match="Complete run contains failed"):
        _read_metric_run(tmp_path, entry, graph, tmp_path)
    output["status"] = "partial"
    savemat(path, {"output": output}, do_compression=True)
    entry.update(file_fingerprint(path))
    partial = _read_metric_run(tmp_path, entry, graph, tmp_path)
    assert partial.metrics[0].status == "failed" and partial.metrics[0].reason == "calculation failed"


def test_producer_trajectory_actual_positions(tmp_path):
    record = _metric_record(tmp_path, values=[[1.0], [0.5], [np.nan]], mask=[[True], [True], [False]],
                            scope="trajectory", axes=("removed_count",), ids=([0, 1, 2],),
                            status="partial", reason="undefined endpoint", details={"actual_fraction": [[0], [0.5], [1.0]]})
    record["metric_id"] = np.array(["efficiency_retention_curve"])
    metric = _read_metric(record, num_nodes=3, num_edges=2)
    assert metric.axis_positions["removed_count"].tolist() == [0, 1, 2]
    assert metric.axis_positions["actual_fraction"].tolist() == [0, 0.5, 1]
    assert metric.valid_mask.tolist() == [True, True, False]
    metric.validate()


def _struct_rows(rows):
    array = np.empty((len(rows), 1), dtype=[(key, object) for key in rows[0]])
    for index, row in enumerate(rows):
        for key, value in row.items():
            array[key][index, 0] = value
    return array


def _attack_record(tmp_path, metric_observation=False):
    schema = tmp_path / "code/graph_analyzer/docs/attack_protocols.md"
    schema.parent.mkdir(parents=True)
    schema.write_text("attack-1.0.0 test fixture", encoding="utf-8")
    observations = np.empty((0, 0))
    if metric_observation:
        metric = _metric_record(tmp_path, values=[[2]], mask=[[True]], scope="graph", axes=())
        metric["parameters"], metric["details"] = {}, {}
        observations = _struct_rows([metric])
    states = []
    for count in (0, 1):
        states.append({"removed_count": count, "round_index": count, "removed_fraction": float(count), "fraction_valid": True,
                       "removed_ids": [] if count == 0 else [1], "remaining_node_ids": [1, 2],
                       "removed_node_ids": [], "removed_edge_ids": [] if count == 0 else [1],
                       "remaining_edge_ids": [1] if count == 0 else [],
                       "remaining_edge_endpoints_original": [[1, 2]] if count == 0 else np.empty((0, 2)),
                       "node_count": 2, "edge_count": 1 - count, "metrics": observations, "status": "ok"})
    samples = [{"requested_fraction": fraction, "requested_removed_count": 0, "state_index": 1,
                "actual_removed_count": 0, "actual_removed_fraction": 0.0, "fraction_valid": True,
                "exact_count_match": True, "status": "ok", "metrics": observations}
               for fraction in (0.0, 0.25)]
    attack = {"schema_version": "attack-1.0.0", "protocol_id": "c" * 64,
              "protocol": {"version": "1.0.0", "target": "edge", "rounding": "floor", "sample_fractions": [0, 0.25],
                           "stop_fraction": 1, "batch_size": 1, "deletion_mode": "single", "sample_policy": "exact"},
              "attack_seed": [], "repeat_index": 1, "randomness": {"algorithm": "none", "seed": [], "used": False},
              "full_single_object_trajectory": True,
              "original_node_count": 2, "original_edge_count": 1, "original_node_ids": [1, 2],
              "original_edge_ids": [1], "directed": False, "target_count": 1, "deleted_ids": [1],
              "states": _struct_rows(states), "sampled": _struct_rows(samples), "status": "ok", "fraction_status": "ok"}
    path = tmp_path / "attack.mat"
    savemat(path, {"attack": attack}, long_field_names=True)
    return _mat_struct(loadmat(path, struct_as_record=False, mat_dtype=True)["attack"], "attack")


def test_attack_retains_repeated_actual_positions_and_isolated_nodes(tmp_path):
    attack = _attack_record(tmp_path)
    native = _read_attack(attack, {"N": 2, "M": 1, "directed": False}, "c" * 64, [], tmp_path)
    assert [row["actual_removed_count"] for row in native["sampled"]] == [0, 0]
    assert [row["requested_fraction"] for row in native["sampled"]] == [0, 0.25]
    assert native["states"][1]["remaining_node_ids"] == [1, 2]


def test_attack_rejects_wrong_actual_sampling_position(tmp_path):
    attack = _attack_record(tmp_path)
    attack["sampled"].reshape(-1)[1].actual_removed_count = np.array([[1]])
    with pytest.raises(PipelineError, match="sampled actual_removed_count"):
        _read_attack(attack, {"N": 2, "M": 1, "directed": False}, "c" * 64, [], tmp_path)


def test_hits_textual_score_axis_decodes_to_unicode(tmp_path):
    record = _metric_record(tmp_path, values=[[0.5, 0.5], [0.5, 0.5]], mask=np.ones((2, 2), dtype=bool),
                            scope="matrix", axes=("node", "score"), ids=([1, 2], ["hub", "authority"]))
    metric = _read_metric(record, num_nodes=2, num_edges=1)
    assert metric.axis_ids["score"].dtype.kind == "U"
    assert metric.axis_ids["score"].tolist() == ["hub", "authority"]
    assert metric.axis_ids["node"].tolist() == [1, 2]
    metric.validate()


def test_ok_status_rejects_invalid_mask(tmp_path):
    record = _metric_record(tmp_path, values=[[np.nan]], mask=[[False]], scope="graph", axes=())
    with pytest.raises(PipelineError, match="status ok"):
        _read_metric(record, num_nodes=1, num_edges=0)


@pytest.mark.parametrize("field", ["values", "valid_mask", "status"])
def test_attack_rejects_sample_metric_corruption(tmp_path, field):
    attack = _attack_record(tmp_path, metric_observation=True)
    sample = attack["sampled"].reshape(-1)[1].metrics.reshape(-1)[0]
    if field == "values":
        sample.values = np.array([[99]])
    elif field == "valid_mask":
        sample.valid_mask = np.array([[False]])
        sample.status = np.array(["partial"])
    else:
        sample.status = np.array(["partial"])
    definitions = [{"metric_id": "test_metric", "metric_version": "1.0.0", "parameters": {}}]
    with pytest.raises(PipelineError, match="sampled metric values/axes/masks/status"):
        _read_attack(attack, {"N": 2, "M": 1, "directed": False}, "c" * 64, definitions, tmp_path)


def test_attack_rejects_invalid_initial_endpoints(tmp_path):
    attack = _attack_record(tmp_path)
    attack["states"].reshape(-1)[0].remaining_edge_endpoints_original = np.array([[1, 1]])
    with pytest.raises(PipelineError, match="initial original edge endpoints"):
        _read_attack(attack, {"N": 2, "M": 1, "directed": False}, "c" * 64, [], tmp_path)


def test_attack_rejects_nested_seed_change(tmp_path):
    attack = _attack_record(tmp_path)
    attack["attack_seed"] = np.array([[123]])
    with pytest.raises(PipelineError, match="seed/repeat/randomness"):
        _read_attack(attack, {"N": 2, "M": 1, "directed": False}, "c" * 64, [], tmp_path,
                     seeds={"attack_seed": [], "repeat_index": 1, "randomness": "none"})


def test_attack_rejects_truncated_stop_boundaries(tmp_path):
    attack = _attack_record(tmp_path)
    attack["states"] = attack["states"][:1]
    with pytest.raises(PipelineError, match="stop/batch boundaries"):
        _read_attack(attack, {"N": 2, "M": 1, "directed": False}, "c" * 64, [], tmp_path)


def test_attack_rejects_changed_surviving_edge_identity(tmp_path):
    attack = _attack_record(tmp_path)
    original = attack["states"].reshape(-1)[0]
    states = np.empty((3, 1), dtype=object)
    for count in range(3):
        state = deepcopy(original)
        state.removed_count = np.array([[count]])
        state.round_index = np.array([[count]])
        state.removed_fraction = np.array([[count / 2]])
        state.removed_ids = np.array([] if count == 0 else [count])
        state.removed_edge_ids = state.removed_ids.copy()
        state.remaining_node_ids = np.array([1, 2, 3])
        state.remaining_edge_ids = np.arange(count + 1, 3)
        state.node_count, state.edge_count = np.array([[3]]), np.array([[2 - count]])
        state.remaining_edge_endpoints_original = np.array([[1, 2], [2, 3]])[count:]
        states[count, 0] = state
    attack.update(states=states, original_node_count=np.array([[3]]), original_edge_count=np.array([[2]]),
                  original_node_ids=np.array([1, 2, 3]), original_edge_ids=np.array([1, 2]),
                  target_count=np.array([[2]]), deleted_ids=np.array([1, 2]))
    states[1, 0].remaining_edge_endpoints_original = np.array([[1, 3]])
    with pytest.raises(PipelineError, match="residual original-ID endpoints"):
        _read_attack(attack, {"N": 3, "M": 2, "directed": False}, "c" * 64, [], tmp_path)


def validate_producer_metric_fixtures(root: str | Path) -> dict:
    """Read task-2's explicitly test-only MATLAB fixtures, never a graph format.

    Invoked by the command at the end of this file, independently of unit tests.
    Test descriptions supply in-memory N/M/direction and synthetic identity labels.
    """
    root = Path(root)
    descriptions = read_json_object(root / "fixture_descriptions.json")
    if descriptions.get("purpose") != "test-only in-memory fixtures; no original graph files":
        raise PipelineError("Expected the producer's explicit metric-only prototype fixture description")
    contexts = {}
    for fixture in descriptions["fixtures"]:
        arc_count = len(fixture["arcs_one_based"])
        contexts[fixture["test_identity"]["graph_id"]] = {
            **fixture["test_identity"], "N": fixture["node_count"],
            "M": arc_count if fixture["directed"] else arc_count // 2,
            "directed": fixture["directed"], "fixture_name": fixture["fixture_name"],
        }
    manifest = root / "manifests/metrics.jsonl"
    rows = read_jsonl(manifest, identity_fields=("graph_id", "topology_hash", "metric_set_id", "protocol_id", "run_id"))
    records = []
    for row in rows:
        context = contexts[row["graph_id"]]
        record = {"run_id": row["run_id"], "fixture_name": context["fixture_name"],
                  "attack": bool(row["protocol_id"]), "file_sha256": row["file_sha256"]}
        try:
            run = _read_metric_run(root, row, context, PROJECT_ROOT)
            for metric in run.metrics:
                metric.validate()
                if metric.metric_id in {"node_count", "edge_count"}:
                    expected = context["N"] if metric.metric_id == "node_count" else context["M"]
                    if metric.values.shape != () or metric.values.item() != expected or not metric.valid_mask.item():
                        raise PipelineError(f"Fixture {metric.metric_id} does not match described context")
                if metric.metric_id == "degree" and not np.array_equal(metric.node_ids, np.arange(1, context["N"] + 1)):
                    raise PipelineError("Fixture degree axis loses original nodes or isolates")
            record.update(status="passed", metric_records=len(run.metrics), metric_ids=[metric.metric_id for metric in run.metrics])
        except PipelineError as exc:
            record.update(status="rejected", reason=str(exc))
        records.append(record)
    return {"verification_scope": "metric-only actual MATLAB fixtures; no original graph files",
            "root": str(root), "manifest": file_fingerprint(manifest),
            "passed": sum(record["status"] == "passed" for record in records),
            "rejected": sum(record["status"] == "rejected" for record in records), "records": records}


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Validate task-2 metric-only MATLAB prototype fixtures")
    parser.add_argument("--producer-fixtures", required=True)
    report = validate_producer_metric_fixtures(parser.parse_args().producer_fixtures)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    raise SystemExit(bool(report["rejected"]))
