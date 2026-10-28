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
    record = _migration_records()['runtime']
    MIGRATION = record['path']
    MIGRATION_SHA256 = record['sha']

_BOUND_TESTS = None
_MODULES = None


def _modules():
    """Return the four runtime-boundary module paths in reviewed order."""
    global _MODULES
    if _MODULES is not None:
        return _MODULES
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_runtime_boundary_modules'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _MODULES = tuple(json.loads(result.stdout))
    return _MODULES


def _bound_tests():
    """Return the bound tests and the compile-fail fixtures."""
    global _BOUND_TESTS
    if _BOUND_TESTS is not None:
        return _BOUND_TESTS
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_runtime_boundary_tests'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _BOUND_TESTS = json.loads(result.stdout)
    return _BOUND_TESTS


def _protected_bundle():
    """Read the runtime migration record, then the modules and tests."""
    global MIGRATION, MIGRATION_SHA256, _MODULES, _BOUND_TESTS
    if ('MIGRATION' in globals() and MIGRATION is not None
            and _MODULES is not None and _BOUND_TESTS is not None):
        return
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo,
         'carla_runtime_boundary_gate', '--protected-bundle'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    if 'MIGRATION' not in globals() or MIGRATION is None:
        MIGRATION = parsed['migration']['path']
        MIGRATION_SHA256 = parsed['migration']['sha']
    if _MODULES is None:
        _MODULES = tuple(parsed['modules'])
    if _BOUND_TESTS is None:
        _BOUND_TESTS = parsed['tests']


def __getattr__(name):
    if name in ('MIGRATION', 'MIGRATION_SHA256'):
        _ensure_migration()
        return MIGRATION if name == 'MIGRATION' else MIGRATION_SHA256
    if name == 'MODULES':
        return _modules()
    if name == 'TESTS':
        return tuple(_bound_tests()['tests'])
    if name == 'FIXTURES':
        return tuple(_bound_tests()['fixtures'])
    if name == 'PROTECTED_INPUTS':
        _protected_bundle()
        return (MIGRATION, *_MODULES, *_BOUND_TESTS['tests'])
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
        raise ValueError(_contract_prefixes()['runtime'] + message)


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
    _gate_bytes_all([(payload, digest, token, label)])


def _gate_bytes_all(items):
    """Require every file digest, in order."""
    if not items:
        return
    import json
    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory(prefix='runtime-boundary-bytes-') as directory:
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


def _gate_steps(names):
    import json
    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory(prefix='boundary-steps-') as directory:
        folder = Path(directory)
        (folder / 'labels.json').write_text(json.dumps(list(names)))
        _run(['--steps', str(folder)])


def _extended_query(payload):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='runtime-edge-') as directory:
        record = Path(directory) / 'edge.json'
        record.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_runtime_edge',
             str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _extended_edge(path, edge, steps):
    return _extended_query({'path': path, 'edge': edge, 'steps': steps})


def _edges_after_steps(steps, edges):
    """Check the view steps, then the module paths, then the extensions."""
    import ast
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps(
        {'steps': steps, 'edges': edges}, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='runtime-after-steps-') as directory:
        path = Path(directory) / 'edges.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_runtime_boundary_gate', '--after-steps', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = 'KeyError: '
        if message.startswith(prefix):
            raise KeyError(ast.literal_eval(message[len(prefix):])) from None
        raise ValueError(message)
    return json.loads(result.stdout)


def _extended_edges(items, steps):
    """Decide every edge and require each extension to meet that edge."""
    if not items:
        return []
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps({
        'steps': steps,
        'items': [{'path': path, 'edge': edge} for path, edge in items],
    }, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='runtime-extended-') as directory:
        path = Path(directory) / 'edges.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_runtime_boundary_gate', '--extended', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _merged_query(payload):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='merged-edge-') as directory:
        record = Path(directory) / 'edge.json'
        record.write_text(text)
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


def _merged_edges(items):
    """Return each edge with its path written first."""
    if not items:
        return []
    return _merged_query([
        {'path': path, 'edge': edge} for path, edge in items])


def _checked_edges(items):
    """Check every file digest, then write each path on its edge."""
    if not items:
        return []
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='runtime-boundary-checked-') as directory:
        folder = Path(directory)
        rows = []
        for index, (path, edge, payload, digest, token, label) in enumerate(items):
            name = str(index)
            (folder / name).write_bytes(payload)
            row = {
                'name': name, 'sha': digest, 'label': label,
                'path': path, 'edge': edge,
            }
            if token is not None:
                row['token'] = token
            rows.append(row)
        (folder / 'labels.json').write_text(json.dumps(rows, separators=(',', ':')))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_runtime_boundary_gate', '--checked-edges', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _checked_edges_with_messages(items):
    """Read the consumer messages, then check every file digest."""
    global _RUNTIME_MESSAGES
    if not items:
        return []
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='runtime-boundary-labeled-') as directory:
        folder = Path(directory)
        rows = []
        for index, (path, edge, payload, digest, token) in enumerate(items):
            name = str(index)
            (folder / name).write_bytes(payload)
            row = {
                'name': name, 'sha': digest, 'path': path, 'edge': edge,
            }
            if token is not None:
                row['token'] = token
            rows.append(row)
        (folder / 'labels.json').write_text(json.dumps(rows, separators=(',', ':')))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_runtime_boundary_gate', '--checked-labeled', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    if _RUNTIME_MESSAGES is None:
        _RUNTIME_MESSAGES = parsed['messages']
    return parsed['edges']


_RUNTIME_MESSAGES = None


def _runtime_messages():
    """Return the runtime-boundary consumer and test messages."""
    global _RUNTIME_MESSAGES
    if _RUNTIME_MESSAGES is not None:
        return _RUNTIME_MESSAGES
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
    _RUNTIME_MESSAGES = json.loads(result.stdout)
    return _RUNTIME_MESSAGES


def _live_endpoints(root, pairs, *, _operation=None):
    """Return each live endpoint from one ledger verification."""
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    try:
        full_audit._operation_check(_operation, root)
        chains = ledger.verify(root, _operation=_operation)
        results = []
        for path, edge in pairs:
            if path in chains:
                results.append(ledger._join(edge, chains[path]))
            else:
                results.append(edge)
        return results
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError) as error:
        if _operation is not None:
            full_audit._operation_fail(_operation, error)
        raise


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
    if __package__:
        from . import runtime_view_contracts as view
    else:
        import runtime_view_contracts as view
    steps = view.steps(root, _operation=_operation)
    parsed = _edges_after_steps(steps, record['edges'])
    pairs = [(path, record['edges'][path]) for path in parsed['modules']]
    decisions = parsed['decisions']
    prepared = []
    for (path, edge), decision in zip(pairs, decisions):
        if decision['extend']:
            # The extension was checked against the original edge.
            edge = decision['edge']
        prepared.append((path, edge))
    currents = _live_endpoints(root, prepared, _operation=_operation)
    edges = {}
    checked = []
    for (path, edge), current in zip(prepared, currents):
        actual = _typed_source.historical_bytes(root, path, _observe_bytes(root, path, (root/path).read_bytes(),
                                _operation=_operation), _operation=_operation)
        checked.append((
            path, edge, actual, current['after_sha256'], current['after_token_sha256']))
    merged = _checked_edges_with_messages(checked)
    for (path, _edge, _actual, _digest, _token, _label), edge in zip(checked, merged):
        edges[path] = edge
    tests = []
    for path, expected in record['correctness_tests'].items():
        tests.append((_typed_source.historical_bytes(root, path, _observe_bytes(root, path, (root/path).read_bytes(),
                                             _operation=_operation), _operation=_operation),
                      expected, None, _runtime_messages()['runtime_test'] + path))
    _gate_bytes_all(tests)
    return edges
