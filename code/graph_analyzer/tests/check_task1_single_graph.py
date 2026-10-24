"""Independent NetworkX/SciPy checks for the Task1 single-graph validation."""
from __future__ import annotations

import json
from pathlib import Path

import networkx as nx
import numpy as np
from scipy.io import loadmat


def records(value: object) -> list[dict]:
    if isinstance(value, dict):
        return [value]
    if isinstance(value, np.ndarray):
        return list(value.flat)
    return list(value) if isinstance(value, list) else []


def scalar(result: dict) -> float:
    return float(np.asarray(result["values"]).squeeze())


def vector(result: dict) -> np.ndarray:
    return np.asarray(result["values"], dtype=float).reshape(-1)


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    validation = root / "validation" / "task1_single_graph"
    source = root.parent / "graph_builder/examples/schema_v1/graphs/c8/c89eb1a8f8398a2503fc3439f5d73715cc830aecdd2d77fba24d456cb43d49ad.mat"
    graph = loadmat(source, simplify_cells=True)
    result = loadmat(validation / "results.mat", simplify_cells=True)
    identity = result["identity"]
    assert identity["graph_id"] == "c89eb1a8f8398a2503fc3439f5d73715cc830aecdd2d77fba24d456cb43d49ad"
    assert identity["topology_hash"] == "87828505821008c574d7e2b59913dd658ae3d8f95d7e69d2b16a2aa33fadd0c7"

    n = int(graph["N"])
    edges = np.asarray(graph["edge_list"], dtype=int).reshape(-1, 2)
    g = nx.Graph()
    g.add_nodes_from(range(1, n + 1))
    g.add_edges_from(map(tuple, edges))
    observations = {row["metric_id"]: row for row in records(result["results"])}
    checks = 0

    def close(name: str, actual: float, expected: float, tol: float = 1e-10) -> None:
        nonlocal checks
        assert np.isclose(actual, expected, atol=tol, rtol=tol), (name, actual, expected)
        checks += 1

    def equal_vector(name: str, actual: np.ndarray, expected: np.ndarray) -> None:
        nonlocal checks
        assert actual.shape == expected.shape, (name, actual.shape, expected.shape)
        assert np.allclose(actual, expected, atol=1e-10, rtol=1e-10), (name, actual, expected)
        checks += 1

    close("node_count", scalar(observations["node_count"]), g.number_of_nodes())
    close("edge_count", scalar(observations["edge_count"]), g.number_of_edges())
    close("density", scalar(observations["density"]), nx.density(g))
    close("isolate_count", scalar(observations["isolate_count"]), len(list(nx.isolates(g))))
    equal_vector("degree", vector(observations["degree"]), np.array([g.degree(i) for i in range(1, n + 1)], dtype=float))
    close("degree_mean", scalar(observations["degree_mean"]), np.mean([d for _, d in g.degree()]))
    degrees = np.array([d for _, d in g.degree()], dtype=float)
    close("degree_variance", scalar(observations["degree_variance"]), np.var(degrees))
    close("degree_heterogeneity", scalar(observations["degree_heterogeneity"]), np.mean(degrees**2) / np.mean(degrees) ** 2)
    close("component_count", scalar(observations["component_count"]), nx.number_connected_components(g))
    sizes = sorted((len(c) for c in nx.connected_components(g)), reverse=True)
    close("largest_component_size", scalar(observations["largest_component_size"]), sizes[0])
    close("second_largest_component_size", scalar(observations["second_largest_component_size"]), sizes[1])
    close("largest_component_fraction", scalar(observations["largest_component_fraction"]), sizes[0] / n)
    close("triangle_count", scalar(observations["triangle_count"]), sum(nx.triangles(g).values()) / 3)
    close("average_clustering", scalar(observations["average_clustering"]), nx.average_clustering(g))
    close("transitivity", scalar(observations["transitivity"]), nx.transitivity(g))
    close("global_efficiency", scalar(observations["global_efficiency"]), nx.global_efficiency(g))
    close("adjacency_spectral_radius", scalar(observations["adjacency_spectral_radius"]), 2.0)
    close("algebraic_connectivity", scalar(observations["algebraic_connectivity"]), 0.0)
    close("reachable_pair_fraction", scalar(observations["reachable_pair_fraction"]), 6 / 12)
    close("node_connectivity", scalar(observations["node_connectivity"]), 0.0)
    close("edge_connectivity", scalar(observations["edge_connectivity"]), 0.0)
    close("modularity", scalar(observations["modularity"]), nx.community.modularity(g, [{1, 2, 3}, {4}]))
    assert observations["indegree"]["status"] == "not_applicable"
    assert observations["outdegree"]["status"] == "not_applicable"
    assert observations["triad_census"]["status"] == "not_applicable"
    checks += 3

    summary = json.loads((validation / "report.json").read_text(encoding="utf-8"))
    assert summary["passed"] and summary["registered_metrics"] == 70
    assert all(item["passed"] for item in summary["analytic_checks"])
    checks += 2
    summary_results = {row["metric_id"]: row for row in summary["summary_results"]}
    close("robustness_schneider", float(summary_results["robustness_schneider"]["values"]), 0.375)
    close("sampled_curve_auc", float(summary_results["sampled_curve_auc"]["values"]), 1.875)
    close("first_threshold_fraction", float(summary_results["first_threshold_fraction"]["values"]), 0.75)
    retention = np.asarray(summary_results["efficiency_retention_curve"]["values"], dtype=float).reshape(-1)
    equal_vector("efficiency_retention_prefix", retention[:3], np.array([1.0, 2.0, 2.0]))
    checks += 4

    report = {
        "passed": True,
        "checks": checks,
        "graph_id": identity["graph_id"],
        "source": str(source),
        "networkx": nx.__version__,
        "result": str(validation / "results.mat"),
        "status_counts": summary["status_counts"],
    }
    (validation / "python_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
