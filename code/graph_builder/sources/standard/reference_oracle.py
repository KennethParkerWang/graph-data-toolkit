"""Create independent NetworkX 3.5 diagnostics for MATLAB source-port tests."""
from pathlib import Path
import hashlib
import json
import networkx as nx
import numpy as np


def main():
    if nx.__version__ != "3.5":
        raise RuntimeError("Use the pinned NetworkX 3.5 reference")
    root = Path(__file__).parent
    manifest = json.loads((root / "networkx_3_5/manifest.json").read_text(encoding="utf-8-sig"))
    for entry in manifest["files"]:
        if entry["file"].endswith(".py"):
            installed = Path(nx.__file__).parent / "generators" / entry["file"]
            if hashlib.sha256(installed.read_bytes()).hexdigest() != entry["sha256"]:
                raise RuntimeError("Installed source differs: " + entry["file"])
    models = {
        "ba": lambda seed: nx.barabasi_albert_graph(30, 3, seed=seed),
        "nw": lambda seed: nx.newman_watts_strogatz_graph(30, 4, .4, seed=seed),
        "hk": lambda seed: nx.powerlaw_cluster_graph(30, 3, .5, seed=seed),
        "random_regular": lambda seed: nx.random_regular_graph(4, 30, seed=seed),
    }
    cases = []
    for name, make in models.items():
        rows = []
        for seed in range(1000, 2024):
            graph = make(seed)
            degrees = np.array([graph.degree(i) for i in range(30)], dtype=float)
            rows.append([graph.number_of_edges(), np.mean(degrees**2), sum(nx.triangles(graph).values())/3, degrees[0]])
        values = np.asarray(rows)
        cases.append({"model": name, "samples": len(rows), "mean": values.mean(axis=0).tolist(), "variance": values.var(axis=0, ddof=1).tolist()})
    target = root / "networkx_diagnostics.json"
    target.write_text(json.dumps({"networkx": nx.__version__, "statistic_order": ["M", "mean_squared_degree", "triangles", "first_node_degree"], "cases": cases}, indent=2), encoding="utf-8")
    print("Saved", len(cases), "reference cases, 1024 graphs per case")


if __name__ == "__main__":
    main()
