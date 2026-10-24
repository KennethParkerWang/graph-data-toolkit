"""Per-task evidence, separate from immutable scientific dataset records."""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import uuid

from .models import PipelineError
from .source import PROJECT_ROOT


def file_reference(path: str | Path) -> dict:
    path = Path(path).resolve()
    result = {"path": str(path), "exists": path.exists(), "kind": "file" if path.is_file() else "missing",
              "file_sha256": "", "hash_error": ""}
    if path.is_file():
        try:
            with path.open("rb") as stream:
                result["file_sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()
        except OSError as exc:
            result["hash_error"] = str(exc)
    elif path.is_dir():
        result["kind"] = "directory"
    return result


def _utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def _write_json(path: Path, value: dict) -> None:
    """Publish task metadata with a same-directory replacement."""
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


class RunWorkspace:
    """Record one task; create persistent intermediate storage only on demand.

    Abrupt process termination may leave status=running. That is evidence for
    inspection, not a claim that an algorithm can resume from its last step.
    """

    def __init__(self, dataset_root: str | Path, parameters: dict, *,
                 inputs: tuple[str | Path, ...] = (), run_root: str | Path | None = None):
        dataset = Path(dataset_root).resolve()
        descriptor = dataset / "dataset.json"
        try:
            metadata = json.loads(descriptor.read_text(encoding="utf-8"))
            dataset_id = metadata.get("dataset_id") if isinstance(metadata, dict) else None
        except (OSError, ValueError):
            dataset_id = None
        if not isinstance(dataset_id, str) or not dataset_id:
            # A failed preflight still has a safe, unambiguous task location.
            dataset_id = "unresolved_" + hashlib.sha256(str(dataset).encode("utf-8")).hexdigest()[:12]
        reserved = re.fullmatch(r"CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]", dataset_id, re.IGNORECASE)
        safe = re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", dataset_id) and not reserved and len(dataset_id) <= 100
        folder = dataset_id if safe else "dataset_" + hashlib.sha256(dataset_id.encode("utf-8")).hexdigest()[:12]
        self.stage = "dataset_builder"
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
        job_id = f"{stamp}_{self.stage}_{uuid.uuid4().hex[:8]}"
        root = Path(run_root).resolve() if run_root is not None else PROJECT_ROOT / "_local/runs"
        if root.is_relative_to(dataset):
            raise PipelineError("Task records root must be outside the scientific dataset")
        # Reject unrecordable parameters before creating a task directory.
        json.dumps(parameters, ensure_ascii=False, allow_nan=False)
        self.task = parameters.get("task", "")
        self.directory = root / folder / job_id
        self.directory.mkdir(parents=True, exist_ok=False)
        for name in ("configs", "logs", "reports"):
            (self.directory / name).mkdir()
        config_file = self.directory / "configs/build.json"
        _write_json(config_file, parameters)
        self.record = {
            "schema_version": "toolkit-run-v1", "dataset_id": dataset_id, "dataset_folder": folder, "dataset_root": str(dataset),
            "job_id": job_id, "stage": self.stage, "status": "running", "started_utc": _utc(),
            "updated_utc": _utc(), "finished_utc": "", "config_file": "configs/build.json",
            "config_file_sha256": file_reference(config_file)["file_sha256"],
            "work_directory": f"work/{self.stage}",
            "inputs": [file_reference(path) for path in (descriptor, dataset / "manifests/graphs.jsonl",
                       dataset / "manifests/metrics.jsonl", *inputs)], "outputs": {}, "summary": {},
        }
        _write_json(self.directory / "run.json", self.record)

    def __enter__(self) -> RunWorkspace:
        self.event({"event": "started", "task": self.task})
        return self

    def work(self) -> Path:
        path = self.directory / self.record["work_directory"]
        path.mkdir(parents=True, exist_ok=True)
        return path

    def event(self, value: dict) -> None:
        row = {"timestamp_utc": _utc(), **value}
        with (self.directory / f"logs/{self.stage}.jsonl").open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(row, ensure_ascii=False, allow_nan=False) + "\n")

    def result(self, outputs: dict, summary: dict | None = None) -> None:
        self.record["outputs"] = outputs
        self.record["summary"] = summary or {}

    def __exit__(self, exc_type, exc, traceback) -> bool:
        self.record["status"] = "failed" if exc is not None else "complete"
        self.record["finished_utc"] = self.record["updated_utc"] = _utc()
        try:
            if exc is not None:
                error = {"type": exc_type.__name__, "message": str(exc)}
                (self.directory / "failures").mkdir(exist_ok=True)
                _write_json(self.directory / "failures/error.json", error)
                self.record["error"] = error
            self.event({"event": "finished", "status": self.record["status"]})
            _write_json(self.directory / f"reports/{self.stage}.json", self.record)
            _write_json(self.directory / "run.json", self.record)
        except Exception as recording_error:
            message = f"Task evidence could not be finalized at {self.directory}: {recording_error}"
            if exc is None:
                raise PipelineError(message) from recording_error
            exc.add_note(message)
        return False
