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
MIGRATION = 'tools/carla_lane_oracle/coverage-invariant-migration.json'
MIGRATION_SHA256 = '56a72d9bccbf9e7b8a6b51db2b9944ef4bbf55d9bcc7311f7f9615be3b3b36ac'
SOURCE_PATHS = (*curve.SOURCE_PATHS, grouped.MODULE,
                'extensions/carla/lane_refinement.mojo')
PROTECTED_INPUTS = (MIGRATION, *curve.PROTECTED_INPUTS,
                    'tools/carla_lane_oracle/grouped-table-contract.json',
                    grouped.MODULE, 'extensions/carla/geometry.mojo',
                    'tests/test_carla_support_dispatch_successor.mojo',
                    'tools/carla_lane_oracle/lane-control-migration.json',
                    'tests/test_carla_lane_control_successor.mojo')

def require(condition, message):
    if not condition:
        raise ValueError('coverage invariant successor: ' + message)

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
                for name, payload in components:
                    target = component_dir / name
                    if target.parent != component_dir:
                        raise ValueError('coverage invariant successor: component record changed: ' + name)
                    target.write_bytes(payload)
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


def read_record(root):
    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())
    _gate(payload)
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    prior = root/'tools/carla_lane_oracle/frozen-arc-producer-migration.json'
    prior_bytes = _typed_source.historical_bytes(root, prior, prior.read_bytes())
    _gate(payload, prior_bytes)
    components = []
    for name, _expected in record['components'].items():
        components.append((name, _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/name, (root/'tools/carla_lane_oracle'/name).read_bytes())))
    _gate(payload, prior_bytes, components)
    return record


def _gate_pair(names):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='invariant-pair-') as directory:
        folder = Path(directory)
        (folder / 'labels.json').write_text(json.dumps(list(names)))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_invariant_gate',
             '--pair', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def predecessor_pins(root, filename):
    """Verify active bytes, reverse every admitted edit, verify historical bytes."""
    filename = str(filename).split('/')[-1]
    record = read_record(root)['pin_files'][filename]
    if __package__:
        from . import coverage_followup_contracts as followup
    else:
        import coverage_followup_contracts as followup
    payload = followup.predecessor_pins(root, filename)
    _gate_digest(payload, record['after_sha256'], 'after', filename)
    pins = json.loads(payload, object_pairs_hook=source.unique_keys)
    seen = set()
    for change in record['transitions']:
        pointer = tuple(change['pointer'])
        require(pointer not in seen, 'duplicate pin placement')
        seen.add(pointer)
        ref = pins
        for part in pointer[:-1]:
            ref = ref[part]
        require(ref[pointer[-1]] == change['after'], 'active pin placement mismatch')
        ref[pointer[-1]] = change['before']
    original = (json.dumps(pins, indent=2)+'\n').encode()
    _gate_digest(original, record['before_sha256'], 'before', filename)
    return original

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
            for path, item in record['sources'].items():
                matches = source.token_sha256(_typed_source.historical_text(root, path, full_audit._observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)) == item['after_token_sha256']
                if not matches:
                    if __package__:
                        from . import coverage_followup_contracts as followup
                    else:
                        import coverage_followup_contracts as followup
                    matches = followup.accepts_predecessor_source(root,path,item['after_token_sha256'], **operation_args)
                require(matches, 'complete successor changed: ' + path)
            curve.verify(root, **operation_args)
            grouped.verify(root, **operation_args)
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
    _gate_digest(payload, record['after_sha256'], 'after', filename)
    pins = json.loads(payload, object_pairs_hook=source.unique_keys)
    seen = set()
    for change in record['transitions']:
        pointer = tuple(change['pointer'])
        require(pointer not in seen, 'duplicate pin placement')
        seen.add(pointer)
        ref = pins
        for part in pointer[:-1]:
            ref = ref[part]
        require(ref[pointer[-1]] == change['after'], 'active pin placement mismatch')
        ref[pointer[-1]] = change['before']
    original = (json.dumps(pins, indent=2)+'\n').encode()
    _gate_digest(original, record['before_sha256'], 'before', filename)
    return original


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
    filenames = ('runtime-source-pins.json', 'sum2-guard-pins.json')
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
