"""Read source observation coordinates and reject altered discrete schedules."""

from copy import deepcopy
from types import SimpleNamespace

import numpy as np
import pytest
from scipy.io import loadmat, savemat

from dataset_builder.config import MetricSelector
from dataset_builder.models import MetricRun, PipelineError
from dataset_builder.projection import project_observations
from dataset_builder.source import _attack_boundaries, _mat_struct, _read_attack, _round_attack_counts
from dataset_builder.tests.test_source import _attack_record, _struct_rows


def _grid_fixture(tmp_path, *, total=7, rounding="floor", version="1.1.0"):
    """Test-only attack records following the published producer schedule rules."""
    schema = tmp_path / "code/graph_analyzer/docs/attack_protocols.md"
    schema.parent.mkdir(parents=True, exist_ok=True)
    schema.write_text("attack-1.1.0 discrete schedule test", encoding="utf-8")
    requested = np.array([0, .1, .2, .3, .4, 1.0])
    sampled = np.array([0, .1, .2, .3, .4, .5, 1.0])
    rounding_fn = {"floor": np.floor, "ceil": np.ceil, "nearest": lambda x: np.floor(x + .5)}[rounding]
    q = rounding_fn(requested * total).astype(int)
    counts = np.unique(np.r_[0, q])
    edges = np.column_stack((np.arange(1, total + 1), np.arange(2, total + 2)))
    node_count = total + 1
    states = []
    for i, count in enumerate(counts):
        previous = counts[i - 1] if i else 0
        remaining = np.arange(count + 1, total + 1)
        axes, ids = np.empty((1, 1), dtype=object), np.empty((1, 1), dtype=object)
        axes[0, 0], ids[0, 0] = "edge", remaining.reshape(-1, 1)
        values = remaining.astype(float)
        mask = remaining != 2
        values[~mask] = np.nan
        metric = {
            "metric_id": "test_edge_metric", "metric_version": "1.0.0", "parameters": {}, "scope": "edge",
            "values": values.reshape(-1, 1), "valid_mask": mask.reshape(-1, 1), "axis_names": axes, "axis_ids": ids,
            "status": "ok" if np.all(mask) else "partial", "reason": "undefined edge value" if not np.all(mask) else "",
            "units": "count", "method": "exact", "elapsed_seconds": 0, "details": {},
        }
        states.append({
            "removed_count": count, "removed_fraction": count / total if total else np.nan,
            "fraction_valid": total > 0, "round_index": i,
            "removed_ids": np.arange(previous + 1, count + 1), "removed_node_ids": [],
            "removed_edge_ids": np.arange(previous + 1, count + 1),
            "remaining_node_ids": np.arange(1, node_count + 1), "remaining_edge_ids": remaining,
            "remaining_edge_endpoints_original": edges[count:], "node_count": node_count, "edge_count": len(remaining),
            "metrics": _struct_rows([metric]), "status": "ok",
        })
    samples = []
    for fraction in sampled:
        count = int(rounding_fn(fraction * total))
        indices = np.flatnonzero(counts == count)
        selected = int(indices[0]) if len(indices) else None
        samples.append({
            "requested_fraction": fraction, "requested_removed_count": count,
            "state_index": selected + 1 if selected is not None else 0,
            "actual_removed_count": count if selected is not None else np.nan,
            "actual_removed_fraction": count / total if selected is not None and total else np.nan,
            "fraction_valid": selected is not None and total > 0, "exact_count_match": selected is not None,
            "status": "ok" if selected is not None else "not_computed",
            "reason": "" if selected is not None else "Requested count was not observed.",
            "metrics": states[selected]["metrics"] if selected is not None else np.empty((0, 0)),
        })
    indices = np.searchsorted(counts, q) + 1
    attack = {
        "schema_version": f"attack-{version}", "protocol_id": "c" * 64,
        "protocol": {"version": version, "target": "edge", "rounding": rounding,
                     "sample_fractions": sampled, "stop_fraction": 1, "batch_size": 1,
                     "deletion_mode": "fraction_grid", "sample_policy": "exact", "attack_fractions": requested},
        "schedule": {"requested_fraction": requested.reshape(-1, 1), "requested_removed_count": q.reshape(-1, 1),
                     "increment": np.diff(np.r_[0, q]).reshape(-1, 1), "state_index": indices.reshape(-1, 1),
                     "round_index": (indices - 1).reshape(-1, 1), "actual_removed_count": q.reshape(-1, 1),
                     "actual_removed_fraction": (q / total if total else np.full(len(q), np.nan)).reshape(-1, 1),
                     "fraction_valid": np.full((len(q), 1), total > 0, dtype=bool)},
        "attack_seed": [], "repeat_index": 1, "randomness": {"algorithm": "none", "seed": [], "used": False},
        "full_single_object_trajectory": np.array_equal(counts, np.arange(total + 1)),
        "original_node_count": node_count, "original_edge_count": total,
        "original_node_ids": np.arange(1, node_count + 1), "original_edge_ids": np.arange(1, total + 1),
        "directed": False, "target_count": total, "deleted_ids": np.arange(1, total + 1),
        "states": _struct_rows(states), "sampled": _struct_rows(samples), "status": "ok",
        "fraction_status": "ok" if total else "undefined",
    }
    path = tmp_path / "grid.mat"
    savemat(path, {"attack": attack}, long_field_names=True)
    record = _mat_struct(loadmat(path, struct_as_record=False, mat_dtype=True)["attack"], "attack")
    graph = {"N": node_count, "M": total, "directed": False, "edge_list": edges}
    definitions = [{"metric_id": "test_edge_metric", "metric_version": "1.0.0", "parameters": {}}]
    return record, graph, definitions


@pytest.mark.parametrize("rounding", ["floor", "ceil", "nearest"])
def test_grid_source_preserves_request_mapping_and_typed_metrics(tmp_path, rounding):
    attack, graph, definitions = _grid_fixture(tmp_path, rounding=rounding)
    observations = {}
    native = _read_attack(attack, graph, "c" * 64, definitions, tmp_path, observations=observations)
    assert len(observations["sampled"]) == 7
    assert len(observations["states"]) == len(native["states"])
    assert observations["sampled"][1].positions["requested_fraction"] == .1
    assert observations["states"][-1].metrics[0].values.shape == (0,)
    assert observations["states"][-1].metadata["remaining_node_ids"] == list(range(1, 9))
    assert observations["sampled"][0].metadata["referenced_state"]["remaining_edge_ids"] == list(range(1, 8))


def test_grid_projection_distinguishes_removed_invalid_and_unobserved(tmp_path):
    attack, graph, definitions = _grid_fixture(tmp_path)
    observations = {}
    _read_attack(attack, graph, "c" * 64, definitions, tmp_path, observations=observations)
    run = MetricRun("a" * 64, "b" * 64, "d" * 64, "c" * 64, "e" * 64, "complete", [], observations=observations)
    selector = MetricSelector("test_edge_metric", "1.0.0", {}, "edge", "d" * 64, "c" * 64,
                              observation_source="sampled", alignment="by_id")
    projected = project_observations(run, selector, missing="mask")
    assert projected.values.shape == (7, 7)
    assert projected.present_mask[0, 1] and not projected.valid_mask[0, 1]
    assert not projected.present_mask[2, 0]  # ID1 was deleted at the .2 request.
    assert not projected.present_mask[5].any()  # Request .5 lies in a batch gap.
    assert np.isnan(projected.axis_positions["actual_removed_fraction"][5])
    assert projected.axis_positions["state_index"].tolist() == [1, 1, 2, 3, 3, 0, 4]
    assert projected.metadata["observation_projection"]["observations"][5]["status"] == "not_computed"
    projected.validate()


def test_empty_target_keeps_nan_fraction_and_repeated_initial_state(tmp_path):
    attack, graph, definitions = _grid_fixture(tmp_path, total=0)
    observations = {}
    _read_attack(attack, graph, "c" * 64, definitions, tmp_path, observations=observations)
    assert len(observations["states"]) == 1
    for observation in observations["sampled"]:
        assert observation.positions["state_index"] == 1
        assert np.isnan(observation.positions["actual_removed_fraction"])
        assert observation.positions["fraction_valid"] is False


@pytest.mark.parametrize("field", ["requested_fraction", "requested_removed_count", "increment", "state_index",
                                   "round_index", "actual_removed_count", "actual_removed_fraction", "fraction_valid"])
def test_grid_rejects_tampered_schedule(tmp_path, field):
    attack, graph, definitions = _grid_fixture(tmp_path)
    schedule = attack["schedule"].reshape(-1)[0]
    value = np.array(getattr(schedule, field), copy=True)
    value[0, 0] = not value[0, 0] if field == "fraction_valid" else value[0, 0] + 1
    setattr(schedule, field, value)
    with pytest.raises(PipelineError, match="Attack schedule"):
        _read_attack(attack, graph, "c" * 64, definitions, tmp_path)


def test_version_one_rejects_fraction_grid(tmp_path):
    attack, graph, definitions = _grid_fixture(tmp_path, version="1.0.0")
    with pytest.raises(PipelineError, match="require protocol version 1.1.0"):
        _read_attack(attack, graph, "c" * 64, definitions, tmp_path)


@pytest.mark.parametrize("field", ["actual_removed_count", "actual_removed_fraction", "fraction_valid", "exact_count_match"])
def test_unobserved_sample_rejects_fabricated_actual_position(tmp_path, field):
    attack, graph, definitions = _grid_fixture(tmp_path)
    sample = attack["sampled"].reshape(-1)[5]
    setattr(sample, field, np.array([[1]]))
    with pytest.raises(PipelineError, match="Unobserved sample"):
        _read_attack(attack, graph, "c" * 64, definitions, tmp_path)


def test_version_one_states_are_typed_without_changing_values(tmp_path):
    attack = _attack_record(tmp_path, metric_observation=True)
    original = deepcopy(attack)
    observations = {}
    _read_attack(attack, {"N": 2, "M": 1, "directed": False}, "c" * 64,
                 [{"metric_id": "test_metric", "metric_version": "1.0.0", "parameters": {}}], tmp_path,
                 observations=observations)
    assert observations["states"][1].metrics[0].values.item() == 2
    assert observations["sampled"][1].positions["actual_removed_count"] == 0
    assert np.array_equal(attack["deleted_ids"], original["deleted_ids"])


@pytest.mark.parametrize("field,value", [("status", "failed"), ("fraction_status", "undefined")])
def test_attack_rejects_inconsistent_summary_status(tmp_path, field, value):
    attack, graph, definitions = _grid_fixture(tmp_path)
    attack[field] = np.array([value])
    with pytest.raises(PipelineError, match="Attack (status|fraction_status) disagrees"):
        _read_attack(attack, graph, "c" * 64, definitions, tmp_path)


@pytest.mark.parametrize("bad_grid", [None, [0.5, 1.0]])
def test_version_one_one_non_grid_requires_empty_grid_field(tmp_path, bad_grid):
    attack = _attack_record(tmp_path)
    attack["schema_version"] = np.array(["attack-1.1.0"])
    protocol = attack["protocol"].reshape(-1)[0]
    protocol.version = np.array(["1.1.0"])
    attack["schedule"] = SimpleNamespace(_fieldnames=[])
    if bad_grid is not None:
        protocol._fieldnames.append("attack_fractions")
        protocol.attack_fractions = np.asarray(bad_grid)
    with pytest.raises(PipelineError, match="attack_fractions"):
        _read_attack(attack, {"N": 2, "M": 1, "directed": False}, "c" * 64, [], tmp_path)
    if "attack_fractions" not in protocol._fieldnames:
        protocol._fieldnames.append("attack_fractions")
    protocol.attack_fractions = np.empty((0, 0))
    _read_attack(attack, {"N": 2, "M": 1, "directed": False}, "c" * 64, [], tmp_path)


def test_nearest_round_matches_matlab_at_adjacent_half_values():
    # Independently measured in R2024b; adding 0.5 rounds the first value too early.
    x = np.array([np.nextafter(.5, 0), .5, np.nextafter(.5, 1), np.nextafter(1.5, 0), 1.5, np.nextafter(1.5, 2)])
    assert _round_attack_counts(x / 2, 2, "nearest").tolist() == [0, 1, 1, 1, 2, 2]
    protocol = {"version": "1.0.0", "stop_fraction": x[0], "batch_size": 1,
                "rounding": "nearest", "sample_policy": "exact", "deletion_mode": "single"}
    assert _attack_boundaries({"schema_version": np.array(["attack-1.0.0"]),
                               "full_single_object_trajectory": np.array([[False]])}, protocol, 1) == [0]


def test_sample_nearest_round_keeps_value_immediately_below_half(tmp_path):
    attack = _attack_record(tmp_path)
    protocol = attack["protocol"].reshape(-1)[0]
    protocol.rounding = np.array(["nearest"])
    protocol.sample_fractions = np.array([0., np.nextafter(.5, 0)])
    attack["sampled"].reshape(-1)[1].requested_fraction = np.array([[np.nextafter(.5, 0)]])
    observations = {}
    _read_attack(attack, {"N": 2, "M": 1, "directed": False}, "c" * 64, [], tmp_path, observations=observations)
    assert observations["sampled"][1].positions["requested_removed_count"] == 0
