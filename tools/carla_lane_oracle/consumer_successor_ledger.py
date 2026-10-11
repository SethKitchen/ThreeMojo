# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""One pinned ledger of reviewed consumer edges for both Map records (#703).

The border-parser and winner-sign records pin most of `extensions/carla/`
as unchanged live inputs. A reviewed change to one of those consumers adds
one edge to this ledger, not a module of its own. An edge names one
consumer, the issue that reviewed it, its source and token digests before
and after, and the correctness tests bound to it. This module pins the
ledger by digest, so only a reviewed change to that pin admits an edge.

The edges of one consumer form a chain in ledger order: each edge starts at
the previous edge's after digest. The first edge must start where each
record already is: at the end of a successor that the record knows, or at
its historical pin. Both records check that start, so the ledger cannot
move a pin by itself. The live source must equal the last edge's after
digest, and the last edge's bound tests must be unchanged. Any other
consumer change still fails closed in both records.
"""
import hashlib
import json
import re
from pathlib import Path

if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

LEDGER = 'tools/carla_lane_oracle/consumer-successor-ledger.json'
LEDGER_SHA256 = 'cd618a63c3128ee53f7221c13250744b2eca2621575a1faf2cd6f1822626764f'
# The records that consult the ledger, and the group of each that pins the
# consumers. An edge must name a consumer that one of them pins.
RECORDS = (('tools/carla_lane_oracle/border-parser-successor.json', 'unchanged_inputs'),
           ('tools/carla_lane_oracle/winner-sign-query-migration.json',
            'canonical_source_unchanged'))
# These sources have reviewed contracts of their own, which the records
# consult separately. A ledger edge cannot take them over.
OWN_CONTRACTS = ('extensions/carla/map.mojo', 'extensions/carla/opendrive.mojo')
EDGE_KEYS = {'issue', 'path', 'before_sha256', 'after_sha256', 'before_token_sha256',
             'after_token_sha256', 'correctness_tests'}
DIGEST = re.compile(r'[0-9a-f]{64}')
CONSUMER = re.compile(r'extensions/carla/[A-Za-z0-9_]+\.mojo')
TEST = re.compile(r'tests/(?:compile_fail/)?[A-Za-z0-9_]+\.mojo')


def require(value, message):
    """Keep every gate active under optimized Python."""
    if not value:
        raise ValueError('reviewed consumer successor ledger: ' + message)


def _sha(content):
    return hashlib.sha256(content).hexdigest()


def _digest(value):
    return type(value) is str and DIGEST.fullmatch(value) is not None


def read_edges(root):
    """Return the ledger's edges once its bytes match the reviewed pin.

    Raises:
        ValueError: If the ledger is not the reviewed one or is malformed.
    """
    raw = (Path(root)/LEDGER).read_bytes()
    require(_sha(raw) == LEDGER_SHA256, 'unreviewed ledger')
    record = json.loads(raw, object_pairs_hook=source.unique_keys)
    require(type(record) is dict and set(record) == {'schema', 'scope', 'edges'}
            and type(record['schema']) is int and record['schema'] == 1
            and type(record['edges']) is list, 'unexpected ledger shape')
    return record['edges']


def _pinned(root):
    pinned = set()
    for path, group in RECORDS:
        pinned.update(json.loads((Path(root)/path).read_bytes())[group])
    return pinned


def _check_edge(edge, pinned):
    require(type(edge) is dict and set(edge) == EDGE_KEYS, 'malformed edge')
    path = edge['path']
    require(type(path) is str and CONSUMER.fullmatch(path) is not None
            and path not in OWN_CONTRACTS and path in pinned,
            'edge outside the pinned consumers: ' + str(path))
    require(type(edge['issue']) is int and edge['issue'] > 0, 'edge has no issue: ' + path)
    require(all(_digest(edge[key]) for key in ('before_sha256', 'after_sha256',
                                               'before_token_sha256', 'after_token_sha256'))
            and edge['before_sha256'] != edge['after_sha256'], 'malformed digests: ' + path)
    tests = edge['correctness_tests']
    require(type(tests) is dict and tests
            and all(type(name) is str and TEST.fullmatch(name) is not None and _digest(value)
                    for name, value in tests.items()),
            'an edge must bind its correctness tests: ' + path)


def verify(root):
    """Return the reviewed chain of each consumer once its live source ends it.

    Returns:
        A dict from each consumer path to its chain: the first edge's before
        digests and the last edge's after digests.

    Raises:
        ValueError: If the ledger is not the reviewed one, an edge is
            malformed or does not start at the previous edge, a live
            consumer is not the last reviewed edge, or a bound test changed.
    """
    root = Path(root)
    edges = read_edges(root)
    pinned = _pinned(root)
    chains = {}
    last = {}
    for edge in edges:
        _check_edge(edge, pinned)
        path = edge['path']
        if path in chains:
            require(edge['before_sha256'] == chains[path]['after_sha256']
                    and edge['before_token_sha256'] == chains[path]['after_token_sha256'],
                    'edge does not start at the previous edge: ' + path)
            chains[path]['after_sha256'] = edge['after_sha256']
            chains[path]['after_token_sha256'] = edge['after_token_sha256']
        else:
            chains[path] = {'path': path,
                            **{key: edge[key] for key in ('before_sha256', 'after_sha256',
                                                          'before_token_sha256',
                                                          'after_token_sha256')}}
        last[path] = edge
    for path, chain in chains.items():
        actual = (root/path).read_bytes()
        require(_sha(actual) == chain['after_sha256']
                and source.token_sha256(actual.decode('utf-8')) == chain['after_token_sha256'],
                'live consumer is not the last reviewed edge: ' + path)
        for name, expected in last[path]['correctness_tests'].items():
            require((root/name).is_file() and _sha((root/name).read_bytes()) == expected,
                    'bound correctness test changed: ' + name)
    return chains


def extend(successors, root):
    """Return a record's successors, extended by the ledger's chains.

    Args:
        successors: The successor of each consumer that the record knows,
            with `before_sha256` and `after_sha256`.
        root: The repository root.

    Returns:
        A new dict. A chain for a known consumer keeps its known start and
        takes the chain's end. A chain for any other consumer is added; the
        record then checks that it starts at the record's historical pin.

    Raises:
        ValueError: If the ledger does not verify, or a chain does not
            start where the record's known successor ends.
    """
    result = dict(successors)
    for path, chain in verify(root).items():
        if path in result:
            require(result[path]['after_sha256'] == chain['before_sha256'],
                    'ledger edge does not start at the previous successor: ' + path)
            merged = dict(result[path])
            merged['after_sha256'] = chain['after_sha256']
            merged['after_token_sha256'] = chain['after_token_sha256']
            result[path] = merged
        else:
            result[path] = chain
    return result
