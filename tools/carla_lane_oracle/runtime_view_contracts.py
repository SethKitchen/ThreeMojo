# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Two exact #333 runtime-view steps after the reviewed runtime boundary edges.

The runtime boundary record admits one reviewed edge for each of four Map
consumers. This record admits one more step for two of them: the lane
invasion event takes a Duration64 and the sensor measurement gets a typed
time view. Each step starts at the exact after digests of the runtime
boundary edge and names the exact after source and token digests. The
runtime boundary check composes the step; the border-parser and winner-sign
records then see one edge from the historical digest to the live source.
The bound correctness test and compile-fail fixtures must be unchanged.
This module reads no consumer source; it never repins one by itself.
"""
import hashlib
import json

if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

MIGRATION = 'tools/carla_lane_oracle/runtime-view-successor.json'
MIGRATION_SHA256 = '40fe6f5aef91b4a9f407f1a8ea83721b317d24b690d947c623feca8b73dcc907'
MODULES = ('extensions/carla/lane_invasion.mojo', 'extensions/carla/sensor_manager.mojo')
FIXTURES = tuple(f'tests/compile_fail/carla_{name}.mojo' for name in (
    'lane_invasion_event_time_rejects_float32_duration',
    'lane_invasion_event_time_rejects_length',
    'lane_invasion_event_time_rejects_raw_float64',
    'measurement_time_is_not_a_raw_float64'))
TESTS = ('tests/test_carla_event_time_quantity.mojo', *FIXTURES)
PROTECTED_INPUTS = (MIGRATION, *TESTS)
KEYS = frozenset({'before_sha256', 'after_sha256', 'before_token_sha256',
                  'after_token_sha256'})


def require(value, message):
    """Keep every gate active under optimized Python."""
    if not value:
        raise ValueError('reviewed runtime view successor: ' + message)


def steps(root):
    """Return each reviewed step by path once its record and tests match."""
    raw = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(raw).hexdigest() == MIGRATION_SHA256, 'unreviewed exact step')
    record = json.loads(raw, object_pairs_hook=source.unique_keys)
    require(type(record['schema']) is int and record['schema'] == 1
            and record['issue'] == 333 and set(record['steps']) == set(MODULES),
            'unexpected successor scope')
    require(set(record['correctness_tests']) == set(TESTS), 'unexpected correctness test set')
    result = {}
    for path in MODULES:
        step = record['steps'][path]
        require(set(step) == KEYS and step['before_sha256'] != step['after_sha256']
                and step['before_token_sha256'] != step['after_token_sha256'],
                'malformed step: ' + path)
        result[path] = dict(step)
    for path, expected in record['correctness_tests'].items():
        require(hashlib.sha256((root/path).read_bytes()).hexdigest() == expected,
                'bound runtime view test changed: ' + path)
    return result
