"""Independent NumPy/SciPy checks on small MATLAB repeat-statistics fixtures."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
import scipy
from scipy.io import loadmat
from scipy.stats import t


def check_stats(s: dict) -> int:
    values = np.asarray(s['raw_values'], dtype=float)
    mask = np.asarray(s['raw_valid_mask'], dtype=bool)
    if values.ndim == 1:
        values, mask = values[None, :], mask[None, :]
    options = s['options']
    probs = np.atleast_1d(options['quantile_probabilities'])
    level = float(options['confidence_level'])
    means = np.atleast_1d(s['mean'])
    sds = np.atleast_1d(s['sample_std'])
    quantiles = np.asarray(s['quantiles']).reshape(values.shape[0], len(probs))
    counts = mask.sum(axis=1)
    np.testing.assert_array_equal(np.atleast_1d(s['count_valid']), counts)
    checks = 1
    for i, row in enumerate(values):
        x = row[mask[i]]
        use = len(x) > 0 and (options['missing_policy'] == 'available_case' or len(x) == len(row))
        assert bool(np.atleast_1d(s['mean_valid'])[i]) == use
        if not use:
            assert np.isnan(means[i]) and np.isnan(quantiles[i]).all()
            checks += 3
            continue
        np.testing.assert_allclose(means[i], np.mean(x), atol=1e-12, rtol=1e-12)
        np.testing.assert_allclose(quantiles[i], np.quantile(x, probs, method='linear'), atol=1e-12, rtol=1e-12)
        checks += 3
        if len(x) < 2:
            assert not np.atleast_1d(s['sample_std_valid'])[i]
            assert not np.atleast_1d(s['ci_valid'])[i]
            checks += 2
            continue
        sd = np.std(x, ddof=1)
        np.testing.assert_allclose(sds[i], sd, atol=1e-12, rtol=1e-12)
        checks += 1
        if options['confidence_method'] == 'student_t':
            half = t.ppf((1 + level) / 2, len(x) - 1) * sd / np.sqrt(len(x))
            np.testing.assert_allclose(np.atleast_1d(s['ci_lower'])[i], np.mean(x) - half, atol=1e-9, rtol=1e-10)
            np.testing.assert_allclose(np.atleast_1d(s['ci_upper'])[i], np.mean(x) + half, atol=1e-9, rtol=1e-10)
            checks += 2
    return checks


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    raw = loadmat(root / 'validation/repeat_statistics_reference.mat', simplify_cells=True)
    checks = check_stats(raw['propagate']) + check_stats(raw['available'])
    report = json.loads((root / 'validation/repeat_statistics_test_report.json').read_text(encoding='utf-8'))
    base = root / report['fixture_root']
    record = report['aggregate_record']
    path = base / record['path']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == record['file_sha256']
    a = loadmat(path, simplify_cells=True)['aggregate']
    assert a['schema_version'] == 'repeat-summary-1.0.0'
    assert hashlib.sha256(a['identity_json'].encode('utf-8')).hexdigest() == a['aggregate_id']
    checks += 3 + check_stats(a['statistics'])
    inputs = np.atleast_1d(a['inputs'])
    assert len({item['run_id'] for item in inputs}) == len(inputs)
    assert len({int(item['attack_seed']) for item in inputs}) == len(inputs)
    checks += 2
    for item in inputs:
        assert hashlib.sha256((base / item['path']).read_bytes()).hexdigest() == item['file_sha256']
        checks += 1
    result = {'passed': True, 'checks': checks, 'numpy': np.__version__, 'scipy': scipy.__version__,
              'methods': ['type7 / numpy linear quantile', 'sample SD ddof=1', 'scipy Student t confidence interval'],
              'aggregate_file': str(path)}
    (root / 'validation/python_repeat_statistics_report.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2, ensure_ascii=True))


if __name__ == '__main__':
    main()
