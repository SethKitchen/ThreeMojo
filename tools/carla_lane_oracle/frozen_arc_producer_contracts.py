# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Complete immediate producer contract for the frozen ARC successor.

Singleton coefficients follow from this exact producer and Box operation
graph. The removed consumer loop is not a general promise about models made
elsewhere. This source binding does not certify native or aggregate behavior.
"""
if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

# #333 explicit historical provenance views; current inputs remain operation-owned.
import json

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
    record = _migration_records()['frozen']
    MIGRATION = record['path']
    MIGRATION_SHA256 = record['sha']

_PATHS = None


def _paths():
    """Return the frozen-arc source and its dependency paths."""
    global _PATHS
    if _PATHS is not None:
        return _PATHS
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_paths'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _PATHS = json.loads(result.stdout)
    return _PATHS


def _ensure_paths():
    """Bind the frozen-arc source before a source read."""
    global SOURCE_PATH
    SOURCE_PATH = _paths()['source']


def _protected_bundle():
    """Read the frozen-arc paths, then the migration record."""
    global _PATHS, SOURCE_PATH, MIGRATION, MIGRATION_SHA256
    if (_PATHS is not None and 'MIGRATION' in globals()
            and MIGRATION is not None):
        SOURCE_PATH = _PATHS['source']
        return
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_gate',
         '--protected-bundle'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    if _PATHS is None:
        _PATHS = parsed['paths']
    SOURCE_PATH = _PATHS['source']
    if 'MIGRATION' not in globals() or MIGRATION is None:
        MIGRATION = parsed['migration']['path']
        MIGRATION_SHA256 = parsed['migration']['sha']


def __getattr__(name):
    if name in ('MIGRATION', 'MIGRATION_SHA256'):
        _ensure_migration()
        return MIGRATION if name == 'MIGRATION' else MIGRATION_SHA256
    if name in ('SOURCE_PATH', 'PROTECTED_INPUTS'):
        _protected_bundle()
    if name == 'SOURCE_PATH':
        return SOURCE_PATH
    if name == 'PROTECTED_INPUTS':
        return (MIGRATION, SOURCE_PATH, *_PATHS['protected'])
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
        raise ValueError(_contract_prefixes()['frozen'] + message)


def _gate(migration, previous=None):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='frozen-arc-gate-') as directory:
        folder = Path(directory)
        record = folder / 'migration.json'
        record.write_bytes(migration)
        arguments = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                     'carla_frozen_arc_gate', '--migration', str(record)]
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


def _digest_and_token(payload, digest, text, token):
    """Read the guard label, then check the pin digest and the token."""
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    body = json.dumps({
        'bytes': payload.decode('utf-8'),
        'sha': digest,
        'text': text,
        'token': token,
    }, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='frozen-digest-token-') as directory:
        path = Path(directory) / 'digest.json'
        path.write_text(body)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_gate',
             '--labeled-digest', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_token(text, expected):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='frozen-arc-token-') as directory:
        target = Path(directory) / 'source.mojo'
        target.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_gate',
             '--source', str(target), '--token', expected],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_digest(payload, expected, kind):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='frozen-arc-digest-') as directory:
        target = Path(directory) / 'pin'
        target.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_gate',
             '--bytes', str(target), '--sha', expected, '--kind', kind],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_prior(actual, expected):
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_gate',
         '--prior', actual, '--cleanup', expected],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _predecessor_request(payload, record, prior_digest):
    """Check the pin digest and refuse a repeated key before the predecessor."""
    import hashlib
    if hashlib.sha256(payload).hexdigest() != record['runtime_pins_after_sha256']:
        raise ValueError(
            'frozen ARC producer contract: unreviewed runtime pin successor')
    # A repeated key is refused before placement. The digest check stays first.
    json.loads(payload, object_pairs_hook=source.unique_keys)
    return json.dumps({
        'after': record['runtime_pins_after_sha256'],
        'before': prior_digest,
        'transitions': record['runtime_token_successors'],
    }, separators=(',', ':'))


def _runtime_predecessor(payload, record, prior_digest, *, _then_paths=False):
    """Read the frozen pin labels, then return the indented predecessor.

    When `_then_paths` is set, the frozen-arc paths are read after that
    predecessor and kept when the path cache is empty.
    """
    import ast
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    global _PATHS
    request = _predecessor_request(payload, record, prior_digest)
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    mode = '--predecessor-paths' if _then_paths else '--predecessor-labels'
    with tempfile.TemporaryDirectory(prefix='frozen-predecessor-') as directory:
        folder = Path(directory)
        (folder / 'payload').write_bytes(payload)
        (folder / 'request.json').write_text(request)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_gate',
             mode, str(folder)],
            capture_output=True, text=_then_paths)
    if result.returncode != 0:
        if _then_paths:
            lines = [line.strip() for line in result.stderr.splitlines()
                     if line.strip() and 'Crashpad' not in line]
            message = lines[-1] if lines else result.stdout.strip()
        else:
            lines = [line.strip() for line in result.stderr.splitlines()
                     if line.strip() and b'Crashpad' not in line]
            message = (lines[-1] if lines else result.stdout).decode(
                'utf-8', 'replace').strip()
        if message.startswith('KeyError: '):
            try:
                raise KeyError(ast.literal_eval(message[len('KeyError: '):]))
            except (SyntaxError, ValueError):
                pass
        raise ValueError(message)
    if not _then_paths:
        return result.stdout
    parsed = json.loads(result.stdout)
    if _PATHS is None:
        _PATHS = parsed['paths']
    return parsed['predecessor'].encode('utf-8')


def _predecessor_then_declarations(payload, record, prior_digest, guard, guard_sha):
    """Read the pin labels, rebuild the predecessor, then return the catalog."""
    import ast
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    request = _predecessor_request(payload, record, prior_digest)
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='frozen-predecessor-catalog-') as directory:
        folder = Path(directory)
        (folder / 'payload').write_bytes(payload)
        (folder / 'request.json').write_text(request)
        (folder / 'guard').write_bytes(guard)
        (folder / 'sha').write_text(guard_sha)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_gate',
             '--predecessor-declarations', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        if message.startswith('KeyError: '):
            try:
                raise KeyError(ast.literal_eval(message[len('KeyError: '):]))
            except (SyntaxError, ValueError):
                pass
        raise ValueError(message)
    return json.loads(result.stdout)


def _producer_review(pairs, arc, stored):
    """Check every producer function and the arc layout in one call."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    payload = json.dumps({
        'functions': [
            {
                'name': item['name'],
                'module': text,
                'owner': list(item['owner']),
                'source': item['source'],
            }
            for item, text in pairs
        ],
        'layout': {'source': arc, 'stored': stored},
    }, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='frozen-review-') as directory:
        path = Path(directory) / 'review.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_gate',
             '--review', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _review_then_labels(pairs, arc, stored):
    """Check the producer review, then read the invariant labels."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    if __package__:
        from . import coverage_invariant_contracts as invariant
    else:
        import coverage_invariant_contracts as invariant
    payload = json.dumps({
        'functions': [
            {
                'name': item['name'],
                'module': text,
                'owner': list(item['owner']),
                'source': item['source'],
            }
            for item, text in pairs
        ],
        'layout': {'source': arc, 'stored': stored},
    }, separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='review-labels-') as directory:
        path = Path(directory) / 'review.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_gate',
             '--review-labels', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    parsed = json.loads(result.stdout)
    if invariant._INVARIANT_LABELS is None:
        invariant._INVARIANT_LABELS = parsed['labels']
    if 'MIGRATION' not in invariant.__dict__ or invariant.MIGRATION is None:
        invariant.MIGRATION = parsed['migration']['path']
        invariant.MIGRATION_SHA256 = parsed['migration']['sha']


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
    """Require the frozen record, then return the companion paths."""
    global _RECORD_PATHS
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='frozen-record-paths-') as directory:
        record = Path(directory) / 'migration.json'
        record.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_gate',
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
    previous = root/paths['reviewed_cleanup']
    _gate(payload, _typed_source.historical_bytes(root, previous, previous.read_bytes()))
    return record


def verify_runtime_pin_successor(root, prior_digest):
    record = read_record(root)
    _gate_prior(prior_digest, record['runtime_pins_before_sha256'])
    if __package__:
        from . import coverage_invariant_contracts as invariant
    else:
        import coverage_invariant_contracts as invariant
    payload = invariant.predecessor_pins(root, source.PINS)
    _runtime_predecessor(payload, record, prior_digest)


def _declaration(text, name, owner):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='declaration-gate-') as directory:
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
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    if not items:
        return []
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(items, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='frozen-declarations-') as directory:
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


def verify_premises(root, *, _operation=None, _then_invariant_labels=False):
    if _operation is not None:
        _check_operation(root, _operation)
    # This scoped check deliberately does not inspect the complete-file hash.
    # Mutation controls invoke it directly to test producer and Box obligations.
    record = read_record(root)
    loaded = []
    for item in record['function_sources']:
        text = _typed_source.historical_text(root, item['path'], _observe_text(
            root, item['path'], (root/item['path']).read_text(), _operation=_operation), _operation=_operation)
        loaded.append((item, text))
    arc = _typed_source.historical_text(root, 'extensions/carla/curve_rounded_arc.mojo', _observe_text(root, 'extensions/carla/curve_rounded_arc.mojo',
                        (root/'extensions/carla/curve_rounded_arc.mojo').read_text(),
                        _operation=_operation), _operation=_operation)
    if _then_invariant_labels:
        _review_then_labels(loaded, arc, record['rounded_arc_routing'])
    else:
        _producer_review(loaded, arc, record['rounded_arc_routing'])
    return len(record['function_sources'])


def _runtime_pin_decision(payload):
    """Return `raise`, `cause`, or `relabel` for one runtime-pin failure."""
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='runtime-pin-failure-') as directory:
        path = Path(directory) / 'decision.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_runtime_pin_failure', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout.strip()


_FROZEN_LABELS = None


def _frozen_labels():
    """Return the frozen runtime-pin labels and the public message."""
    global _FROZEN_LABELS
    if _FROZEN_LABELS is not None:
        return _FROZEN_LABELS
    import os
    import subprocess
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_pin_labels'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _FROZEN_LABELS = json.loads(result.stdout)
    return _FROZEN_LABELS


def _relabel_runtime_pin(error, operation_present):
    """Return whether this failure becomes the public runtime-pin diagnostic."""
    labels = _frozen_labels()
    message = labels['premise']
    try:
        payload = json.dumps({
            'stage': labels['stage_error'],
            'operation': operation_present,
            'exact_value_error': type(error) is ValueError,
            'error_args': list(error.args),
            'expected_error': labels['expected_error_prefix'] + message,
        }, separators=(',', ':'))
    except (TypeError, ValueError):
        return False
    if _runtime_pin_decision(payload) != labels['decision_cause']:
        return False
    cause = error.__cause__
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    try:
        payload = json.dumps({
            'stage': labels['stage_cause'],
            'exact_contract_error': type(cause) is full_audit.ContractError,
            'cause_args': None if cause is None else list(cause.args),
            'expected_cause': message,
        }, separators=(',', ':'))
    except (TypeError, ValueError):
        return False
    return _runtime_pin_decision(payload) == labels['decision_relabel']


def verify(root, *, _operation=None, _then_invariant_labels=False):
    if _operation is not None:
        _check_operation(root, _operation)
    operation_args = {} if _operation is None else {'_operation': _operation}
    record = read_record(root)
    try:
        _, guard_payload = _verified_pin_pair(
            root,
            record['runtime_pins_before_sha256'],
            _then_paths=True,
            **operation_args,
        )
    except ValueError as error:
        # Preserve this public runtime-pin diagnostic after complete admission
        # rejects the same fixed input. Never relabel private operation faults.
        if not _relabel_runtime_pin(error, _operation is not None):
            raise
        raise ValueError(_frozen_labels()['public']) from error
    _ensure_paths()
    _digest_and_token(
        guard_payload,
        record['guard_pins_unchanged_sha256'],
        _typed_source.historical_text(root, SOURCE_PATH, _observe_text(
            root, SOURCE_PATH, (root/SOURCE_PATH).read_text(), _operation=_operation), _operation=_operation),
        record['source_successor']['after_token_sha256'])
    if __package__:
        from . import reviewed_cleanup_contracts as cleanup
    else:
        import reviewed_cleanup_contracts as cleanup
    dependencies = []
    for path, expected in record['premise_dependencies'].items():
        dependencies.append((path, _typed_source.historical_text(root, path, _observe_text(
            root, path, (root/path).read_text(), _operation=_operation), _operation=_operation),
            expected['token_sha256']))
    cleanup.verify_dependencies(dependencies)
    verify_premises(
        root,
        _then_invariant_labels=_then_invariant_labels,
        **operation_args,
    )
    return record


def _runtime_pin_predecessor(payload, record, prior_digest, *, _then_paths=False):
    return _runtime_predecessor(
        payload, record, prior_digest, _then_paths=_then_paths)


def _verified_pin_pair(
        root, prior_digest, *, _operation=None, _guard_sha=None, _then_paths=False,
):
    """Reconstruct frozen runtime bytes and retain the invariant guard bytes.

    When `_guard_sha` is set, the predecessor and the declaration catalog
    are one check. That call returns the catalog. When `_then_paths` is
    set, the frozen-arc paths are read after the predecessor.
    """
    if _operation is not None:
        _check_operation(root, _operation)
    record = read_record(root)
    _gate_prior(prior_digest, record['runtime_pins_before_sha256'])
    if __package__:
        from . import coverage_invariant_contracts as invariant
    else:
        import coverage_invariant_contracts as invariant
    runtime_payload, guard_payload = (invariant.predecessor_pin_pair(root)
        if _operation is None else
        invariant._predecessor_pin_pair(root, _operation=_operation))
    if _guard_sha is None:
        runtime_predecessor = _runtime_pin_predecessor(
            runtime_payload, record, prior_digest, _then_paths=_then_paths)
        return runtime_predecessor, guard_payload
    return _predecessor_then_declarations(
        runtime_payload, record, prior_digest, guard_payload, _guard_sha)
