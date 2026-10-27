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


_MIGRATION_RECORDS = None


def _migration_records():
    """Return the reviewed migration paths and digests."""
    global _MIGRATION_RECORDS
    if _MIGRATION_RECORDS is not None:
        return _MIGRATION_RECORDS
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_migration_records'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _MIGRATION_RECORDS = json.loads(result.stdout)
    return _MIGRATION_RECORDS


def _ensure_migration():
    """Bind this checker's migration path and digest."""
    global MIGRATION, MIGRATION_SHA256
    if 'MIGRATION' in globals() and MIGRATION is not None:
        return
    record = _migration_records()['render']
    MIGRATION = record['path']
    MIGRATION_SHA256 = record['sha']

_PATHS = None


def _paths():
    """Return the render-actor module and bound tests."""
    global _PATHS
    if _PATHS is not None:
        return _PATHS
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_render_actor_paths'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _PATHS = json.loads(result.stdout)
    return _PATHS


def _actor_modules():
    return tuple(_paths()['modules'])


def _actor_tests():
    return tuple(_paths()['tests'])


def __getattr__(name):
    if name in ('MIGRATION', 'MIGRATION_SHA256'):
        _ensure_migration()
        return MIGRATION if name == 'MIGRATION' else MIGRATION_SHA256
    if name == 'MODULES':
        return _actor_modules()
    if name == 'TESTS':
        return _actor_tests()
    if name == 'PROTECTED_INPUTS':
        _ensure_migration()
        return (MIGRATION, *_actor_modules(), *_actor_tests())
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')


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



_CONTRACT_PREFIXES = None


def _contract_prefixes():
    """Return the reviewed contract prefixes."""
    global _CONTRACT_PREFIXES
    if _CONTRACT_PREFIXES is not None:
        return _CONTRACT_PREFIXES
    import json
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_contract_prefixes'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _CONTRACT_PREFIXES = json.loads(result.stdout)
    return _CONTRACT_PREFIXES


def require(value, message):
    if not value:
        raise ValueError(_contract_prefixes()['render'] + message)


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
    _gate_bytes_all([(payload, digest, token, label)])


def _gate_bytes_all(items):
    """Require every file digest, in order."""
    if not items:
        return
    import json
    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory(prefix='render-actor-bytes-') as directory:
        folder = Path(directory)
        rows = []
        for index, (payload, digest, token, label) in enumerate(items):
            name = str(index)
            (folder / name).write_bytes(payload)
            row = {'name': name, 'sha': digest, 'label': label}
            if token is not None:
                row['token'] = token
            rows.append(row)
        (folder / 'labels.json').write_text(json.dumps(rows, separators=(',', ':')))
        _run(['--bytes-all', str(folder)])


def _merged_edge(path, edge):
    """Return `edge` with `path` written first."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps({'path': path, 'edge': edge}, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='render-actor-edge-') as directory:
        record = Path(directory) / 'edge.json'
        record.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_merged_edge',
             str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


_RENDER_MESSAGES = None


def _render_messages():
    """Return the render-actor consumer and test messages."""
    global _RENDER_MESSAGES
    if _RENDER_MESSAGES is not None:
        return _RENDER_MESSAGES
    import json
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo,
         'carla_bound_consumer_messages'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _RENDER_MESSAGES = json.loads(result.stdout)
    return _RENDER_MESSAGES


def verify(root, *, _operation=None):
    """Verify live ledger endpoints; return the original historical edges.

    Root contracts compose these descriptors with the ledger exactly once.
    """
    if _operation is not None:
        _check_operation(root, _operation)
    _ensure_migration()
    raw = _typed_source.historical_bytes(root, MIGRATION, _observe_bytes(root, MIGRATION, (root/MIGRATION).read_bytes(),
                         _operation=_operation), _operation=_operation)
    _gate_record(raw)
    record = json.loads(raw, object_pairs_hook=source.unique_keys)
    edges = {}
    checked = []
    for path in _actor_modules():
        edge = record['edges'][path]
        current = ledger.endpoint(root, path, edge, _operation=_operation)
        actual = _typed_source.historical_bytes(root, path, _observe_bytes(root, path, (root/path).read_bytes(),
                                _operation=_operation), _operation=_operation)
        checked.append((
            path, edge, actual, current['after_sha256'], current['after_token_sha256'],
            _render_messages()['render_consumer'] + path))
    _gate_bytes_all([
        (actual, digest, token, label)
        for _path, _edge, actual, digest, token, label in checked])
    for path, edge, _actual, _digest, _token, _label in checked:
        edges[path] = _merged_edge(path, edge)
    tests = []
    for path, expected in record['correctness_tests'].items():
        tests.append((_typed_source.historical_bytes(root, path, _observe_bytes(root, path, (root/path).read_bytes(),
                                             _operation=_operation), _operation=_operation),
                      expected, None, _render_messages()['render_test'] + path))
    _gate_bytes_all(tests)
    return edges
