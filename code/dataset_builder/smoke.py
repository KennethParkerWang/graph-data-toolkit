"""Reproducible small fixture benchmark; explicitly separate from producer acceptance."""

from __future__ import annotations

import importlib.metadata
import json
from pathlib import Path
import platform
import time
from typing import Any

import numpy as np

from .cache import build_cache, sample_fingerprint
from .dataset import TrainingDataset, make_pyg_loader, make_torch_loader
from .examples.framework_records import framework_samples


def run_framework_smoke(output: str | Path, *, workers: int = 2) -> dict[str, Any]:
    if workers < 0:
        raise ValueError("workers must be nonnegative")
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    samples = framework_samples()
    measurements = []
    for shard_size in (2, 8):
        for compression in (None, "lzf", "gzip"):
            label = f"size_{shard_size}_{compression or 'none'}"
            start = time.perf_counter()
            index = build_cache(
                iter(samples), output / label, {"fixture_only": True, "fixture_version": "framework-v1"},
                shard_size=shard_size, compression=compression,
                compression_opts=1 if compression == "gzip" else None,
            )
            write_seconds = time.perf_counter() - start
            start = time.perf_counter()
            with TrainingDataset(index) as dataset:
                assert not dataset._handles, "Dataset initialization opened a shard"
                assert len(dataset) == len(samples)
                for i, expected in enumerate(samples):
                    actual = dataset[i]
                    assert sample_fingerprint(actual) == sample_fingerprint(expected)
                cache_id = dataset.index["cache_id"]
            read_seconds = time.perf_counter() - start
            measurements.append({
                "shard_size": shard_size, "compression": compression,
                "compression_opts": 1 if compression == "gzip" else None,
                "file_bytes": sum(path.stat().st_size for path in index.parent.glob("shard_*.h5")),
                "write_seconds": write_seconds, "read_seconds": read_seconds,
                "index": str(index), "cache_id": cache_id,
            })
    selected = min(measurements, key=lambda row: (row["file_bytes"], row["read_seconds"]))
    batches = {}
    for kind, factory in (("torch", make_torch_loader), ("pyg", make_pyg_loader)):
        for worker_count in sorted({0, workers}):
            started = time.perf_counter()
            seen = []
            with TrainingDataset(selected["index"]) as dataset:
                loader = factory(dataset, batch_size=3, num_workers=worker_count, shuffle=False)
                batch_count = 0
                for batch in loader:
                    batch_count += 1
                    batch_ids = batch["sample_id"]
                    expected = samples[len(seen):len(seen) + len(batch_ids)]
                    assert batch_ids == [sample.sample_id for sample in expected]
                    assert int(batch["num_nodes"].sum()) == sum(sample.graph.num_nodes for sample in expected)
                    assert batch["edge_index"].shape[0] == 2
                    assert batch["edge_index"].device.type == "cpu"
                    for i, sample in enumerate(expected):
                        curve = batch["targets"]["curve_demo"]
                        length = sample.targets["curve_demo"].values.size
                        np.testing.assert_array_equal(curve["valid_mask"][i, :length].numpy(), sample.targets["curve_demo"].valid_mask)
                        np.testing.assert_allclose(curve["raw_values"][i, :length].numpy(), sample.targets["curve_demo"].values, equal_nan=True)
                        assert not bool(curve["valid_mask"][i, length:].any())
                        positions = curve["axis_positions"]["removed_count"]
                        np.testing.assert_array_equal(positions["values"][i, :length].numpy(), sample.targets["curve_demo"].axis_positions["removed_count"])
                    if kind == "pyg":
                        graph_batch = batch["graph_batch"]
                        assert graph_batch.num_nodes == sum(sample.graph.num_nodes for sample in expected)
                        np.testing.assert_array_equal(graph_batch.edge_index.numpy(), batch["edge_index"].numpy())
                        np.testing.assert_array_equal(graph_batch.original_edge_id.numpy(), batch["original_edge_id"].numpy())
                    seen.extend(batch_ids)
                assert len(seen) == len(samples) and len(set(seen)) == len(samples)
            batches[f"{kind}_workers_{worker_count}"] = {
                "batches": batch_count, "samples": len(seen), "seconds": time.perf_counter() - started,
            }
    versions = {name: importlib.metadata.version(name) for name in ("numpy", "scipy", "h5py", "torch", "torch-geometric")}
    report = {
        "status": "passed", "acceptance_level": "independent_framework_only",
        "producer_matlab_roundtrip_verified": False,
        "sample_count": len(samples), "graph_count": len(samples),
        "covered": ["directed_reciprocal_arcs", "isolated_nodes", "empty_edges", "scalar_node_edge_curve",
                    "ragged_actual_positions", "partial_invalid_mask", "shard_roundtrip", "lazy_init", "cpu_multiworker_pyg"],
        "environment": {"python": platform.python_version(), "platform": platform.platform(), **versions},
        "measurements": measurements, "batches": batches,
        "small_fixture_choice": selected,
        "measurement_limit": "One local pass over 8 in-memory fixtures; metadata overhead dominates. Re-benchmark actual producer samples before choosing production shard/compression settings.",
    }
    report_path = output / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"report": str(report_path), **report}
