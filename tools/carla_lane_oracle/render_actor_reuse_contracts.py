# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""One exact #306 render-resource consumer edge, never arbitrary repinning.

The border-parser and winner-sign records pin this Map consumer as an
unchanged live input. This record admits one reviewed edge: its historical
digest before, and its exact source and token digests after. The bound
correctness tests must also be unchanged. Any other consumer change still
fails closed in both records.
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

MIGRATION = 'tools/carla_lane_oracle/render-actor-reuse-successor.json'
MIGRATION_SHA256 = 'c4d146fe145289a1ad443956d2941d1e90186d448b8056f8be97d72f4f672771'
MODULES = ('extensions/carla/render_actors.mojo',)
TESTS = ('tests/test_carla_render_reuse.mojo', 'tests/test_carla_model_cache.mojo',
         'tests/test_carla_walker_render_motion.mojo')
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
        raise ValueError('reviewed render actor reuse successor: ' + message)


def _run(arguments):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_render_actor_gate', *arguments],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_record(payload):
    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory(prefix='render-actor-gate-') as directory:
        record = Path(directory) / 'migration.json'
        record.write_bytes(payload)
        _run(['--migration', str(record)])


def _gate_bytes(payload, digest, token, label):
    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory(prefix='render-actor-gate-') as directory:
        target = Path(directory) / 'payload'
        target.write_bytes(payload)
        arguments = ['--bytes', str(target), '--sha', digest, '--label', label]
        if token is not None:
            arguments.extend(['--token', token])
        _run(arguments)


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
    edges = {}
    for path in MODULES:
        edge = record['edges'][path]
        current = ledger.endpoint(root, path, edge, _operation=_operation)
        actual = _typed_source.historical_bytes(root, path, _observe_bytes(root, path, (root/path).read_bytes(),
                                _operation=_operation), _operation=_operation)
        _gate_bytes(actual, current['after_sha256'], current['after_token_sha256'],
                    'unreviewed render actor consumer: ' + path)
        edges[path] = {'path': path, **edge}
    for path, expected in record['correctness_tests'].items():
        _gate_bytes(_typed_source.historical_bytes(root, path, _observe_bytes(root, path, (root/path).read_bytes(),
                                             _operation=_operation), _operation=_operation),
                    expected, None, 'bound render actor test changed: ' + path)
    return edges
