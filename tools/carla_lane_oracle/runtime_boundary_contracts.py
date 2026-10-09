# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Four exact #333 runtime-boundary consumer edges, never arbitrary repinning.

The border-parser and winner-sign records pin these Map consumers as
unchanged live inputs. This record admits one reviewed edge for each: its
historical digest before, and its exact source and token digests after. The
bound correctness tests and compile-fail fixtures must also be unchanged.
Any other consumer change still fails closed in both records.
"""
import hashlib
import json

if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

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


def require(value, message):
    if not value:
        raise ValueError('reviewed runtime boundary successor: ' + message)


def verify(root):
    """Return each reviewed edge by path once the live sources match it."""
    raw = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(raw).hexdigest() == MIGRATION_SHA256, 'unreviewed exact edge')
    record = json.loads(raw, object_pairs_hook=source.unique_keys)
    require(type(record['schema']) is int and record['schema'] == 1
            and record['issue'] == 333 and set(record['edges']) == set(MODULES),
            'unexpected successor scope')
    require(set(record['correctness_tests']) == set(TESTS), 'unexpected correctness test set')
    edges = {}
    for path in MODULES:
        edge = record['edges'][path]
        require(set(edge) == {'before_sha256', 'after_sha256', 'before_token_sha256',
                              'after_token_sha256'}
                and edge['before_sha256'] != edge['after_sha256'], 'malformed edge: ' + path)
        actual = (root/path).read_bytes()
        require(hashlib.sha256(actual).hexdigest() == edge['after_sha256']
                and source.token_sha256(actual.decode('utf-8')) == edge['after_token_sha256'],
                'unreviewed runtime boundary consumer: ' + path)
        edges[path] = {'path': path, **edge}
    for path, expected in record['correctness_tests'].items():
        require(hashlib.sha256((root/path).read_bytes()).hexdigest() == expected,
                'bound runtime boundary test changed: ' + path)
    return edges
