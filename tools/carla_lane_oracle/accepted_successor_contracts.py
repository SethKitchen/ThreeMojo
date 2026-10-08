# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Explicit current-graph checks before reversible historical projection."""
import hashlib
import json
try:
    import source_contracts as source
except ModuleNotFoundError:
    from tools.carla_lane_oracle import source_contracts as source

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
    record = read_record(root)
    for path, item in record['sources'].items():
        require(source.token_sha256((root/path).read_text()) == item['after_token_sha256'],
                'unreviewed complete successor: ' + path)
        require(hashlib.sha256(item['before_complete_module'].encode()).hexdigest()
                == item['before_sha256'], 'historical module changed: ' + path)
    try:
        import rounded_line_selector_contracts as line
        import distance_validation_contracts as distance
        import grouped_y_finiteness_contracts as grouped
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import rounded_line_selector_contracts as line
        from tools.carla_lane_oracle import distance_validation_contracts as distance
        from tools.carla_lane_oracle import grouped_y_finiteness_contracts as grouped
    try:
        line.verify(root)
        distance.verify(root)
        grouped.verify(root)
    except ValueError as error:
        raise ValueError(
            'unreviewed complete successor: ' + str(error)) from error
    return record


def predecessor_text(root, path):
    record = verify_current(root)
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
