# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Source-bound private support and dispatch successor, without a coverage waiver.

The exact historical pin files stay immutable in this standalone proposal.
A composed integration must migrate runtime and guarded-caller pins separately.
"""

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

MIGRATION = 'tools/carla_lane_oracle/curve-support-dispatch-migration.json'
MIGRATION_SHA256 = '1a6d7794bf0869a1e717685e556d8400e075ab97917ce8d855da6bd61c3ee19f'
SOURCE_PATHS = tuple('extensions/carla/' + name + '.mojo' for name in
                     ('curve_minimizer_support', 'curve_sample_dispatch'))
PROTECTED_INPUTS = (MIGRATION, *SOURCE_PATHS, 'extensions/carla/curve_interval.mojo',
                    'extensions/carla/curve_sum2.mojo', 'extensions/carla/curve_bounds.mojo',
                    'extensions/carla/map.mojo', 'extensions/carla/lane_refinement.mojo')


def _check_operation(root, operation):
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    full_audit._operation_check(operation, root)


def _observe_text(root, path, text, *, _operation=None, supplied=False):
    if _operation is None:
        return text
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    return full_audit._observe_text(
        root, path, text, _operation=_operation, supplied=supplied)



def require(condition, message):
    if not condition:
        raise ValueError('curve support/dispatch contract: ' + message)


def read_record(root):
    payload = _typed_source.historical_bytes(root, root/MIGRATION, (root/MIGRATION).read_bytes())
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256,
            'unreviewed migration record')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(record['schema'] == 1 and set(record['sources']) == set(SOURCE_PATHS),
            'wrong successor schema or source set')
    return record



def reviewed_source(root, path, expected, *, _operation=None):
    """Compose the exact raw inverse theorem with this retained outer proof."""
    if _operation is not None:
        _check_operation(root, _operation)
    text = _typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)
    if source.token_sha256(text) == expected:
        return text
    require(path == 'extensions/carla/curve_sample_dispatch.mojo',
            'unreviewed source successor: ' + path)
    if __package__:
        from . import raw_cut_inverse_contracts as raw
    else:
        import raw_cut_inverse_contracts as raw
    record = raw.verify(root, **({} if _operation is None else {'_operation': _operation}))
    require(record['before_token_sha256'] == expected, 'raw predecessor edge mismatch')
    return record['before_source']

def verify_premises(root, *, _operation=None):
    # Deliberately independent of complete-module successor digest checks.
    # Bind operation graphs, local guards, full caller bodies, and declarations.
    if _operation is not None:
        _check_operation(root, _operation)
    if __package__:
        from . import sum2_guard_contracts as guard
    else:
        import sum2_guard_contracts as guard
    record = read_record(root)
    operation_args = {} if _operation is None else {'_operation': _operation}
    for path, item in record['sources'].items():
        require(guard.significant(reviewed_source(root,path,item['after_token_sha256'], **operation_args)) ==
                guard.significant(item['after_source']), 'successor operations changed: ' + path)
    for path, item in record['premise_modules'].items():
        require(guard.significant(_typed_source.historical_text(root, path, _observe_text(root, path, (root/path).read_text(), _operation=_operation), _operation=_operation)) ==
                guard.significant(item['source']), 'interval/environment premise changed: ' + path)
    for item in record['premise_functions']:
        physical_text = _observe_text(root, item['path'], (root/item['path']).read_text(), _operation=_operation)
        text = _typed_source.historical_text(root, item['path'], physical_text, _operation=_operation)
        actual = guard.declaration(text, item['name'], tuple(item['owner']))
        matched = guard.significant(actual) == guard.significant(item['source'])
        if not matched and (item['path'], item['name'], tuple(item['owner'])) == (
                'extensions/carla/map.mojo', '_try_winner_seed', ()):
            try:
                if __package__:
                    from . import seed_count_contracts as seed_count
                else:
                    import seed_count_contracts as seed_count
                predecessor = seed_count.reviewed_text(root, item['path'], physical_text, **operation_args)
                actual = guard.declaration(predecessor, item['name'], ())
                matched = guard.significant(actual) == guard.significant(item['source'])
            except (ValueError, OSError) as error:
                require(False, 'reviewed Map caller premise changed: ' + str(error))
        if not matched and item['path'] == 'extensions/carla/lane_refinement.mojo':
            try:
                if __package__:
                    from . import lane_control_contracts as lane
                else:
                    import lane_control_contracts as lane
                matched = lane.accepts_predecessor(root, item['path'], item['name'],
                                                  tuple(item['owner']), item['source'], **operation_args)
            except RuntimeError as error:
                require(False, 'reviewed lane caller premise changed: ' + str(error))
        require(matched, 'index or guarded caller premise changed: ' + item['name'])
    for item in record['reference_functions']:
        actual = guard.declaration(_typed_source.historical_text(root, item['path'], _observe_text(root, item['path'], (root/item['path']).read_text(), _operation=_operation), _operation=_operation), item['name'], ())
        require(source.token_sha256(actual) == item['token_sha256'],
                'native predecessor reference changed: ' + item['name'])
    return record


def verify(root, *, _operation=None):
    if _operation is not None:
        _check_operation(root, _operation)
    record = read_record(root)
    operation_args = {} if _operation is None else {'_operation': _operation}
    for path, item in record['sources'].items():
        require(source.token_sha256(reviewed_source(root,path,item['after_token_sha256'], **operation_args)) == item['after_token_sha256'],
                'complete successor changed: ' + path)
    verify_premises(root, **operation_args)
    return record


def verify_historical_pin_inputs(root):
    # Use only before the centrally reviewed integration migration. This is
    # not called by verify: a later exact pin successor must remain possible.
    record = read_record(root)
    for path, expected in record['historical_pins'].items():
        require(hashlib.sha256(_typed_source.historical_bytes(root, root/path, (root/path).read_bytes())).hexdigest() == expected,
                'standalone historical pin input changed: ' + path)
