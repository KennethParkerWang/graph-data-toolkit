"""Verify task1 handoff graphs -> task2 MATLAB results using SciPy, read only."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat

from check_result_roundtrip import records


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    report = json.loads((root / 'validation/graph_adapter_report.json').read_text(encoding='utf-8'))
    base, source = root / report['fixture_root'], root / report['input_fixture_root']
    graph_records = [json.loads(x) for x in (base / 'manifests/graphs.jsonl').read_text(encoding='utf-8').splitlines() if x]
    outputs = {r['graph_id']: r for r in report['records']}
    checks = 0
    for row in graph_records:
        original, copied = source / row['path'], base / row['path']
        assert hashlib.sha256(original.read_bytes()).hexdigest() == row['file_sha256']
        assert copied.read_bytes() == original.read_bytes()
        graph = loadmat(copied, simplify_cells=True)
        assert hashlib.sha256(graph['meta']['recipe_json'].encode('utf-8')).hexdigest() == graph['graph_id']
        edge_list = np.asarray(graph['edge_list']).reshape(-1, 2)
        n, m = int(graph['N']), int(graph['M'])
        text = f"topology-v1\n{n}\n{int(graph['directed'])}\n{m}\n" + ''.join(f'{int(u)},{int(v)}\n' for u, v in edge_list)
        assert hashlib.sha256(text.encode('utf-8')).hexdigest() == graph['topology_hash']
        output_record = outputs[row['graph_id']]
        result_path = base / output_record['path']
        assert hashlib.sha256(result_path.read_bytes()).hexdigest() == output_record['file_sha256']
        output = loadmat(result_path, simplify_cells=True)['output']
        for key in ('graph_id', 'topology_hash', 'origin_graph_id'):
            assert output[key] == graph[key] == row[key]
        for id_key, json_key in [('run_id', 'run_identity_json'), ('metric_set_id', 'metric_set_identity_json')]:
            assert hashlib.sha256(output[json_key].encode('utf-8')).hexdigest() == output[id_key]
        observations = {r['metric_id']: r for r in records(output['results'])}
        assert observations['node_count']['values'] == n
        assert observations['edge_count']['values'] == m
        assert observations['node_count']['valid_mask']
        assert observations['edge_count']['valid_mask']
        degree = np.atleast_1d(observations['degree']['values'])
        assert len(degree) == n and degree.sum() == 2 * m
        checks += 15
    assert len(graph_records) == 5
    result = {'passed': True, 'checks': checks, 'handoff_graphs': len(graph_records),
              'fixture_root': report['fixture_root'], 'original_graph_files_unchanged': True}
    (root / 'validation/python_graph_adapter_report.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2, ensure_ascii=True))


if __name__ == '__main__':
    main()
