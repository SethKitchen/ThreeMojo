# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Four exact #333 runtime-boundary consumer edges, never arbitrary repinning.

The border-parser and winner-sign records pin these Map consumers as
unchanged live inputs. This record admits one reviewed edge for each: its
historical digest before, and its exact source and token digests after. The
bound correctness tests and compile-fail fixtures must also be unchanged.
The runtime view record can extend an edge by one exact reviewed step; the
composed edge still starts at the historical digest. Any other consumer
change still fails closed in both records.
"""
if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

# #333 explicit historical provenance views; current inputs remain operation-owned.
import json

if __package__:
    from . import source_contracts as source
    from . import consumer_successor_ledger as ledger
else:
    import source_contracts as source
    import consumer_successor_ledger as ledger

MIGRATION = 'tools/carla_lane_oracle/runtime-boundary-successor.json'
MIGRATION_SHA256 = '992854b1191bd365fca3e5e8d3a7fc751ac2eb3196b33684e04ebad833baab00'
MODULES = ('extensions/carla/cameras.mojo', 'extensions/carla/lane_invasion.mojo',
           'extensions/carla/sensor_manager.mojo', 'extensions/carla/world.mojo')
FIXTURES = tuple(f'tests/compile_fail/carla_{name}.mojo' for name in (
    'event_camera_time_rejects_float32_duration', 'event_camera_time_rejects_length',
    'event_camera_time_rejects_raw_float64', 'lane_invasion_time_rejects_float32_duration',
    'lane_invasion_time_rejects_length', 'lane_invasion_time_rejects_raw_float64',
    'light_search_distance_rejects_duration', 'light_search_distance_rejects_float32_length',
    'light_search_distance_rejects_raw_float64'))
TESTS = ('tests/test_carla_sensors.mojo', 'tests/test_carla_sensors_world.mojo',
         'tests/test_carla_world_signals.mojo', *FIXTURES)
PROTECTED_INPUTS = (MIGRATION, *MODULES, *TESTS)


def _check_operation(root, operation):
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    full_audit._operation_check(operation, root)


def _observe_bytes(root, path, payload, *, _operation=None):
    if _operation is None:
        return payload
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    return full_audit._observe_bytes(root, path, payload, _operation=_operation)



def require(value, message):
    if not value:
        raise ValueError('reviewed runtime boundary successor: ' + message)


def _run(arguments):
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_runtime_boundary_gate', *arguments],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_record(payload):
    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory(prefix='runtime-boundary-gate-') as directory:
        record = Path(directory) / 'migration.json'
        record.write_bytes(payload)
        _run(['--migration', str(record)])


def _gate_bytes(payload, digest, token, label):
    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory(prefix='runtime-boundary-gate-') as directory:
        target = Path(directory) / 'payload'
        target.write_bytes(payload)
        arguments = ['--bytes', str(target), '--sha', digest, '--label', label]
        if token is not None:
            arguments.extend(['--token', token])
        _run(arguments)


def _gate_steps(names):
    import json
    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory(prefix='boundary-steps-') as directory:
        folder = Path(directory)
        (folder / 'labels.json').write_text(json.dumps(list(names)))
        _run(['--steps', str(folder)])


def _gate_extend(step, edge, path):
    _run([
        '--extend', '--path', path,
        '--step-sha', step['before_sha256'], '--edge-sha', edge['after_sha256'],
        '--step-token', step['before_token_sha256'],
        '--edge-token', edge['after_token_sha256'],
    ])


def verify(root, *, _operation=None):
    """Verify live ledger endpoints; return the original historical edges.

    Root contracts compose these descriptors with the ledger exactly once.
    """
    if _operation is not None:
        _check_operation(root, _operation)
    raw = _typed_source.historical_bytes(root, MIGRATION, _observe_bytes(root, MIGRATION, (root/MIGRATION).read_bytes(),
                         _operation=_operation), _operation=_operation)
    _gate_record(raw)
    record = json.loads(raw, object_pairs_hook=source.unique_keys)
    if __package__:
        from . import runtime_view_contracts as view
    else:
        import runtime_view_contracts as view
    steps = view.steps(root, _operation=_operation)
    _gate_steps(steps)
    edges = {}
    for path in MODULES:
        edge = record['edges'][path]
        if path in steps:
            # A later reviewed step starts exactly where this edge ends.
            step = steps[path]
            _gate_extend(step, edge, path)
            edge = {**edge, 'after_sha256': step['after_sha256'],
                    'after_token_sha256': step['after_token_sha256']}
        current = ledger.endpoint(root, path, edge, _operation=_operation)
        actual = _typed_source.historical_bytes(root, path, _observe_bytes(root, path, (root/path).read_bytes(),
                                _operation=_operation), _operation=_operation)
        _gate_bytes(actual, current['after_sha256'], current['after_token_sha256'],
                    'unreviewed runtime boundary consumer: ' + path)
        edges[path] = {'path': path, **edge}
    for path, expected in record['correctness_tests'].items():
        _gate_bytes(_typed_source.historical_bytes(root, path, _observe_bytes(root, path, (root/path).read_bytes(),
                                             _operation=_operation), _operation=_operation),
                    expected, None, 'bound runtime boundary test changed: ' + path)
    return edges
