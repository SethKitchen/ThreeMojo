# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Explicit current-graph checks before reversible historical projection."""
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

MIGRATION = 'tools/carla_lane_oracle/accepted-successor-migration.json'
MIGRATION_SHA256 = 'bb3a7b5e08a0a5400679f410da2c4574b45924294133df2f180f71fd74064d91'
SOURCE_PATHS = ('extensions/carla/curve_rounded_line.mojo',
                'extensions/carla/spiral_domain_proof.mojo',
                'extensions/carla/spiral_grouped_roundoff_proof.mojo')
COMPONENTS = ('rounded-line-singleton-migration.json',
              'rounded-line-selector-migration.json',
              'distance-validation-contract.json',
              'grouped-y-successor-record.json', 'grouped-y-proof.md',
              'grouped-y-exponent-ledger.json')
PROTECTED_INPUTS = (MIGRATION, *SOURCE_PATHS,
    *('tools/carla_lane_oracle/' + name for name in COMPONENTS),
    'tests/test_carla_rounded_line_singleton_contract.mojo',
    'tests/test_carla_rounded_line_selector.mojo',
    'tests/_reference_spiral_domain_validation.mojo',
    'tests/test_spiral_distance_representation_validation.mojo',
    'tests/_reference_grouped_y_refusal.mojo',
    'tests/test_spiral_grouped_y_differential.mojo',
    *sorted(set().union(*source.GROUP_PATHS.values())))


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
        raise ValueError('accepted source successor: ' + message)


def _gate(migration, prior=None, components=None):
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='accepted-gate-') as directory:
        folder = Path(directory)
        record = folder / 'migration.json'
        record.write_bytes(migration)
        arguments = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                     'carla_accepted_gate', '--migration', str(record)]
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
                        raise ValueError('accepted source successor: component record changed: ' + name)
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
    with tempfile.TemporaryDirectory(prefix='accepted-digest-') as directory:
        target = Path(directory) / 'pin'
        target.write_bytes(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_accepted_gate',
             '--bytes', str(target), '--sha', expected, '--kind', kind,
             '--label', label],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _gate_sources(pairs):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='accepted-sources-') as directory:
        folder = Path(directory)
        labels = []
        for index, (text, token, module, module_sha, path) in enumerate(pairs):
            (folder / f'{index}.text').write_text(text)
            (folder / f'{index}.module').write_text(module)
            labels.append({'path': path, 'token': token, 'module_sha': module_sha})
        (folder / 'labels.json').write_text(json.dumps(labels))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_accepted_gate',
             '--sources', str(folder)],
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
    prior = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle/coverage-followup-migration.json', (root/'tools/carla_lane_oracle/coverage-followup-migration.json').read_bytes())
    _gate(payload, prior)
    components = []
    for name, _expected in record['components'].items():
        components.append((name, _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/name, (root/'tools/carla_lane_oracle'/name).read_bytes())))
    _gate(payload, prior, components)
    return record


def verify_current(root):
    return _verify_current(root)


def _verify_current(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    record = read_record(root)
    operation_args = {} if _operation is None else {'_operation': _operation}
    pairs = []
    for path, item in record['sources'].items():
        text = _typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)
        pairs.append((text, item['after_token_sha256'], item['before_complete_module'], item['before_sha256'], path))
    if pairs:
        _gate_sources(pairs)
    if __package__:
        from . import rounded_line_selector_contracts as line
        from . import distance_validation_contracts as distance
        from . import grouped_y_finiteness_contracts as grouped
    else:
        import rounded_line_selector_contracts as line
        import distance_validation_contracts as distance
        import grouped_y_finiteness_contracts as grouped
    try:
        if _operation is None:
            line.verify(root)
        else:
            line._verify(root, _operation=_operation)
        distance.verify(root, **operation_args)
        grouped.verify(root, **operation_args)
    except ValueError as error:
        raise ValueError(
            'unreviewed complete successor: ' + str(error)) from error
    return record


def predecessor_text(root, path, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    record = verify_current(root) if _operation is None else _verify_current(root, _operation=_operation)
    require(path in record['sources'], 'unlisted historical source request')
    return record['sources'][path]['before_complete_module']


def _gate_places(rows):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='accepted-places-') as directory:
        folder = Path(directory)
        (folder / 'labels.json').write_text(json.dumps(rows))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_accepted_gate',
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


def predecessor_pins(root, filename, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    operation_args = {} if _operation is None else {'_operation': _operation}
    filename = str(filename).split('/')[-1]
    record = (verify_current(root) if _operation is None else _verify_current(root, _operation=_operation))['pin_files'][filename]
    payload = (root/'tools/carla_lane_oracle'/filename).read_bytes()
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        payload = _typed_source.historical_bytes(root, 'tools/carla_lane_oracle/'+filename, full_audit._observe_bytes(root, 'tools/carla_lane_oracle/'+filename, payload, _operation=_operation), _operation=_operation)
    return _restore_pin(payload, record, filename)


def _restore_pin(payload, record, filename):
    """Rebuild one accepted pin predecessor.

    The rebuild checks the pin digest, then a repeated key, then the
    placements. The restored bytes are checked after that rebuild.
    """
    import json
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
    with tempfile.TemporaryDirectory(prefix='accepted-predecessor-') as directory:
        folder = Path(directory)
        (folder / 'payload').write_bytes(payload)
        (folder / 'request.json').write_text(request)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_accepted_gate',
             '--predecessor', str(folder)],
            capture_output=True)
    if result.returncode != 0:
        failed = [line.strip() for line in result.stderr.splitlines()
                  if line.strip() and b'Crashpad' not in line]
        message = (failed[-1] if failed else result.stdout).decode(
            'utf-8', 'replace').strip()
        raise ValueError(message)
    return result.stdout


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    operation_args = {} if _operation is None else {'_operation': _operation}
    record = (verify_current(root) if _operation is None else _verify_current(root, _operation=_operation))
    for name in record['pin_files']:
        predecessor_pins(root, name, **operation_args)
    return record


def _verify_current_for_pin_pair(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    record = read_record(root)
    operation_args = {} if _operation is None else {'_operation': _operation}
    try:
        pairs = []
        for path, item in record['sources'].items():
            text = _typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)
            pairs.append((text, item['after_token_sha256'], item['before_complete_module'], item['before_sha256'], path))
        if pairs:
            _gate_sources(pairs)
    except ValueError as error:
        raise ValueError(
            'unreviewed complete successor: ' + str(error)) from error
    if __package__:
        from . import rounded_line_selector_contracts as line
        from . import distance_validation_contracts as distance
        from . import grouped_y_finiteness_contracts as grouped
    else:
        import rounded_line_selector_contracts as line
        import distance_validation_contracts as distance
        import grouped_y_finiteness_contracts as grouped
    try:
        _, observed_current_admission = line._verify_for_pin_pair(root, **operation_args)
        distance.verify(root, **operation_args)
        grouped.verify(root, **operation_args)
    except ValueError as error:
        raise ValueError(
            'unreviewed complete successor: ' + str(error)) from error
    return record, observed_current_admission


def _pin_predecessor(payload, record, filename):
    return _restore_pin(payload, record, filename)


def _read_current_pair_pin(root, filename, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    relative = 'tools/carla_lane_oracle/' + filename
    try:
        payload = full_audit._regular(root, relative).read_bytes()
    except (OSError, UnicodeError) as error:
        raise ValueError(
            'accepted source successor: unreadable current paired pin: ' + filename) from error
    if _operation is not None:
        _typed_source.historical_bytes(root, relative, full_audit._observe_bytes(root, relative, payload, _operation=_operation), _operation=_operation)
    require(type(payload) is bytes,
            'current paired pin is not builtin bytes: ' + filename)
    return payload


def _gate_pair(names):
    import json
    import os
    import subprocess
    import tempfile
    from pathlib import Path
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='accepted-pair-') as directory:
        folder = Path(directory)
        (folder / 'labels.json').write_text(json.dumps(list(names)))
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_accepted_gate',
             '--pair', str(folder)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def predecessor_pin_pair(root):
    """Qualify once and reconstruct the fixed runtime/guard predecessor pair.

    Args:
        root: Root whose live sources and active pin bytes are checked afresh.
    Returns:
        A tuple of runtime then guard historical bytes, with no admission data.
    Raises:
        ValueError: A source, pin, path, or executing-checker contract fails.
        OSError: An existing qualification or historical input cannot be read.
    """
    record, observed_current_admission = _verify_current_for_pin_pair(root)
    filenames = ('runtime-source-pins.json', 'sum2-guard-pins.json')
    _gate_pair(record['pin_files'])
    runtime_name, guard_name = filenames
    if observed_current_admission:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        runtime_raw = _read_current_pair_pin(root, runtime_name)
    else:
        runtime_raw = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/runtime_name, (root/'tools/carla_lane_oracle'/runtime_name).read_bytes())
    runtime_payload = _pin_predecessor(
        runtime_raw, record['pin_files'][runtime_name], runtime_name)
    if observed_current_admission:
        executing = full_audit.executing_checker_bindings()
        guard_raw = _read_current_pair_pin(root, guard_name)
    else:
        guard_raw = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/guard_name, (root/'tools/carla_lane_oracle'/guard_name).read_bytes())
    guard_payload = _pin_predecessor(
        guard_raw, record['pin_files'][guard_name], guard_name)
    if observed_current_admission:
        for filename, consumed_raw in ((runtime_name, runtime_raw), (guard_name, guard_raw)):
            final_raw = _read_current_pair_pin(root, filename)
            require(final_raw == consumed_raw, 'current paired pin changed: ' + filename)
        full_audit.require(full_audit.executing_checker_bindings() == executing,
                           'executing checker changed during paired pin projection')
    return runtime_payload, guard_payload



def _predecessor_pin_pair(root, *, _operation=None):
    """Qualify once and reconstruct the fixed runtime/guard predecessor pair.

    Args:
        root: Root whose live sources and active pin bytes are checked afresh.
    Returns:
        A tuple of runtime then guard historical bytes, with no admission data.
    Raises:
        ValueError: A source, pin, path, or executing-checker contract fails.
        OSError: An existing qualification or historical input cannot be read.
    """
    if _operation is not None:
        _check_operation(root, _operation)
    if _operation is None:
        return predecessor_pin_pair(root)
    record, observed_current_admission = _verify_current_for_pin_pair(root, _operation=_operation)
    filenames = ('runtime-source-pins.json', 'sum2-guard-pins.json')
    _gate_pair(record['pin_files'])
    runtime_name, guard_name = filenames
    if observed_current_admission:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        runtime_raw = _read_current_pair_pin(root, runtime_name, _operation=_operation)
    else:
        runtime_raw = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/runtime_name, (root/'tools/carla_lane_oracle'/runtime_name).read_bytes(), _operation=_operation)
    runtime_payload = _pin_predecessor(
        runtime_raw, record['pin_files'][runtime_name], runtime_name)
    if observed_current_admission:
        executing = full_audit.executing_checker_bindings()
        guard_raw = _read_current_pair_pin(root, guard_name, _operation=_operation)
    else:
        guard_raw = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle'/guard_name, (root/'tools/carla_lane_oracle'/guard_name).read_bytes(), _operation=_operation)
    guard_payload = _pin_predecessor(
        guard_raw, record['pin_files'][guard_name], guard_name)
    if observed_current_admission:
        for filename, consumed_raw in ((runtime_name, runtime_raw), (guard_name, guard_raw)):
            final_raw = _read_current_pair_pin(root, filename, _operation=_operation)
            require(final_raw == consumed_raw, 'current paired pin changed: ' + filename)
        full_audit.require(full_audit.executing_checker_bindings() == executing,
                           'executing checker changed during paired pin projection')
    return runtime_payload, guard_payload
