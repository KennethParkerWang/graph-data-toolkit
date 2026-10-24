# Data sources and provenance

The original workspace contains both generated graphs and downloaded real-network archives. This public release keeps source catalogs and code references, but does not copy the raw archives into Git.

## Synthetic model references

Model-specific source URLs, citations, reference versions, and license notes are recorded in:

- `code/graph_builder/sources/standard/catalog.json`
- `code/graph_builder/sources/standard/source_notes.json`
- `code/graph_builder/sources/author_lou/catalog.json`

The standard NetworkX and CPython reference files that are safe to redistribute remain beside those catalogs. Paper PDFs and author archives with unresolved redistribution terms are omitted; obtain them directly from the URLs recorded in the catalog when source verification requires them.

## Real networks

Real-network downloads are intentionally external because they are large, provider-controlled, or subject to dataset-specific terms. A reproducible acquisition record should include:

1. provider URL and release or commit;
2. original filename and expected byte count;
3. SHA-256 checksum;
4. citation and license or terms;
5. parsing and node-remapping rules;
6. the resulting graph-v1 identity if the source is imported.

The local project used this pattern for single-network and multi-network collections. Recreate that record under a separate dataset archive instead of committing downloaded files to this repository.
