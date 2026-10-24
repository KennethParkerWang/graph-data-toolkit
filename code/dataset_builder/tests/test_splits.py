from copy import deepcopy

import pytest

from dataset_builder.models import PipelineError
from dataset_builder.splits import build_split_manifest, validate_split_manifest, write_split_manifest


def identity(name, origin=None, topology=None, size=4, model="er", **kwargs):
    return {"graph_id": name, "origin_graph_id": origin or name, "topology_hash": topology or name,
            "N": size, "model": model, **kwargs}


def random_config():
    return {"mode": "random", "fractions": {"train": .6, "val": .2, "test": .2}, "seed": 19, "conflict": "error"}


def test_transitive_origin_absent_parent_duplicate_topology_grouping():
    graphs = [identity("a", origin="absent"), identity("b", origin="absent", topology="shared"),
              identity("c", topology="shared"), identity("d", parent_graph_id="c"), identity("e")]
    manifest = build_split_manifest(graphs, random_config())
    assert len({manifest["assignments"][name] for name in "abcd"}) == 1
    assert sorted(len(group["graph_ids"]) for group in manifest["groups"]) == [1, 4]
    assert manifest == build_split_manifest(reversed(graphs), random_config())
    validate_split_manifest(manifest)


def test_cross_family_conflicts_are_rejected_excluded_or_explicitly_assigned():
    graphs = [identity("a", topology="same", model="er"), identity("b", topology="same", model="ba")]
    cfg = {"mode": "family", "families": {"train": ["er"], "val": [], "test": ["ba"]},
           "unassigned": "error", "conflict": "error"}
    with pytest.raises(PipelineError, match="spans"):
        build_split_manifest(graphs, cfg)
    cfg["conflict"] = "exclude"
    excluded = build_split_manifest(graphs, cfg)
    assert excluded["assignments"] == {} and len(excluded["excluded"]) == 2
    cfg.update(conflict="assign", group_assignments={"a": "test"})
    assert build_split_manifest(graphs, cfg)["assignments"] == {"a": "test", "b": "test"}
    cfg["group_assignments"]["b"] = "train"
    with pytest.raises(PipelineError, match="Conflicting explicit"):
        build_split_manifest(graphs, cfg)


def test_size_ranges_and_unassigned_group_exclusion():
    cfg = {"mode": "size", "size_ranges": {"train": [1, 5], "val": [6, 9], "test": [10, None]},
           "unassigned": "error", "conflict": "error"}
    graphs = [identity("a", size=2), identity("b", size=7), identity("c", size=10)]
    assert build_split_manifest(graphs, cfg)["assignments"] == {"a": "train", "b": "val", "c": "test"}
    cfg["size_ranges"]["train"] = [1, 1]
    cfg["unassigned"] = "exclude"
    manifest = build_split_manifest(graphs, cfg)
    assert [item["graph_id"] for item in manifest["excluded"]] == ["a"]


def test_immutable_manifest_and_tampering(tmp_path):
    manifest = build_split_manifest([identity("a")], random_config())
    path = write_split_manifest(tmp_path / "split.json", manifest)
    assert write_split_manifest(path, manifest) == path
    tampered = deepcopy(manifest)
    tampered["assignments"]["a"] = "unexpected"
    with pytest.raises(PipelineError, match="content/hash"):
        validate_split_manifest(tampered)
    cfg = random_config()
    cfg["seed"] += 1
    with pytest.raises(PipelineError, match="overwrite"):
        write_split_manifest(path, build_split_manifest([identity("a")], cfg))


def test_split_inputs_reject_missing_identity_and_duplicate_graphs():
    with pytest.raises(PipelineError, match="Duplicate graph_id"):
        build_split_manifest([identity("a"), identity("a")], random_config())
    missing = identity("a")
    del missing["origin_graph_id"]
    with pytest.raises(PipelineError, match="origin_graph_id"):
        build_split_manifest([missing], random_config())


def test_long_absent_ancestry_chain_uses_iterative_path_compression():
    count = 2500
    graphs = [identity(f"z{index:05}", origin=f"a{count-index:05}",
                       parent_graph_id=f"a{count-index+1:05}") for index in range(count)]
    manifest = build_split_manifest(graphs, random_config())
    assert len(manifest["groups"]) == 1
    assert len(manifest["groups"][0]["graph_ids"]) == count


def test_empty_split_corpus_is_rejected():
    with pytest.raises(PipelineError, match="empty graph corpus"):
        build_split_manifest([], random_config())
