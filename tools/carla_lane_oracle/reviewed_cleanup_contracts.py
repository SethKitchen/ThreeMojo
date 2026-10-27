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
    from . import ideal_projection
else:
    import accepted_successor_contracts as accepted
    import ideal_projection

MIGRATION = 'tools/carla_lane_oracle/reviewed-cleanup-migration.json'
MIGRATION_SHA256 = '01753344fe01d885eb3bbaf253815bca01816c57c09b6e7cc1c3a233808b42a9'
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


def _protected_inputs():
    """Return the protected inputs, including the Mojo path tables."""
    _ensure_paths()
    return (*cache_key.PROTECTED_INPUTS, *accepted.PROTECTED_INPUTS, MIGRATION, _record_paths()['runtime_pins'],
            *SOURCE_PATHS, *PREMISE_PATHS, *frozen.PROTECTED_INPUTS,
            *invariant.PROTECTED_INPUTS, *_protected_tail())


def __getattr__(name):
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



def require(condition, message):
    if not condition:
        raise ValueError('reviewed cleanup source contract: ' + message)


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


def read_record(root):
    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())
    _gate(payload)
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    previous = root/_record_paths()['winner_sign']
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
    premises = {}
    for item in _cleanup_declarations()['declarations']:
        premises[item['key']] = _declaration(
            texts[item['source']], item['name'], tuple(item['owner']))
    _cleanup_premises(premises)



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


def _gate_words(text, kind, label):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='cleanup-words-') as directory:
        target = Path(directory) / 'source.mojo'
        target.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cleanup_gate',
             '--words', str(target), '--kind', kind, '--label', label],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _dependency_choice(token, expected, path):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    pins = _dependency_pins()
    payload = json.dumps({
        'token': token,
        'expected': expected,
        'path': path,
        'trig_path': pins['trig_path'],
        'trig_token': pins['trig_token'],
        'geometry_path': pins['geometry_path'],
        'geometry_token': pins['geometry_token'],
    }, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='dependency-words-') as directory:
        record = Path(directory) / 'choice.json'
        record.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_dependency_words', str(record)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout.strip()


def verify_dependency(path, text, expected):
    # A fixed whole-module fingerprint admits only equivalent stored words.
    # Historical pins remain unchanged; other dependencies retain exact tokens.
    pins = _dependency_pins()
    choice = _dependency_choice(ideal_projection.token_sha256(text), expected, path)
    if choice == pins['trig_choice']:
        _gate_words(text, pins['trig_choice'], path)
    elif choice == pins['geometry_choice']:
        _gate_words(text, pins['geometry_choice'], path)


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    operation_args = {} if _operation is None else {'_operation': _operation}
    record = read_record(root)
    _, guard_payload = frozen._verified_pin_pair(root, record['runtime_pins_after_sha256'], **operation_args)
    _gate_digest(guard_payload, record['guard_pins_after_sha256'])
    labels = _cleanup_declarations()
    pairs = []
    for path, transition in record['sources'].items():
        text = accepted.predecessor_text(root, path, **operation_args) if path in accepted.SOURCE_PATHS else _typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)
        if (path == labels['junction']
                and not ideal_projection.texts_match(
                    ideal_projection.token_sha256(text),
                    transition['after_token_sha256'])):
            try:
                if __package__:
                    from . import full_audit_cleanup_contracts as full_audit
                else:
                    import full_audit_cleanup_contracts as full_audit
                text = full_audit.reviewed_text(root, path, text, **operation_args)
            except (ValueError, OSError) as error:
                raise ValueError('reviewed cleanup source contract: ' + labels['unreviewed'] + path) from error
        pairs.append((text, transition['after_token_sha256'],
                      labels['unreviewed'] + path))
    if pairs:
        _gate_tokens(pairs)
    for path, expected in record['premise_dependencies'].items():
        verify_dependency(path, _typed_source.historical_text(root, path, _observe_text(
            root, path, (root/path).read_text(), _operation=_operation), _operation=_operation),
            expected['token_sha256'])
    verify_premises(root, **operation_args)
    frozen.verify(root, **operation_args)
    if _operation is None:
        invariant.verify(root)
    else:
        invariant._verify_owned(root, _operation=_operation)
    return record
