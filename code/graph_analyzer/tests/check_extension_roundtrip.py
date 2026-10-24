"""Check new result-only graph fixtures without defining an original graph format."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat

from check_repeat_statistics import check_stats
from check_result_roundtrip import records


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    base = root / 'examples/extension_result_fixtures'
    rows = [json.loads(x) for x in (base / 'manifests/metrics.jsonl').read_text(encoding='utf-8').splitlines() if x]
    checks = 0
    grids = full_paths = 0
    for row in rows:
        path = base / row['path']
        assert path.stat().st_size == row['file_bytes']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == row['file_sha256']
        o = loadmat(path, simplify_cells=True)['output']
        assert o['run_id'] == row['run_id']
        for id_key, json_key in [('run_id', 'run_identity_json'), ('metric_set_id', 'metric_set_identity_json')]:
            assert hashlib.sha256(o[json_key].encode('utf-8')).hexdigest() == o[id_key]
        checks += 5
        a = o['attack']
        states = records(a['states'])
        actual = np.array([s['removed_count'] for s in states])
        total = int(a['target_count'])
        if a['protocol']['deletion_mode'] == 'fraction_grid':
            grids += 1
            requested = np.atleast_1d(a['protocol']['attack_fractions'])
            q = np.floor(requested * total)
            expected = np.unique(np.r_[0, q])
            np.testing.assert_array_equal(actual, expected)
            schedule = a['schedule']
            np.testing.assert_array_equal(schedule['requested_removed_count'], q)
            np.testing.assert_array_equal(schedule['increment'], np.diff(np.r_[0, q]))
            np.testing.assert_array_equal(schedule['state_index'], np.searchsorted(expected, q) + 1)
            np.testing.assert_allclose(schedule['actual_removed_fraction'], q / total)
            assert not a['full_single_object_trajectory']
            checks += 6
        else:
            full_paths += 1
            np.testing.assert_array_equal(actual, np.arange(total + 1))
            assert a['full_single_object_trajectory']
            checks += 2
        for s in states:
            assert int(s['node_count']) == int(a['original_node_count'])
            assert int(s['edge_count']) == total - int(s['removed_count'])
            observations = records(s['metrics'])
            assert {r['parameters']['component_mode'] for r in observations} == {'weak', 'strong'}
            assert all(r['valid_mask'] for r in observations)
            checks += 4
        for r in records(o['summaries']):
            assert r['status'] == 'ok' and r['valid_mask']
            checks += 1
    summaries = list((base / 'analyses/repeat_statistics').glob('*.mat.json'))
    for sidecar in summaries:
        record = json.loads(sidecar.read_text(encoding='utf-8'))
        path = base / record['path']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == record['file_sha256']
        a = loadmat(path, simplify_cells=True)['aggregate']
        assert hashlib.sha256(a['identity_json'].encode('utf-8')).hexdigest() == a['aggregate_id']
        checks += 2 + check_stats(a['statistics'])
        for item in np.atleast_1d(a['inputs']):
            assert hashlib.sha256((base / item['path']).read_bytes()).hexdigest() == item['file_sha256']
            checks += 1
    assert grids >= 1 and full_paths >= 4 and len(summaries) >= 3
    result = {'passed': True, 'checks': checks, 'raw_run_files': len(rows), 'full_edge_repeats': full_paths,
              'fraction_grid_runs': grids, 'derived_summaries': len(summaries)}
    (root / 'validation/python_extension_roundtrip_report.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
