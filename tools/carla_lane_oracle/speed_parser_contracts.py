# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""One exact parser grammar/correctness successor, never arbitrary repinning."""
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
MIGRATION = 'tools/carla_lane_oracle/speed-parser-successor.json'
MIGRATION_SHA256 = '47e949673fb8740816c06d455654c7e7ae43f65ce7d7568a201e83ae16c49364'
MODULE = 'extensions/carla/speed_limits.mojo'
TESTS = ('tests/test_carla_speed_lexical.mojo', 'tests/test_carla_speed_xml_lexical.mojo')
PROTECTED_INPUTS = (MIGRATION, MODULE, *TESTS)


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



def require(value, message):
    if not value:
        raise ValueError('reviewed speed parser successor: ' + message)


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    raw = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes(), _operation=_operation)
    require(hashlib.sha256(raw).hexdigest() == MIGRATION_SHA256, 'unreviewed exact edge')
    record = json.loads(raw, object_pairs_hook=source.unique_keys)
    require(type(record['schema']) is int and record['schema'] == 1 and record['path'] == MODULE,
            'unexpected successor scope')
    require(set(record['correctness_tests']) == set(TESTS), 'unexpected correctness test set')
    require(hashlib.sha256(_typed_source.historical_bytes(root, root/'tools/carla_lane_oracle/accepted-successor-migration.json', (root/'tools/carla_lane_oracle/accepted-successor-migration.json').read_bytes(), _operation=_operation)).hexdigest()
            == record['prior_accepted_migration_sha256'], 'prior accepted lineage changed')
    for side in ('before', 'after'):
        text = record[side+'_complete_module']
        require(hashlib.sha256(text.encode()).hexdigest() == record[side+'_sha256']
                and source.token_sha256(text) == record[side+'_token_sha256'], 'recorded source identity changed')
    require(source.token_sha256(_typed_source.historical_text(root, MODULE, _observe_text(
        root, MODULE, (root/MODULE).read_text(), _operation=_operation), _operation=_operation)) == record['after_token_sha256'],
            'actual grammar, validation, binding or mantissa graph changed')
    for path, expected in record['correctness_tests'].items():
        require(hashlib.sha256(_typed_source.historical_bytes(root, root/path, (root/path).read_bytes(), _operation=_operation)).hexdigest() == expected,
                'bound parser/XML correctness test changed: ' + path)
    return record
