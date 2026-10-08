#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Fail-closed source-integrity gates for the reviewed runtime dependency paths.

These gates bind complete source tokens, including qualifiers and imports.
They do not prove helper mathematics, runtime execution, termination or cost.
No checker updates pins automatically. Repository-controlled pins are reviewed
inputs, never an independent proof when changed together with production.
"""
from functools import lru_cache
import hashlib
import io
import json
from pathlib import Path
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


def require(condition, message):
    if not condition:
        raise ValueError(message)


def tokens(text):
    try:
        return list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, IndentationError) as error:
        raise ValueError('invalid source tokens: ' + str(error)) from error


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
            try:
                import cache_key_contracts as cache_key
            except ModuleNotFoundError:
                from tools.carla_lane_oracle import cache_key_contracts as cache_key
            try:
                checked = cache_key.predecessor_source(root)
            except (ValueError, OSError) as error:
                raise ValueError('runtime source dependency changed [' + group + ']: ' + path
                                 + ' (' + str(error) + ')') from error
        elif path == PREFIX + 'map.mojo' and token_sha256(text) != pins['groups'][group][path]:
            try:
                import seed_count_contracts as seed_count
            except ModuleNotFoundError:
                from tools.carla_lane_oracle import seed_count_contracts as seed_count
            try:
                require(hashlib.sha256(text.encode()).hexdigest() == seed_count.AFTER_SHA256,
                        'unreviewed supplied Map source')
                checked = seed_count.historical_source(root)
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
