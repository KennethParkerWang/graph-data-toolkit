"""Deterministic split manifests with transitive provenance/topology grouping."""

from __future__ import annotations

from collections import defaultdict
from pathlib import Path
import json
import os
import tempfile
from typing import Any, Iterable, Mapping

from .config import canonical_json, content_id
from .models import GraphRecord, PipelineError

SPLITS = ("train", "val", "test")


def _identity(value: GraphRecord | Mapping[str, Any]) -> dict[str, Any]:
    if isinstance(value, GraphRecord):
        data = {"graph_id": value.graph_id, "origin_graph_id": value.origin_graph_id,
                "topology_hash": value.topology_hash, "num_nodes": value.num_nodes,
                "metadata": value.metadata}
    else:
        data = dict(value)
    metadata = data.get("metadata", data.get("meta", {}))
    graph_id = data.get("graph_id")
    origin = data.get("origin_graph_id")
    topology = data.get("topology_hash")
    if any(not isinstance(x, str) or not x for x in (graph_id, origin, topology)):
        raise PipelineError("Each split identity needs graph_id, origin_graph_id and topology_hash")
    parents = []
    for source in (data, metadata):
        for key in ("parent_graph_id", "parent_graph_ids"):
            raw = source.get(key, [])
            parents.extend([raw] if isinstance(raw, str) else raw)
    if any(not isinstance(parent, str) or not parent for parent in parents):
        raise PipelineError(f"Invalid parent IDs for {graph_id}")
    size = data.get("num_nodes", data.get("N"))
    if isinstance(size, bool) or not isinstance(size, int) or size < 1:
        raise PipelineError(f"Invalid node count for {graph_id}")
    return {"graph_id": graph_id, "origin_graph_id": origin, "topology_hash": topology,
            "num_nodes": size, "model": data.get("model", metadata.get("model")),
            "parent_graph_ids": sorted(set(parents))}


def build_groups(graphs: Iterable[GraphRecord | Mapping[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, list[str]]]:
    identities = sorted((_identity(value) for value in graphs), key=lambda value: value["graph_id"])
    if not identities:
        raise PipelineError("Cannot construct a split manifest from an empty graph corpus")
    if len({item["graph_id"] for item in identities}) != len(identities):
        raise PipelineError("Duplicate graph_id in split input")
    parent: dict[str, str] = {}

    def find(key: str) -> str:
        parent.setdefault(key, key)
        root = key
        while parent[root] != root:
            root = parent[root]
        while parent[key] != key:
            previous = parent[key]
            parent[key] = root
            key = previous
        return root

    def union(left: str, right: str) -> None:
        left, right = find(left), find(right)
        if left != right:
            parent[max(left, right)] = min(left, right)

    for value in identities:
        node = "graph:" + value["graph_id"]
        union(node, "graph:" + value["origin_graph_id"])
        union(node, "topology:" + value["topology_hash"])
        for ancestor in value["parent_graph_ids"]:
            union(node, "graph:" + ancestor)
    components: dict[str, list[str]] = defaultdict(list)
    for value in identities:
        components[find("graph:" + value["graph_id"])].append(value["graph_id"])
    groups = {content_id({"group_schema": "graph-provenance-group-v1", "graph_ids": sorted(ids)}): sorted(ids)
              for ids in components.values()}
    return identities, dict(sorted(groups.items()))


def _requested_split(graph: dict[str, Any], config: Mapping[str, Any]) -> str | None:
    mode = config["mode"]
    if mode == "family":
        if not graph["model"]:
            raise PipelineError(f"Missing model for family split: {graph['graph_id']}")
        matched = [split for split, families in config["families"].items() if graph["model"] in families]
    elif mode == "size":
        matched = [split for split, bounds in config["size_ranges"].items()
                   if (bounds[0] is None or graph["num_nodes"] >= bounds[0])
                   and (bounds[1] is None or graph["num_nodes"] <= bounds[1])]
    else:
        raise PipelineError(f"Unknown split mode: {mode}")
    if len(matched) > 1:
        raise PipelineError(f"Overlapping split rules for {graph['graph_id']}")
    return matched[0] if matched else None


def build_split_manifest(graphs: Iterable[GraphRecord | Mapping[str, Any]], config: Mapping[str, Any]) -> dict[str, Any]:
    """Config mode is random/size/family; all splits and conflict policy are explicit.

    Random requires fractions and seed. Size requires inclusive size_ranges;
    family requires families. Non-random modes require unassigned=error/exclude.
    conflict=error/exclude/assign controls groups spanning requested partitions;
    assign requires group_assignments (group_id or member graph_id -> split).
    """
    config = json.loads(canonical_json(dict(config)))
    mode = config.get("mode")
    if mode not in {"random", "size", "family"}:
        raise PipelineError("Explicit split mode must be random, size or family")
    conflict = config.get("conflict")
    if conflict not in {"error", "exclude", "assign"}:
        raise PipelineError("Explicit conflict policy must be error, exclude or assign")
    required = {"mode", "conflict"} | ({"fractions", "seed"} if mode == "random" else {"unassigned", "size_ranges" if mode == "size" else "families"})
    allowed = required | {"group_assignments"}
    if not required <= set(config) or set(config) - allowed:
        raise PipelineError(f"Split config requires {sorted(required)}; allowed fields {sorted(allowed)}")
    overrides = config.get("group_assignments", {})
    if not isinstance(overrides, dict) or any(value not in SPLITS for value in overrides.values()):
        raise PipelineError("group_assignments must map graph/group IDs to train/val/test")
    if conflict == "assign" and not overrides:
        raise PipelineError("conflict=assign requires explicit group_assignments")
    if mode == "random":
        fractions = config["fractions"]
        if set(fractions) != set(SPLITS) or any(isinstance(v, bool) or not isinstance(v, (int, float)) or v < 0 for v in fractions.values()):
            raise PipelineError("fractions must give nonnegative train/val/test probabilities")
        if abs(sum(fractions.values()) - 1) > 1e-12:
            raise PipelineError("Split fractions must sum to one")
        if isinstance(config["seed"], bool) or not isinstance(config["seed"], int):
            raise PipelineError("Split seed must be an explicit integer")
    else:
        if config["unassigned"] not in {"error", "exclude"}:
            raise PipelineError("unassigned must be error or exclude")
        rules = config["size_ranges" if mode == "size" else "families"]
        if not isinstance(rules, dict) or set(rules) != set(SPLITS):
            raise PipelineError("Split rules must explicitly contain train, val, and test")
        if mode == "size":
            for bounds in rules.values():
                if not isinstance(bounds, list) or len(bounds) != 2 or any(x is not None and (isinstance(x, bool) or not isinstance(x, int) or x < 1) for x in bounds):
                    raise PipelineError("size_ranges must be inclusive [min, max] positive integers or null")
                if all(x is not None for x in bounds) and bounds[0] > bounds[1]:
                    raise PipelineError("size_ranges minimum exceeds maximum")
        elif any(not isinstance(families, list) or any(not isinstance(x, str) or not x for x in families) for families in rules.values()):
            raise PipelineError("families must be lists of model strings")
    identities, groups = build_groups(graphs)
    by_id = {item["graph_id"]: item for item in identities}
    known = set(groups) | set(by_id)
    if set(overrides) - known:
        raise PipelineError(f"Unknown group assignment IDs: {sorted(set(overrides) - known)}")
    assignments: dict[str, str] = {}
    group_records = []
    excluded = []
    for group_id, members in groups.items():
        override_values = {overrides[key] for key in [group_id, *members] if key in overrides}
        if len(override_values) > 1:
            raise PipelineError(f"Conflicting explicit assignments for group {group_id}")
        reason = ""
        if override_values:
            split = next(iter(override_values))
            reason = "explicit_group_assignment"
        elif mode == "random":
            draw = int(content_id({"seed": config["seed"], "group_id": group_id})[:16], 16) / 2**64
            split = "train" if draw < fractions["train"] else "val" if draw < fractions["train"] + fractions["val"] else "test"
        else:
            requested = {_requested_split(by_id[member], config) for member in members}
            if None in requested:
                if config["unassigned"] == "error":
                    raise PipelineError(f"Unassigned graph in provenance group {group_id}")
                split, reason = None, "group_contains_unassigned_graph"
            elif len(requested) > 1:
                if conflict != "exclude":
                    raise PipelineError(f"Group {group_id} spans {sorted(requested)}; explicit group assignment required")
                split, reason = None, "group_spans_requested_partitions"
            else:
                split = next(iter(requested))
        group_records.append({"group_id": group_id, "graph_ids": members, "split": split, "reason": reason})
        if split is None:
            excluded.extend({"graph_id": member, "group_id": group_id, "reason": reason} for member in members)
        else:
            assignments.update({member: split for member in members})
    body = {"schema_version": "split-manifest-v1", "grouping_version": "graph-provenance-group-v1",
            "config": config, "graph_identities": identities, "groups": group_records,
            "assignments": dict(sorted(assignments.items())), "excluded": excluded}
    return {"split_id": content_id(body), **body}


def validate_split_manifest(manifest: Mapping[str, Any]) -> None:
    expected = build_split_manifest(manifest["graph_identities"], manifest["config"])
    if canonical_json(expected) != canonical_json(dict(manifest)):
        raise PipelineError("Split manifest content/hash does not match reproducible assignments")


def write_split_manifest(path: str | Path, manifest: Mapping[str, Any]) -> Path:
    """Atomically publish once; existing different content is never overwritten."""
    validate_split_manifest(manifest)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = (canonical_json(dict(manifest)) + "\n").encode("utf-8")
    if path.exists():
        if path.read_bytes() != encoded:
            raise PipelineError(f"Refusing to overwrite different fixed split manifest: {path}")
        return path
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.link(temp_name, path)
        except FileExistsError:
            if path.read_bytes() != encoded:
                raise PipelineError(f"Concurrent conflicting split publication: {path}")
    finally:
        Path(temp_name).unlink(missing_ok=True)
    return path
