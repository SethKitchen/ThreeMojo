# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""One exact #306 render-resource consumer edge, never arbitrary repinning.

The border-parser and winner-sign records pin this Map consumer as an
unchanged live input. This record admits one reviewed edge: its historical
digest before, and its exact source and token digests after. The bound
correctness tests must also be unchanged. Any other consumer change still
fails closed in both records.
"""
import hashlib
import json

if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

MIGRATION = 'tools/carla_lane_oracle/render-actor-reuse-successor.json'
MIGRATION_SHA256 = 'c4d146fe145289a1ad443956d2941d1e90186d448b8056f8be97d72f4f672771'
MODULES = ('extensions/carla/render_actors.mojo',)
TESTS = ('tests/test_carla_render_reuse.mojo', 'tests/test_carla_model_cache.mojo',
         'tests/test_carla_walker_render_motion.mojo')
PROTECTED_INPUTS = (MIGRATION, *MODULES, *TESTS)


def require(value, message):
    if not value:
        raise ValueError('reviewed render actor reuse successor: ' + message)


def verify(root):
    """Return each reviewed edge by path once the live sources match it."""
    raw = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(raw).hexdigest() == MIGRATION_SHA256, 'unreviewed exact edge')
    record = json.loads(raw, object_pairs_hook=source.unique_keys)
    require(type(record['schema']) is int and record['schema'] == 1
            and record['issue'] == 306 and set(record['edges']) == set(MODULES),
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
                'unreviewed render actor consumer: ' + path)
        edges[path] = {'path': path, **edge}
    for path, expected in record['correctness_tests'].items():
        require(hashlib.sha256((root/path).read_bytes()).hexdigest() == expected,
                'bound render actor test changed: ' + path)
    return edges
