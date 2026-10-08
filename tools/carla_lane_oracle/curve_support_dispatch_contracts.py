# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Source-bound private support and dispatch successor, without a coverage waiver.

The exact historical pin files stay immutable in this standalone proposal.
A composed integration must migrate runtime and guarded-caller pins separately.
"""
import hashlib
import json

try:
    import source_contracts as source
except ModuleNotFoundError:
    from tools.carla_lane_oracle import source_contracts as source

MIGRATION = 'tools/carla_lane_oracle/curve-support-dispatch-migration.json'
MIGRATION_SHA256 = '1a6d7794bf0869a1e717685e556d8400e075ab97917ce8d855da6bd61c3ee19f'
SOURCE_PATHS = tuple('extensions/carla/' + name + '.mojo' for name in
                     ('curve_minimizer_support', 'curve_sample_dispatch'))
PROTECTED_INPUTS = (MIGRATION, *SOURCE_PATHS, 'extensions/carla/curve_interval.mojo',
                    'extensions/carla/curve_sum2.mojo', 'extensions/carla/curve_bounds.mojo',
                    'extensions/carla/map.mojo', 'extensions/carla/lane_refinement.mojo')


def require(condition, message):
    if not condition:
        raise ValueError('curve support/dispatch contract: ' + message)


def read_record(root):
    payload = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256,
            'unreviewed migration record')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(record['schema'] == 1 and set(record['sources']) == set(SOURCE_PATHS),
            'wrong successor schema or source set')
    return record



def reviewed_source(root, path, expected):
    """Compose the exact raw inverse theorem with this retained outer proof."""
    text = (root/path).read_text()
    if source.token_sha256(text) == expected:
        return text
    require(path == 'extensions/carla/curve_sample_dispatch.mojo',
            'unreviewed source successor: ' + path)
    try:
        import raw_cut_inverse_contracts as raw
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import raw_cut_inverse_contracts as raw
    record = raw.verify(root)
    require(record['before_token_sha256'] == expected, 'raw predecessor edge mismatch')
    return record['before_source']

def verify_premises(root):
    # Deliberately independent of complete-module successor digest checks.
    # Bind operation graphs, local guards, full caller bodies, and declarations.
    try:
        import sum2_guard_contracts as guard
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import sum2_guard_contracts as guard
    record = read_record(root)
    for path, item in record['sources'].items():
        require(guard.significant(reviewed_source(root,path,item['after_token_sha256'])) ==
                guard.significant(item['after_source']), 'successor operations changed: ' + path)
    for path, item in record['premise_modules'].items():
        require(guard.significant((root/path).read_text()) ==
                guard.significant(item['source']), 'interval/environment premise changed: ' + path)
    for item in record['premise_functions']:
        text = (root/item['path']).read_text()
        actual = guard.declaration(text, item['name'], tuple(item['owner']))
        matched = guard.significant(actual) == guard.significant(item['source'])
        if not matched and (item['path'], item['name'], tuple(item['owner'])) == (
                'extensions/carla/map.mojo', '_try_winner_seed', ()):
            try:
                try:
                    import seed_count_contracts as seed_count
                except ModuleNotFoundError:
                    from tools.carla_lane_oracle import seed_count_contracts as seed_count
                predecessor = seed_count.reviewed_text(root, item['path'], text)
                actual = guard.declaration(predecessor, item['name'], ())
                matched = guard.significant(actual) == guard.significant(item['source'])
            except (ValueError, OSError) as error:
                require(False, 'reviewed Map caller premise changed: ' + str(error))
        if not matched and item['path'] == 'extensions/carla/lane_refinement.mojo':
            try:
                try:
                    import lane_control_contracts as lane
                except ModuleNotFoundError:
                    from tools.carla_lane_oracle import lane_control_contracts as lane
                matched = lane.accepts_predecessor(root, item['path'], item['name'],
                                                  tuple(item['owner']), item['source'])
            except RuntimeError as error:
                require(False, 'reviewed lane caller premise changed: ' + str(error))
        require(matched, 'index or guarded caller premise changed: ' + item['name'])
    for item in record['reference_functions']:
        actual = guard.declaration((root/item['path']).read_text(), item['name'], ())
        require(source.token_sha256(actual) == item['token_sha256'],
                'native predecessor reference changed: ' + item['name'])
    return record


def verify(root):
    record = read_record(root)
    for path, item in record['sources'].items():
        require(source.token_sha256(reviewed_source(root,path,item['after_token_sha256'])) == item['after_token_sha256'],
                'complete successor changed: ' + path)
    verify_premises(root)
    return record


def verify_historical_pin_inputs(root):
    # Use only before the centrally reviewed integration migration. This is
    # not called by verify: a later exact pin successor must remain possible.
    record = read_record(root)
    for path, expected in record['historical_pins'].items():
        require(hashlib.sha256((root/path).read_bytes()).hexdigest() == expected,
                'standalone historical pin input changed: ' + path)
