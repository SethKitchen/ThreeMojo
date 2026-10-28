# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Narrow source successor for reviewed CARLA control-flow cleanups.

The retained migration records describe their historical sources. This record
binds exactly three successors and preserves every other dependency. Source
integrity does not establish native behavior, coverage, or floating-point mode.
"""
if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

# #333 explicit historical provenance views; current inputs remain operation-owned.
import json

if __package__:
    from . import source_contracts as source
    from . import frozen_arc_producer_contracts as frozen
    from . import coverage_invariant_contracts as invariant
else:
    import source_contracts as source
    import frozen_arc_producer_contracts as frozen
    import coverage_invariant_contracts as invariant
if __package__:
    from . import cache_key_contracts as cache_key
else:
    import cache_key_contracts as cache_key


if __package__:
    from . import accepted_successor_contracts as accepted
else:
    import accepted_successor_contracts as accepted


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
    record = _migration_records()['cleanup']
    MIGRATION = record['path']
    MIGRATION_SHA256 = record['sha']

# A fixture that invokes the protected guard must carry its complete inputs.
_CLEANUP_PATHS = None


def _cleanup_paths():
    """Return the successor paths and the premise paths."""
    global _CLEANUP_PATHS
    if _CLEANUP_PATHS is not None:
        return _CLEANUP_PATHS
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_paths'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _CLEANUP_PATHS = json.loads(result.stdout)
    return _CLEANUP_PATHS


def _ensure_paths():
    """Bind the successor and premise paths before a source read."""
    global SOURCE_PATHS, PREMISE_PATHS
    data = _cleanup_paths()
    SOURCE_PATHS = tuple(data['sources'])
    PREMISE_PATHS = tuple(data['premises'])


_PROTECTED_TAIL = None


def _protected_tail():
    """Return the protected inputs that follow the invariant closure."""
    global _PROTECTED_TAIL
    if _PROTECTED_TAIL is not None:
        return _PROTECTED_TAIL
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_protected'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _PROTECTED_TAIL = tuple(json.loads(result.stdout))
    return _PROTECTED_TAIL


def _records_then_tail():
    """Read the companion record paths, then the protected tail."""
    global _RECORD_PATHS, _PROTECTED_TAIL
    if _RECORD_PATHS is not None and _PROTECTED_TAIL is not None:
        return
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
         '--records-tail'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    if _RECORD_PATHS is None:
        _RECORD_PATHS = parsed['records']
    if _PROTECTED_TAIL is None:
        _PROTECTED_TAIL = tuple(parsed['tail'])


def _protected_bundle():
    """Read the cleanup paths and the migration record, then the tail."""
    global _CLEANUP_PATHS, MIGRATION, MIGRATION_SHA256
    global SOURCE_PATHS, PREMISE_PATHS, _RECORD_PATHS, _PROTECTED_TAIL
    if (_CLEANUP_PATHS is not None
            and 'MIGRATION' in globals() and MIGRATION is not None
            and _RECORD_PATHS is not None and _PROTECTED_TAIL is not None):
        SOURCE_PATHS = tuple(_CLEANUP_PATHS['sources'])
        PREMISE_PATHS = tuple(_CLEANUP_PATHS['premises'])
        return
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
         '--protected-bundle'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    if _CLEANUP_PATHS is None:
        _CLEANUP_PATHS = parsed['paths']
    SOURCE_PATHS = tuple(_CLEANUP_PATHS['sources'])
    PREMISE_PATHS = tuple(_CLEANUP_PATHS['premises'])
    if 'MIGRATION' not in globals() or MIGRATION is None:
        MIGRATION = parsed['migration']['path']
        MIGRATION_SHA256 = parsed['migration']['sha']
    if _RECORD_PATHS is None:
        _RECORD_PATHS = parsed['records']
    if _PROTECTED_TAIL is None:
        _PROTECTED_TAIL = tuple(parsed['tail'])


def _composed_ready():
    return (_CLEANUP_PATHS is not None
            and 'MIGRATION' in globals() and MIGRATION is not None
            and _RECORD_PATHS is not None and _PROTECTED_TAIL is not None
            and frozen._PATHS is not None
            and 'MIGRATION' in frozen.__dict__ and frozen.MIGRATION is not None
            and 'MIGRATION' in invariant.__dict__
            and invariant.MIGRATION is not None
            and invariant._PROTECTED_TAIL is not None
            and 'MIGRATION' in invariant.curve.__dict__
            and invariant.curve.MIGRATION is not None
            and invariant.curve._PATHS is not None)


def _composed_inputs():
    """Read the cleanup bundle, then the frozen and invariant inputs."""
    global _CLEANUP_PATHS, MIGRATION, MIGRATION_SHA256
    global SOURCE_PATHS, PREMISE_PATHS, _RECORD_PATHS, _PROTECTED_TAIL
    if _composed_ready():
        SOURCE_PATHS = tuple(_CLEANUP_PATHS['sources'])
        PREMISE_PATHS = tuple(_CLEANUP_PATHS['premises'])
        return
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
         '--composed-inputs'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    cleanup = parsed['cleanup']
    if _CLEANUP_PATHS is None:
        _CLEANUP_PATHS = cleanup['paths']
    SOURCE_PATHS = tuple(_CLEANUP_PATHS['sources'])
    PREMISE_PATHS = tuple(_CLEANUP_PATHS['premises'])
    if 'MIGRATION' not in globals() or MIGRATION is None:
        MIGRATION = cleanup['migration']['path']
        MIGRATION_SHA256 = cleanup['migration']['sha']
    if _RECORD_PATHS is None:
        _RECORD_PATHS = cleanup['records']
    if _PROTECTED_TAIL is None:
        _PROTECTED_TAIL = tuple(cleanup['tail'])
    frozen_part = parsed['frozen']
    if frozen._PATHS is None:
        frozen._PATHS = frozen_part['paths']
    frozen.SOURCE_PATH = frozen._PATHS['source']
    if 'MIGRATION' not in frozen.__dict__ or frozen.MIGRATION is None:
        frozen.MIGRATION = frozen_part['migration']['path']
        frozen.MIGRATION_SHA256 = frozen_part['migration']['sha']
    inv = parsed['invariant']
    if 'MIGRATION' not in invariant.__dict__ or invariant.MIGRATION is None:
        invariant.MIGRATION = inv['invariant']['path']
        invariant.MIGRATION_SHA256 = inv['invariant']['sha']
    curve = invariant.curve
    if 'MIGRATION' not in curve.__dict__ or curve.MIGRATION is None:
        curve.MIGRATION = inv['dispatch']['path']
        curve.MIGRATION_SHA256 = inv['dispatch']['sha']
    if curve._PATHS is None:
        curve._PATHS = inv['paths']
    if invariant._PROTECTED_TAIL is None:
        invariant._PROTECTED_TAIL = tuple(inv['tail'])


def _protected_inputs():
    """Return the protected inputs, including the Mojo path tables."""
    _composed_inputs()
    return (*cache_key.PROTECTED_INPUTS, *accepted.PROTECTED_INPUTS, MIGRATION, _RECORD_PATHS['runtime_pins'],
            *SOURCE_PATHS, *PREMISE_PATHS, *frozen.PROTECTED_INPUTS,
            *invariant.PROTECTED_INPUTS, *_PROTECTED_TAIL)


def __getattr__(name):
    if name in ('MIGRATION', 'MIGRATION_SHA256'):
        _ensure_migration()
        return MIGRATION if name == 'MIGRATION' else MIGRATION_SHA256
    if name == 'SOURCE_PATHS':
        _ensure_paths()
        return SOURCE_PATHS
    if name == 'PREMISE_PATHS':
        _ensure_paths()
        return PREMISE_PATHS
    if name == 'PROTECTED_INPUTS':
        return _protected_inputs()
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


def require(condition, message):
    if not condition:
        raise ValueError(_contract_prefixes()['cleanup'] + message)


def _gate(migration, previous=None):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='cleanup-gate-') as directory:
        folder = Path(directory)
        record = folder / 'migration.json'
        record.write_bytes(migration)
        arguments = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                     'carla_cleanup_gate', '--migration', str(record)]
        if previous is not None:
            previous_path = folder / 'previous.json'
            previous_path.write_bytes(previous)
            arguments.extend(['--previous', str(previous_path)])
        result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _tokens_or_restore(rows):
    """Check the junction digest, then every successor token when it matches."""
    if not rows:
        return {'restore': False}
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(rows, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='cleanup-token-restore-') as directory:
        path = Path(directory) / 'tokens.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--tokens-or-restore', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _gate_tokens(pairs):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='cleanup-tokens-') as directory:
        folder = Path(directory)
        labels = []
        for index, (text, token, label) in enumerate(pairs):
            (folder / f'{index}.text').write_text(text)
            labels.append({'label': label, 'token': token})
        (folder / 'labels.json').write_text(json.dumps(labels))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--tokens', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _sha256(payload):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='cleanup-sha-') as directory:
        target = Path(directory) / 'payload'
        target.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--sha-of', str(target)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout.strip()


def _gate_digest(payload, expected):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='cleanup-digest-') as directory:
        target = Path(directory) / 'guard'
        target.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--bytes', str(target), '--sha', expected],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _declarations_after_digest(payload, expected):
    """Check the guard-pin digest, then return the declaration catalog."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='cleanup-catalog-digest-') as directory:
        path = Path(directory) / 'guard'
        path.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_cleanup_declarations', '--after', str(path),
             '--sha', expected],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


_RECORD_PATHS = None


def _record_paths():
    """Return the companion migration record paths."""
    global _RECORD_PATHS
    if _RECORD_PATHS is not None:
        return _RECORD_PATHS
    import os
    import subprocess
    from pathlib import Path
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


def _paths_after_record(payload):
    """Require the cleanup record, then return the companion paths."""
    global _RECORD_PATHS
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='cleanup-record-paths-') as directory:
        record = Path(directory) / 'migration.json'
        record.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--record-paths', str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    if _RECORD_PATHS is None:
        _RECORD_PATHS = parsed
    return parsed


def read_record(root):
    _ensure_migration()
    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())
    paths = _paths_after_record(payload)
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    previous = root/paths['winner_sign']
    _gate(payload, _typed_source.historical_bytes(root, previous, previous.read_bytes()))
    return record


def _cleanup_premises(texts):
    """Check the five reviewed premise declarations."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='cleanup-premises-') as directory:
        folder = Path(directory)
        (folder / 'sources.json').write_text(json.dumps(texts, separators=(',', ':')))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_cleanup_premises', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _declaration(text, name, owner):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='cleanup-declaration-') as directory:
        source = Path(directory) / 'source.mojo'
        source.write_text(text)
        arguments = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                     'carla_cleanup_gate', '--declaration', str(source),
                     '--name', name]
        for part in owner:
            arguments.extend(['--owner', part])
        result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def _declarations(items):
    """Return the declaration texts in the requested order."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    if not items:
        return []
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(items, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='cleanup-declarations-') as directory:
        path = Path(directory) / 'declarations.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_lane_declarations',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _catalog_then_frozen(texts):
    """Check the premise catalog, then read the frozen migration record."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps({'texts': list(texts)}, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='catalog-frozen-') as directory:
        path = Path(directory) / 'sources.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_premises',
             '--catalog-migration', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    if 'MIGRATION' not in frozen.__dict__ or frozen.MIGRATION is None:
        frozen.MIGRATION = parsed['path']
        frozen.MIGRATION_SHA256 = parsed['sha']


def _catalog_premises(texts):
    """Read the declaration catalog, then check the premise fragments."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps(list(texts), separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='cleanup-catalog-') as directory:
        path = Path(directory) / 'sources.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_premises',
             '--catalog', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _declared_premises(texts, items):
    """Read each premise declaration and check it in one call."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps({
        'sources': list(texts),
        'declarations': [{
            'source': item['source'],
            'name': item['name'],
            'owner': list(item['owner']),
            'key': item['key'],
        } for item in items],
    }, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='cleanup-declared-') as directory:
        path = Path(directory) / 'declared.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_premises',
             '--declared', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def verify_premises(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    _ensure_paths()
    line = _typed_source.historical_text(root, SOURCE_PATHS[0], _observe_text(root, SOURCE_PATHS[0],
                         (root/SOURCE_PATHS[0]).read_text(), _operation=_operation), _operation=_operation)
    arc = _typed_source.historical_text(root, SOURCE_PATHS[1], _observe_text(root, SOURCE_PATHS[1],
                         (root/SOURCE_PATHS[1]).read_text(), _operation=_operation), _operation=_operation)
    junction = _typed_source.historical_text(root, SOURCE_PATHS[2], _observe_text(root, SOURCE_PATHS[2],
                         (root/SOURCE_PATHS[2]).read_text(), _operation=_operation), _operation=_operation)
    texts = (line, arc, junction)
    if _operation is None:
        _catalog_then_frozen(texts)
    else:
        _catalog_premises(texts)



# Only the two explicit reviewed constant sets have a stored-word contract.
# Every other token, including indentation and statement boundaries, stays bound.
_CLEANUP_DECLARATIONS = None


def _cleanup_declarations():
    """Return the cleanup declarations, the junction path, and the label."""
    global _CLEANUP_DECLARATIONS
    if _CLEANUP_DECLARATIONS is not None:
        return _CLEANUP_DECLARATIONS
    import json
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_declarations'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _CLEANUP_DECLARATIONS = json.loads(result.stdout)
    return _CLEANUP_DECLARATIONS


_DEPENDENCY_PINS = None


def _dependency_pins():
    """Return the trig and geometry paths and token digests."""
    global _DEPENDENCY_PINS
    if _DEPENDENCY_PINS is not None:
        return _DEPENDENCY_PINS
    import json
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo,
         'carla_cleanup_dependency_pins'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _DEPENDENCY_PINS = json.loads(result.stdout)
    return _DEPENDENCY_PINS


def _checked_dependency_words(items):
    """Choose every dependency word check, then check the selected words."""
    if not items:
        return
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(items, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='dependency-words-') as directory:
        record = Path(directory) / 'choice.json'
        record.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_dependency_words', '--checked', str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _dependency_fields(path, text, expected, pins):
    return {
        'text': text,
        'expected': expected,
        'path': path,
        'trig_path': pins['trig_path'],
        'trig_token': pins['trig_token'],
        'geometry_path': pins['geometry_path'],
        'geometry_token': pins['geometry_token'],
    }


def _pinned_dependency_words(items):
    """Read the dependency pins, then check the selected words."""
    if not items:
        return
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps([
        {'text': item['text'], 'expected': item['expected'], 'path': item['path']}
        for item in items
    ], separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='pinned-dependency-words-') as directory:
        record = Path(directory) / 'choice.json'
        record.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_dependency_words', '--pinned', str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _words_then_paths(items):
    """Check the pinned dependency words, then read the cleanup paths."""
    global _CLEANUP_PATHS, SOURCE_PATHS, PREMISE_PATHS
    if not items:
        _ensure_paths()
        return
    if _CLEANUP_PATHS is not None:
        _pinned_dependency_words([
            {'text': text, 'expected': expected, 'path': path}
            for path, text, expected in items])
        SOURCE_PATHS = tuple(_CLEANUP_PATHS['sources'])
        PREMISE_PATHS = tuple(_CLEANUP_PATHS['premises'])
        return
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps([
        {'text': text, 'expected': expected, 'path': path}
        for path, text, expected in items
    ], separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='words-paths-') as directory:
        record = Path(directory) / 'choice.json'
        record.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_dependency_words', '--pinned-paths', str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    if _CLEANUP_PATHS is None:
        _CLEANUP_PATHS = json.loads(result.stdout)
    SOURCE_PATHS = tuple(_CLEANUP_PATHS['sources'])
    PREMISE_PATHS = tuple(_CLEANUP_PATHS['premises'])


def verify_dependencies(items):
    """Read the dependency pins, then run the selected word checks."""
    if not items:
        return
    _pinned_dependency_words([
        {'text': text, 'expected': expected, 'path': path}
        for path, text, expected in items])


def verify_dependency(path, text, expected):
    # A fixed whole-module fingerprint admits only equivalent stored words.
    # Historical pins remain unchanged; other dependencies retain exact tokens.
    _pinned_dependency_words([
        {'text': text, 'expected': expected, 'path': path}])


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    operation_args = {} if _operation is None else {'_operation': _operation}
    record = read_record(root)
    _, guard_payload = frozen._verified_pin_pair(root, record['runtime_pins_after_sha256'], **operation_args)
    labels = _declarations_after_digest(
        guard_payload, record['guard_pins_after_sha256'])
    pairs = []
    paths = []
    for path, transition in record['sources'].items():
        text = accepted.predecessor_text(root, path, **operation_args) if path in accepted.SOURCE_PATHS else _typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)
        row = {
            'text': text,
            'token': transition['after_token_sha256'],
            'label': labels['unreviewed'] + path,
        }
        if path == labels['junction']:
            row['restore'] = True
        pairs.append(row)
        paths.append(path)
    if pairs:
        checked = _tokens_or_restore(pairs)
        if checked['restore']:
            index = checked['index']
            path = paths[index]
            try:
                if __package__:
                    from . import full_audit_cleanup_contracts as full_audit
                else:
                    import full_audit_cleanup_contracts as full_audit
                pairs[index]['text'] = full_audit.reviewed_text(
                    root, path, pairs[index]['text'], **operation_args)
            except (ValueError, OSError) as error:
                raise ValueError(
                    _contract_prefixes()['cleanup'] + pairs[index]['label']) from error
            _gate_tokens([
                (item['text'], item['token'], item['label']) for item in pairs])
    dependencies = []
    for path, expected in record['premise_dependencies'].items():
        dependencies.append((path, _typed_source.historical_text(root, path, _observe_text(
            root, path, (root/path).read_text(), _operation=_operation), _operation=_operation),
            expected['token_sha256']))
    if _operation is None:
        _words_then_paths(dependencies)
    else:
        verify_dependencies(dependencies)
    verify_premises(root, **operation_args)
    frozen.verify(
        root,
        _then_invariant_labels=_operation is None,
        **operation_args,
    )
    if _operation is None:
        invariant.verify(root)
    else:
        invariant._verify_owned(root, _operation=_operation)
    return record
