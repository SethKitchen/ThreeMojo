# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Complete immediate producer contract for the frozen ARC successor.

Singleton coefficients follow from this exact producer and Box operation
graph. The removed consumer loop is not a general promise about models made
elsewhere. This source binding does not certify native or aggregate behavior.
"""
import hashlib
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


def read_record(root):
    payload = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256,
            'unreviewed migration record')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(type(record['schema']) is int and record['schema'] == 1,
            'unsupported migration schema')
    previous = root/'tools/carla_lane_oracle/reviewed-cleanup-migration.json'
    require(hashlib.sha256(previous.read_bytes()).hexdigest() ==
            record['previous_cleanup_migration_sha256'],
            'historical three-file cleanup changed')
    require(record['source_successor']['path'] == SOURCE_PATH,
            'wrong successor source')
    return record


def verify_runtime_pin_successor(root, prior_digest):
    record = read_record(root)
    require(prior_digest == record['runtime_pins_before_sha256'],
            'runtime pin predecessor differs from accepted cleanup')
    if __package__:
        from . import coverage_invariant_contracts as invariant
    else:
        import coverage_invariant_contracts as invariant
    payload = invariant.predecessor_pins(root, source.PINS)
    require(hashlib.sha256(payload).hexdigest() == record['runtime_pins_after_sha256'],
            'unreviewed runtime pin successor')
    pins = json.loads(payload, object_pairs_hook=source.unique_keys)
    transitions = record['runtime_token_successors']
    require(len(transitions) == 3 and
            {(item['group'], item['path']) for item in transitions} == {
                ('eligibility', SOURCE_PATH), ('optional_runtime', SOURCE_PATH),
                ('translation', SOURCE_PATH)},
            'wrong runtime successor placements')
    for item in transitions:
        require(pins['groups'][item['group']][item['path']] == item['after'],
                'runtime successor token mismatch')
        pins['groups'][item['group']][item['path']] = item['before']
    predecessor = (json.dumps(pins, indent=2)+'\n').encode()
    require(hashlib.sha256(predecessor).hexdigest() == prior_digest,
            'runtime predecessor reconstruction failed')


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
    for item in record['function_sources']:
        actual = guard.declaration(_observe_text(
            root, item['path'], (root/item['path']).read_text(), _operation=_operation),
                                   item['name'], tuple(item['owner']))
        require(guard.significant(actual) == guard.significant(item['source']),
                'complete producer/Box function changed: ' + item['name'])
    arc = _observe_text(root, 'extensions/carla/curve_rounded_arc.mojo',
                        (root/'extensions/carla/curve_rounded_arc.mojo').read_text(),
                        _operation=_operation)
    require(guard.declaration_routing(arc) == record['rounded_arc_routing'],
            'RoundedArc/Box field layout, imports, or declaration owners changed')
    return len(record['function_sources'])


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    operation_args = {} if _operation is None else {'_operation': _operation}
    record = read_record(root)
    _, guard_payload = _verified_pin_pair(root, record['runtime_pins_before_sha256'], **operation_args)
    require(hashlib.sha256(guard_payload).hexdigest() ==
            record['guard_pins_unchanged_sha256'], 'guard pin lineage changed')
    require(source.token_sha256(_observe_text(
        root, SOURCE_PATH, (root/SOURCE_PATH).read_text(), _operation=_operation)) ==
            record['source_successor']['after_token_sha256'],
            'complete frozen ARC successor changed')
    if __package__:
        from . import reviewed_cleanup_contracts as cleanup
    else:
        import reviewed_cleanup_contracts as cleanup
    for path, expected in record['premise_dependencies'].items():
        cleanup.verify_dependency(path, _observe_text(
            root, path, (root/path).read_text(), _operation=_operation),
            expected['token_sha256'])
    verify_premises(root, **operation_args)
    return record


def _runtime_pin_predecessor(payload, record, prior_digest):
    require(hashlib.sha256(payload).hexdigest() == record['runtime_pins_after_sha256'],
            'unreviewed runtime pin successor')
    pins = json.loads(payload, object_pairs_hook=source.unique_keys)
    transitions = record['runtime_token_successors']
    require(len(transitions) == 3 and
            {(item['group'], item['path']) for item in transitions} == {
                ('eligibility', SOURCE_PATH), ('optional_runtime', SOURCE_PATH),
                ('translation', SOURCE_PATH)},
            'wrong runtime successor placements')
    for item in transitions:
        require(pins['groups'][item['group']][item['path']] == item['after'],
                'runtime successor token mismatch')
        pins['groups'][item['group']][item['path']] = item['before']
    predecessor = (json.dumps(pins, indent=2)+'\n').encode()
    require(hashlib.sha256(predecessor).hexdigest() == prior_digest,
            'runtime predecessor reconstruction failed')
    return predecessor


def _verified_pin_pair(root, prior_digest, *, _operation=None):
    """Reconstruct frozen runtime bytes and retain the invariant guard bytes."""
    if _operation is not None:
        _check_operation(root, _operation)
    record = read_record(root)
    require(prior_digest == record['runtime_pins_before_sha256'],
            'runtime pin predecessor differs from accepted cleanup')
    if __package__:
        from . import coverage_invariant_contracts as invariant
    else:
        import coverage_invariant_contracts as invariant
    runtime_payload, guard_payload = (invariant.predecessor_pin_pair(root)
        if _operation is None else
        invariant._predecessor_pin_pair(root, _operation=_operation))
    runtime_predecessor = _runtime_pin_predecessor(runtime_payload, record, prior_digest)
    return runtime_predecessor, guard_payload
