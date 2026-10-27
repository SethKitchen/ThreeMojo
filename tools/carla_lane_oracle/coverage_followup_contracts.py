# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Explicit reviewed raw-cut, finite-moment, budget, and ordered-lane lineage."""
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
if __package__:
    from . import accepted_successor_contracts as accepted
else:
    import accepted_successor_contracts as accepted
if __package__:
    from . import cache_key_contracts as cache_key
else:
    import cache_key_contracts as cache_key


MIGRATION = 'tools/carla_lane_oracle/coverage-followup-migration.json'
MIGRATION_SHA256 = '911929b7dc80b5c6e09e0cf27b2c8e1f9db52cd8df398d397fc70c900fed759e'
SOURCE_PATHS = ('extensions/carla/curve_sample_dispatch.mojo',
                'extensions/carla/spiral_moment_proof.mojo',
                'extensions/carla/curve_bounds.mojo',
                'extensions/carla/lane_refinement.mojo',
                'extensions/carla/spiral_grouped_roundoff_proof.mojo',
                'extensions/carla/spiral_roundoff_proof.mojo')
PROTECTED_INPUTS = (*cache_key.PROTECTED_INPUTS, MIGRATION, *SOURCE_PATHS,
    'tools/carla_lane_oracle/raw-cut-inverse-migration.json',
    'tools/carla_lane_oracle/moment-finiteness-contract.json',
    'tools/carla_lane_oracle/envelope-budget-contract.json',
    'tests/test_carla_raw_cut_successor.mojo',
    'tests/test_carla_envelope_budget_dominance.mojo',
    'tools/carla_lane_oracle/lane-order-migration.json',
    'tests/test_carla_lane_order_successor.mojo',
    'tools/carla_lane_oracle/selection-finiteness-contract.json',
    'tests/test_spiral_selection_finite_contract.mojo',
    'tests/_reference_roundoff_selection.mojo',
    'tests/_reference_grouped_selection.mojo')

def _check_operation(root, operation):
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    full_audit._operation_check(operation, root)


def _observe_text(root, path, text, *, _operation=None):
    if _operation is None:
        return text
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    return full_audit._observe_text(root, path, text, _operation=_operation)



def require(condition, message):
    if not condition:
        raise ValueError('coverage followup successor: ' + message)


def _gate(migration, prior=None, components=None):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='followup-gate-') as directory:
        folder = Path(directory)
        record = folder / 'migration.json'
        record.write_bytes(migration)
        arguments = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                     'carla_followup_gate', '--migration', str(record)]
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
                        raise ValueError('coverage followup successor: component migration record changed: ' + name)
                    target.write_bytes(payload)
                arguments.extend(['--components', str(component_dir)])
        result = subprocess.run(arguments, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def read_record(root):
    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())
    _gate(payload)
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    prior = root/'tools/carla_lane_oracle/coverage-invariant-migration.json'
    prior_bytes = _typed_source.historical_bytes(root, prior, prior.read_bytes())
    _gate(payload, prior_bytes)
    components = []
    for name, _digest in record['components'].items():
        components.append((name, _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/name, (root/'tools/carla_lane_oracle'/name).read_bytes())))
    _gate(payload, prior_bytes, components)
    return record

def _gate_digest(payload, expected, kind, label):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='followup-digest-') as directory:
        target = Path(directory) / 'pin'
        target.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_followup_gate',
             '--bytes', str(target), '--sha', expected, '--kind', kind,
             '--label', label],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_places(rows):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='followup-places-') as directory:
        folder = Path(directory)
        (folder / 'labels.json').write_text(json.dumps(rows))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_followup_gate',
             '--places', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _apply_transitions(pins, transitions):
    rows = []
    seen = set()
    for change in transitions:
        pointer = tuple(change['pointer'])
        duplicate = pointer in seen
        actual = ''
        if not duplicate:
            ref = pins
            for part in pointer[:-1]:
                ref = ref[part]
            actual = ref[pointer[-1]]
            seen.add(pointer)
        rows.append({'duplicate': duplicate, 'actual': actual,
                     'expected': change['after']})
    _gate_places(rows)
    for change in transitions:
        pointer = tuple(change['pointer'])
        ref = pins
        for part in pointer[:-1]:
            ref = ref[part]
        ref[pointer[-1]] = change['before']


def predecessor_pins(root, filename):
    filename = str(filename).split('/')[-1]
    record = read_record(root)['pin_files'][filename]
    payload = accepted.predecessor_pins(root, filename)
    _gate_digest(payload, record['after_sha256'], 'after', filename)
    pins = json.loads(payload, object_pairs_hook=source.unique_keys)
    _apply_transitions(pins, record['transitions'])
    payload = (json.dumps(pins,indent=2)+'\n').encode()
    _gate_digest(payload, record['before_sha256'], 'before', filename)
    return payload

def _source_view(root, path, physical_text, *, _operation=None):
    """Keep supplied physical views only for the helper's named authority domain."""
    if __package__:
        from . import full_audit_cleanup_contracts as cleanup
    else:
        import full_audit_cleanup_contracts as cleanup
    if path == cache_key.MODULE or path in cleanup.SOURCE_PATHS:
        return cache_key.reviewed_text(root, path, physical_text, _operation=_operation)
    historical = _typed_source.historical_text(root, path, physical_text, _operation=_operation)
    # For unrelated modules cache_key's historical API is an identity function.
    return cache_key.reviewed_text(root, path, historical, _operation=_operation)


def _gate_tokens(pairs):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='followup-tokens-') as directory:
        folder = Path(directory)
        labels = []
        for index, (body, token, name) in enumerate(pairs):
            (folder / f'{index}.text').write_text(body)
            labels.append({'path': name, 'token': token})
        (folder / 'labels.json').write_text(json.dumps(labels))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_followup_gate',
             '--tokens', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    record = read_record(root)
    operation_args = {} if _operation is None else {'_operation': _operation}
    if _operation is None:
        predecessor_pin_pair(root)
    else:
        _predecessor_pin_pair(root, _operation=_operation)
    pairs = []
    for path,item in record['sources'].items():
        text = accepted.predecessor_text(root, path, **operation_args) if path in accepted.SOURCE_PATHS else _source_view(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), **operation_args)
        pairs.append((text, item['after_token_sha256'], path))
    if pairs:
        _gate_tokens(pairs)
    if __package__:
        from . import raw_cut_inverse_contracts as raw
        from . import moment_finiteness_contracts as moment
        from . import envelope_budget_contracts as budget
        from . import lane_order_contracts as order
        from . import selection_finiteness_contracts as selection
    else:
        import raw_cut_inverse_contracts as raw
        import moment_finiteness_contracts as moment
        import envelope_budget_contracts as budget
        import lane_order_contracts as order
        import selection_finiteness_contracts as selection
    raw.verify(root, **operation_args); moment.verify(root, **operation_args); budget.verify(root, **operation_args); order.verify(root, **operation_args); selection.verify(root, **operation_args)
    return record

def accepts_predecessor_source(root,path,expected, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    record = verify(root, **({} if _operation is None else {'_operation': _operation}))
    return path in record['sources'] and record['sources'][path]['before_token_sha256'] == expected


def _pin_predecessor(payload, record, filename):
    _gate_digest(payload, record['after_sha256'], 'after', filename)
    pins = json.loads(payload, object_pairs_hook=source.unique_keys)
    _apply_transitions(pins, record['transitions'])
    payload = (json.dumps(pins,indent=2)+'\n').encode()
    _gate_digest(payload, record['before_sha256'], 'before', filename)
    return payload


def predecessor_pin_pair(root):
    """Reconstruct the fixed pair from two separately checked record reads.

    Args:
        root: Root whose record observations precede one fresh inner pair.
    Returns:
        A tuple of runtime then guard historical bytes, with no admission data.
    Raises:
        ValueError: A record, inner qualification, or pin reconstruction fails.
        OSError: A required input cannot be read.
    """
    return _predecessor_pin_pair(root)


def _gate_pair(names):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='followup-pair-') as directory:
        folder = Path(directory)
        (folder / 'labels.json').write_text(json.dumps(list(names)))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_followup_gate',
             '--pair', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


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
    if _operation is not None:
        _check_operation(root, _operation)
    filenames = ('runtime-source-pins.json', 'sum2-guard-pins.json')
    runtime_record = read_record(root)
    _gate_pair(runtime_record['pin_files'])
    runtime_item = runtime_record['pin_files'][filenames[0]]
    guard_record = read_record(root)
    _gate_pair(guard_record['pin_files'])
    guard_item = guard_record['pin_files'][filenames[1]]
    if _operation is None:
        runtime_payload, guard_payload = accepted.predecessor_pin_pair(root)
    else:
        runtime_payload, guard_payload = accepted._predecessor_pin_pair(root, _operation=_operation)
    runtime_predecessor = _pin_predecessor(runtime_payload, runtime_item, filenames[0])
    guard_predecessor = _pin_predecessor(guard_payload, guard_item, filenames[1])
    return runtime_predecessor, guard_predecessor
