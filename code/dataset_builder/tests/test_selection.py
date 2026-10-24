from copy import deepcopy

import numpy as np
import pytest

from dataset_builder.config import SelectionConfig
from dataset_builder.models import GraphRecord, MetricArray, MetricRun, PipelineError
from dataset_builder.selection import select_samples


def graph():
    return GraphRecord("g", "t", "g", 3, False, np.array([[1, 2]], dtype=np.uint32))


def metric(values=(1., 0., np.nan), mask=(True, True, False), positions=(0., .5, 1.)):
    return MetricArray("robustness", "v1", {"method": "exact"}, "trajectory", np.array(values),
                       ("fraction",), np.array(mask), "partial", reason="Last value undefined",
                       axis_positions={"fraction": np.array(positions)}, metadata={"units": "ratio"})


def run(run_id="r1", value=None):
    return MetricRun("g", "t", "set", "attack", run_id, "partial", [value or metric()], source={"file_sha256": run_id})


def config(mode="keep", missing="error", run_ids="all"):
    return SelectionConfig.from_dict({"feature_keys": {}, "target_keys": {"curve": {
        "metric_id": "robustness", "metric_version": "v1", "parameters": {"method": "exact"},
        "scope": "trajectory", "metric_set_id": "set", "protocol_id": "attack"}},
        "repeat_mode": mode, "missing": missing, "run_ids": run_ids})


def test_exact_selection_preserves_zero_status_and_axes():
    selected = select_samples(graph(), [run()], config(), "train")[0]
    result = selected.targets["curve"]
    np.testing.assert_equal(result.values, [1, 0, np.nan])
    np.testing.assert_equal(result.valid_mask, [True, True, False])
    np.testing.assert_equal(result.axis_positions["fraction"], [0, .5, 1])
    assert result.status == "partial" and not selected.features
    assert selected.provenance["metric_sources"][0]["run_id"] == "r1"


def test_version_parameters_topology_and_duplicate_conflicts():
    wrong = run()
    wrong.metrics[0].metric_version = "v2"
    with pytest.raises(PipelineError, match="version/parameters"):
        select_samples(graph(), [wrong], config(missing="mask"), "train")
    wrong = run()
    wrong.topology_hash = "different"
    with pytest.raises(PipelineError, match="topology_hash"):
        select_samples(graph(), [wrong], config(), "train")
    with pytest.raises(PipelineError, match="Duplicate run"):
        select_samples(graph(), [run(), run()], config(), "train")


def test_repeat_mean_uses_masks_and_retains_counts_variance_sources():
    first = run("r1")
    second = run("r2", metric((3., np.nan, 9.), (True, False, True)))
    second.metrics[0].status = "partial"
    selected = select_samples(graph(), [first, second], config("mean"), "val")[0].targets["curve"]
    np.testing.assert_equal(selected.values, [2, 0, 9])
    summary = selected.metadata["repeat_summary"]
    assert summary["count"] == [2, 1, 1]
    assert summary["variance"] == [1, 0, 0]
    assert [item["run_id"] for item in summary["runs"]] == ["r1", "r2"]
    np.testing.assert_equal(first.metrics[0].values, [1, 0, np.nan])


@pytest.mark.parametrize("change", ["positions", "node_ids", "metadata", "length"])
def test_repeat_mean_rejects_semantically_different_arrays(change):
    second = run("r2")
    if change == "positions":
        second.metrics[0].axis_positions["fraction"] = np.array([0, .25, 1])
    elif change == "node_ids":
        second.metrics[0].node_ids = np.array([3, 2, 1])
    elif change == "metadata":
        second.metrics[0].metadata["units"] = "different"
    else:
        second.metrics[0] = metric((1, 2), (True, True), (0, 1))
    with pytest.raises(PipelineError, match="Cannot average"):
        select_samples(graph(), [run(), second], config("mean"), "train")


def test_missing_run_explicit_error_or_mask_and_mean_count():
    with pytest.raises(PipelineError, match="requested run r2"):
        select_samples(graph(), [run()], config("mean", run_ids=["r1", "r2"]), "train")
    selected = select_samples(graph(), [run()], config("mean", "mask", ["r1", "r2"]), "train")[0]
    assert selected.targets["curve"].metadata["repeat_summary"]["count"] == [1, 1, 0]
    assert selected.targets["curve"].metadata["repeat_summary"]["variance"] == [0, 0, None]
    assert selected.targets["curve"].metadata["repeat_summary"]["runs"][1]["status"] == "not_computed"
    samples = select_samples(graph(), [run()], config("keep", "mask", ["r1", "r2"]), "train")
    assert len(samples) == 2
    assert not samples[1].targets["curve"].valid_mask.any()
    np.testing.assert_equal(samples[1].targets["curve"].axis_positions["fraction"], [0, .5, 1])


def test_static_features_broadcast_without_becoming_targets():
    cfg = config().to_dict()
    cfg["feature_keys"]["size"] = {"metric_id": "size", "metric_version": "v1", "parameters": {},
                                    "scope": "graph", "metric_set_id": "static", "protocol_id": ""}
    size = MetricArray("size", "v1", {}, "graph", np.array(3), (), np.array(True), "ok")
    static = MetricRun("g", "t", "static", "", "static_run", "ok", [size])
    samples = select_samples(graph(), [static, run("r1"), run("r2")], cfg, "train")
    assert len(samples) == 2
    assert all(sample.features["size"].values == 3 for sample in samples)
    assert all(set(sample.targets) == {"curve"} for sample in samples)


def test_missing_metric_all_runs_records_unknown_shape_without_invented_axes():
    absent = run()
    absent.metrics = []
    result = select_samples(graph(), [absent], config(missing="mask"), "test")[0].targets["curve"]
    assert result.status == "not_computed" and result.values.size == 0
    assert result.metadata["shape_unknown"]
    assert result.axis_names == ()
    result.validate()


def test_explicit_config_rejects_multiple_attack_protocols_or_implicit_selection():
    cfg = config().to_dict()
    cfg["feature_keys"]["other"] = deepcopy(cfg["target_keys"]["curve"])
    cfg["feature_keys"]["other"]["protocol_id"] = "another_attack"
    with pytest.raises(PipelineError, match="one attack protocol"):
        SelectionConfig.from_dict(cfg)
    del cfg["feature_keys"]["other"]
    del cfg["run_ids"]
    with pytest.raises(PipelineError, match="requires exactly"):
        SelectionConfig.from_dict(cfg)


def test_complete_matrix_with_infinite_distance_is_kept_but_not_meaned():
    cfg = config().to_dict()
    cfg["target_keys"]["curve"]["scope"] = "matrix"
    source = MetricArray("robustness", "v1", {"method": "exact"}, "matrix",
                         np.array([[0., np.inf], [np.inf, 0.]]), ("source_node", "target_node"),
                         np.ones((2, 2), dtype=bool), "ok",
                         axis_ids={"source_node": np.array([1, 3]), "target_node": np.array([1, 3])},
                         metadata={"allows_infinity": True})
    source_run = run(value=source)
    source_run.status = "complete"
    kept = select_samples(graph(), [source_run], cfg, "train")[0].targets["curve"]
    assert np.isinf(kept.values[0, 1]) and kept.valid_mask.all()
    np.testing.assert_equal(kept.axis_ids["source_node"], [1, 3])
    cfg["repeat_mode"] = "mean"
    with pytest.raises(PipelineError, match="valid nonfinite"):
        select_samples(graph(), [source_run], cfg, "train")


def test_repeat_mean_preserves_per_run_details_and_runtime_without_conflict():
    first, second = run(), run("r2")
    first.metrics[0].metadata.update(elapsed_seconds=1., details={"witness": [1, 2]})
    second.metrics[0].metadata.update(elapsed_seconds=2., details={"witness": [2, 3]})
    result = select_samples(graph(), [first, second], config("mean"), "train")[0].targets["curve"]
    summaries = result.metadata["repeat_summary"]["runs"]
    assert summaries[1]["metric_metadata"]["elapsed_seconds"] == 2
    assert summaries[0]["valid_mask"] == [True, True, False]


def test_explicit_missing_static_repeat_is_not_dropped():
    cfg = config(missing="mask", run_ids=["r1", "r2"]).to_dict()
    cfg["target_keys"]["curve"]["protocol_id"] = ""
    existing = run()
    existing.protocol_id = ""
    samples = select_samples(graph(), [existing], cfg, "train")
    assert len(samples) == 2
    assert samples[1].targets["curve"].status == "not_computed"
    assert not samples[1].targets["curve"].valid_mask.any()


def two_static_sets():
    cfg = config().to_dict()
    cfg["target_keys"]["curve"]["protocol_id"] = ""
    cfg["feature_keys"]["feature"] = deepcopy(cfg["target_keys"]["curve"])
    cfg["feature_keys"]["feature"]["metric_set_id"] = "independent_set"
    left, right = run("left_run"), run("right_run")
    left.protocol_id = right.protocol_id = ""
    right.metric_set_id = "independent_set"
    return cfg, left, right


def test_unique_static_sets_compose_once_despite_distinct_run_hashes():
    cfg, left, right = two_static_sets()
    samples = select_samples(graph(), [left, right], cfg, "train")
    assert len(samples) == 1
    assert set(samples[0].features) == {"feature"}
    assert set(samples[0].targets) == {"curve"}
    assert {source["run_id"] for source in samples[0].provenance["metric_sources"]} == {"left_run", "right_run"}


@pytest.mark.parametrize("mode", ["keep", "mean"])
def test_independent_repeated_streams_require_explicit_groups_even_when_masked(mode):
    cfg, left, right = two_static_sets()
    cfg.update(missing="mask", repeat_mode=mode)
    second = deepcopy(right)
    second.run_id = "another_independent_run"
    with pytest.raises(PipelineError, match="explicit run_groups"):
        select_samples(graph(), [left, right, second], cfg, "train")


def test_explicit_run_groups_bind_metric_set_specific_runs_and_filter_unselected():
    cfg, left, right = two_static_sets()
    second_left, second_right = deepcopy(left), deepcopy(right)
    second_left.run_id, second_right.run_id = "left_two", "right_two"
    second_right.metrics[0].values[0] = 8
    cfg["run_groups"] = {"g": {
        "pair_one": {"set": "left_run", "independent_set": "right_two"},
        "pair_two": {"set": "left_two", "independent_set": "right_run"}}}
    extra = deepcopy(left)
    extra.run_id = "unselected"
    extra.metrics[0].metric_version = "irrelevant_version"
    samples = select_samples(graph(), [left, right, second_left, second_right, extra], cfg, "train")
    assert len(samples) == 2
    assert samples[0].provenance["repeat_id"] == "pair_one"
    assert samples[0].features["feature"].values[0] == 8
    assert samples[1].features["feature"].values[0] == 1
    cfg["repeat_mode"] = "mean"
    averaged = select_samples(graph(), [left, right, second_left, second_right], cfg, "train")
    assert len(averaged) == 1 and averaged[0].features["feature"].values[0] == 4.5


def test_multiple_attack_metric_sets_fail_at_config_without_bindings():
    cfg, _, _ = two_static_sets()
    for selectors in (cfg["feature_keys"], cfg["target_keys"]):
        for selector in selectors.values():
            selector["protocol_id"] = "same_attack"
    cfg["missing"] = "mask"
    with pytest.raises(PipelineError, match="Independent attack metric sets"):
        SelectionConfig.from_dict(cfg)


def test_explicit_groups_missing_run_retains_requested_id_and_status():
    cfg, left, right = two_static_sets()
    cfg.update(missing="mask", run_groups={"g": {"pair": {"set": "missing_run", "independent_set": "right_run"}}})
    result = select_samples(graph(), [left, right], cfg, "train")[0]
    assert result.targets["curve"].status == "not_computed"
    missing_source = next(source for source in result.provenance["metric_sources"] if source["key"] == "curve")
    assert missing_source["run_id"] == "missing_run" and missing_source["run_status"] == "not_computed"


def test_group_bindings_must_cover_graph_and_all_metric_sets_without_duplicates():
    cfg, left, right = two_static_sets()
    cfg["run_groups"] = {"another_graph": {"pair": {"set": "left_run", "independent_set": "right_run"}}}
    with pytest.raises(PipelineError, match="no explicit run_groups"):
        select_samples(graph(), [left, right], cfg, "train")
    cfg["run_groups"] = {"g": {"pair": {"set": "left_run"}}}
    with pytest.raises(PipelineError, match="bind every selected"):
        SelectionConfig.from_dict(cfg)
    cfg["run_groups"] = {"g": {"pair": {"set": "left_run", "independent_set": "right_run"},
                                   "duplicate": {"set": "left_run", "independent_set": "right_run"}}}
    with pytest.raises(PipelineError, match="Duplicate run group"):
        SelectionConfig.from_dict(cfg)


def test_mean_successful_empty_results_remain_ok():
    empty = metric((), (), ())
    empty.valid_mask = np.empty((0,), dtype=bool)
    empty.status = "ok"
    result = select_samples(graph(), [run(value=empty)], config("mean"), "train")[0].targets["curve"]
    assert result.values.size == 0 and result.status == "ok"


@pytest.mark.parametrize("status", ["failed", "not_applicable", "undefined", "not_computed"])
def test_mean_uniform_unavailable_results_keep_distinct_status(status):
    unavailable = metric((np.nan, np.nan, np.nan), (False, False, False))
    unavailable.status = status
    result = select_samples(graph(), [run(value=unavailable)], config("mean"), "train")[0].targets["curve"]
    assert result.status == status and not result.valid_mask.any()


def test_run_provenance_retains_seeds_definitions_attack_deletions_once():
    cfg = config().to_dict()
    cfg["feature_keys"]["same_result"] = deepcopy(cfg["target_keys"]["curve"])
    source = run()
    source.metadata = {"seeds": {"attack_seed": 7, "repeat_index": 2},
                       "run_identity_json": '{"repeat_index":2}', "metric_version": "1.0.0",
                       "selections": [{"metric_id": "robustness"}],
                       "attack": {"protocol_id": "attack", "target": "edge", "deleted_ids": np.array([2, 1]),
                                  "original_count": 2, "fraction": np.nan,
                                  "states": [{"results": [1, 2, 3]}], "sampled": [{"results": [4, 5]}]}}
    selected = select_samples(graph(), [source], cfg, "train")[0]
    compact = selected.provenance["source_runs"]
    assert len(compact) == 1
    metadata = compact[0]["metadata"]
    assert metadata["seeds"] == {"attack_seed": 7, "repeat_index": 2}
    assert metadata["run_identity_json"] == '{"repeat_index":2}'
    np.testing.assert_equal(metadata["attack"]["deleted_ids"], [2, 1])
    assert np.isnan(metadata["attack"]["fraction"])
    assert "states" not in metadata["attack"] and "sampled" not in metadata["attack"]
    assert "states" in source.metadata["attack"]


def test_mean_definition_metadata_supports_legitimate_nonfinite_provenance():
    first, second = run(), run("r2")
    for source in (first, second):
        source.metrics[0].metadata["fraction_denominator"] = np.nan
        source.metrics[0].metadata["source_coordinates"] = np.array([0., np.nan])
    selected = select_samples(graph(), [first, second], config("mean"), "train")[0]
    np.testing.assert_equal(selected.targets["curve"].values, [1, 0, np.nan])
    assert len(selected.provenance["source_runs"]) == 2


def test_hits_text_coordinate_repeat_mean_preserves_labels_and_detects_reordering():
    cfg = config("mean").to_dict()
    cfg["target_keys"]["curve"].update(metric_id="hits", scope="matrix", parameters={})
    first = MetricArray("hits", "v1", {}, "matrix", np.array([[.2, .3], [.8, .7]]),
                        ("node", "score"), np.ones((2, 2), dtype=bool), "ok",
                        axis_ids={"node": np.array([1, 2]), "score": np.array(["hub", "authority"])})
    second = deepcopy(first)
    second.values = np.array([[.4, .5], [.6, .5]])
    selected = select_samples(graph(), [run("r1", first), run("r2", second)], cfg, "train")[0]
    np.testing.assert_equal(selected.targets["curve"].axis_ids["score"], ["hub", "authority"])
    np.testing.assert_allclose(selected.targets["curve"].values, [[.3, .4], [.7, .6]])
    second.axis_ids["score"] = np.array(["authority", "hub"])
    with pytest.raises(PipelineError, match="actual axes/IDs"):
        select_samples(graph(), [run("r1", first), run("r2", second)], cfg, "train")


@pytest.mark.parametrize("source,singleton", [("states", False), ("states", True), ("sampled", False), ("sampled", True)])
def test_state_only_observations_require_projection_even_under_missing_mask(source, singleton):
    observed = run()
    observed.metrics = []
    record = {"metric_id": "robustness", "metric_version": "v1", "parameters": {"method": "exact"},
              "scope": "graph", "values": 3., "valid_mask": True, "status": "ok"}
    observation = {"removed_count": 0, "metrics": record if singleton else [record]}
    observed.metadata = {"attack": {source: observation if singleton else [observation]}}
    with pytest.raises(PipelineError, match="Explicit observation projection required; this adapter only selects producer results/summaries"):
        select_samples(graph(), [observed], config(missing="mask"), "train")


def test_observation_source_and_alignment_are_explicit_and_bound_to_config_identity():
    legacy = config().to_dict()
    omitted = deepcopy(legacy)
    del omitted["target_keys"]["curve"]["observation_source"]
    del omitted["target_keys"]["curve"]["alignment"]
    assert SelectionConfig.from_dict(omitted).config_id == SelectionConfig.from_dict(legacy).config_id
    states = deepcopy(legacy)
    states["target_keys"]["curve"].update(observation_source="states", alignment="by_id")
    sampled = deepcopy(states)
    sampled["target_keys"]["curve"]["observation_source"] = "sampled"
    assert len({SelectionConfig.from_dict(value).config_id for value in (legacy, states, sampled)}) == 3
    del states["target_keys"]["curve"]["alignment"]
    with pytest.raises(PipelineError, match="explicit alignment"):
        SelectionConfig.from_dict(states)
    legacy["target_keys"]["curve"]["alignment"] = "by_id"
    with pytest.raises(PipelineError, match="only to explicit"):
        SelectionConfig.from_dict(legacy)
    sampled["target_keys"]["curve"]["protocol_id"] = ""
    with pytest.raises(PipelineError, match="attack protocol_id"):
        SelectionConfig.from_dict(sampled)
