#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Reproduce the fixed-count quadrant-zero stored GL/trig coefficient table.

Python standard library only. Default and --check are read-only. No evaluator,
compiler, subprocess, network, private snapshots, or geometry sample is used.
"""
if __package__:
    from . import source_contracts as source
else:
    import source_contracts as source

if __package__:
    from . import source_contracts as _typed_source
else:
    import source_contracts as _typed_source

import argparse
from fractions import Fraction
import hashlib
# #333 explicit historical provenance views; current inputs remain operation-owned.
import json
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
if __package__:
    from . import ideal_projection
    from . import source_contracts
    from . import sum2_contracts
    from . import sum2_guard_contracts
else:
    import ideal_projection
    import source_contracts
    import sum2_contracts
    import sum2_guard_contracts
F = Fraction
ROOT = Path(__file__).resolve().parents[2]
SIGN = 1 << 63
INFINITY = 0x7FF0000000000000
MAX_FINITE = INFINITY - 1
_MOMENT_FILES = None
_MOMENT_PLAN = None


class CheckError(ValueError):
    """An input, source pin, coefficient, endpoint, or format is unsupported."""


def require(condition, message):
    # Do not use assert for verification: python -O must not disable checks.
    if not condition:
        raise CheckError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def fraction_of_word(word):
    require(type(word) is int and 0 <= word < 1 << 64, 'invalid UInt64 word')
    exponent = (word >> 52) & 0x7FF
    require(exponent != 0x7FF, 'nonfinite binary64 word')
    significand = word & ((1 << 52) - 1)
    shift = -1074
    if exponent:
        significand += 1 << 52
        shift = exponent - 1023 - 52
    value = F(significand << shift) if shift >= 0 else F(significand, 1 << -shift)
    return -value if word & SIGN else value


def next_up(word):
    if word in (0, SIGN):
        return 1
    return word - 1 if word & SIGN else word + 1


def next_down(word):
    if word in (0, SIGN):
        return SIGN | 1
    return word + 1 if word & SIGN else word - 1


def verify_bracket(value, low, high):
    require(fraction_of_word(low) <= value <= fraction_of_word(high),
            'endpoints do not enclose exact coefficient')
    following, preceding = next_up(low), next_down(high)
    require(following == INFINITY or fraction_of_word(following) > value,
            'lower endpoint is not greatest-below (or equal)')
    require(preceding == (SIGN | INFINITY) or fraction_of_word(preceding) < value,
            'upper endpoint is not least-above (or equal)')
    if value == 0:
        require((low, high) == (SIGN, 0), 'zero bracket must be [-0, +0]')


def bracket(value):
    """Exact integer lattice floor/ceil; no host floating-point conversion."""
    value = F(value)
    if not value:
        return SIGN, 0
    positive = abs(value)
    require(positive <= fraction_of_word(MAX_FINITE), 'binary64 overflow')
    numerator, denominator = positive.numerator, positive.denominator
    exponent = numerator.bit_length() - denominator.bit_length()
    if (numerator < denominator << exponent if exponent >= 0
            else numerator << -exponent < denominator):
        exponent -= 1
    shift = max(exponent - 52, -1074)
    if shift >= 0:
        significand = numerator // (denominator << shift)
    else:
        significand = (numerator << -shift) // denominator
    if exponent < -1022:
        low = significand
    else:
        low = ((exponent + 1023) << 52) | (significand - (1 << 52))
    high = low if fraction_of_word(low) == positive else low + 1
    pair = (SIGN | high, SIGN | low) if value < 0 else (low, high)
    verify_bracket(value, *pair)
    return pair


def nearest_even(value):
    if not value:
        return 0
    low, high = bracket(value)
    below, above = fraction_of_word(low), fraction_of_word(high)
    if value - below < above - value:
        return low
    if above - value < value - below:
        return high
    return low if low % 2 == 0 else high


def _rounded_words(literals):
    try:
        return ideal_projection.decimal_words(literals)
    except ValueError as error:
        raise CheckError(str(error)) from error


def _moment_error(mode, payload):
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-error-') as directory:
        path = Path(directory) / 'error.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_errors',
             mode, str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout.strip()


def decimal_word(token):
    value = F(token)
    # Fractions have no signed zero; a source literal does. `1/0` still
    # raises from the fraction above, before this classification.
    try:
        result = ideal_projection.signed_classified_word(token, not value)
    except ValueError as error:
        try:
            result = _moment_error('--result', {'error': str(error)})
        except ValueError as classified:
            raise CheckError(str(classified)) from error
        if result != 'nearest':
            raise CheckError(result) from error
        return nearest_even(value)
    if result == 'signed':
        return SIGN
    return int(result)


def normalized_block(text):
    """Keep indentation and operation spelling; ignore comments/blank lines."""
    return ideal_projection.normalized_block(text)


def selected_block(text, begin, end):
    try:
        return ideal_projection.selected_block(text, begin, end)
    except ValueError as error:
        raise CheckError(str(error)) from error


def _constant_error(error, name):
    try:
        message = _moment_error('--constant', {'message': str(error), 'name': name})
    except ValueError as failure:
        raise CheckError(str(failure)) from error
    raise CheckError(message) from error


def parse_array(text, name, size):
    # Match the complete top-level logical declaration, never a bracketed
    # prefix inside a conditional, concatenation, string or executable suffix.
    try:
        literals = ideal_projection.array_literals(text, name, size)
    except ValueError as error:
        _constant_error(error, name)
    return _rounded_words(literals)


def _moment_route_batch(mode, payload):
    """Run one stored-moment route batch and return its stdout."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-routes-') as directory:
        path = Path(directory) / 'routes.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_routes',
             mode, str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return result.stdout


def _moment_node_sums(payload):
    """Return the rounded node-sum fractions that match their pin."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-node-sums-') as directory:
        path = Path(directory) / 'sums.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_moment_node_sums', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _moment_legacy_projection(payload):
    """Return the projection record when the legacy pin digest matches."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-legacy-projection-') as directory:
        path = Path(directory) / 'projection.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_moment_projection', '--legacy', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _moment_projection(payload):
    """Return the ideal projection record when the spirals match."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-projection-') as directory:
        path = Path(directory) / 'projection.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_moment_projection', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _moment_array_fractions(payload):
    """Return the stored words and fractions when the array names match."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-array-fractions-') as directory:
        path = Path(directory) / 'arrays.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_arrays',
             '--fractions', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _moment_arrays(items):
    """Return the stored array words that match their pins."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(items, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-arrays-') as directory:
        path = Path(directory) / 'arrays.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_arrays',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _moment_scalars(payload):
    """Check the stored scalar words that match their pins."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-scalars-') as directory:
        path = Path(directory) / 'scalars.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_scalars',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)


def _moment_fraction_groups(payload):
    """Return the exact fraction spellings for each stored array."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-fractions-') as directory:
        path = Path(directory) / 'fractions.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo,
             'carla_moment_fractions', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _moment_scalars_and_blocks(payload):
    """Return the normalized blocks when the scalars and digests match."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-scalars-blocks-') as directory:
        path = Path(directory) / 'blocks.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_blocks',
             '--scalars', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _moment_blocks_and_digests(payload):
    """Return the normalized blocks when every route digest matches."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-blocks-digests-') as directory:
        path = Path(directory) / 'blocks.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_blocks',
             '--digests', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _moment_blocks(items):
    """Return the normalized operation blocks that match their pins."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(items, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-blocks-') as directory:
        path = Path(directory) / 'blocks.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_blocks',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return json.loads(result.stdout)


def _moment_guard(mode, payload):
    try:
        ideal_projection.moment_guard(mode, payload)
    except ValueError as error:
        raise CheckError(str(error)) from error


_NAME_SPEC = None


def _moment_pin_spec(dependencies):
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps({'dependencies': dependencies}, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-pin-spec-') as directory:
        path = Path(directory) / 'spec.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_pin_spec',
             str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    return json.loads(result.stdout)


def _name_spec():
    global _NAME_SPEC
    if _NAME_SPEC is None:
        _NAME_SPEC = _moment_pin_spec({})
    return _NAME_SPEC


def _array_specs():
    return {name: (record['path'], record['size'])
            for name, record in _name_spec()['arrays'].items()}


def _scalar_names():
    return set(_name_spec()['scalars'])


def _block_paths():
    return dict(_name_spec()['block_paths'])


def _block_boundaries():
    return {name: (record['begin'], record['end'])
            for name, record in _name_spec()['boundaries'].items()}


def _routing_paths():
    return dict(_name_spec()['routing_paths'])


def _moment_files():
    """Return the pin file, the stored table, and the word count."""
    global _MOMENT_FILES
    if _MOMENT_FILES is not None:
        return _MOMENT_FILES
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_files'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    _MOMENT_FILES = json.loads(result.stdout)
    return _MOMENT_FILES


def _pins():
    return Path(_moment_files()['pins'])


def _table():
    return Path(_moment_files()['table'])


def _word_count():
    return _moment_files()['words']


def _moment_plan():
    """Return the moment dependency record and the check messages."""
    global _MOMENT_PLAN
    if _MOMENT_PLAN is not None:
        return _MOMENT_PLAN
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_check_plan'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise CheckError(message)
    _MOMENT_PLAN = json.loads(result.stdout)
    return _MOMENT_PLAN


_DEPENDENCIES_READY = False


def _dependencies():
    """Return the dependency record, with paths from the accumulation group."""
    global DEPENDENCIES, _DEPENDENCIES_READY
    if _DEPENDENCIES_READY:
        return DEPENDENCIES
    plan = _moment_plan()
    interval = plan['interval']
    group = plan['additional_groups'][0]
    DEPENDENCIES = {
        'group': plan['group'],
        'pin_file': plan['pin_file'],
        'paths': [interval] + [path for path in source_contracts.GROUP_PATHS[group]
                               if path != interval],
        'additional_groups': list(plan['additional_groups']),
        'guard_pin_file': str(sum2_guard_contracts.PINS),
    }
    _DEPENDENCIES_READY = True
    return DEPENDENCIES


def __getattr__(name):
    if name == 'ARRAY_SPECS':
        return _array_specs()
    if name == 'SCALAR_NAMES':
        return _scalar_names()
    if name == 'BLOCK_PATHS':
        return _block_paths()
    if name == 'BLOCK_BOUNDARIES':
        return _block_boundaries()
    if name == 'ROUTING_PATHS':
        return _routing_paths()
    if name == 'PINS':
        return _pins()
    if name == 'DATA':
        return _table()
    if name == 'WORD_COUNT':
        return _word_count()
    if name == 'DEPENDENCIES':
        return _dependencies()
    raise AttributeError(f'module {__name__!r} has no attribute {name!r}')


def _require_moment_pins(pins):
    spec = _moment_pin_spec(_dependencies())
    try:
        ideal_projection.require_moment_pins(pins, spec)
    except ValueError as error:
        raise CheckError(str(error)) from error


def verify_inputs(root):
    messages = _moment_plan()['messages']
    arrays = _moment_plan()['arrays']
    pins = json.loads(_typed_source.historical_text(root, root / _pins(), (root / _pins()).read_text(encoding='utf-8')),
                      object_pairs_hook=source_contracts.unique_keys)
    _require_moment_pins(pins)
    constants = {}
    stored_words = {}
    flat_names = []
    loaded_arrays = []
    for name, record in pins['arrays'].items():
        loaded_arrays.append((name, record, _typed_source.historical_text(root, root / record['path'], (root / record['path']).read_text(encoding='utf-8'))))
    try:
        checked = _moment_array_fractions({
            'arrays': [{
                'name': name,
                'source': text,
                'size': len(record['words']),
                'expected': record['words'],
                'message': messages['stored_words'] + name,
            } for name, record, text in loaded_arrays],
            'invalid': messages['invalid_word'],
            'names': list(arrays),
            'message': messages['array_set'],
        })
    except ValueError as error:
        message = str(error)
        word = _cli_failures()['word']
        if message.startswith(word):
            message = message[len(word):]
        marker = 'stored array literal: '
        if message.startswith(marker):
            name, rest = message[len(marker):].split('\n', 1)
            _constant_error(ValueError(rest), name)
        raise CheckError(message) from error
    stored = checked['words']
    grouped = checked['fractions']
    for name, words in stored.items():
        stored_words[name] = [int(word) for word in words]
        flat_names.append(name)
    for name in flat_names:
        constants[name] = [F(text) for text in grouped[name]]
    constants[_moment_plan()['stored_words']] = stored_words
    loaded_scalars = []
    for name, record in pins['scalars'].items():
        loaded_scalars.append((name, record, _typed_source.historical_text(root, root / record['path'], (root / record['path']).read_text(encoding='utf-8'))))
    blocks = {}
    block_items = []
    for name, record in pins['blocks'].items():
        block_items.append((name, record))
    loaded_blocks = []
    for name, record in block_items:
        loaded_blocks.append((name, record, _typed_source.historical_text(root, root / record['path'], (root / record['path']).read_text(encoding='utf-8'))))
    routing_items = []
    for name, record in pins['routing'].items():
        routing_items.append((name, record))
    try:
        blocks = _moment_scalars_and_blocks({
            'scalars': {
                'items': [{
                    'name': name,
                    'source': text,
                    'expected': record['word'],
                    'message': messages['scalar_word'] + name,
                } for name, record, text in loaded_scalars],
                'overflow': messages['overflow'],
            },
            'blocks': [{
                'name': name, 'source': text, 'begin': record['begin'],
                'end': record['end'], 'expected': record['normalized_source'],
                'digest': record['sha256'],
            } for name, record, text in loaded_blocks],
            'digests': [{
                'text': record['normalized_tokens'],
                'digest': record['sha256'],
                'message': messages['routing_pin'] + name,
            } for name, record in routing_items],
        })
    except ValueError as error:
        message = str(error)
        word = _cli_failures()['word']
        if message.startswith(word):
            message = message[len(word):]
        marker = 'stored scalar literal: '
        if message.startswith(marker):
            name, rest = message[len(marker):].split('\n', 1)
            _constant_error(ValueError(rest), name)
        raise CheckError(message) from error
    loaded_routes = []
    for name, record in routing_items:
        loaded_routes.append((name, record, _typed_source.historical_text(root, root / record['path'], (root / record['path']).read_text(encoding='utf-8'))))
    try:
        currents = json.loads(_moment_route_batch('--currents', [{
            'name': name,
            'source': source,
        } for name, record, source in loaded_routes]))
    except ValueError as error:
        raise CheckError(str(error)) from error
    projected = None
    caller = _moment_plan()['ideal_caller']
    for name, record, source in loaded_routes:
        if name == caller:
            # Keep the historical routing pin. Admit the reference module
            # before the try-only refusal and the route pins.
            try:
                projected = ideal_projection.project_try_only_reference(source, root)
            except ValueError as error:
                raise CheckError(
                    messages['routing'] + name + ': ' + str(error)) from error
    checked = {
        'accepts': [{
            'current': currents[name],
            'expected': record['normalized_tokens'],
            'message': messages['routing'] + name,
            'strip': name == caller,
        } for name, record, source in loaded_routes],
    }
    if projected is not None:
        checked['source'] = projected
    try:
        _moment_route_batch('--checked', checked)
    except ValueError as error:
        message = str(error)
        if message.startswith('spiral moment try: '):
            raise CheckError(messages['routing'] + caller + ': ' + message) from error
        raise CheckError(message) from error
    try:
        source_contracts.verify_group(root, _dependencies()['group'])
    except ValueError as error:
        raise CheckError(messages['closure'] + str(error)) from error
    projection = pins['ideal_projection']
    _dependencies()
    interval = _typed_source.historical_text(root, root / DEPENDENCIES['paths'][0], (root / DEPENDENCIES['paths'][0]).read_text(encoding='utf-8'))
    try:
        _moment_legacy_projection({
            'legacy': projection['legacy_normalized_source'],
            'current': blocks[_moment_plan()['spiral_block']],
            'interval': interval,
            'pins': projection,
            'legacy_sha256': projection['legacy_sha256'],
        })
    except ValueError as error:
        message = str(error)
        if message == 'historical ideal pin digest changed' or message in (
                'missing or ambiguous stored-half declaration',
                'wrong ideal-projection result pins'):
            raise CheckError(message) from error
        raise CheckError(messages['projection'] + message) from error
    # Diagnose this record's own projection obligations before the cache-key
    # successor rechecks its immutable historical hash. Keep the complete
    # interval/helper dependency check above, and all transitive checks here.
    try:
        source_contracts.verify_group(root, _dependencies()['additional_groups'][0])
        sum2_contracts.verify(root)
    except ValueError as error:
        raise CheckError(messages['closure'] + str(error)) from error
    try:
        node_sums = _moment_node_sums({
            'nodes': [str(word) for word in stored_words[_moment_plan()['nodes']]],
            'weights': [str(word) for word in stored_words[_moment_plan()['weights']]],
            'expected': pins['rounded_node_sums'],
            'message': messages['node_sums'],
        })
    except ValueError as error:
        raise CheckError(str(error)) from error
    constants[_moment_plan()['sums_name']] = [F(text) for text in node_sums]
    return constants, pins


def derive_coefficients(constants):
    """All 64 rows, exactly; share only unscaled prefix sums across counts.

    S[k,n] = sum(p<n,i) w[i]*(p+q[i]/2)**(2*k).
    M[k,n] = S[k,n]/(2*n**(2*k+1)). This is algebraic common work only.
    """
    plan = _moment_plan()
    stored = constants[plan['stored_words']]
    names = plan['arrays']
    try:
        return ideal_projection.derive_rows(
            stored[names[0]], stored[names[1]],
            stored[names[2]], stored[names[3]])
    except ValueError as error:
        raise CheckError(str(error)) from error


def _coefficient_words(rows):
    """Return cosine words, then sine words, for every derived row."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    payload = json.dumps(rows, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='coefficient-words-') as directory:
        path = Path(directory) / 'rows.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_gate',
             '--coefficient-words', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = _cli_failures()['derive']
        if message.startswith(prefix):
            message = message[len(prefix):]
        raise CheckError(message)
    return json.loads(result.stdout)


def words_from_rows(rows):
    """Return the coefficient words as integers when the rows are well formed."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(rows, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='integer-rows-') as directory:
        path = Path(directory) / 'rows.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_gate',
             '--integer-rows', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = _cli_failures()['derive']
        if message.startswith(prefix):
            raise CheckError(message[len(prefix):])
        raise ValueError(message)
    return [int(item) for item in json.loads(result.stdout)]


def _moment_payload(rows):
    """Return the moment payload when the derived rows are well formed."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(rows, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-payload-rows-') as directory:
        path = Path(directory) / 'rows.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_gate',
             '--payload-rows', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = _cli_failures()['derive']
        if message.startswith(prefix):
            raise CheckError(message[len(prefix):])
        raise CheckError(message) from ValueError(message)
    return json.loads(result.stdout)


def generate_source(rows):
    """Return the canonical table source when the derived rows are well formed."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(rows, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-source-rows-') as directory:
        path = Path(directory) / 'rows.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_gate',
             '--source-rows', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = _cli_failures()['derive']
        if message.startswith(prefix):
            raise CheckError(message[len(prefix):])
        raise CheckError(message) from ValueError(message)
    return result.stdout.encode('utf-8')


def _parsed_table(payload):
    """Return the table words as integers when the declaration matches."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='parsed-table-') as directory:
        path = Path(directory) / 'table.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_stored_words',
             '--table', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return [int(item) for item in json.loads(result.stdout)]


def parse_table(data):
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError as error:
        raise CheckError(_moment_plan()['messages']['utf8']) from error
    try:
        return _parsed_table({'source': text, 'count': _word_count()})
    except ValueError as error:
        raise CheckError(str(error)) from error


def _verified_table(payload):
    """Return the table words when the derived rows match that table."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    text = json.dumps(payload, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='verified-table-') as directory:
        path = Path(directory) / 'table.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_moment_gate',
             '--verified-table', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    return [int(item) for item in json.loads(result.stdout)]


def verify_table(data, rows):
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError as error:
        raise CheckError(_moment_plan()['messages']['utf8']) from error
    try:
        return _verified_table({'rows': rows, 'source': text})
    except ValueError as error:
        message = str(error)
        prefix = _cli_failures()['derive']
        if message.startswith(prefix):
            raise CheckError(message[len(prefix):])
        raise CheckError(message) from error


def _moment_meta_from_rows(rows, root, projection, dependencies, routing, blocks):
    """Return the report meta when the derived rows and the fields match."""
    import ast
    import os
    import subprocess
    import tempfile
    repo = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(repo / '.venv' / 'bin' / 'mojo'))
    text = json.dumps({
        'rows': rows, 'root': root, 'projection': projection,
        'dependencies': dependencies, 'routing': routing, 'blocks': blocks,
    }, separators=(',', ':'))
    with tempfile.TemporaryDirectory(prefix='moment-meta-rows-') as directory:
        path = Path(directory) / 'meta.json'
        path.write_text(text)
        result = subprocess.run(
            ['sh', str(repo / 'tools' / 'tool.sh'), mojo, 'carla_moment_meta',
             '--rows', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        derive = _cli_failures()['derive']
        if message.startswith(derive):
            raise CheckError(message[len(derive):])
        key = _cli_failures()['key']
        if message.startswith(key):
            raise KeyError(ast.literal_eval(message[len(key):])) from None
        raise CheckError(message) from ValueError(message)
    return json.loads(result.stdout)


def make_report(root, rows, pins):
    projection = pins['ideal_projection']
    meta = _moment_meta_from_rows(
        rows, str(root.resolve()), projection, _dependencies(),
        pins['routing'], pins['blocks'])
    blobs = [
        _typed_source.historical_bytes(root, root / _pins(), (root / _pins()).read_bytes()),
        _typed_source.historical_bytes(
            root, root / source_contracts.PINS,
            (root / source_contracts.PINS).read_bytes()),
        _typed_source.historical_bytes(
            root, root / sum2_guard_contracts.PINS,
            (root / sum2_guard_contracts.PINS).read_bytes()),
    ]
    try:
        return json.loads(ideal_projection.moment_report(meta, blobs))
    except ValueError as error:
        raise CheckError(str(error)) from error


_CLI_FAILURES = None


def _cli_failures():
    """Return the checker failure prefixes."""
    global _CLI_FAILURES
    if _CLI_FAILURES is not None:
        return _CLI_FAILURES
    import json
    import os
    import subprocess
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    result = subprocess.run(
        ['sh', str(root / 'tools' / 'tool.sh'), mojo, 'carla_cli_failures'],
        capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    _CLI_FAILURES = json.loads(result.stdout)
    return _CLI_FAILURES


def main(argv=None):
    plan = _moment_plan()
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help=plan['help_check'])
    mode.add_argument('--generate', action='store_true', help=plan['help_generate'])
    parser.add_argument('--report', action='store_true', help=plan['help_report'])
    parser.add_argument('--output', type=Path, help=plan['help_output'])
    parser.add_argument('--repo-root', type=Path, default=ROOT, help=plan['help_root'])
    args = parser.parse_args(argv)
    if args.check and args.report:
        parser.error(plan['error_check'])
    if args.output is not None and not (args.generate or args.report):
        parser.error(plan['error_output'])
    root = args.repo_root.resolve()
    try:
        constants, pins = verify_inputs(root)
        rows = derive_coefficients(constants)
        if not args.generate:
            verify_table((root / _table()).read_bytes(), rows)
        report = make_report(root, rows, pins)
        report_plan = plan
        if args.generate or args.report:
            output = args.output or Path(os.environ.get(report_plan['output_env'],
                                                        str(root / report_plan['output_dir'])))
            # Never let an output option overwrite tracked source inputs/tools.
            protected = [root / _table(), root / _pins(), Path(__file__).resolve(),
                         root / source_contracts.PINS, root / sum2_guard_contracts.PINS] + [root / path for path in _dependencies()['paths']] + [root / record['path']
                         for group in report_plan['pin_groups']
                         for record in pins[group].values()]
            if __package__:
                from . import coverage_invariant_contracts as invariant
            else:
                import coverage_invariant_contracts as invariant
            products = {report_plan['report_name']: invariant._indent_json(report)}
            if args.generate:
                products.update({
                    _table().name: generate_source(rows),
                    report_plan['words_name']: ideal_projection.payload_bytes(
                        _moment_payload(rows)['be64']),
                    report_plan['coefficients_name']: invariant._indent_json(
                        {report_plan['counts_key']: rows}),
                })
            _moment_guard('--output', {
                'destinations': [str((output / name).resolve()) for name in products],
                'protected': [str(path.resolve()) for path in protected],
            })
            output.mkdir(parents=True, exist_ok=True)
            for name, data in products.items():
                (output / name).write_bytes(data)
        print(report_plan['pass_line'])
        print(report_plan['sha_prefix'] + report['source_sha256'])
        return 0
    except (CheckError, OSError, ValueError, KeyError, TypeError) as error:
        print(_cli_failures()['moments'] + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
