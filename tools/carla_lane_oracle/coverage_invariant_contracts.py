# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Reversible, exact successor for three independently reviewed invariants.

Historical records remain immutable. Current live guarded bodies and protected
use inventories remain checked by the maintained guard. These source checks do
not supply runtime hits, waive required outcomes, or establish a native pass.
"""
if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

# #333 explicit historical provenance views; current inputs remain operation-owned.
import json
if __package__:
    from . import source_contracts as source
    from . import curve_support_dispatch_contracts as curve
    from . import grouped_table_contracts as grouped
else:
    import source_contracts as source
    import curve_support_dispatch_contracts as curve
    import grouped_table_contracts as grouped

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
    record = _migration_records()['invariant']
    MIGRATION = record['path']
    MIGRATION_SHA256 = record['sha']

_SOURCES = None


def _sources():
    """Return the four coverage-invariant source paths in reviewed order."""
    global _SOURCES
    if _SOURCES is not None:
        return _SOURCES
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_invariant_sources'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _SOURCES = tuple(json.loads(result.stdout))
    return _SOURCES


_PROTECTED_TAIL = None


def _protected_tail():
    """Return the protected inputs that follow the dispatch closure."""
    global _PROTECTED_TAIL
    if _PROTECTED_TAIL is not None:
        return _PROTECTED_TAIL
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_invariant_protected'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _PROTECTED_TAIL = tuple(json.loads(result.stdout))
    return _PROTECTED_TAIL


def _dispatch_ready():
    return ('MIGRATION' in curve.__dict__ and curve.MIGRATION is not None
            and curve._PATHS is not None)


def _input_bundle():
    """Read the invariant migration and the dispatch paths, then the tail."""
    global MIGRATION, MIGRATION_SHA256, _PROTECTED_TAIL
    if ('MIGRATION' in globals() and MIGRATION is not None
            and _PROTECTED_TAIL is not None and _dispatch_ready()):
        return
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_invariant_gate',
         '--input-bundle'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    if 'MIGRATION' not in globals() or MIGRATION is None:
        MIGRATION = parsed['invariant']['path']
        MIGRATION_SHA256 = parsed['invariant']['sha']
    if not _dispatch_ready():
        if 'MIGRATION' not in curve.__dict__ or curve.MIGRATION is None:
            curve.MIGRATION = parsed['dispatch']['path']
            curve.MIGRATION_SHA256 = parsed['dispatch']['sha']
        if curve._PATHS is None:
            curve._PATHS = parsed['paths']
    if _PROTECTED_TAIL is None:
        _PROTECTED_TAIL = tuple(parsed['tail'])


def __getattr__(name):
    if name in ('MIGRATION', 'MIGRATION_SHA256'):
        _ensure_migration()
        return MIGRATION if name == 'MIGRATION' else MIGRATION_SHA256
    if name == 'SOURCE_PATHS':
        return _sources()
    if name == 'PROTECTED_INPUTS':
        _input_bundle()
        return (MIGRATION, *curve.PROTECTED_INPUTS, *_PROTECTED_TAIL)
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')


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
        raise ValueError(_contract_prefixes()['invariant'] + message)

def _gate(migration, prior=None, components=None):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='invariant-gate-') as directory:
        folder = Path(directory)
        record = folder / 'migration.json'
        record.write_bytes(migration)
        arguments = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                     'carla_invariant_gate', '--migration', str(record)]
        if prior is not None:
            prior_path = folder / 'prior.json'
            prior_path.write_bytes(prior)
            arguments.extend(['--prior', str(prior_path)])
            if components is not None:
                component_dir = folder / 'components'
                component_dir.mkdir()
                names = [name for name, _payload in components]
                (component_dir / 'names.json').write_text(json.dumps(names))
                for index, (_name, payload) in enumerate(components):
                    (component_dir / str(index)).write_bytes(payload)
                arguments.extend(['--components', str(component_dir)])
        result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_digest(payload, expected, kind, label):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='invariant-digest-') as directory:
        target = Path(directory) / 'pin'
        target.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_invariant_gate',
             '--bytes', str(target), '--sha', expected, '--kind', kind,
             '--label', label],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


_INVARIANT_LABELS = None


def _invariant_labels():
    """Return the pin file names, the prior record, and the messages."""
    global _INVARIANT_LABELS
    if _INVARIANT_LABELS is not None:
        return _INVARIANT_LABELS
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_invariant_labels'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _INVARIANT_LABELS = json.loads(result.stdout)
    return _INVARIANT_LABELS


def _labels_with_migration():
    """Return the invariant labels after the migration path is bound."""
    global _INVARIANT_LABELS, MIGRATION, MIGRATION_SHA256
    if (
        _INVARIANT_LABELS is not None
        and 'MIGRATION' in globals()
        and MIGRATION is not None
    ):
        return _INVARIANT_LABELS
    import json
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_invariant_labels',
         '--with-migration'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    data = json.loads(result.stdout)
    if _INVARIANT_LABELS is None:
        _INVARIANT_LABELS = data['labels']
    if not ('MIGRATION' in globals() and MIGRATION is not None):
        MIGRATION = data['migration']['path']
        MIGRATION_SHA256 = data['migration']['sha']
    return _INVARIANT_LABELS


def read_record(root):
    labels = _labels_with_migration()
    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())
    _gate(payload)
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    prior = root/labels['prior']
    prior_bytes = _typed_source.historical_bytes(root, prior, prior.read_bytes())
    _gate(payload, prior_bytes)
    components = []
    oracle = labels['oracle']
    for name, _expected in record['components'].items():
        components.append((name, _typed_source.historical_bytes(root, root/oracle/name, (root/oracle/name).read_bytes())))
    _gate(payload, prior_bytes, components)
    return record


_GATED_PAIR = None


def _gate_pair(names):
    """Require this ordered pin pair once for the same names."""
    global _GATED_PAIR
    labels = tuple(names)
    if _GATED_PAIR == labels:
        return
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='invariant-pair-') as directory:
        folder = Path(directory)
        (folder / 'labels.json').write_text(json.dumps(list(labels)))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_invariant_gate',
             '--pair', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _GATED_PAIR = labels


def _invariant_predecessor(payload, record, filename):
    """Return the indented coverage-invariant pin predecessor."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    request = json.dumps({
        'after': record['after_sha256'],
        'before': record['before_sha256'],
        'label': filename,
        'transitions': record['transitions'],
    }, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='invariant-predecessor-') as directory:
        folder = Path(directory)
        (folder / 'payload').write_bytes(payload)
        (folder / 'request.json').write_text(request)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_invariant_gate',
             '--predecessor', str(folder)],
            capture_output=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and b'Crashpad' not in line]
        message = (lines[-1] if lines else result.stdout).decode(
            'utf-8', 'replace').strip()
        raise ValueError(message)
    return result.stdout


def _component_tool(mode, payload):
    """Run one component-path mode and return its stdout."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='component-path-') as directory:
        path = Path(directory) / 'payload'
        path.write_bytes(payload.encode('utf-8'))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_component_path',
             mode, str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def _require_component_names(directory, names):
    """Require every component name to stay inside `directory`."""
    _component_tool('--confine', json.dumps(
        {'directory': str(directory), 'names': list(names)},
        separators=(',', ':')))


def _path_basename(text):
    """Return the text after the last `/`."""
    return _component_tool('--base', text)


def _indent_json(value):
    """Return `json.dumps(value, indent=2)` plus a newline, as bytes."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps(value, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='json-indent-') as directory:
        path = Path(directory) / 'value.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_json_indent', str(path)],
            capture_output=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and b'Crashpad' not in line]
        message = (lines[-1] if lines else result.stdout).decode(
            'utf-8', 'replace').strip()
        raise ValueError(message)
    return result.stdout + b'\n'


def predecessor_pins(root, filename):
    """Verify active bytes, reverse every admitted edit, verify historical bytes."""
    filename = _path_basename(str(filename))
    record = read_record(root)['pin_files'][filename]
    if __package__:
        from . import coverage_followup_contracts as followup
    else:
        import coverage_followup_contracts as followup
    payload = followup.predecessor_pins(root, filename)
    return _pin_predecessor(payload, record, filename)

def _matches_then_dispatch(pairs):
    """Compare the successor digests, then read the dispatch migration."""
    if not pairs:
        return {'flags': [], 'matched': True}
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps([
        {'actual': actual, 'expected': expected} for actual, expected in pairs
    ], separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='match-migration-') as directory:
        path = Path(directory) / 'texts.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_dispatch_source',
             '--match-migration', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def verify(root, *, _operation=None):
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    _operation, _owns_operation = full_audit._operation_enter(root, 'invariant', _operation)
    operation_args = {} if _operation is None else {'_operation': _operation}
    try:
        with source.lexical_memo_scope():
            record = read_record(root)
            (predecessor_pin_pair(root) if _operation is None else
             _predecessor_pin_pair(root, _operation=_operation))
            loaded = []
            for path, item in record['sources'].items():
                loaded.append((
                    path,
                    source.token_sha256(_typed_source.historical_text(root, path, full_audit._observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)),
                    item['after_token_sha256']))
            checked = _matches_then_dispatch([
                (digest, expected) for _path, digest, expected in loaded])
            matched_flags = [flag == 'true' for flag in checked['flags']]
            if checked['matched'] and (
                    'MIGRATION' not in curve.__dict__ or curve.MIGRATION is None):
                curve.MIGRATION = checked['migration']['path']
                curve.MIGRATION_SHA256 = checked['migration']['sha']
            pending = [
                (path, expected) for (path, _digest, expected), matched in zip(loaded, matched_flags)
                if not matched]
            accepted = {}
            if pending:
                if __package__:
                    from . import coverage_followup_contracts as followup
                else:
                    import coverage_followup_contracts as followup
                if _operation is not None:
                    followup._check_operation(root, _operation)
                followup_record = followup.verify(root, **operation_args)
                for path, expected in pending:
                    accepted[path] = (
                        path in followup_record['sources']
                        and followup_record['sources'][path]['before_token_sha256'] == expected)
            for (path, _digest, expected), matched in zip(loaded, matched_flags):
                if not matched:
                    matched = accepted[path]
                require(matched, _invariant_labels()['successor'] + path)
            curve.verify(
                root, _then_grouped_identity=True, **operation_args)
            grouped.verify(
                root,
                _then_lane_paths=_operation is None,
                **operation_args,
            )
            if __package__:
                from . import lane_control_contracts as lane
            else:
                import lane_control_contracts as lane
            lane.verify(root, **operation_args)
            if _owns_operation:
                _operation.finish(root)
            return record
    finally:
        if _owns_operation:
            _operation.close()


def _verify_owned(root, *, _operation):
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    full_audit._operation_borrow(_operation, root, 'invariant')
    return verify(root, _operation=_operation)


def _pin_predecessor(payload, record, filename):
    import hashlib
    labels = _invariant_labels()
    if hashlib.sha256(payload).hexdigest() != record['after_sha256']:
        _gate_digest(payload, record['after_sha256'], labels['after'], filename)
    # A repeated key is refused before placement. The digest check stays first.
    json.loads(payload, object_pairs_hook=source.unique_keys)
    return _invariant_predecessor(payload, record, filename)


def predecessor_pin_pair(root):
    """Reconstruct the independently verified historical pin pair.

    Args:
        root: Root whose physical records and current sources must be checked.
    Returns:
        Runtime then guard historical pin bytes, without borrowed authority.
    Raises:
        ValueError: A record, source, or predecessor reconstruction is invalid.
        OSError: A required physical input cannot be read.
    """
    return _predecessor_pin_pair(root)


def _predecessor_pin_pair(root, *, _operation=None):
    """Reconstruct the fixed pair from two separately checked record reads.

    Args:
        root: Root whose record observations precede one fresh inner pair.
    Returns:
        A tuple of runtime then guard historical bytes, with no admission data.
    Raises:
        ValueError: A record, inner qualification, or pin reconstruction fails.
        OSError: A required input cannot be read.
    """
    filenames = tuple(_invariant_labels()['filenames'])
    runtime_record = read_record(root)
    _gate_pair(runtime_record['pin_files'])
    runtime_item = runtime_record['pin_files'][filenames[0]]
    guard_record = read_record(root)
    _gate_pair(guard_record['pin_files'])
    guard_item = guard_record['pin_files'][filenames[1]]
    if __package__:
        from . import coverage_followup_contracts as followup
    else:
        import coverage_followup_contracts as followup
    runtime_payload, guard_payload = (followup.predecessor_pin_pair(root) if _operation is None else
                                    followup._predecessor_pin_pair(root, _operation=_operation))
    runtime_predecessor = _pin_predecessor(runtime_payload, runtime_item, filenames[0])
    guard_predecessor = _pin_predecessor(guard_payload, guard_item, filenames[1])
    return runtime_predecessor, guard_predecessor
