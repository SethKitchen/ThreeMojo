# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact guarded raw-inverse successor; no unproved branch exclusion."""
import hashlib
import json
if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

MIGRATION = 'tools/carla_lane_oracle/raw-cut-inverse-migration.json'
MIGRATION_SHA256 = '4f4eb051d9c1f9194796d3073fcadfa9f49dda4c44a851da0a3409ba09587dd0'
SOURCE_PATH = 'extensions/carla/curve_sample_dispatch.mojo'
PROTECTED_INPUTS = (MIGRATION, SOURCE_PATH, 'extensions/carla/curve_sum2.mojo',
                    'tools/carla_lane_oracle/curve-support-dispatch-migration.json',
                    'tests/test_carla_raw_cut_successor.mojo',
                    'tests/test_carla_support_dispatch_successor.mojo')


def require(condition, message):
    if not condition:
        raise ValueError('raw cut inverse contract: ' + message)


def read_record(root):
    payload = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256,
            'unreviewed migration record')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(record['schema'] == 1 and record['path'] == SOURCE_PATH,
            'wrong successor source or schema')
    require(source.token_sha256(record['before_source']) == record['before_token_sha256']
            and source.token_sha256(record['after_source']) == record['after_token_sha256'],
            'recorded source/token mismatch')
    return record


def verify_premises(root):
    # Independently bind the complete lexical operations rather than relying
    # on the successor digest. The proof requires this exact stored predicate,
    # fresh environment guard, admission tests, and ordered adjacent candidates.
    if __package__:
        from . import sum2_guard_contracts as guard
    else:
        import sum2_guard_contracts as guard
    record = read_record(root)
    require(guard.significant((root/SOURCE_PATH).read_text()) ==
            guard.significant(record['after_source']), 'raw inverse operation graph changed')
    require(guard.significant((root/'extensions/carla/curve_sum2.mojo').read_text()) ==
            guard.significant(record['environment_source']), 'environment guard premise changed')
    require(hashlib.sha256((root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_bytes()).hexdigest() ==
            record['predecessor_migration_sha256'], 'historical predecessor record changed')
    predecessor = json.loads((root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_text(),
                             object_pairs_hook=source.unique_keys)
    require(predecessor['sources'][SOURCE_PATH]['after_token_sha256'] ==
            record['before_token_sha256'], 'successor is not bound to accepted predecessor')
    require(source.token_sha256((root/'tests/test_carla_raw_cut_successor.mojo').read_text()) ==
            record['native_fixture_token_sha256'], 'independent exact-word native fixture changed')
    ref = guard.declaration((root/'tests/test_carla_support_dispatch_successor.mojo').read_text(),
                            '_reference_sample_dispatch_cut', ())
    require(guard.significant(ref) == guard.significant(record['native_reference_source']),
            'native predecessor reference changed')
    return record


def verify(root):
    record = read_record(root)
    require(source.token_sha256((root/SOURCE_PATH).read_text()) == record['after_token_sha256'],
            'complete raw inverse successor changed')
    verify_premises(root)
    return record
