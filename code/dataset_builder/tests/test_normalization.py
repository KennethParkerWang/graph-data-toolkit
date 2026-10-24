import numpy as np
import pytest

from dataset_builder.models import GraphRecord, MetricArray, PipelineError, TrainingSample
from dataset_builder.normalization import FeatureNormalizer


def sample(name="a", values=(1., 3., np.nan), mask=(True, True, False), split="train"):
    graph = GraphRecord(name, name, name, 3, False, np.empty((0, 2), dtype=np.uint32))
    feature = MetricArray("degree", "v1", {}, "node", np.array(values), ("node",), np.array(mask), "partial")
    target = MetricArray("label", "v1", {}, "graph", np.array(9.), (), np.array(True), "ok")
    return TrainingSample(name, graph, {"degree": feature}, {"target": target}, split, {"selection_id": "selection"})


def test_streaming_masked_train_stats_roundtrip_and_unchanged_targets():
    first, second = sample(), sample("b", (5., 7., 999.), (True, True, False))
    normalizer = FeatureNormalizer().fit(iter([first, second]))
    stats = normalizer.to_dict()["features"]["degree"]
    assert stats["count"] == 4 and stats["mean"] == 4 and stats["variance"] == 5
    restored = FeatureNormalizer.from_dict(normalizer.to_dict())
    result = restored.transform(sample("held_out", (100., 3., 999.), (True, True, False), "test"))
    np.testing.assert_allclose(result.features["degree"].values[:2], [(100 - 4) / np.sqrt(5), -1 / np.sqrt(5)])
    assert result.features["degree"].values[2] == 999
    assert result.targets["target"].values == 9
    assert result.targets["target"].metadata == {}
    assert normalizer.to_dict()["training_sample_ids"] == ["a", "b"]
    np.testing.assert_equal(first.features["degree"].values, [1, 3, np.nan])


def test_held_out_fit_rejected_and_unfitted_transform_rejected():
    with pytest.raises(PipelineError, match="train only"):
        FeatureNormalizer().fit([sample(split="val")])
    with pytest.raises(PipelineError, match="Fit or restore"):
        FeatureNormalizer().transform(sample())


def test_zero_variance_and_all_invalid_and_state_integrity():
    normalizer = FeatureNormalizer().fit([sample(values=(2., 2., 2.), mask=(True, True, True))])
    np.testing.assert_equal(normalizer.transform(sample()).features["degree"].values, [-1, 1, np.nan])
    assert normalizer.to_dict()["features"]["degree"]["scale"] == 1
    with pytest.raises(PipelineError, match="no valid training"):
        FeatureNormalizer().fit([sample(mask=(False, False, False))])
    state = normalizer.to_dict()
    state["features"]["degree"]["mean"] = 123
    with pytest.raises(PipelineError, match="modified normalizer"):
        FeatureNormalizer.from_dict(state)


def test_definition_conflict_and_duplicate_sample_are_errors():
    original = sample()
    another = sample("b")
    another.features["degree"].metric_version = "v2"
    with pytest.raises(PipelineError, match="definition conflict"):
        FeatureNormalizer().fit([original, another])
    with pytest.raises(PipelineError, match="Duplicate sample"):
        FeatureNormalizer().fit([original, original])


def test_valid_infinity_requires_explicit_transform():
    original = sample(values=(np.inf, 3, 4), mask=(True, True, True))
    original.features["degree"].metadata["allows_infinity"] = True
    with pytest.raises(PipelineError, match="valid nonfinite"):
        FeatureNormalizer().fit([original])
    assert original.features["degree"].valid_mask.all()


def test_transform_rejects_conflicting_computation_method():
    original = sample()
    original.features["degree"].metadata["method"] = "exact"
    normalizer = FeatureNormalizer().fit([original])
    different = sample("heldout", split="test")
    different.features["degree"].metadata["method"] = "numerical"
    with pytest.raises(PipelineError, match="definition conflict"):
        normalizer.transform(different)
