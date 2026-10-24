# Validation and evidence boundaries

The repository keeps interface checks, scientific production, and research conclusions separate.

## Small checks included here

- MATLAB graph-builder self-tests and model-boundary checks.
- Five small graph-v1 interoperability fixtures under `code/graph_builder/examples/schema_v1/`.
- Metric registry and result-fixture checks under `code/graph_analyzer/`.
- Python unit tests for selection, projection, splitting, caching, and source identity under `code/dataset_builder/tests/`.

## Typical Python check

```powershell
Push-Location code
try {
    ..\.venv\Scripts\python.exe -m pytest dataset_builder/tests -q -p no:cacheprovider
} finally {
    Pop-Location
}
```

Use a fresh environment and the requirements file before running the command. The exact MATLAB entry points are documented by each module README.

## What a check does not prove

A passing fixture or smoke check does not prove that a large dataset was generated, that all attack labels exist, that a training cache is scientifically complete, or that a model reaches a paper-level result. Those claims require a separately recorded dataset, configuration, run status, and measured result.
