# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Explicit reviewed raw-cut, finite-moment, budget, and ordered-lane lineage."""
import hashlib
import json
try:
    import source_contracts as source
except ModuleNotFoundError:
    from tools.carla_lane_oracle import source_contracts as source
try:
    import accepted_successor_contracts as accepted
except ModuleNotFoundError:
    from tools.carla_lane_oracle import accepted_successor_contracts as accepted
try:
    import cache_key_contracts as cache_key
except ModuleNotFoundError:
    from tools.carla_lane_oracle import cache_key_contracts as cache_key


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

def require(condition, message):
    if not condition:
        raise ValueError('coverage followup successor: ' + message)

def read_record(root):
    payload = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256, 'unreviewed migration record')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(type(record['schema']) is int and record['schema'] == 1
            and set(record['sources']) == set(SOURCE_PATHS), 'wrong exact successor set')
    prior = root/'tools/carla_lane_oracle/coverage-invariant-migration.json'
    require(hashlib.sha256(prior.read_bytes()).hexdigest() ==
            record['prior_invariant_migration_sha256'], 'historical invariant record changed')
    for name, digest in record['components'].items():
        require(hashlib.sha256((root/'tools/carla_lane_oracle'/name).read_bytes()).hexdigest()
                == digest, 'component migration record changed: ' + name)
    return record

def predecessor_pins(root, filename):
    filename = str(filename).split('/')[-1]
    record = read_record(root)['pin_files'][filename]
    payload = accepted.predecessor_pins(root, filename)
    require(hashlib.sha256(payload).hexdigest() == record['after_sha256'],
            'unreviewed runtime pin successor: ' + filename)
    pins = json.loads(payload, object_pairs_hook=source.unique_keys)
    seen = set()
    for change in record['transitions']:
        pointer = tuple(change['pointer'])
        require(pointer not in seen, 'duplicate pin placement')
        seen.add(pointer)
        ref = pins
        for part in pointer[:-1]: ref = ref[part]
        require(ref[pointer[-1]] == change['after'], 'active pin placement mismatch')
        ref[pointer[-1]] = change['before']
    payload = (json.dumps(pins,indent=2)+'\n').encode()
    require(hashlib.sha256(payload).hexdigest() == record['before_sha256'],
            'historical pin reconstruction failed')
    return payload

def verify(root):
    record = read_record(root)
    for name in record['pin_files']: predecessor_pins(root,name)
    for path,item in record['sources'].items():
        require(source.token_sha256(accepted.predecessor_text(root, path) if path in accepted.SOURCE_PATHS else cache_key.reviewed_text(root, path, (root/path).read_text())) == item['after_token_sha256'],
                'complete successor changed: ' + path)
    try:
        import raw_cut_inverse_contracts as raw
        import moment_finiteness_contracts as moment
        import envelope_budget_contracts as budget
        import lane_order_contracts as order
        import selection_finiteness_contracts as selection
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import raw_cut_inverse_contracts as raw
        from tools.carla_lane_oracle import moment_finiteness_contracts as moment
        from tools.carla_lane_oracle import envelope_budget_contracts as budget
        from tools.carla_lane_oracle import lane_order_contracts as order
        from tools.carla_lane_oracle import selection_finiteness_contracts as selection
    raw.verify(root); moment.verify(root); budget.verify(root); order.verify(root); selection.verify(root)
    return record

def accepts_predecessor_source(root,path,expected):
    record = verify(root)
    return path in record['sources'] and record['sources'][path]['before_token_sha256'] == expected
