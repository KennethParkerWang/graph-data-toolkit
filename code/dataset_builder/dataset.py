"""Lazy, process-local HDF5 Dataset; PyTorch is optional until constructing a loader."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import h5py

from .cache import TRAINING_SCHEMA, _safe_shard_path, file_sha256, load_index, read_sample, sample_fingerprint
from .models import PipelineError, TrainingSample


class TrainingDataset:
    """Map-style dataset returning :class:`TrainingSample` objects on demand.

    Initialization reads index JSON only. Handles are opened lazily in the
    current worker, dropped during pickling, and discarded after a PID change.
    The object follows torch's Dataset protocol without importing torch.
    """

    def __init__(self, index_path: str | Path, split: str | None = None, *,
                 expected_provenance: dict[str, Any] | None = None, verify_checksums: bool = True,
                 max_open_shards: int = 8):
        if isinstance(max_open_shards, bool) or not isinstance(max_open_shards, int) or max_open_shards < 1:
            raise PipelineError("max_open_shards must be a positive integer")
        self.index_path = str(Path(index_path).resolve())
        self.index = load_index(self.index_path, expected_provenance)
        self.rows = [row for row in self.index["samples"] if split is None or row["split"] == split]
        self.verify_checksums = verify_checksums
        self.max_open_shards = max_open_shards
        self._handles: dict[str, h5py.File] = {}
        self._pid = os.getpid()

    def __len__(self) -> int:
        return len(self.rows)

    def _handle(self, name: str) -> h5py.File:
        if self._pid != os.getpid():
            self.close()
            self._pid = os.getpid()
        if name not in self._handles:
            if len(self._handles) >= self.max_open_shards:
                self._handles.pop(next(iter(self._handles))).close()
            path = _safe_shard_path(Path(self.index_path).parent, name)
            try:
                info = self.index["shards"][name]
                if self.verify_checksums and (path.stat().st_size != info["file_bytes"] or file_sha256(path) != info["file_sha256"]):
                    raise PipelineError(f"Cache shard checksum mismatch: {path}")
                handle = h5py.File(path, "r")
                if handle.attrs.get("schema_version") != TRAINING_SCHEMA or handle.attrs.get("cache_id") != self.index["cache_id"]:
                    handle.close()
                    raise PipelineError(f"Cache shard identity mismatch: {path}")
                self._handles[name] = handle
            except (OSError, KeyError) as exc:
                raise PipelineError(f"Cannot open cache shard {path}: {exc}") from exc
        handle = self._handles.pop(name)
        self._handles[name] = handle
        return handle

    def __getitem__(self, item: int) -> TrainingSample:
        row = self.rows[item]
        try:
            sample = read_sample(self._handle(row["shard"])[row["group"]])
        except (OSError, KeyError, ValueError, TypeError) as exc:
            if isinstance(exc, PipelineError):
                raise
            raise PipelineError(f"Cannot load cache sample {row['sample_id']}: {exc}") from exc
        if sample.sample_id != row["sample_id"] or sample.graph.graph_id != row["graph_id"] or sample.split != row["split"]:
            raise PipelineError(f"Cache sample identity mismatch: {row['sample_id']}")
        if sample_fingerprint(sample) != row["fingerprint"]:
            raise PipelineError(f"Cache sample content mismatch: {row['sample_id']}")
        return sample

    def close(self) -> None:
        for handle in self._handles.values():
            handle.close()
        self._handles.clear()

    def __getstate__(self) -> dict[str, Any]:
        state = self.__dict__.copy()
        state["_handles"] = {}
        state["_pid"] = None
        return state

    def __enter__(self):
        return self

    def __exit__(self, *_exc):
        self.close()

    def __del__(self):
        if hasattr(self, "_handles"):
            self.close()


class PyGTrainingDataset(TrainingDataset):
    """Lazy adapter for ``torch_geometric.loader.DataLoader`` directly.

    Standard PyG batches combine topology and retain a per-graph list in
    ``training_sample``. For padded selected metrics, use make_pyg_loader with
    the ordinary TrainingDataset instead.
    """

    def __init__(self, index_path: str | Path, split: str | None = None, *,
                 bidirectional: bool = True, **kwargs):
        super().__init__(index_path, split=split, **kwargs)
        self.bidirectional = bidirectional

    def __getitem__(self, item: int):
        from .batching import to_pyg_data
        return to_pyg_data(super().__getitem__(item), bidirectional=self.bidirectional)


def make_torch_loader(dataset: TrainingDataset, *, batch_size: int, num_workers: int = 0,
                      bidirectional: bool = True, **kwargs):
    from functools import partial
    from torch.utils.data import DataLoader
    from .batching import collate_samples
    if isinstance(dataset, PyGTrainingDataset):
        raise PipelineError("make_torch_loader expects TrainingDataset; native PyG DataLoader accepts PyGTrainingDataset")
    if "collate_fn" in kwargs:
        raise PipelineError("Use collate_samples to preserve metric masks and ragged axes")
    return DataLoader(dataset, batch_size=batch_size, num_workers=num_workers,
                      collate_fn=partial(collate_samples, bidirectional=bidirectional), **kwargs)


def make_pyg_loader(dataset: TrainingDataset, *, batch_size: int, num_workers: int = 0,
                    bidirectional: bool = True, **kwargs):
    """Yield PyG Batch topology plus correctly padded metric dictionaries.

    PyG's default loader replaces custom collators and assumes compatible
    target shapes. A torch DataLoader with our PyG collator retains graph,
    node, edge and trajectory metrics without accidentally concatenating axes.
    """
    from functools import partial
    from torch.utils.data import DataLoader
    from .batching import collate_pyg_samples
    if isinstance(dataset, PyGTrainingDataset):
        raise PipelineError("make_pyg_loader expects TrainingDataset; native PyG DataLoader accepts PyGTrainingDataset")
    if "collate_fn" in kwargs:
        raise PipelineError("Use collate_pyg_samples for ragged PyG targets")
    return DataLoader(dataset, batch_size=batch_size, num_workers=num_workers,
                      collate_fn=partial(collate_pyg_samples, bidirectional=bidirectional), **kwargs)
