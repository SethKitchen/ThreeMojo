# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Reversible, exact successor for three independently reviewed invariants.

Historical records remain immutable. Current live guarded bodies and protected
use inventories remain checked by the maintained guard. These source checks do
not supply runtime hits, waive required outcomes, or establish a native pass.
"""
import hashlib
import json
try:
    import source_contracts as source
    import curve_support_dispatch_contracts as curve
    import grouped_table_contracts as grouped
except ModuleNotFoundError:
    from tools.carla_lane_oracle import source_contracts as source
    from tools.carla_lane_oracle import curve_support_dispatch_contracts as curve
    from tools.carla_lane_oracle import grouped_table_contracts as grouped
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

def read_record(root):
    payload = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256,
            'unreviewed migration record')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(type(record['schema']) is int and record['schema'] == 1,
            'unsupported schema')
    require(set(record['sources']) == set(SOURCE_PATHS), 'wrong successor set')
    prior = root/'tools/carla_lane_oracle/frozen-arc-producer-migration.json'
    require(hashlib.sha256(prior.read_bytes()).hexdigest() ==
            record['prior_frozen_migration_sha256'], 'historical frozen record changed')
    for name, expected in record['components'].items():
        require(hashlib.sha256((root/'tools/carla_lane_oracle'/name).read_bytes()).hexdigest()
                == expected, 'component record changed: ' + name)
    return record

def predecessor_pins(root, filename):
    """Verify active bytes, reverse every admitted edit, verify historical bytes."""
    filename = str(filename).split('/')[-1]
    record = read_record(root)['pin_files'][filename]
    try:
        import coverage_followup_contracts as followup
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import coverage_followup_contracts as followup
    payload = followup.predecessor_pins(root, filename)
    require(hashlib.sha256(payload).hexdigest() == record['after_sha256'],
            'unreviewed runtime pin successor: ' + filename if filename == 'runtime-source-pins.json' else 'unreviewed guarded pin successor: ' + filename)
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
    require(hashlib.sha256(original).hexdigest() == record['before_sha256'],
            'historical pin reconstruction failed: ' + filename)
    return original

def verify(root):
    record = read_record(root)
    for name in record['pin_files']:
        predecessor_pins(root, name)
    for path, item in record['sources'].items():
        matches = source.token_sha256((root/path).read_text()) == item['after_token_sha256']
        if not matches:
            try:
                import coverage_followup_contracts as followup
            except ModuleNotFoundError:
                from tools.carla_lane_oracle import coverage_followup_contracts as followup
            matches = followup.accepts_predecessor_source(root,path,item['after_token_sha256'])
        require(matches, 'complete successor changed: ' + path)
    curve.verify(root)
    grouped.verify(root)
    try:
        import lane_control_contracts as lane
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import lane_control_contracts as lane
    lane.verify(root)
    return record
