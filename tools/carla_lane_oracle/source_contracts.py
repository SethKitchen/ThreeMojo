#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Fail-closed source-integrity gates for the reviewed runtime dependency paths.

These gates bind complete source tokens, including qualifiers and imports.
They do not prove helper mathematics, runtime execution, termination or cost.
No checker updates pins automatically. Repository-controlled pins are reviewed
inputs, never an independent proof when changed together with production.
"""
from contextlib import contextmanager
from contextvars import ContextVar
from functools import lru_cache
import hashlib
import io
import json
from pathlib import Path
from threading import get_ident
import tokenize

PINS = Path('tools/carla_lane_oracle/runtime-source-pins.json')
PREFIX = 'extensions/carla/'
GROUP_PATHS = {
    'canonical_accumulation': tuple(PREFIX + name + '.mojo' for name in (
        'curve_sum2', 'lane_geometry', 'curve_interval', 'curve_bounds',
        'spiral_roundoff_proof', 'lane_refinement', 'map', 'map_builder',
        'spiral_domain_proof', 'spiral_moment_proof', 'spiral_moment_table')),
    'optional_runtime': tuple(PREFIX + name + '.mojo' for name in (
        'curve_minimizer_support', 'curve_objective_model', 'curve_sample_dispatch',
        'spiral_grouped_lane', 'spiral_grouped_roundoff_proof', 'curve_bounds',
        'lane_refinement', 'map', 'lane_value_bounds', 'curve_interval', 'curve_sum2',
        'curve_trig', 'lane_geometry', 'geometry', 'road_info', 'polynomial',
        'spiral_domain_proof', 'spiral_moment_proof', 'spiral_moment_table',
        'spiral_roundoff_proof', 'curve_frozen_arc')),
    'stored_arithmetic': (PREFIX + 'curve_interval.mojo',),
    'eligibility': tuple(PREFIX + name + '.mojo' for name in (
        'spiral_domain_proof', 'spiral_moment_proof', 'spiral_moment_table',
        'spiral_roundoff_proof', 'curve_rounded_arc', 'curve_rounded_line',
        'curve_frozen_arc', 'geometry', 'road_info', 'polynomial',
        'curve_trig', 'spiral_moment_table_data')),
    'translation': tuple(PREFIX + name + '.mojo' for name in (
        'curve_bounds', 'spiral_domain_proof', 'curve_frozen_arc', 'lane_refinement')),
    'support': tuple(PREFIX + name + '.mojo' for name in (
        'lane_refinement', 'map', 'lane_distance', 'junction_bounds',
        'spiral_domain_proof', 'spiral_moment_table', 'spiral_moment_proof',
        'spiral_roundoff_proof')),
}
QUALIFIER_FILES = ('curve_bounds.mojo', 'curve_trig.mojo',
                   'curve_interval.mojo', 'lane_value_bounds.mojo')
QUALIFIERS = {'var', 'mut', 'out', 'ref', 'comptime', 'raises'}


# Only immutable lexical strings belong here. This scope never stores roots,
# paths, source reads, inventories, dependency graphs or verification results.
_LEXICAL_MEMO_LIMIT = 256
_lexical_memo = ContextVar('lane_oracle_lexical_memo', default=None)


class _LexicalMemo:
    def __init__(self):
        self.entries = {}
        self.thread = get_ident()
        self.active = True


def _active_lexical_memo():
    memo = _lexical_memo.get()
    if memo is not None and memo.active and memo.thread == get_ident():
        return memo
    return None


@contextmanager
def lexical_memo_scope():
    """Reuse pure lexical strings during one complete verification.

    Args:
        None. Nested entries borrow the current invocation's bounded memo.
    Returns:
        A context manager that drops every entry on outermost exit.
    Raises:
        Propagates the verification's exceptions without caching them.
    """
    if _active_lexical_memo() is not None:
        yield
        return
    memo = _LexicalMemo()
    token = _lexical_memo.set(memo)
    try:
        yield
    finally:
        # A copied context can outlive this invocation. Invalidate its shared
        # state too, rather than let it revive or refill an expired memo.
        memo.active = False
        memo.entries.clear()
        _lexical_memo.reset(token)


def _lexical_string(function, arguments, dependencies=()):
    """Memoize exact immutable arguments and a string result inside the scope."""
    scope = _active_lexical_memo()
    # Preserve non-tuple owners and other unusual inputs by evaluating them
    # normally. Never retain a mutable object as part of an allegedly exact key.
    if scope is None or not all(
            type(value) is str or value is None or
            (type(value) is tuple and all(type(part) is str for part in value))
            for value in arguments):
        return function(*arguments)
    memo = scope.entries
    key = (function, dependencies, arguments)
    if key in memo:
        return memo[key]
    result = function(*arguments)
    # Exceptions never create entries. Only a complete immutable output may be
    # reused; mutable wrappers returned by other helpers must remain fresh.
    if type(result) is str:
        if len(memo) >= _LEXICAL_MEMO_LIMIT:
            del memo[next(iter(memo))]
        memo[key] = result
    return result


def require(condition, message):
    if not condition:
        raise ValueError(message)


@lru_cache(maxsize=32)
def _token_snapshot(text):
    """Cache only lexical output for exact immutable text, never validation.

    TokenInfo is an immutable named tuple; its fields are strings, integers,
    and coordinate tuples. The bounded snapshot therefore has no mutable parts.
    """
    try:
        return tuple(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, IndentationError) as error:
        raise ValueError('invalid source tokens: ' + str(error)) from error


def tokens(text):
    # Preserve a fresh mutable outer list for every caller. Filesystem reads,
    # production discovery and all proof comparisons still run on each call.
    return list(_token_snapshot(text))


@lru_cache(maxsize=128)
def token_sha256(text):
    # Retain INDENT/DEDENT, statement boundaries, every qualifier, string,
    # operator and literal. Ignore comments and continuation/blank lines.
    kept = [(item.type, item.string) for item in tokens(text)
            if item.type not in (tokenize.COMMENT, tokenize.NL, tokenize.ENDMARKER)]
    return hashlib.sha256(json.dumps(kept, separators=(',', ':')).encode()).hexdigest()


@lru_cache(maxsize=128)
def qualifier_sha256(text):
    # Bind every discarded qualifier at its NAME-token ordinal, independent
    # of whitespace, grouping and comments. The AST gate binds the names and
    # all retained executable syntax. In combination this covers qualifiers
    # without rejecting the existing harmless redundant-parentheses control.
    names = [item.string for item in tokens(text) if item.type == tokenize.NAME]
    pairs = [(index, name) for index, name in enumerate(names) if name in QUALIFIERS]
    return hashlib.sha256(json.dumps(pairs, separators=(',', ':')).encode()).hexdigest()


def unique_keys(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate runtime source pin key: ' + key)
        result[key] = value
    return result


def read_pins(root):
    pins = json.loads((root / PINS).read_text(encoding='utf-8'),
                      object_pairs_hook=unique_keys)
    require(isinstance(pins, dict) and set(pins) == {'schema', 'groups', 'qualifiers'},
            'wrong runtime source pin keys')
    require(type(pins['schema']) is int and pins['schema'] == 1,
            'unsupported runtime source pin schema')
    require(isinstance(pins['groups'], dict) and set(pins['groups']) == set(GROUP_PATHS),
            'wrong runtime dependency group set')
    for group, paths in GROUP_PATHS.items():
        actual = pins['groups'][group]
        require(isinstance(actual, dict) and set(actual) == set(paths),
                'wrong runtime dependency path set: ' + group)
        for path, value in actual.items():
            require(isinstance(value, str) and len(value) == 64 and
                    all(c in '0123456789abcdef' for c in value),
                    'invalid runtime dependency digest: ' + path)
    require(isinstance(pins['qualifiers'], dict) and
            set(pins['qualifiers']) == set(QUALIFIER_FILES),
            'wrong qualifier file set')
    return pins


def verify_group(root, group):
    require(group in GROUP_PATHS, 'unknown runtime dependency group: ' + str(group))
    pins = read_pins(root)
    result = {}
    for path in GROUP_PATHS[group]:
        text = (root / path).read_text(encoding='utf-8')
        checked = text
        if path == PREFIX + 'lane_refinement.mojo' and token_sha256(text) != pins['groups'][group][path]:
            if __package__:
                from . import cache_key_contracts as cache_key
            else:
                import cache_key_contracts as cache_key
            try:
                checked = cache_key.predecessor_source(root)
            except (ValueError, OSError) as error:
                raise ValueError('runtime source dependency changed [' + group + ']: ' + path
                                 + ' (' + str(error) + ')') from error
        elif path == PREFIX + 'map.mojo' and token_sha256(text) != pins['groups'][group][path]:
            if __package__:
                from . import seed_count_contracts as seed_count
            else:
                import seed_count_contracts as seed_count
            try:
                checked = seed_count.reviewed_text(root, path, text)
            except (ValueError, OSError) as error:
                raise ValueError('runtime source dependency changed [' + group + ']: ' + path
                                 + ' (' + str(error) + ')') from error
        require(token_sha256(checked) == pins['groups'][group][path],
                'runtime source dependency changed [' + group + ']: ' + path)
        result[path] = hashlib.sha256(text.encode()).hexdigest()
    return result


def verify_qualifiers(root, filename, text):
    pins = read_pins(root)
    require(filename in QUALIFIER_FILES, 'unexpected qualifier path')
    require(qualifier_sha256(text) == pins['qualifiers'][filename],
            'lexical qualifier/specialization changed: ' + filename)
