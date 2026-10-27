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

MIGRATION = 'tools/carla_lane_oracle/frozen-arc-producer-migration.json'
MIGRATION_SHA256 = '70091e23400193257514363570187b47890e3c08c352fe79eb08bf291737cc9f'
SOURCE_PATH = 'extensions/carla/curve_frozen_arc.mojo'
PROTECTED_INPUTS = (MIGRATION, SOURCE_PATH, 'extensions/carla/polynomial.mojo',
                    'extensions/carla/road.mojo')


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
        raise ValueError('frozen ARC producer contract: ' + message)


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


def _gate_places(transitions, pins):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    rows = []
    for item in transitions:
        rows.append({
            'group': item['group'],
            'path': item['path'],
            'actual': pins['groups'][item['group']][item['path']],
            'expected': item['after'],
        })
    with tempfile.TemporaryDirectory(prefix='frozen-places-') as directory:
        folder = Path(directory)
        (folder / 'labels.json').write_text(json.dumps(rows))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_gate',
             '--places', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_functions(pairs):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    def canon(value):
        return json.dumps([[item[0], item[1]] for item in value], separators=(',', ':'))
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    rows = [{'name': name, 'actual': canon(actual), 'expected': canon(expected)}
            for actual, expected, name in pairs]
    with tempfile.TemporaryDirectory(prefix='frozen-functions-') as directory:
        folder = Path(directory)
        (folder / 'labels.json').write_text(json.dumps(rows))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_gate',
             '--functions', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_layout(actual, expected):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='frozen-layout-') as directory:
        folder = Path(directory)
        left = folder / 'layout.txt'
        right = folder / 'stored.txt'
        left.write_text(actual)
        right.write_text(expected)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_frozen_arc_gate',
             '--layout', str(left), '--stored', str(right)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def read_record(root):
    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())
    _gate(payload)
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    previous = root/'tools/carla_lane_oracle/reviewed-cleanup-migration.json'
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
    _gate_digest(payload, record['runtime_pins_after_sha256'], 'after')
    pins = json.loads(payload, object_pairs_hook=source.unique_keys)
    transitions = record['runtime_token_successors']
    _gate_places(transitions, pins)
    for item in transitions:
        pins['groups'][item['group']][item['path']] = item['before']
    predecessor = (json.dumps(pins, indent=2)+'\n').encode()
    _gate_digest(predecessor, prior_digest, 'before')


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


def verify_premises(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    # This scoped check deliberately does not inspect the complete-file hash.
    # Mutation controls invoke it directly to test producer and Box obligations.
    if __package__:
        from . import sum2_guard_contracts as guard
    else:
        import sum2_guard_contracts as guard
    record = read_record(root)
    pairs = []
    for item in record['function_sources']:
        actual = _declaration(_typed_source.historical_text(root, item['path'], _observe_text(
            root, item['path'], (root/item['path']).read_text(), _operation=_operation), _operation=_operation),
                                   item['name'], tuple(item['owner']))
        pairs.append((guard.significant(actual), guard.significant(item['source']), item['name']))
    _gate_functions(pairs)
    arc = _typed_source.historical_text(root, 'extensions/carla/curve_rounded_arc.mojo', _observe_text(root, 'extensions/carla/curve_rounded_arc.mojo',
                        (root/'extensions/carla/curve_rounded_arc.mojo').read_text(),
                        _operation=_operation), _operation=_operation)
    _gate_layout(guard.declaration_routing(arc), record['rounded_arc_routing'])
    return len(record['function_sources'])


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    operation_args = {} if _operation is None else {'_operation': _operation}
    record = read_record(root)
    try:
        _, guard_payload = _verified_pin_pair(root, record['runtime_pins_before_sha256'], **operation_args)
    except ValueError as error:
        # Preserve this public runtime-pin diagnostic after complete admission
        # rejects the same fixed input. Never relabel private operation faults.
        message = ('full-audit cleanup successor: unchanged premise, record or fixture changed: '
                   'tools/carla_lane_oracle/runtime-source-pins.json')
        if (_operation is not None or type(error) is not ValueError
                or error.args != ('unreviewed complete successor: ' + message,)):
            raise
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        cause = error.__cause__
        if type(cause) is not full_audit.ContractError or cause.args != (message,):
            raise
        raise ValueError('frozen ARC producer contract: unreviewed runtime pin successor') from error
    _gate_digest(guard_payload, record['guard_pins_unchanged_sha256'], 'guard')
    _gate_token(_typed_source.historical_text(root, SOURCE_PATH, _observe_text(
        root, SOURCE_PATH, (root/SOURCE_PATH).read_text(), _operation=_operation), _operation=_operation),
        record['source_successor']['after_token_sha256'])
    if __package__:
        from . import reviewed_cleanup_contracts as cleanup
    else:
        import reviewed_cleanup_contracts as cleanup
    for path, expected in record['premise_dependencies'].items():
        cleanup.verify_dependency(path, _typed_source.historical_text(root, path, _observe_text(
            root, path, (root/path).read_text(), _operation=_operation), _operation=_operation),
            expected['token_sha256'])
    verify_premises(root, **operation_args)
    return record


def _runtime_pin_predecessor(payload, record, prior_digest):
    _gate_digest(payload, record['runtime_pins_after_sha256'], 'after')
    pins = json.loads(payload, object_pairs_hook=source.unique_keys)
    transitions = record['runtime_token_successors']
    _gate_places(transitions, pins)
    for item in transitions:
        pins['groups'][item['group']][item['path']] = item['before']
    predecessor = (json.dumps(pins, indent=2)+'\n').encode()
    _gate_digest(predecessor, prior_digest, 'before')
    return predecessor


def _verified_pin_pair(root, prior_digest, *, _operation=None):
    """Reconstruct frozen runtime bytes and retain the invariant guard bytes."""
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
    runtime_predecessor = _runtime_pin_predecessor(runtime_payload, record, prior_digest)
    return runtime_predecessor, guard_payload
