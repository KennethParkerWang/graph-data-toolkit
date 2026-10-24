"""Small deterministic advanced-metric reference fixtures; no production data.

Requires NetworkX 3.5 and SciPy. This script calls their public implementations;
it does not read or translate the MATLAB implementations.
"""
from pathlib import Path
import json
import warnings

import networkx as nx
import numpy as np
import scipy
from scipy.linalg import eigvals
from scipy.special import logsumexp


def expected(metric_id, values, parameters=None):
    data = np.asarray(values)
    if not np.all(np.isfinite(data)):
        return None
    return {
        "metric_id": metric_id,
        "parameters": parameters or {},
        "values": data.real.tolist(),
        "imaginary": data.imag.tolist() if np.iscomplexobj(data) else [],
    }


def fixtures():
    graphs = [
        ("path4", nx.path_graph(4)),
        ("cycle4", nx.cycle_graph(4)),
        ("star5", nx.star_graph(4)),
        ("complete4", nx.complete_graph(4)),
        ("barbell6", nx.barbell_graph(3, 0)),
        ("directed4", nx.DiGraph([(0, 1), (0, 2), (1, 0), (1, 2), (2, 3)])),
        ("directed_cycle4", nx.DiGraph([(0, 1), (1, 2), (2, 3), (3, 0)])),
    ]
    cases = []
    for name, graph in graphs:
        n = len(graph)
        adjacency = nx.to_numpy_array(graph, nodelist=range(n))
        results = []
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", RuntimeWarning)
            for source in ("in", "out") if graph.is_directed() else ("out",):
                for target in ("in", "out") if graph.is_directed() else ("in",):
                    results.append(expected(
                        "degree_assortativity",
                        nx.degree_assortativity_coefficient(graph, x=source, y=target),
                        {"source_degree": source, "target_degree": target},
                    ))
        partition = [int(i >= n // 2) for i in range(n)]
        communities = [{i for i in range(n) if partition[i] == label} for label in set(partition)]
        for resolution in [0.7, 1.0, 1.5]:
            results.append(expected("modularity", nx.community.modularity(graph, communities, resolution=resolution),
                                    {"partition": partition, "resolution": resolution}))
        eigenvalues = eigvals(adjacency)
        results.append(expected("adjacency_spectral_radius", np.max(np.abs(eigenvalues))))
        if graph.is_directed():
            results.append(expected("reciprocity", nx.reciprocity(graph)))
            # NetworkX source=in/out uses predecessor/successor neighborhoods.
            # Its source=in+out has multiplicity semantics, so our distinct-union
            # mode is verified analytically in MATLAB instead of falsely equated.
            for mode in ("in", "out"):
                for target in ("in", "out", "in+out"):
                    degrees = nx.average_neighbor_degree(graph, source=mode, target=target)
                    values = np.array([degrees[i] for i in range(n)])
                    if all((graph.in_degree(i) if mode == "in" else graph.out_degree(i)) > 0 for i in range(n)):
                        results.append(expected("average_neighbor_degree", values,
                                                {"neighbor_mode": mode, "target_degree": "total" if target == "in+out" else target}))
        else:
            results.append(expected("average_neighbor_degree", list(nx.average_neighbor_degree(graph).values())))
            rich = nx.rich_club_coefficient(graph, normalized=False)
            results.append(expected("rich_club", list(rich.values()), {"thresholds": list(rich)}))
            results.append(expected("adjacency_spectrum", np.linalg.eigvalsh(adjacency)))
            laplacian = nx.laplacian_spectrum(graph)
            results.append(expected("laplacian_spectrum", laplacian))
            results.append(expected("algebraic_connectivity", laplacian[1]))
            results.append(expected("natural_connectivity", logsumexp(np.linalg.eigvalsh(adjacency)) - np.log(n)))
            resistance_dict = nx.resistance_distance(graph)
            resistance = np.array([[resistance_dict[i][j] for j in range(n)] for i in range(n)])
            results.append(expected("effective_resistance", resistance))
            results.append(expected("kirchhoff_index", np.triu(resistance, 1).sum()))
        cases.append({"name": name, "directed": graph.is_directed(), "adjacency": adjacency.tolist(),
                      "expected": [item for item in results if item is not None]})
    return {"networkx_version": nx.__version__, "numpy_version": np.__version__,
            "scipy_version": scipy.__version__, "randomness": "none", "cases": cases}


if __name__ == "__main__":
    if nx.__version__ != "3.5":
        raise RuntimeError("Reference fixtures are pinned to NetworkX 3.5.")
    output = Path(__file__).with_name("advanced_reference.json")
    data = fixtures()
    output.write_text(json.dumps(data, indent=2, allow_nan=False), encoding="utf-8")
    print(json.dumps({"output": str(output), "cases": len(data["cases"]),
                      "reference_values": sum(len(case["expected"]) for case in data["cases"]),
                      "networkx_version": data["networkx_version"]}))
