"""Run from the project root: python code/run_dataset_builder.py --help."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

from .models import PipelineError
from .source import PROJECT_ROOT, SCHEMA_PATHS, read_json_object


def main(argv: list[str] | None = None) -> int:
    # Keep dataset paths readable through Windows pipes as well as UTF-8 terminals.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="ID-validated graph/metric loading and derived training caches")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("contract-status", help="List the actual formal schema publications")
    split = sub.add_parser("split", help="Publish an immutable group split from explicit rules")
    split.add_argument("dataset", type=Path)
    split.add_argument("--config", type=Path, required=True)
    validate = sub.add_parser("validate", help="Read and validate selected source data")
    validate.add_argument("dataset", type=Path)
    validate.add_argument("--selection", type=Path, required=True)
    convert = sub.add_parser("convert", help="Build shards under datasets/<id>/training/<cache_id>")
    convert.add_argument("dataset", type=Path)
    convert.add_argument("--selection", type=Path, required=True)
    convert.add_argument("--split", type=Path, required=True)
    convert.add_argument("--normalization", choices=("none", "standardize"), required=True)
    convert.add_argument("--shard-size", type=int, required=True)
    convert.add_argument("--compression", choices=("none", "lzf", "gzip"), required=True)
    convert.add_argument("--gzip-level", type=int, choices=range(10), default=1)
    smoke = sub.add_parser("framework-smoke", help="Independent in-memory fixtures; does not claim producer MAT compatibility")
    smoke.add_argument("--output", type=Path, required=True)
    smoke.add_argument("--workers", type=int, default=2)
    for command in (split, validate, convert):
        command.add_argument("--run-root", type=Path, help="Task records root (default: _local/runs)")
    args = parser.parse_args(argv)
    try:
        if args.command == "contract-status":
            result = {}
            for kind, relative in SCHEMA_PATHS.items():
                path = PROJECT_ROOT / relative
                result[kind] = {"path": str(path), "published": path.is_file()}
                if path.is_file():
                    result[kind]["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0 if all(item["published"] for item in result.values()) else 2
        if args.command == "framework-smoke":
            from .smoke import run_framework_smoke
            result = run_framework_smoke(args.output, workers=args.workers)
        else:
            from .pipeline import convert_dataset, create_split, load_selection, validate_dataset
            if args.command == "split":
                result = {"split_manifest": str(create_split(args.dataset, read_json_object(args.config), run_root=args.run_root))}
            elif args.command == "validate":
                result = validate_dataset(args.dataset, load_selection(args.selection), run_root=args.run_root)
            else:
                index = convert_dataset(
                    args.dataset, load_selection(args.selection), args.split,
                    normalization=args.normalization, shard_size=args.shard_size,
                    compression=None if args.compression == "none" else args.compression,
                    compression_opts=args.gzip_level if args.compression == "gzip" else None,
                    run_root=args.run_root,
                )
                result = {"cache_index": str(index)}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (PipelineError, OSError, ImportError) as exc:
        print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
