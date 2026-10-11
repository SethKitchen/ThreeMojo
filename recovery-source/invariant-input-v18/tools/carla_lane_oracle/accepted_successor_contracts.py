# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Explicit current-graph checks before reversible historical projection."""
import hashlib
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


def read_record(root):
    payload = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256,
            'unreviewed migration record')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(type(record['schema']) is int and record['schema'] == 1
            and set(record['sources']) == set(SOURCE_PATHS), 'wrong exact successor set')
    require(hashlib.sha256((root/'tools/carla_lane_oracle/coverage-followup-migration.json').read_bytes()).hexdigest()
            == record['prior_followup_migration_sha256'], 'historical followup record changed')
    require(set(record['components']) == set(COMPONENTS), 'wrong component set')
    for name, expected in record['components'].items():
        require(hashlib.sha256((root/'tools/carla_lane_oracle'/name).read_bytes()).hexdigest()
                == expected, 'component record changed: ' + name)
    return record


def verify_current(root):
    return _verify_current(root)


def _verify_current(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    record = read_record(root)
    operation_args = {} if _operation is None else {'_operation': _operation}
    for path, item in record['sources'].items():
        require(source.token_sha256(_observe_text(root, path, (root/path).read_text(), _operation=_operation)) == item['after_token_sha256'],
                'unreviewed complete successor: ' + path)
        require(hashlib.sha256(item['before_complete_module'].encode()).hexdigest()
                == item['before_sha256'], 'historical module changed: ' + path)
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


def predecessor_pins(root, filename):
    filename = str(filename).split('/')[-1]
    record = verify_current(root)['pin_files'][filename]
    payload = (root/'tools/carla_lane_oracle'/filename).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == record['after_sha256'],
            'unreviewed runtime pin successor: ' + filename)
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
    payload = (json.dumps(pins, indent=2)+'\n').encode()
    require(hashlib.sha256(payload).hexdigest() == record['before_sha256'],
            'historical pins failed reconstruction')
    return payload


def verify(root):
    record = verify_current(root)
    for name in record['pin_files']:
        predecessor_pins(root, name)
    return record


def _verify_current_for_pin_pair(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    record = read_record(root)
    operation_args = {} if _operation is None else {'_operation': _operation}
    for path, item in record['sources'].items():
        require(source.token_sha256(_observe_text(root, path, (root/path).read_text(), _operation=_operation)) == item['after_token_sha256'],
                'unreviewed complete successor: ' + path)
        require(hashlib.sha256(item['before_complete_module'].encode()).hexdigest()
                == item['before_sha256'], 'historical module changed: ' + path)
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
    require(hashlib.sha256(payload).hexdigest() == record['after_sha256'],
            'unreviewed runtime pin successor: ' + filename)
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
    payload = (json.dumps(pins, indent=2)+'\n').encode()
    require(hashlib.sha256(payload).hexdigest() == record['before_sha256'],
            'historical pins failed reconstruction')
    return payload


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
        full_audit._observe_bytes(root, relative, payload, _operation=_operation)
    require(type(payload) is bytes,
            'current paired pin is not builtin bytes: ' + filename)
    return payload


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
    require(tuple(record['pin_files']) == filenames, 'wrong fixed ordered pin pair')
    runtime_name, guard_name = filenames
    if observed_current_admission:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        runtime_raw = _read_current_pair_pin(root, runtime_name)
    else:
        runtime_raw = (root/'tools/carla_lane_oracle'/runtime_name).read_bytes()
    runtime_payload = _pin_predecessor(
        runtime_raw, record['pin_files'][runtime_name], runtime_name)
    if observed_current_admission:
        executing = full_audit.executing_checker_bindings()
        guard_raw = _read_current_pair_pin(root, guard_name)
    else:
        guard_raw = (root/'tools/carla_lane_oracle'/guard_name).read_bytes()
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
    require(tuple(record['pin_files']) == filenames, 'wrong fixed ordered pin pair')
    runtime_name, guard_name = filenames
    if observed_current_admission:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
        runtime_raw = _read_current_pair_pin(root, runtime_name, _operation=_operation)
    else:
        runtime_raw = (root/'tools/carla_lane_oracle'/runtime_name).read_bytes()
    runtime_payload = _pin_predecessor(
        runtime_raw, record['pin_files'][runtime_name], runtime_name)
    if observed_current_admission:
        executing = full_audit.executing_checker_bindings()
        guard_raw = _read_current_pair_pin(root, guard_name, _operation=_operation)
    else:
        guard_raw = (root/'tools/carla_lane_oracle'/guard_name).read_bytes()
    guard_payload = _pin_predecessor(
        guard_raw, record['pin_files'][guard_name], guard_name)
    if observed_current_admission:
        for filename, consumed_raw in ((runtime_name, runtime_raw), (guard_name, guard_raw)):
            final_raw = _read_current_pair_pin(root, filename, _operation=_operation)
            require(final_raw == consumed_raw, 'current paired pin changed: ' + filename)
        full_audit.require(full_audit.executing_checker_bindings() == executing,
                           'executing checker changed during paired pin projection')
    return runtime_payload, guard_payload
