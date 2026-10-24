"""Validate MATLAB graph-v1 samples with NumPy/SciPy; no old project needed.

Usage: python verify_graph_io.py [dataset_root]
This is an interoperability verifier, not the task-3 training Dataset.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

import numpy as np
from scipy import sparse
from scipy.io import loadmat
from scipy.io.matlab import mat_struct


def text(value) -> str:
    if isinstance(value, str):
        return value
    array = np.asarray(value)
    if array.dtype.kind not in "US":
        raise ValueError("expected MATLAB char")
    if array.size == 0:
        return ""
    if array.size != 1:
        raise ValueError("only character rows are supported")
    return str(array.item())


def struct(value) -> mat_struct:
    if isinstance(value, mat_struct):
        return value
    array = np.asarray(value)
    if array.size != 1 or not isinstance(array.item(), mat_struct):
        raise ValueError("expected scalar MATLAB struct")
    return array.item()


def numeric(value, dtype: str, shape: tuple[int, ...]) -> np.ndarray:
    array = np.asarray(value)
    if array.dtype != np.dtype(dtype) or array.shape != shape:
        raise ValueError(f"expected {dtype} {shape}, got {array.dtype} {array.shape}")
    return array


def canonical(value) -> str:
    """Mirror gg_io_canonical_json for scientific checks, not recipe rewriting."""
    def encode(node):
        if isinstance(node, dict):
            return {key: encode(node[key]) for key in sorted(node)}
        if isinstance(node, mat_struct):
            return {key: encode(getattr(node, key)) for key in sorted(node._fieldnames)}
        if isinstance(node, str):
            return node
        if not isinstance(node, np.ndarray):
            raise TypeError(f"unsupported canonical value: {type(node)}")
        if node.dtype.kind in "US":
            return text(node)
        if node.dtype.kind == "O":
            members = list(node.ravel(order="F"))
            if len(members) == 1 and isinstance(members[0], mat_struct):
                return encode(members[0])
            key = "__struct_array__" if all(isinstance(x, mat_struct) for x in members) else "__cell_array__"
            return {key: True, "shape": list(node.shape), "values": [encode(x) for x in members]}
        dtype_names = {"bool": "logical", "float64": "double", "float32": "single"}
        dtype = dtype_names.get(node.dtype.name, node.dtype.name)
        values = []
        for item in node.ravel(order="F"):
            if node.dtype.kind == "b":
                values.append(bool(item))
            elif node.dtype.kind in "iu":
                values.append(str(int(item)))
            elif node.dtype.kind == "f" and np.isfinite(item):
                values.append("0" if item == 0 else format(float(item), ".17g"))
            else:
                raise ValueError("metadata must contain finite real numeric arrays")
        return {"dtype": dtype, "shape": list(node.shape), "values": values}

    return json.dumps(encode(value), ensure_ascii=False, separators=(",", ":"))


def verify(root: Path) -> list[dict]:
    index_path = root / "manifests" / "graphs.jsonl"
    lines = index_path.read_text(encoding="utf-8").splitlines()
    records = [json.loads(line) for line in lines]
    if len({row["graph_id"] for row in records}) != len(records):
        raise ValueError("duplicate graph IDs")
    fixtures = {}
    for record in records:
        graph_id = record["graph_id"]
        expected_path = f"graphs/{graph_id[:2]}/{graph_id}.mat"
        if record["path"] != expected_path:
            raise ValueError("noncanonical graph path")
        path = root / expected_path
        payload = path.read_bytes()
        assert len(payload) == record["file_bytes"]
        assert hashlib.sha256(payload).hexdigest() == record["file_sha256"]
        saved = loadmat(path, mat_dtype=True, struct_as_record=False, squeeze_me=False)
        n = int(numeric(saved["N"], "uint32", (1, 1)).item())
        m = int(numeric(saved["M"], "uint64", (1, 1)).item())
        directed = bool(numeric(saved["directed"], "bool", (1, 1)).item())
        edges = numeric(saved["edge_list"], "uint32", (m, 2))
        a = saved["A"]
        assert sparse.issparse(a) and a.shape == (n, n)
        # SciPy versions may expose sparse logical MAT data as bool or uint8.
        assert a.dtype in (np.dtype("bool"), np.dtype("uint8"))
        assert np.all(a.data == 1) and np.all(a.diagonal() == 0)
        assert n == record["N"] and m == record["M"] and directed == record["directed"]
        assert text(saved["schema_version"]) == "graph-v1"
        assert text(saved["graph_id"]) == graph_id
        assert text(saved["origin_graph_id"]) == record["origin_graph_id"]
        if m:
            assert np.all((edges >= 1) & (edges <= n))
            order = np.lexsort((edges[:, 1], edges[:, 0]))
            assert np.array_equal(order, np.arange(m))
            assert np.unique(edges, axis=0).shape[0] == m
        u = edges[:, 0].astype(np.int64) - 1
        v = edges[:, 1].astype(np.int64) - 1
        expected = sparse.csr_matrix((np.ones(m, dtype=bool), (u, v)), shape=(n, n))
        if not directed:
            assert np.all(edges[:, 0] < edges[:, 1])
            expected = expected + expected.T
        assert (a.astype(bool) != expected).nnz == 0
        stream = f"topology-v1\n{n}\n{int(directed)}\n{m}\n"
        stream += "".join(f"{int(left)},{int(right)}\n" for left, right in edges)
        topology = hashlib.sha256(stream.encode("utf-8")).hexdigest()
        assert topology == text(saved["topology_hash"]) == record["topology_hash"]
        meta = struct(saved["meta"])
        recipe = text(meta.recipe_json)
        assert hashlib.sha256(recipe.encode("utf-8")).hexdigest() == graph_id
        assert text(meta.model) == record["model"]
        assert text(meta.generator_id) == record["generator_id"]
        assert text(meta.implementation_version) == record["implementation_version"]
        available = bool(numeric(meta.source_edge_order_available, "bool", (1, 1)).item())
        assert available == ("source_edge_order" in saved)
        if available:
            edge_order = numeric(saved["source_edge_order"], "uint64", (m, 1)).ravel()
            assert np.array_equal(np.sort(edge_order), np.arange(1, m + 1, dtype=np.uint64))
        ignored = {"created_utc", "matlab_version", "elapsed_seconds", "duration_seconds",
                   "generation_elapsed_seconds", "recipe_json"}
        scientific = {name: saved[name] for name in ("schema_version", "graph_id", "origin_graph_id",
                                                     "topology_hash", "N", "M", "directed")}
        scientific["meta"] = {name: getattr(meta, name) for name in meta._fieldnames if name not in ignored}
        if available:
            scientific["source_edge_order"] = saved["source_edge_order"]
        assert hashlib.sha256(canonical(scientific).encode("utf-8")).hexdigest() == record["scientific_sha256"]
        params = struct(meta.parameters)
        if "fixture" in params._fieldnames:
            fixtures[text(params.fixture)] = (saved, meta)
    if fixtures:
        assert len(fixtures) == 5
        undirected, meta = fixtures["undirected_triangle_isolate"]
        assert int(undirected["N"].item()) == 4 and int(undirected["M"].item()) == 3
        attributes = struct(meta.attributes)
        np.testing.assert_array_equal(attributes.community.ravel(), [1, 1, 1, 2])
        np.testing.assert_array_equal(attributes.coordinates, [[0, 0], [1, 0], [0, 1], [2, 2]])
        assert text(meta.custom_note) == "社区与坐标保持节点顺序"
        directed, _ = fixtures["directed_reciprocal_isolate"]
        assert directed["A"].tocsr()[0, 1] and directed["A"].tocsr()[1, 0]
        empty, _ = fixtures["edgeless_three"]
        assert empty["edge_list"].shape == (0, 2) and empty["A"].shape == (3, 3)
        derived, _ = fixtures["derived_relabeling"]
        assert text(derived["origin_graph_id"]) == text(undirected["graph_id"])
    print(f"GRAPH_IO_PYTHON_OK {len(records)} graphs; MAT types, directions, IDs, hashes, attributes and isolated nodes")
    return records


if __name__ == "__main__":
    default = Path(__file__).resolve().parents[1] / "examples" / "schema_v1"
    verify(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else default)
