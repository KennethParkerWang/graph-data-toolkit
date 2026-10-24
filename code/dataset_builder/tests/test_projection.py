from copy import deepcopy

import numpy as np
import pytest

from dataset_builder.config import MetricSelector, SelectionConfig
from dataset_builder.models import GraphRecord, MetricArray, MetricRun, ObservationRecord, PipelineError
from dataset_builder.projection import project_observations
from dataset_builder.selection import select_samples


def selector(scope="graph", source="states"):
    return MetricSelector("observed_metric", "v1", {}, scope, "set", "attack", source, "by_id")


def metric(values, *, axes=(), ids=None, scope="graph", valid=None, status="ok", **kwargs):
    values = np.asarray(values)
    return MetricArray("observed_metric", "v1", {}, scope, values, axes,
                       np.ones(values.shape, dtype=bool) if valid is None else np.asarray(valid, dtype=bool),
                       status, axis_ids={} if ids is None else {key: np.asarray(value) for key, value in ids.items()},
                       metadata={"units": "count", "method": "exact"}, **kwargs)


def state(index, value, *, count=None, fraction=None, status="complete", reason=""):
    count = index - 1 if count is None else count
    return ObservationRecord(index, [] if value is None else [value],
                             {"removed_count": count, "removed_fraction": count / 3 if fraction is None else fraction,
                              "fraction_valid": not (fraction is not None and np.isnan(fraction)),
                              "round_index": index - 1, "state_index": index},
                             status, reason, {"remaining_node_ids": np.array([2, 3])})


def sampled(index, value, requested, actual, *, state_index=1, status="ok"):
    return ObservationRecord(index, [] if value is None else [value],
                             {"requested_fraction": requested, "requested_removed_count": int(requested * 3),
                              "actual_removed_count": actual, "actual_removed_fraction": actual / 3,
                              "fraction_valid": True, "state_index": state_index,
                              "exact_count_match": actual == int(requested * 3)}, status)


def run(observations, *, source="states", run_id="r1"):
    return MetricRun("g", "t", "set", "attack", run_id, "complete", [],
                     source={"file_sha256": run_id}, observations={source: observations})


def config(scope="graph", source="states", *, missing="mask", mode="keep", run_ids="all"):
    return SelectionConfig({}, {"observed": selector(scope, source)}, mode, missing, run_ids)


def graph():
    return GraphRecord("g", "t", "g", 5, False, np.array([[1, 2], [1, 3], [2, 4]], dtype=np.uint32))


def project(records, *, scope="graph", source="states", missing="error"):
    return project_observations(run(records, source=source), selector(scope, source), missing=missing)


def test_scalar_observations_preserve_integer_values_and_all_temporal_fields():
    records = [state(1, metric(np.uint32(3))), state(2, metric(np.uint32(0)), fraction=np.nan)]
    result = project(records)
    assert result.scope == "graph" and result.axis_names == ("observation",)
    assert result.values.dtype == np.uint32
    np.testing.assert_equal(result.values, [3, 0])
    np.testing.assert_equal(result.axis_ids["observation"], [1, 2])
    np.testing.assert_equal(result.present_mask, [True, True])
    np.testing.assert_equal(result.valid_mask, [True, True])
    np.testing.assert_equal(result.axis_positions["fraction_valid"], [True, False])
    assert np.isnan(result.axis_positions["removed_fraction"][1])
    assert set(result.metadata["axis_position_axes"].values()) == {"observation"}
    assert result.metadata["observation_projection"]["observations"][0]["metadata"]["remaining_node_ids"].tolist() == [2, 3]


def test_repeated_requested_samples_remain_separate_and_keep_actual_positions():
    records = [sampled(1, metric(3.), .11, 0), sampled(2, metric(3.), .11, 0),
               sampled(3, metric(3.), .19, 0)]
    result = project(records, source="sampled")
    assert result.values.shape == (3,)
    np.testing.assert_equal(result.axis_positions["requested_fraction"], [.11, .11, .19])
    np.testing.assert_equal(result.axis_positions["actual_removed_count"], [0, 0, 0])
    np.testing.assert_equal(result.axis_ids["observation"], [1, 2, 3])


def test_logical_dtype_and_present_false_value_are_preserved():
    result = project([state(1, metric(True)), state(2, metric(False)), state(3, None)], missing="mask")
    assert result.values.dtype == np.bool_
    np.testing.assert_equal(result.values, [True, False, False])
    np.testing.assert_equal(result.present_mask, [True, True, False])
    np.testing.assert_equal(result.valid_mask, [True, True, False])


def test_shrinking_node_union_is_by_original_id_and_distinguishes_invalid_from_absent():
    first = metric(np.array([20, 10, 30], dtype=np.int16), axes=("node",), ids={"node": [2, 1, 3]},
                   scope="node", node_ids=np.array([2, 1, 3]))
    second = metric(np.array([0, -7], dtype=np.int16), axes=("node",), ids={"node": [3, 2]},
                    scope="node", node_ids=np.array([3, 2]), valid=[True, False], status="partial",
                    reason="node 2 measurement undefined")
    result = project([state(1, first), state(2, second)], scope="node")
    assert result.axis_names == ("observation", "node") and result.values.dtype == np.int16
    np.testing.assert_equal(result.node_ids, [2, 1, 3])
    np.testing.assert_equal(result.values, [[20, 10, 30], [-7, 0, 0]])
    np.testing.assert_equal(result.present_mask, [[True, True, True], [True, False, True]])
    np.testing.assert_equal(result.valid_mask, [[True, True, True], [False, False, True]])
    rows = result.metadata["observation_projection"]["observations"]
    np.testing.assert_equal(rows[1]["metric"]["axis_ids"]["node"], [3, 2])
    assert rows[1]["metric"]["reason"] == "node 2 measurement undefined"
    np.testing.assert_equal(second.values, [0, -7])


def test_shrinking_edge_ids_do_not_become_residual_row_numbers():
    records = [state(1, metric([8., 3.], axes=("edge",), ids={"edge": [8, 3]}, scope="edge", edge_ids=np.array([8, 3]))),
               state(2, metric([7.], axes=("edge",), ids={"edge": [3]}, scope="edge", edge_ids=np.array([3])))]
    result = project(records, scope="edge")
    np.testing.assert_equal(result.edge_ids, [8, 3])
    np.testing.assert_equal(result.values, [[8, 3], [np.nan, 7]])
    np.testing.assert_equal(result.present_mask, [[True, True], [False, True]])


def test_sparse_original_matrix_coordinates_union_only_observed_ids():
    first = metric([[11., 12.], [21., 22.]], axes=("source_node", "target_node"),
                   ids={"source_node": [1000000000, 2], "target_node": [2, 1000000000]}, scope="matrix")
    second = metric([[99.]], axes=("source_node", "target_node"),
                    ids={"source_node": [2], "target_node": [1000000000]}, scope="matrix")
    result = project([state(1, first), state(2, second)], scope="matrix")
    assert result.values.shape == (2, 2, 2)
    np.testing.assert_equal(result.values[0], first.values)
    assert result.values[1, 1, 1] == 99
    assert result.present_mask[1].sum() == 1


def test_string_semantic_coordinates_are_mapped_exactly_without_interpolation():
    first = metric([[1., 2.], [3., 4.]], axes=("node", "score"),
                   ids={"node": [1, 2], "score": ["hub", "authority"]}, scope="matrix")
    second = metric([[9., 8.]], axes=("node", "score"),
                    ids={"node": [2], "score": ["authority", "hub"]}, scope="matrix")
    result = project([state(1, first), state(2, second)], scope="matrix")
    np.testing.assert_equal(result.axis_ids["score"], ["hub", "authority"])
    np.testing.assert_equal(result.values[1, 1], [8, 9])
    assert not result.present_mask[1, 0].any()


def test_distribution_coordinates_keep_exact_bin_values_and_gaps():
    first = metric([2., 8.], axes=("bin",), ids={"bin": [0.1, 0.9]}, scope="distribution")
    second = metric([4., 6.], axes=("bin",), ids={"bin": [0.9, 1.7]}, scope="distribution")
    result = project([state(1, first), state(2, second)], scope="distribution")
    np.testing.assert_equal(result.axis_ids["bin"], [0.1, 0.9, 1.7])
    np.testing.assert_equal(result.values, [[2, 8, np.nan], [np.nan, 4, 6]])


def test_partial_missing_metric_is_masked_but_a_present_undefined_value_remains_present():
    unavailable = metric(np.nan, valid=False, status="undefined", reason="empty normalization denominator")
    result = project([state(1, metric(0.)), state(2, None, status="not_computed"), state(3, unavailable)], missing="mask")
    np.testing.assert_equal(result.values, [0, np.nan, np.nan])
    np.testing.assert_equal(result.present_mask, [True, False, True])
    np.testing.assert_equal(result.valid_mask, [True, False, False])
    with pytest.raises(PipelineError, match="missing selected metric"):
        project([state(1, metric(0.)), state(2, None)], missing="error")


@pytest.mark.parametrize("source", ["states", "sampled"])
def test_empty_or_absent_observation_source_follows_missing_policy_without_scalar_invention(source):
    empty = run([], source=source)
    absent = deepcopy(empty)
    absent.observations = {}
    for raw, available in ((empty, True), (absent, False)):
        with pytest.raises(PipelineError, match="no .* observations"):
            project_observations(raw, selector(source=source), missing="error")
        result = project_observations(raw, selector(source=source), missing="mask")
        assert result.values.shape == (0,) and result.axis_names == ()
        assert result.metadata["shape_unknown"] and not result.present_mask.any()
        assert result.metadata["observation_projection"]["source_available"] is available
        result.validate()


def test_all_missing_rows_keep_positions_in_provenance_without_invented_shape():
    records = [sampled(1, None, .1, 0, state_index=0, status="not_computed"),
               sampled(2, None, .1, 0, state_index=0, status="not_computed")]
    result = project(records, source="sampled", missing="mask")
    assert result.values.size == 0 and result.axis_names == ()
    rows = result.metadata["observation_projection"]["observations"]
    assert len(rows) == 2 and rows[1]["positions"]["requested_fraction"] == .1


def test_present_unknown_unavailable_shape_is_not_a_missing_metric_error():
    value = metric([], valid=[], status="not_applicable", reason="no domain")
    value.metadata["shape_unknown"] = True
    result = project([state(1, value)], missing="error")
    assert result.status == "not_applicable" and result.metadata["shape_unknown"]
    assert result.metadata["observation_projection"]["observations"][0]["metric_present"]


def test_known_values_cannot_be_hidden_by_a_shape_unknown_annotation():
    value = metric(4.)
    value.metadata["shape_unknown"] = True
    with pytest.raises(PipelineError, match="shape_unknown must describe"):
        project([state(1, value)])


def test_successful_empty_edges_preserve_known_empty_axis():
    value = metric(np.array([], dtype=np.uint32), axes=("edge",), ids={"edge": np.array([], dtype=np.int64)},
                   scope="edge", edge_ids=np.array([], dtype=np.int64))
    result = project([state(1, value), state(2, deepcopy(value))], scope="edge")
    assert result.values.shape == (2, 0) and result.status == "ok"
    assert result.axis_names == ("observation", "edge") and not result.metadata.get("shape_unknown")


@pytest.mark.parametrize("field,value", [("metric_version", "v2"), ("parameters", {"new": 1}), ("scope", "node")])
def test_definition_conflicts_fail_even_after_an_absent_observation_under_mask(field, value):
    wrong = metric(3.)
    setattr(wrong, field, value)
    with pytest.raises(PipelineError, match="version/parameters/scope conflict"):
        project([state(1, None), state(2, wrong)], missing="mask")


@pytest.mark.parametrize("change,pattern", [
    ("duplicate_metric", "duplicate matching"), ("duplicate_index", "duplicate observation"),
    ("duplicate_axis", "duplicate coordinate"), ("dtype", "dtypes differ"),
    ("missing_coordinates", "explicit coordinate"), ("wrong_axes", "names/ranks differ")])
def test_structural_conflicts_fail_closed(change, pattern):
    value = metric(np.array([1, 2], dtype=np.int32), axes=("node",), ids={"node": [1, 2]}, scope="node")
    records = [state(1, value), state(2, deepcopy(value))]
    if change == "duplicate_metric":
        records[1].metrics.append(deepcopy(value))
    elif change == "duplicate_index":
        records[1].index = 1
    elif change == "duplicate_axis":
        records[1].metrics[0].axis_ids["node"] = np.array([1, 1])
    elif change == "dtype":
        records[1].metrics[0].values = np.array([1., 2.])
    elif change == "missing_coordinates":
        records[1].metrics[0].axis_ids = {}
    else:
        records[1].metrics[0].axis_names = ("different",)
        records[1].metrics[0].axis_ids = {"different": np.array([1, 2])}
    with pytest.raises(PipelineError, match=pattern):
        project(records, scope="node", missing="mask")


def test_projection_preserves_authorized_infinite_values_but_mean_requires_explicit_transform():
    finite, infinite = metric(2.), metric(np.inf)
    infinite.metadata.update(allows_infinity=True, infinity_definition={"definition": "unreachable distance"})
    raw = run([state(1, finite), state(2, infinite)])
    kept = select_samples(graph(), [raw], config(), "train")[0].targets["observed"]
    assert kept.values[1] == np.inf and kept.valid_mask.all() and kept.metadata["allows_infinity"]
    with pytest.raises(PipelineError, match="valid nonfinite"):
        select_samples(graph(), [raw], config(mode="mean"), "train")


def test_repeat_mean_retains_presence_counts_invalid_counts_and_per_run_observations():
    first = run([state(1, metric(2.)), state(2, None, status="not_computed"),
                 state(3, metric(np.nan, valid=False, status="undefined", reason="no denominator"))])
    second = run([state(1, metric(4.)), state(2, metric(0.)), state(3, metric(8.))], run_id="r2")
    result = select_samples(graph(), [first, second], config(mode="mean"), "train")[0].targets["observed"]
    np.testing.assert_equal(result.values, [3, 0, 8])
    np.testing.assert_equal(result.present_mask, [True, True, True])
    assert result.metadata["repeat_summary"]["present_count"] == [2, 1, 2]
    assert result.metadata["repeat_summary"]["count"] == [2, 1, 1]
    rows = result.metadata["repeat_summary"]["runs"][0]["metric_metadata"]["observation_projection"]["observations"]
    assert rows[2]["metric"]["reason"] == "no denominator"


@pytest.mark.parametrize("change", ["positions", "coordinates", "observation_index"])
def test_repeat_mean_rejects_positions_or_coordinate_mismatches(change):
    value = metric([1., 2.], axes=("node",), ids={"node": [1, 2]}, scope="node")
    first, second = run([state(1, value)]), run([state(1, deepcopy(value))], run_id="r2")
    if change == "positions":
        second.observations["states"][0].positions["removed_count"] = 1
    elif change == "coordinates":
        second.observations["states"][0].metrics[0].axis_ids["node"] = np.array([2, 1])
    else:
        second.observations["states"][0].index = 2
    with pytest.raises(PipelineError, match="actual axes/IDs/shapes differ"):
        select_samples(graph(), [first, second], config(scope="node", mode="mean"), "train")


def test_missing_whole_repeat_does_not_inherit_actual_positions_from_other_run():
    raw = run([state(1, metric(2.)), state(2, metric(1.))])
    samples = select_samples(graph(), [raw], config(run_ids=("r1", "r2")), "train")
    missing = samples[1].targets["observed"]
    assert missing.values.size == 0 and missing.metadata["shape_unknown"]
    assert missing.axis_positions == {} and missing.axis_ids == {}
    result = select_samples(graph(), [raw], config(mode="mean", run_ids=("r1", "r2")), "train")[0].targets["observed"]
    assert result.metadata["repeat_summary"]["present_count"] == [1, 1]


def test_explicit_source_does_not_fall_back_to_an_identical_static_result():
    raw = run([state(1, metric(7.))])
    raw.metrics = [metric(99.)]
    result = select_samples(graph(), [raw], config(), "train")[0].targets["observed"]
    np.testing.assert_equal(result.values, [7.])
    legacy = config().to_dict()
    legacy["target_keys"]["observed"].update(observation_source="results", alignment=None)
    result = select_samples(graph(), [raw], legacy, "train")[0].targets["observed"]
    assert result.values == 99. and result.axis_names == ()
