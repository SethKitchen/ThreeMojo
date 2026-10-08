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
    try:
        import coverage_invariant_contracts as invariant
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import coverage_invariant_contracts as invariant
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


def verify_premises(root):
    # This scoped check deliberately does not inspect the complete-file hash.
    # Mutation controls invoke it directly to test producer and Box obligations.
    try:
        import sum2_guard_contracts as guard
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import sum2_guard_contracts as guard
    record = read_record(root)
    for item in record['function_sources']:
        actual = guard.declaration((root/item['path']).read_text(),
                                   item['name'], tuple(item['owner']))
        require(guard.significant(actual) == guard.significant(item['source']),
                'complete producer/Box function changed: ' + item['name'])
    arc = (root/'extensions/carla/curve_rounded_arc.mojo').read_text()
    require(guard.declaration_routing(arc) == record['rounded_arc_routing'],
            'RoundedArc/Box field layout, imports, or declaration owners changed')
    return len(record['function_sources'])


def verify(root):
    record = read_record(root)
    verify_runtime_pin_successor(root, record['runtime_pins_before_sha256'])
    try:
        import coverage_invariant_contracts as invariant
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import coverage_invariant_contracts as invariant
    guard_payload = invariant.predecessor_pins(root, 'sum2-guard-pins.json')
    require(hashlib.sha256(guard_payload).hexdigest() ==
            record['guard_pins_unchanged_sha256'], 'guard pin lineage changed')
    require(source.token_sha256((root/SOURCE_PATH).read_text()) ==
            record['source_successor']['after_token_sha256'],
            'complete frozen ARC successor changed')
    try:
        import reviewed_cleanup_contracts as cleanup
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import reviewed_cleanup_contracts as cleanup
    for path, expected in record['premise_dependencies'].items():
        cleanup.verify_dependency(path, (root/path).read_text(), expected['token_sha256'])
    verify_premises(root)
    return record
