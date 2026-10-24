"""Validate only task2's MAT-v7 result fixtures; no original graph schema."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat


def text(value: object) -> str:
    return str(value)


def records(value: object) -> list:
    if isinstance(value, dict):
        return [value]
    if isinstance(value, np.ndarray):
        return list(value.flat)
    return list(value) if isinstance(value, list) else []


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    fixtures = root / 'examples' / 'result_fixtures'
    rows = [json.loads(line) for line in (fixtures / 'manifests' / 'metrics.jsonl').read_text(encoding='utf-8').splitlines() if line]
    checks = 0
    statuses: set[str] = set()
    kinds: set[str] = set()

    def check_metrics(items: object) -> None:
        nonlocal checks
        for item in records(items):
            values = np.asarray(item['values'])
            mask = np.asarray(item['valid_mask'])
            assert values.shape == mask.shape, item['metric_id']
            assert np.all(np.isin(mask, [0, 1]))
            statuses.add(text(item['status']))
            kinds.add(text(item['scope']))
            assert np.all(~np.isnan(values[mask.astype(bool)]))
            checks += 3

    for row in rows:
        path = fixtures / row['path']
        assert path.stat().st_size == row['file_bytes']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == row['file_sha256']
        raw = loadmat(path, simplify_cells=True)
        assert 'output' in raw and 'A' not in raw
        o = raw['output']
        assert o['schema_version'] == 'metric-v1'
        for key in ('graph_id', 'topology_hash', 'metric_set_id', 'run_id', 'status'):
            assert o[key] == row[key]
        for id_field, json_field in [('metric_set_id', 'metric_set_identity_json'), ('run_id', 'run_identity_json')]:
            assert hashlib.sha256(o[json_field].encode('utf-8')).hexdigest() == o[id_field]
        checks += 11
        check_metrics(o['results'])
        check_metrics(o['summaries'])
        if isinstance(o['attack'], dict) and 'states' in o['attack']:
            attack = o['attack']
            states = records(attack['states'])
            removed = [int(state['removed_count']) for state in states]
            assert removed == list(range(attack['target_count'] + 1))
            for state in states:
                check_metrics(state['metrics'])
                assert len(np.atleast_1d(state['remaining_node_ids'])) == state['node_count']
                assert len(np.atleast_1d(state['remaining_edge_ids'])) == state['edge_count']
                checks += 2
            for sample in records(attack['sampled']):
                state = states[int(sample['state_index']) - 1]
                assert sample['actual_removed_count'] == state['removed_count']
                checks += 1
    assert {'graph', 'node', 'edge', 'matrix', 'distribution', 'trajectory'} <= kinds
    assert 'undefined' in statuses and 'ok' in statuses
    report = {'passed': True, 'result_files': len(rows), 'checks': checks, 'scopes': sorted(kinds), 'statuses': sorted(statuses), 'numpy': np.__version__}
    (root / 'validation' / 'python_roundtrip_report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
