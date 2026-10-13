# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Four exact #333 runtime-boundary consumer edges, never arbitrary repinning.

The border-parser and winner-sign records pin these Map consumers as
unchanged live inputs. This record admits one reviewed edge for each: its
historical digest before, and its exact source and token digests after. The
bound correctness tests and compile-fail fixtures must also be unchanged.
The runtime view record can extend an edge by one exact reviewed step; the
composed edge still starts at the historical digest. Any other consumer
change still fails closed in both records.
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
    from . import consumer_successor_ledger as ledger
else:
    import source_contracts as source
    import consumer_successor_ledger as ledger

MIGRATION = 'tools/carla_lane_oracle/runtime-boundary-successor.json'
MIGRATION_SHA256 = '992854b1191bd365fca3e5e8d3a7fc751ac2eb3196b33684e04ebad833baab00'
MODULES = ('extensions/carla/cameras.mojo', 'extensions/carla/lane_invasion.mojo',
           'extensions/carla/sensor_manager.mojo', 'extensions/carla/world.mojo')
FIXTURES = tuple(f'tests/compile_fail/carla_{name}.mojo' for name in (
    'event_camera_time_rejects_float32_duration', 'event_camera_time_rejects_length',
    'event_camera_time_rejects_raw_float64', 'lane_invasion_time_rejects_float32_duration',
    'lane_invasion_time_rejects_length', 'lane_invasion_time_rejects_raw_float64',
    'light_search_distance_rejects_duration', 'light_search_distance_rejects_float32_length',
    'light_search_distance_rejects_raw_float64'))
TESTS = ('tests/test_carla_sensors.mojo', 'tests/test_carla_sensors_world.mojo',
         'tests/test_carla_world_signals.mojo', *FIXTURES)
PROTECTED_INPUTS = (MIGRATION, *MODULES, *TESTS)


def _check_operation(root, operation):
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    full_audit._operation_check(operation, root)


def _observe_bytes(root, path, payload, *, _operation=None):
    if _operation is None:
        return payload
    if __package__:
        from . import full_audit_cleanup_contracts as full_audit
    else:
        import full_audit_cleanup_contracts as full_audit
    return full_audit._observe_bytes(root, path, payload, _operation=_operation)



def require(value, message):
    if not value:
        raise ValueError('reviewed runtime boundary successor: ' + message)


def verify(root, *, _operation=None):
    """Verify live ledger endpoints; return the original historical edges.

    Root contracts compose these descriptors with the ledger exactly once.
    """
    if _operation is not None:
        _check_operation(root, _operation)
    raw = _typed_source.historical_bytes(root, MIGRATION, _observe_bytes(root, MIGRATION, (root/MIGRATION).read_bytes(),
                         _operation=_operation), _operation=_operation)
    require(hashlib.sha256(raw).hexdigest() == MIGRATION_SHA256, 'unreviewed exact edge')
    record = json.loads(raw, object_pairs_hook=source.unique_keys)
    require(type(record['schema']) is int and record['schema'] == 1
            and record['issue'] == 333 and set(record['edges']) == set(MODULES),
            'unexpected successor scope')
    require(set(record['correctness_tests']) == set(TESTS), 'unexpected correctness test set')
    if __package__:
        from . import runtime_view_contracts as view
    else:
        import runtime_view_contracts as view
    steps = view.steps(root, _operation=_operation)
    require(set(steps) <= set(MODULES), 'runtime view step outside the boundary scope')
    edges = {}
    for path in MODULES:
        edge = record['edges'][path]
        require(set(edge) == {'before_sha256', 'after_sha256', 'before_token_sha256',
                              'after_token_sha256'}
                and edge['before_sha256'] != edge['after_sha256'], 'malformed edge: ' + path)
        if path in steps:
            # A later reviewed step starts exactly where this edge ends.
            step = steps[path]
            require(step['before_sha256'] == edge['after_sha256']
                    and step['before_token_sha256'] == edge['after_token_sha256'],
                    'runtime view step does not extend the edge: ' + path)
            edge = {**edge, 'after_sha256': step['after_sha256'],
                    'after_token_sha256': step['after_token_sha256']}
        current = ledger.endpoint(root, path, edge, _operation=_operation)
        actual = _typed_source.historical_bytes(root, path, _observe_bytes(root, path, (root/path).read_bytes(),
                                _operation=_operation), _operation=_operation)
        require(hashlib.sha256(actual).hexdigest() == current['after_sha256']
                and source.token_sha256(actual.decode('utf-8')) == current['after_token_sha256'],
                'unreviewed runtime boundary consumer: ' + path)
        edges[path] = {'path': path, **edge}
    for path, expected in record['correctness_tests'].items():
        require(hashlib.sha256(_typed_source.historical_bytes(root, path, _observe_bytes(root, path, (root/path).read_bytes(),
                                             _operation=_operation), _operation=_operation)).hexdigest() == expected,
                'bound runtime boundary test changed: ' + path)
    return edges
