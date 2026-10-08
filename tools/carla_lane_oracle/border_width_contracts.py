# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""One exact OpenDRIVE border-width successor (#577), never arbitrary repinning."""
import hashlib
import json
try:
    import source_contracts as source
except ModuleNotFoundError:
    from tools.carla_lane_oracle import source_contracts as source
MIGRATION = 'tools/carla_lane_oracle/border-width-successor.json'
MIGRATION_SHA256 = '98d7445347941c9336753186bf5fdc9e0192a9c93b03178fba515115a743406e'
MODULE = 'extensions/carla/opendrive.mojo'
TESTS = ('tests/test_carla_lane_borders.mojo',)
PROTECTED_INPUTS = (MIGRATION, MODULE, *TESTS)


def require(value, message):
    if not value:
        raise ValueError('reviewed border-width successor: ' + message)


def verify(root):
    raw = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(raw).hexdigest() == MIGRATION_SHA256, 'unreviewed exact edge')
    record = json.loads(raw, object_pairs_hook=source.unique_keys)
    require(type(record['schema']) is int and record['schema'] == 1 and record['path'] == MODULE,
            'unexpected successor scope')
    require(set(record['correctness_tests']) == set(TESTS), 'unexpected correctness test set')
    actual = (root/MODULE).read_bytes()
    require(hashlib.sha256(actual).hexdigest() == record['after_sha256']
            and source.token_sha256(actual.decode()) == record['after_token_sha256'],
            'reader source differs from the reviewed border-width edge')
    for path, expected in record['correctness_tests'].items():
        require(hashlib.sha256((root/path).read_bytes()).hexdigest() == expected,
                'bound border-width correctness test changed: ' + path)
    return record
