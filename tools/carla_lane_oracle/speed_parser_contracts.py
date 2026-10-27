# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""One exact parser grammar/correctness successor, never arbitrary repinning."""
if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

# #333 explicit historical provenance views; current inputs remain operation-owned.
import json
from pathlib import Path
if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

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
    record = _migration_records()['speed']
    MIGRATION = record['path']
    MIGRATION_SHA256 = record['sha']

_PATHS = None


def _paths():
    """Return the speed-limit module and its two correctness tests."""
    global _PATHS
    if _PATHS is not None:
        return _PATHS
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_speed_parser_paths'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _PATHS = json.loads(result.stdout)
    return _PATHS


def _ensure_paths():
    """Bind the module and tests before a source read."""
    global MODULE, TESTS
    data = _paths()
    MODULE = data['module']
    TESTS = tuple(data['tests'])


def __getattr__(name):
    if name in ('MIGRATION', 'MIGRATION_SHA256'):
        _ensure_migration()
        return MIGRATION if name == 'MIGRATION' else MIGRATION_SHA256
    if name in ('MODULE', 'TESTS', 'PROTECTED_INPUTS'):
        _ensure_paths()
        _ensure_migration()
    if name == 'MODULE':
        return MODULE
    if name == 'TESTS':
        return TESTS
    if name == 'PROTECTED_INPUTS':
        return (MIGRATION, MODULE, *TESTS)
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')


def _check_operation(root, operation):
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    full_audit._operation_check(operation, root)


def _observe_text(root, path, text, *, _operation=None, mode='default'):
    if _operation is None:
        return text
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    return full_audit._observe_text(
        root, path, text, _operation=_operation, mode=mode)



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
        raise ValueError(_contract_prefixes()['speed'] + message)


def _gate(migration, accepted, module, lexical, xml):
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='speed-gate-') as directory:
        folder = Path(directory)
        names = {}
        for name, payload, binary in (
            ('migration', migration, True), ('accepted', accepted, True),
            ('module', module, False), ('lexical', lexical, True),
            ('xml', xml, True),
        ):
            path = folder / name
            if binary:
                path.write_bytes(payload)
            else:
                path.write_text(payload)
            names[name] = str(path)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_speed_gate',
             '--migration', names['migration'], '--accepted', names['accepted'],
             '--module', names['module'], '--lexical', names['lexical'],
             '--xml', names['xml']],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


_RECORD_PATHS = None


def _record_paths():
    """Return the companion migration record paths."""
    global _RECORD_PATHS
    if _RECORD_PATHS is not None:
        return _RECORD_PATHS
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_record_paths'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _RECORD_PATHS = json.loads(result.stdout)
    return _RECORD_PATHS


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    _ensure_paths()
    root = Path(root)
    _ensure_migration()
    raw = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes(), _operation=_operation)
    accepted_path = _record_paths()['accepted']
    accepted = _typed_source.historical_bytes(root, root/accepted_path, (root/accepted_path).read_bytes(), _operation=_operation)
    module = _typed_source.historical_text(root, MODULE, _observe_text(
        root, MODULE, (root/MODULE).read_text(), _operation=_operation), _operation=_operation)
    lexical = _typed_source.historical_bytes(root, root/TESTS[0], (root/TESTS[0]).read_bytes(), _operation=_operation)
    xml = _typed_source.historical_bytes(root, root/TESTS[1], (root/TESTS[1]).read_bytes(), _operation=_operation)
    _gate(raw, accepted, module, lexical, xml)
    return json.loads(raw, object_pairs_hook=source.unique_keys)
