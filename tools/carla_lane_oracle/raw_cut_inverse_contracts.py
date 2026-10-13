# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Exact guarded raw-inverse successor; no unproved branch exclusion."""

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source
import hashlib
# #333 explicit historical provenance views; current inputs remain operation-owned.
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
    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256,
            'unreviewed migration record')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(record['schema'] == 1 and record['path'] == SOURCE_PATH,
            'wrong successor source or schema')
    require(source.token_sha256(record['before_source']) == record['before_token_sha256']
            and source.token_sha256(record['after_source']) == record['after_token_sha256'],
            'recorded source/token mismatch')
    return record


def verify_premises(root, *, _operation=None):
    # Independently bind the complete lexical operations rather than relying
    # on the successor digest. The proof requires this exact stored predicate,
    # fresh environment guard, admission tests, and ordered adjacent candidates.
    if __package__:
        from . import sum2_guard_contracts as guard
    else:
        import sum2_guard_contracts as guard
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
    record = read_record(root)
    text = (root/SOURCE_PATH).read_text()
    if _operation is not None:
        text = full_audit._observe_text(root, SOURCE_PATH, text, _operation=_operation)
    text = _typed_source.historical_text(root, SOURCE_PATH, text, _operation=_operation)
    require(guard.significant(text) ==
            guard.significant(record['after_source']), 'raw inverse operation graph changed')
    environment = (root/'extensions/carla/curve_sum2.mojo').read_text()
    if _operation is not None:
        environment = full_audit._observe_text(root, 'extensions/carla/curve_sum2.mojo', environment, _operation=_operation)
    environment = _typed_source.historical_text(root, 'extensions/carla/curve_sum2.mojo', environment, _operation=_operation)
    require(guard.significant(environment) ==
            guard.significant(record['environment_source']), 'environment guard premise changed')
    predecessor_payload = _typed_source.historical_bytes(root, root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json', (root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_bytes(), _operation=_operation)
    require(hashlib.sha256(predecessor_payload).hexdigest() ==
            record['predecessor_migration_sha256'], 'historical predecessor record changed')
    predecessor_text = (root/'tools/carla_lane_oracle/curve-support-dispatch-migration.json').read_text()
    if _operation is not None:
        predecessor_text = full_audit._observe_text(root, 'tools/carla_lane_oracle/curve-support-dispatch-migration.json', predecessor_text, _operation=_operation, _checked_raw=predecessor_payload)
    predecessor_text = _typed_source.historical_text(root, 'tools/carla_lane_oracle/curve-support-dispatch-migration.json', predecessor_text, _operation=_operation)
    predecessor = json.loads(predecessor_text,
                             object_pairs_hook=source.unique_keys)
    require(predecessor['sources'][SOURCE_PATH]['after_token_sha256'] ==
            record['before_token_sha256'], 'successor is not bound to accepted predecessor')
    fixture = (root/'tests/test_carla_raw_cut_successor.mojo').read_text()
    if _operation is not None:
        fixture = full_audit._observe_text(root, 'tests/test_carla_raw_cut_successor.mojo', fixture, _operation=_operation)
    fixture = _typed_source.historical_text(root, 'tests/test_carla_raw_cut_successor.mojo', fixture, _operation=_operation)
    require(source.token_sha256(fixture) ==
            record['native_fixture_token_sha256'], 'independent exact-word native fixture changed')
    reference = (root/'tests/test_carla_support_dispatch_successor.mojo').read_text()
    if _operation is not None:
        reference = full_audit._observe_text(root, 'tests/test_carla_support_dispatch_successor.mojo', reference, _operation=_operation)
    reference = _typed_source.historical_text(root, 'tests/test_carla_support_dispatch_successor.mojo', reference, _operation=_operation)
    ref = guard.declaration(reference,
                            '_reference_sample_dispatch_cut', ())
    require(guard.significant(ref) == guard.significant(record['native_reference_source']),
            'native predecessor reference changed')
    return record


def verify(root, *, _operation=None):
    if _operation is not None:
        if __package__:
            from . import full_audit_cleanup_contracts as full_audit
        else:
            import full_audit_cleanup_contracts as full_audit
    record = read_record(root)
    text = (root/SOURCE_PATH).read_text()
    if _operation is not None:
        text = full_audit._observe_text(root, SOURCE_PATH, text, _operation=_operation)
    text = _typed_source.historical_text(root, SOURCE_PATH, text, _operation=_operation)
    require(source.token_sha256(text) == record['after_token_sha256'],
            'complete raw inverse successor changed')
    verify_premises(root, _operation=_operation)
    return record
