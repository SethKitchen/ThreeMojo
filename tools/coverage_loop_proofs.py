# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Bind conservative constant-loop proofs without changing runtime probes.

The original instrumenter and manifest remain authoritative. The official
report path verifies this receipt against current sources and tool contents,
then derives an outcome-masked manifest for the native reporter. Unknown
syntax or bindings keep both outcomes. This module never executes source.
"""

import argparse
import ast
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import sys
import tokenize

import cache_key
import coverage_toolchain_identity

ACTIVE_SOURCE_SHA256 = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
ACTIVE_TOOLCHAIN_SHA256 = hashlib.sha256(Path(coverage_toolchain_identity.__file__).read_bytes()).hexdigest()
ACTIVE_INVENTORY_SHA256 = hashlib.sha256(Path(cache_key.__file__).read_bytes()).hexdigest()


SCHEMA = 'constant-loops-v2'
# A conservative common subset of signed Int on supported CPU targets.
# No arithmetic expression is folded; both literal endpoints fit signed i32.
MAX_ENDPOINT = (1 << 31) - 1
TOOL_INPUTS = (
    'coverage/build_cli.mojo', 'coverage/instrument.mojo',
    'coverage/scanner.mojo', 'coverage/runtime.mojo',
    'coverage/report.mojo', 'coverage/report_cli.mojo', 'coverage/mcdc.mojo',
    'tools/coverage_loop_proofs.py', 'tools/coverage_io.py',
    'tools/cache_key.py', 'tools/native_test_support.py',
    'tools/coverage_toolchain_identity.py',
    'tools/coverage_hit_aot.py', 'tools/coverage_hit_cache.c',
    'tools/coverage_write_interposer.c', 'tools/test_environment.py',
    'tools/run_suite.py', 'Makefile',
)


def maintained_inputs(root, *, exclude=None, staged=False):
    """Use the maintained cache inventory, including native fixtures/assets.

    The declared output root is excluded even when COV_DIR is customized.
    This inventory, not TOOL_INPUTS, is the integrity boundary.
    """
    root = Path(root).resolve()
    excluded = Path(exclude).resolve() if exclude is not None else None
    result = {}
    for relative in cache_key.input_paths(root):
        path = relative_source(root, relative.as_posix())
        if excluded is not None and path.resolve().is_relative_to(excluded):
            continue
        if staged and (relative.parts[0] == 'hits' or relative.as_posix() in {'loop-proofs.json', 'generation-inputs.json'}):
            continue
        result[relative.as_posix()] = file_sha256(path)
    return result


def _origin_header(raw, offset):
    end = raw.find(b'\n', offset)
    if end < 0:
        raise ValueError('Truncated generation origin header')
    return raw[offset:end].split(b' '), end + 1


def _origin_length(value):
    if not re.fullmatch(rb'0|[1-9][0-9]*', value):
        raise ValueError('Invalid generation origin byte length')
    return int(value)


def _origin_part(raw, offset, size):
    if size > len(raw) - offset:
        raise ValueError('Truncated generation origin payload')
    return raw[offset:offset + size], offset + size


def generation_origins(root, build, manifest, compiler, flags, mojo):
    """Validate a trusted producer's exact input/output/manifest pairing."""
    index = (build / 'origins.ready').read_bytes()
    fields, offset = _origin_header(index, 0)
    if len(fields) != 4 or fields[0] != b'COVORIGIN_INDEX2':
        raise ValueError('Missing or incomplete instrumentation generation')
    count, size, checkpoint_size = map(_origin_length, fields[1:])
    if count < 1 or count > len(index):
        raise ValueError('Invalid generation module count')
    recorded_manifest, offset = _origin_part(index, offset, size)
    if recorded_manifest != manifest:
        raise ValueError('Generation manifest does not match the original manifest')
    checkpoint, offset = _origin_part(index, offset, checkpoint_size)
    names = []
    for _ in range(count):
        length, offset = _origin_header(index, offset)
        if len(length) != 1:
            raise ValueError('Invalid generation source identity')
        name, offset = _origin_part(index, offset, _origin_length(length[0]))
        names.append(name.decode('utf-8'))
    if offset != len(index) or len(set(names)) != len(names):
        raise ValueError('Trailing or duplicate generation records')
    expected_checkpoint = canonical(generation_checkpoint(root, build, compiler, flags, mojo, names)) + b'\n'
    if checkpoint != expected_checkpoint or (build / 'generation-inputs.json').read_bytes() != checkpoint:
        raise ValueError('Stale or modified generation origin checkpoint; regenerate with current sources/tools/compiler')
    expected_files = {name + '.cov-origin' for name in names}
    actual_files = {path.relative_to(build).as_posix() for path in build.rglob('*.cov-origin')}
    if actual_files != expected_files:
        raise ValueError('Missing or extra generation origin records; rebuild the stage')
    origins, fragments = {}, []
    for name in names:
        if not name.endswith('.mojo'):
            raise ValueError('Invalid generation module identity')
        original = relative_source(root, name).read_bytes()
        generated = relative_source(build, name).read_bytes()
        raw = relative_source(build, name + '.cov-origin').read_bytes()
        header, cursor = _origin_header(raw, 0)
        if len(header) != 5 or header[0] != b'COVORIGIN1':
            raise ValueError('Malformed source generation origin')
        parts = []
        for length in header[1:]:
            part, cursor = _origin_part(raw, cursor, _origin_length(length))
            parts.append(part)
        if cursor != len(raw) or parts[0].decode('utf-8') != name:
            raise ValueError('Trailing or mixed-module generation origin')
        if original != parts[1] or generated != parts[2]:
            raise ValueError('Source/staged bytes do not match their generation origin: ' + name)
        fragment = parts[3]
        if any(record[1] != name.removesuffix('.mojo') for record in manifest_records(fragment)):
            raise ValueError('Generation fragment identifies another module')
        fragments.append(fragment)
        origins[name] = {'source': sha256(original), 'instrumented': sha256(generated),
                         'origin_sha256': sha256(raw), 'fragment_sha256': sha256(fragment)}
    if b''.join(fragments) != manifest:
        raise ValueError('Generation fragments do not reconstruct the original manifest')
    return {'index_sha256': sha256(index), 'checkpoint_sha256': sha256(checkpoint), 'modules': origins}


def canonical(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True,
                      separators=(',', ':'), allow_nan=False).encode()


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for piece in iter(lambda: stream.read(1 << 20), b''):
            digest.update(piece)
    return digest.hexdigest()


def relative_source(root, name):
    """Accept only existing, root-contained, ordinary relative source names."""
    relative = PurePosixPath(name)
    if (not name or relative.is_absolute() or '..' in relative.parts
            or relative.as_posix() != name or '\\' in name or ':' in name):
        raise ValueError('Invalid coverage source identity: ' + repr(name))
    path = root / name
    if not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError('Missing or escaped coverage source: ' + name)
    return path


def manifest_records(raw):
    """Parse the original, unmasked manifest; proof records are never input."""
    records, seen = [], set()
    for line in raw.decode('utf-8').splitlines():
        fields = line.split()
        if not fields:
            continue
        if (fields[0] not in {'L', 'B', 'C', 'M'}
                or len(fields) != (4 if fields[0] in {'C', 'M'} else 3)
                or not re.fullmatch(r'[1-9][0-9]*', fields[2])
                or (len(fields) == 4 and not re.fullmatch(r'0|[1-9][0-9]*', fields[3]))):
            raise ValueError('Malformed original coverage manifest: ' + line)
        module = PurePosixPath(fields[1])
        if (module.is_absolute() or '..' in module.parts or module.as_posix() != fields[1]
                or '\\' in fields[1] or ':' in fields[1]):
            raise ValueError('Invalid coverage source identity: ' + fields[1])
        record = tuple(fields)
        if record in seen:
            raise ValueError('Duplicate coverage manifest entry: ' + line)
        seen.add(record)
        records.append(record)
    return records


def _statements(source):
    """Tokenize a deliberately small lexical subset, failing closed on doubt."""
    # Normalize physical endings for recognition only; source binding uses the
    # original bytes. Quoted text is a single token and cannot add bindings.
    source = source.replace('\r\n', '\n').replace('\r', '\n')
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(source).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return None
    if any(token.type == tokenize.ERRORTOKEN for token in tokens):
        return None
    statements, current = [], []
    for token in tokens:
        if token.type in (tokenize.INDENT, tokenize.DEDENT, tokenize.COMMENT,
                          tokenize.NL, tokenize.ENDMARKER):
            continue
        if token.type == tokenize.NEWLINE:
            if current:
                statements.append(current)
                current = []
        else:
            current.append(token)
    if current:
        return None
    return statements


def constant_loops(source):
    """Return source-proved candidates; no dataflow or user code evaluation.

    Only top-level function bodies qualify initially. Methods, nested
    functions and trait/generic name-resolution uncertainty keep both
    outcomes. A module-wide binding veto is stronger than scope guessing.
    """
    statements = _statements(source)
    if statements is None:
        return {}
    names = [token for statement in statements for token in statement
             if token.type == tokenize.NAME]
    wildcard = any(any(token.string == 'import' for token in statement)
                   and any(token.string == '*' for token in statement)
                   for statement in statements)
    if wildcard:
        return {}
    headers, allowed_range_positions, declarations = [], set(), []
    for statement in statements:
        first = statement[0]
        while declarations and declarations[-1][0] >= first.start[1]:
            declarations.pop()
        words = [token.string for token in statement]
        if words[0] in {'def', 'struct', 'trait'} or words[:2] == ['async', 'def']:
            kind = 'def' if words[0] == 'async' else words[0]
            # A generic function's parameters can alter expression bindings.
            name_position = 2 if words[0] == 'async' else 1
            generic = (len(words) > name_position + 1
                       and words[name_position + 1] == '[')
            declarations.append((first.start[1], kind, generic))
            continue
        # Narrow loop target grammar. More complex targets remain unknown.
        if (len(words) < 5 or words[0] != 'for'
                or statement[1].type != tokenize.NAME or words[2] != 'in'
                or words[-1] != ':'):
            continue
        rhs = statement[3:-1]
        if rhs and rhs[0].string == 'range' and len(rhs) > 1 and rhs[1].string == '(':
            allowed_range_positions.add(rhs[0].start)
        supported_scope = (len(declarations) == 1
                           and declarations[0][1] == 'def'
                           and not declarations[0][2])
        if supported_scope:
            headers.append((first.start[0], rhs))
    range_is_builtin = all(token.start in allowed_range_positions
                           for token in names if token.string == 'range')
    list_is_builtin = not any(token.string == 'List' for token in names)
    found = {}
    for line, rhs in headers:
        expression = tokenize.untokenize([(token.type, token.string)
                                         for token in rhs]).strip()
        try:
            node = ast.parse(expression, mode='eval').body
        except (SyntaxError, ValueError, RecursionError):
            continue
        count, kind = None, None
        if (range_is_builtin and isinstance(node, ast.Call)
                and isinstance(node.func, ast.Name) and node.func.id == 'range'
                and not node.keywords and len(node.args) in (1, 2)
                and all(isinstance(arg, ast.Constant) and type(arg.value) is int
                        and 0 <= arg.value <= MAX_ENDPOINT for arg in node.args)):
            values = [arg.value for arg in node.args]
            start, stop = (0, values[0]) if len(values) == 1 else values
            count, kind = max(0, stop - start), 'literal-range'
        elif (list_is_builtin and isinstance(node, ast.List)
              and not any(isinstance(element, ast.Starred) for element in node.elts)):
            count, kind = len(node.elts), 'literal-list'
        if kind is not None:
            found[line] = {'line': line, 'kind': kind, 'cardinality': count,
                           'required': 'T' if count else 'F',
                           'impossible': 'F' if count else 'T',
                           'expression': expression}
    return found



# The independently reviewed count theorem is not dynamic inference. The exact
# complete consumer binds count declaration, dominating guard, all intervening
# statements and builtin range resolution. The producer module binds Int typing.
REVIEWED_COUNT_MODULE = 'extensions/carla/curve_sample_dispatch'
REVIEWED_COUNT_SOURCES = {
    'extensions/carla/curve_sample_dispatch.mojo':
        '91ede65bbc39ac57ca54239513b462d3c71e90cacd085b8bafb2bff514767a86',
    'extensions/carla/curve_bounds.mojo':
        'a57a5fa078fc6f36389a0abdce1eaa483a1cb7b7325688689a5602e8680ca3fb',
}


# Each row is a separate reviewed theorem. This table does not recognize
# arbitrary methods, generic functions, dynamic bounds, or producer patterns.
REVIEWED_LOOP_RULES = {
    # Compile-time range uses deliberately disable generic inference. These
    # six runtime literals are independently bound to the complete reviewed
    # module, including imports and all range uses. No comptime site is masked.
    'extensions/carla/spiral_moment_proof': ({
        'extensions/carla/spiral_moment_proof.mojo':
            'f42f436b6e616e39bc2cda70491abf2e441aa40d5d8d1aa7f7ecffe3d0b0d5ac',
    }, (
        (92, 'literal-range', 5, 5, 'range(5)', 'moment-weight-five-nodes'),
        # Separate theorem: immutable Int pieces passes the dominating 1..64 guard.
        (97, 'reviewed-nonempty-range', 1, 64, 'range(pieces)',
         'moment-admitted-piece-count-1-to-64'),
        (98, 'literal-range', 5, 5, 'range(5)', 'moment-piece-five-nodes'),
        (111, 'literal-range', 21, 21, 'range(1, 22)', 'moment-power-twenty-one'),
        (119, 'literal-range', 21, 21, 'range(1, 22)', 'moment-normalize-twenty-one'),
        (125, 'literal-range', 11, 11, 'range(11)', 'moment-eleven-coefficients'),
        (163, 'literal-range', 4, 4, 'range(1, 5)', 'moment-node-four-successors'),
    )),
    'extensions/carla/speed_limits': ({
        'extensions/carla/speed_limits.mojo':
            '1e95ebc085e03a44e4daaef20a94b724dedc4240a2099227e82be54d32b045f6',
    }, (
        (154, 'reviewed-nonempty-iterator', 1, None, 'number.as_bytes()',
         'speed-number-nonempty-owned-byte-view'),
    )),
    'extensions/carla/rtree': ({
        'extensions/carla/rtree.mojo':
            'be63ea929c25e0a55600d19568e5f8a117e2f712850ea3da0d977c39b002d460',
        'extensions/carla/map.mojo':
            '52dd32213d64275be94ba714bc9b6a57c28f5ba1303525ef1a1aac20b4743c07',
        'tests/_published_seed_selector.mojo':
            'fbab95376d7b6c1bc2e04b1e0f3f20ae5c125af8eda403e2a54ea6d8bc3c8a93',
        'tests/test_small_loop_witnesses.mojo':
            '8f768e04ecaebdb132cf359819be03cb039d5a546b823674c22ac06a1b790362',
    }, (
        (666, 'reviewed-nonempty-iterator', 1, 16, 'node.children',
         'rtree-retained-frontier-reaches-inserted-nodes'),
    )),
    REVIEWED_COUNT_MODULE: (REVIEWED_COUNT_SOURCES, (
        (126, 'reviewed-nonempty-range', 1, 2, 'range(count)',
         'sample-dispatch-count-1-or-2'),
    )),
    'extensions/carla/lane_distance': ({
        'extensions/carla/lane_distance.mojo':
            '9d0aacab9fccb0a34f8d5c3a5edca1a1fd7ebcded961fc579ec6a44f3880497d',
        'extensions/carla/curve_distance.mojo':
            '46176387129dd37a5887f3aeec7c96bbb386e4980063cb96f09619832cb09a79',
    }, (
        (50, 'reviewed-nonempty-range', 1, 3, 'range(axes)',
         'refinement-square-normalized-axes-1-to-3'),
    )),
    'extensions/carla/curve_interval': ({
        'extensions/carla/curve_interval.mojo':
            'ff6bf0d35b357047c609ea7cb6dbcbe535446cf4e315d9eac5f6c341ddbf1040',
    }, (
        (592, 'literal-list', 4, 4,
         '[actual_rate.low, actual_rate.high, one, two]',
         'stored-blend-four-float64-elements'),
    )),
    'extensions/humanoid/skeleton/head/hair/strands': ({
        'extensions/humanoid/skeleton/head/hair/strands.mojo':
            'b38db045a18fbdbf5fc391a8b6795b03afb0b4e10bb0328e3da4e1b98a0f64a1',
    }, (
        (195, 'literal-range', 2, 2, 'range(2)', 'hair-upload-two-endpoints'),
        (201, 'literal-range', 3, 3, 'range(3)', 'hair-upload-three-channels'),
    )),
}


# Each additional row is a separately source-reviewed local/caller theorem.
# Complete source bindings are fixed review inputs, never refreshed at runtime.
# A mismatch withholds that row; all original reachable probes remain mandatory.
GUARDED_LOOP_SOURCE_SHA256 = {
    'extensions/carla/agents_route.mojo':
        '416a86c052dc86cf709bfd33bec5b15ef360c07f6f5cb53aa42a3e9968d33199',
    'extensions/carla/curve_rounded_arc.mojo':
        '7bc84049fed26cb7b14b4fa4603ee36d55cdeb7055c62df50cf10d6a2ce90745',
    'extensions/carla/curve_rounded_line.mojo':
        '6741ad9d7434c08070de3c959cb49ac42939ac633d1dcd48c9f5cdfdaa719aed',
    'extensions/carla/junction_bounds.mojo':
        'c933e03b6bde0bede8fb0745e9c1ef075d9699fde72b74795368943381d1aa74',
    'extensions/carla/lane_refinement.mojo':
        'd6bb8cb266fa350491f71e92295e70bcbfc2566b34db02400b3a6cb5bb5a93ad',
    'extensions/carla/map.mojo':
        '52dd32213d64275be94ba714bc9b6a57c28f5ba1303525ef1a1aac20b4743c07',
    'extensions/carla/opendrive.mojo':
        '9ff9b750af2c1c1a92fe3f3dfe1e49566e9d6f8c39a3576e0d4cf542bc8cdc28',
    'extensions/carla/road.mojo':
        'd9b6f60ae0b0b2fe38ef8dbe797a759f3de5e72dc8fb97bff15ca5dfff251db0',
    'extensions/humanoid/skeleton/head/hair/density.mojo':
        'cf1a58fa00938a2522e25fdf9b061ec53bec3e3bf08dbe99ed2eb942a37b8ab9',
    'extensions/humanoid/skeleton/head/hair/groom.mojo':
        'd4f041e4f7686930d89c4dd504b79e3bca1231d038261d9ab30f4ff013c2c4f9',
    'extensions/humanoid/skeleton/head/hair/shading.mojo':
        '9e799dccc63511086a7c065a6725c35fdf8796f4d336351787e139087ef01286',
    'extensions/humanoid/skeleton/head/hair/strands.mojo':
        'b38db045a18fbdbf5fc391a8b6795b03afb0b4e10bb0328e3da4e1b98a0f64a1',
    'tests/test_carla_route_search.mojo':
        '50874817a790dbea31b01cfeff51615be4181474a01ccefb98e42caea9421e8b',
}

# module, line, kind, maximum, expression, proof ID, extra inputs, caller names
GUARDED_LOOP_RULES = (
    ('extensions/carla/curve_rounded_line', 93, 'reviewed-nonempty-range', None, 'range(len(lanes))', 'rounded-line-validated-lane-list', ('extensions/carla/road.mojo',), ()),
    ('extensions/carla/curve_rounded_arc', 228, 'reviewed-nonempty-range', None, 'range(len(lanes))', 'rounded-arc-validated-lane-list', ('extensions/carla/road.mojo',), ()),
    ('extensions/carla/lane_refinement', 145, 'reviewed-nonempty-iterator', None, 'road.sections[section].lanes', 'axis-search-validated-lane-list', ('extensions/carla/road.mojo',), ()),
    ('extensions/carla/lane_refinement', 726, 'reviewed-nonempty-iterator', None, 'two.cells', 'dominance-explicit-nonempty-cells', (), ()),
    ('extensions/carla/lane_refinement', 1289, 'reviewed-nonempty-iterator', None, 'certificate.cells', 'resumption-explicit-nonempty-cells', (), ()),
    ('extensions/carla/lane_refinement', 1314, 'reviewed-nonempty-iterator', None, 'certificate.cells', 'resumption-transaction-retains-cells', (), ()),
    ('extensions/carla/junction_bounds', 706, 'reviewed-nonempty-range', None, 'range(len(breaks) - 1)', 'junction-retained-two-endpoint-breaks', (), ()),
    ('extensions/carla/map', 1491, 'reviewed-nonempty-range', 128, 'range(1 << level)', 'winner-eight-positive-dyadic-cardinalities', (), ()),
    ('extensions/carla/map', 2272, 'reviewed-nonempty-iterator', None, 'certificates', 'query-retained-certificate-list', (), ()),
    ('extensions/carla/map', 2279, 'reviewed-nonempty-range', None, 'range(len(indices))', 'query-nonempty-winner-rescan', (), ()),
    ('extensions/carla/map', 2301, 'reviewed-nonempty-range', None, 'range(len(indices))', 'query-nonempty-competitor-rescan', (), ()),
    ('extensions/carla/map', 2373, 'reviewed-nonempty-iterator', 12, 'metadata', 'winner-fixed-twelve-metadata-elements', (), ()),
    ('extensions/carla/map', 2378, 'reviewed-nonempty-iterator', None, 'certificates', 'query-nonempty-prefix-certificates', (), ()),
    ('extensions/carla/map', 2387, 'literal-range', 4, 'range(4)', 'winner-four-frontier-reservations', (), ()),
    ('extensions/carla/map', 2396, 'literal-range', 10, 'range(10)', 'target-ten-frontier-reservations', (), ()),
    ('extensions/humanoid/skeleton/head/hair/density', 100, 'reviewed-nonempty-range', 262144, 'range(count)', 'density-validated-positive-cube-count', (), ()),
    ('extensions/humanoid/skeleton/head/hair/density', 137, 'reviewed-nonempty-range', None, 'range(len(groom))', 'density-partitioned-nonempty-groom', ('extensions/humanoid/skeleton/head/hair/groom.mojo',), ()),
    ('extensions/humanoid/skeleton/head/hair/strands', 180, 'reviewed-nonempty-range', None, 'range(len(self.groom.points))', 'hair-retained-nonempty-points', ('extensions/humanoid/skeleton/head/hair/density.mojo', 'extensions/humanoid/skeleton/head/hair/groom.mojo', 'extensions/humanoid/skeleton/head/hair/shading.mojo', 'extensions/carla/agents_route.mojo', 'tests/test_carla_route_search.mojo'), ()),
    ('extensions/humanoid/skeleton/head/hair/strands', 191, 'reviewed-nonempty-range', None, 'range(len(self.groom))', 'hair-retained-nonempty-strands', ('extensions/humanoid/skeleton/head/hair/density.mojo', 'extensions/humanoid/skeleton/head/hair/groom.mojo', 'extensions/humanoid/skeleton/head/hair/shading.mojo', 'extensions/carla/agents_route.mojo', 'tests/test_carla_route_search.mojo'), ()),
    ('extensions/carla/opendrive', 450, 'reviewed-nonempty-iterator', None, 'records', 'border-active-maintained-nonempty-callers', (), ('_active',)),
    ('extensions/carla/opendrive', 593, 'reviewed-nonempty-range', None, 'range(len(ids))', 'border-positive-record-count-keeps-ids', (), ()),
    ('extensions/carla/opendrive', 601, 'reviewed-nonempty-range', None, 'range(len(ids))', 'border-inner-scan-retains-positive-ids', (), ()),
    ('extensions/carla/opendrive', 615, 'reviewed-nonempty-iterator', None, 'borders[i]', 'border-outer-list-explicitly-nonempty', (), ()),
    ('extensions/carla/opendrive', 617, 'reviewed-nonempty-iterator', None, 'inner', 'border-inner-owned-nonempty-list', (), ()),
    ('extensions/carla/opendrive', 621, 'reviewed-nonempty-iterator', None, 'cuts', 'border-cuts-retain-initial-section-start', (), ()),
    ('extensions/carla/opendrive', 787, 'literal-list', 4, '["a", "b", "c", "d"]', 'border-four-offset-coefficients', (), ()),
)


# These two retained-state theorems have separate producer dependencies and
# caller/write censuses. Do not relax the generic callers-equal-bindings rule.
# Construction keeps an independent positive partition. Each shade rechecks
# starts equality and current point count; immutable groom borrows preserve it.
# The CARLA paths are unrelated name collisions, conservatively bound in full.
_HAIR_RETAINED_CENSUS = (
    (('_shadow_depths', '_upload'), (
        'extensions/humanoid/skeleton/head/hair/strands.mojo',
    )),
    (('_topology',), (
        'extensions/humanoid/skeleton/head/hair/strands.mojo',
        'extensions/carla/agents_route.mojo',
        'tests/test_carla_route_search.mojo',
    )),
)
HAIR_RETAINED_RULE_CENSUS = {
    (180, 'hair-retained-nonempty-points'): _HAIR_RETAINED_CENSUS,
    (191, 'hair-retained-nonempty-strands'): _HAIR_RETAINED_CENSUS,
}


# Historical table hashes remain review inputs. Only this exact successor may
# project Map to its predecessor, after checking the live dependency closure,
# premises and count-control fixture. Receipts always retain the live hash.
_MAP_SUCCESSOR_LINES = {
    1491: 1485, 2272: 2264, 2279: 2271, 2301: 2293,
    2373: 2365, 2378: 2370, 2387: 2379, 2396: 2388,
}


# A separate exact source pair for the HairDensity boundary correction.
# Historical hashes/rules stay unchanged. The four retained hair theorems were
# reviewed again: rebuild still validates its positive cube and owned partition;
# the checked helper only returns positive Int or raises; query validation is
# read-only. Neither correction changes groom ownership, successful shading
# borrows, topology checks, or the retained caller/write census above.
DENSITY_SOURCE = 'extensions/humanoid/skeleton/head/hair/density.mojo'
DENSITY_BEFORE_SHA256 = 'cf1a58fa00938a2522e25fdf9b061ec53bec3e3bf08dbe99ed2eb942a37b8ab9'
DENSITY_AFTER_SHA256 = '2d5595ac114901265ea9e13d905f81529dfccb9cd8ddf05185313b5aada07929'
_DENSITY_SUCCESSOR_LINES = {100: 101, 137: 138}

# This fixed inverse exists only to preserve historical test fixtures on either
# physical source state. Admission always checks complete hashes; it never
# projects an arbitrary changed module or refreshes either binding.
_DENSITY_SOURCE_EDITS = (
    ('''from std.math import ceil, floor, isfinite, max, min
''',
     '''from std.math import ceil, floor, isfinite, max, min
from std.sys import size_of
'''),
    ('''                # Finite cubic volume and resolution at most 64 bound
                # segment length below 2^50 and sample count at most 211.
                var samples = max(1, Int(ceil(length / (cell * 0.5))))''',
     '''                # Check the rounded count before its Float32-to-Int cast.
                # Every accepted count is positive, without an artificial cap.
                var samples = _checked_density_samples(length / (cell * 0.5))'''),
    ('''            Error: If the point or direction is not finite.
''',
     '''            Error: If the point or direction is not finite, or the current
                resolution or diameter is outside its domain.
'''),
    ('''            raise Error("Hair optical depth needs a finite light direction")
''',
     '''            raise Error("Hair optical depth needs a finite light direction")
        self.validate()
'''),
    ('',
     '''

def _checked_density_samples(ratio: Float32) raises -> Int:
    """Round a sample ratio up, with at least one representable sample.

    Args:
        ratio: The segment length divided by the half-cell step.

    Returns:
        At least one sample, preserving the minimum for finite small values.

    Raises:
        Error: If the rounded count is nonfinite or exceeds signed Int.
    """
    comptime assert size_of[Int]() == 4 or size_of[Int]() == 8
    var rounded = ceil(ratio)
    if not isfinite(rounded):
        raise Error("Hair density sample count is not representable")
    if rounded <= 1:
        return 1
    # Int.MIN is exactly -2^(width-1) on the supported signed Int widths.
    # Convert that exact power before negation; never negate Int.MIN as Int.
    # Float32(Int.MAX) rounds up to the excluded limit and is not inclusive.
    var exclusive_limit = -Float32(Int.MIN)
    if rounded >= exclusive_limit:
        raise Error("Hair density sample count is not representable")
    return Int(rounded)
'''),
)


def reviewed_density_source(root, *, successor=False):
    """Return one exact reviewed side, rejecting all unknown live sources."""
    path = relative_source(root, DENSITY_SOURCE)
    raw = path.read_bytes()
    current = sha256(raw)
    wanted = DENSITY_AFTER_SHA256 if successor else DENSITY_BEFORE_SHA256
    if current not in {DENSITY_BEFORE_SHA256, DENSITY_AFTER_SHA256}:
        raise ValueError('Unreviewed HairDensity source')
    text = raw.decode('utf-8')
    if current != wanted:
        for before, after in (_DENSITY_SOURCE_EDITS if successor
                              else reversed(_DENSITY_SOURCE_EDITS)):
            if not before:
                if successor:
                    text += after
                elif text.endswith(after):
                    text = text[:-len(after)]
                else:
                    raise ValueError('Missing reviewed HairDensity helper')
            else:
                old, new = (before, after) if successor else (after, before)
                if text.count(old) != 1:
                    raise ValueError('Ambiguous reviewed HairDensity edit')
                text = text.replace(old, new, 1)
    if sha256(text.encode('utf-8')) != wanted or path.read_bytes() != raw:
        raise ValueError('HairDensity paired source identity mismatch')
    return text


# These theorems apply ONLY to the repaired source. They do not assert the
# old numeric-envelope argument or a maximum of 247 for arbitrary helper input.
# For signed 32/64-bit Int, -Float32(Int.MIN) is exactly 2^(width-1). The helper
# classifies the actual ceil result, returns 1 for every finite value <=1,
# refuses values >= that exclusive limit, then converts only (1, limit).
# Thus its return is positive without a global FP-state assumption.
# Query validation dominates resolution*4, so that separate count is 16..256.
# The unchanged reporter protocol serializes nonemptiness as cardinality 1;
# minimum_cardinality retains the tighter reviewed fact in the bound receipt.
DENSITY_REPAIRED_RULES = (
    (149, 'reviewed-nonempty-range', 1, None, 'range(samples)',
     'density-checked-representable-positive-samples'),
    (223, 'reviewed-nonempty-range', 16, 256, 'range(self.resolution * 4)',
     'density-query-validated-positive-step-count'),
)


def _density_stdlib_unshadowed(root):
    """Refuse unreviewed project std resolver surfaces, including packages.

    SDK payloads are bound separately. The project's standard virtualenv and
    non-input caches are not include roots and must not veto the real SDK.
    A project directory symlink could hide an additional resolver surface;
    conservatively refuse it instead of following it outside the checked tree.
    """
    root = Path(root)
    if not root.is_dir():
        return False

    def unreadable(error):
        raise error

    try:
        for directory, folders, files in os.walk(root, onerror=unreadable):
            base = Path(directory)
            # Refuse alternate/unknown suffixes as well as .mojo, .mojoc and
            # .mojopkg. This includes Mojo's alternate source-file suffix.
            if any(name.casefold() == 'std' or name.casefold().startswith('std.')
                   for name in (*folders, *files)):
                return False
            folders[:] = [name for name in folders if name not in cache_key.SKIP
                          and (base / name).relative_to(root) != Path('coverage/build')]
            if any((base / name).is_symlink() for name in folders):
                return False
    except (OSError, ValueError):
        return False
    return True


def repaired_density_loops(root, *, include_roots=()):
    """Admit local repaired loops, never their unsafe historical counterparts."""
    try:
        if file_sha256(relative_source(root, DENSITY_SOURCE)) != DENSITY_AFTER_SHA256:
            return {}
    except (OSError, ValueError):
        return {}
    if not all(_density_stdlib_unshadowed(path) for path in (root, *include_roots)):
        return {}
    return {line: {
        'line': line, 'kind': kind, 'cardinality': 1,
        'minimum_cardinality': minimum,
        'maximum_cardinality': maximum, 'required': 'T', 'impossible': 'F',
        'expression': expression, 'proof_id': proof_id,
        'dependency_sha256': {DENSITY_SOURCE: DENSITY_AFTER_SHA256},
    } for line, kind, minimum, maximum, expression, proof_id in DENSITY_REPAIRED_RULES}


def _reviewed_dependency_hashes(root, bindings, *, include_roots=()):
    """Verify fixed historical bindings without admitting arbitrary successors."""
    actual = {}
    for name, expected in bindings.items():
        path = relative_source(root, name)
        raw = path.read_bytes()
        digest = sha256(raw)
        if (name == DENSITY_SOURCE and expected == DENSITY_BEFORE_SHA256
                and digest == DENSITY_AFTER_SHA256):
            # Explicit paired admission for the four re-reviewed hair rows.
            if not all(_density_stdlib_unshadowed(path)
                       for path in (root, *include_roots)):
                return None
            actual[name] = digest
            continue
        if digest != expected:
            if (name != 'extensions/carla/map.mojo'
                    or expected != GUARDED_LOOP_SOURCE_SHA256[name]):
                return None
            from carla_lane_oracle import seed_count_contracts as seed_count
            if digest != seed_count.AFTER_SHA256:
                return None
            predecessor = seed_count.historical_source(root).encode('utf-8')
            if sha256(predecessor) != expected or path.read_bytes() != raw:
                return None
        actual[name] = digest
    return actual


def _historical_reviewed_nonempty_loops(root, module):
    """Return only named source-reviewed nonempty iterator proofs.

    A mismatch retains both outcomes. Constants require a new source review;
    they are never derived from the current files or automatically refreshed.
    """
    rule = REVIEWED_LOOP_RULES.get(module)
    if rule is None:
        return {}
    bindings, sites = rule
    try:
        if module == 'extensions/carla/rtree':
            # Fail closed on any newly introduced private frontier caller.
            # This is a fixed census, not inference about arbitrary callers.
            callers = {
                path.as_posix() for path in cache_key.input_paths(Path(root))
                if path.suffix == '.mojo'
                and re.search(r'\b_nearest_(?:begin|next)\b',
                              relative_source(root, path.as_posix()).read_text())
            }
            if callers != set(bindings):
                return {}
        actual = _reviewed_dependency_hashes(root, bindings)
        if actual is None:
            return {}
    except (OSError, ValueError, ImportError):
        return {}
    return {line: {
        'line': line, 'kind': kind, 'cardinality': minimum,
        'maximum_cardinality': maximum, 'required': 'T', 'impossible': 'F',
        'expression': expression, 'proof_id': proof_id,
        'dependency_sha256': actual,
    } for line, kind, minimum, maximum, expression, proof_id in sites}


def guarded_loop_proof(root, rule, *, include_roots=()):
    """Verify one explicit theorem without enabling its sibling rules."""
    module, line, kind, maximum, expression, proof_id, extras, callers = rule
    bindings = {
        name: GUARDED_LOOP_SOURCE_SHA256[name]
        for name in (module + '.mojo', *extras)
    }
    try:
        actual_bindings = _reviewed_dependency_hashes(root, bindings, include_roots=include_roots)
        if actual_bindings is None:
            return None
        if (module == 'extensions/carla/map'
                and actual_bindings[module + '.mojo'] != bindings[module + '.mojo']):
            line = _MAP_SUCCESSOR_LINES.get(line)
            if line is None:
                return None
        if (module + '.mojo' == DENSITY_SOURCE
                and actual_bindings[DENSITY_SOURCE] == DENSITY_AFTER_SHA256):
            line = _DENSITY_SUCCESSOR_LINES.get(line)
            if line is None:
                return None
        if callers:
            # A private helper's local precondition is backed by the complete
            # maintained caller census. New calls or aliases fail closed.
            pattern = r'\b(?:' + '|'.join(re.escape(name) for name in callers) + r')\b'
            actual = {
                path.as_posix() for path in cache_key.input_paths(Path(root))
                if path.suffix == '.mojo'
                and re.search(pattern,
                              relative_source(root, path.as_posix()).read_text())
            }
            if actual != set(bindings):
                return None
        if module == 'extensions/humanoid/skeleton/head/hair/strands':
            census = HAIR_RETAINED_RULE_CENSUS.get((line, proof_id))
            if not census:
                return None
            for names, expected in census:
                if not expected or not set(expected).issubset(bindings):
                    return None
                pattern = r'\b(?:' + '|'.join(re.escape(name) for name in names) + r')\b'
                actual = {
                    path.as_posix() for path in cache_key.input_paths(Path(root))
                    if path.suffix == '.mojo'
                    and re.search(pattern,
                                  relative_source(root, path.as_posix()).read_text())
                }
                if actual != set(expected):
                    return None
    except (OSError, ValueError, ImportError):
        return None
    cardinality = maximum if kind in {'literal-range', 'literal-list'} else 1
    return {
        'line': line, 'kind': kind, 'cardinality': cardinality,
        'maximum_cardinality': maximum, 'required': 'T', 'impossible': 'F',
        'expression': expression, 'proof_id': proof_id,
        'dependency_sha256': actual_bindings,
    }


def reviewed_nonempty_loops(root, module, *, include_roots=()):
    """Keep historical rules and independently admit each new exact theorem."""
    result = _historical_reviewed_nonempty_loops(root, module)
    if module + '.mojo' == DENSITY_SOURCE:
        result.update(repaired_density_loops(root, include_roots=include_roots))
    for rule in GUARDED_LOOP_RULES:
        if rule[0] != module:
            continue
        proof = guarded_loop_proof(root, rule, include_roots=include_roots)
        if proof is None:
            continue
        if proof['line'] in result:
            raise ValueError('Conflicting reviewed loop proof: ' + module)
        result[proof['line']] = proof
    return result


def _counts(records):
    counts = {kind: 0 for kind in ('L', 'B', 'C', 'M')}
    for record in records:
        counts[record[0]] += 1
    counts['potential_outcomes'] = 2 * (counts['B'] + counts['C'])
    counts['potential_total'] = counts['L'] + counts['potential_outcomes'] + counts['M']
    return counts


def _symbolic_path(path, root, build):
    path = Path(path).resolve()
    for token, base in [('@BUILD@', build), ('@ROOT@', root)]:
        if path.is_relative_to(base):
            relative = path.relative_to(base).as_posix()
            return token if relative == '.' else token + '/' + relative
    return str(path)


def _executable(value, root):
    path = root / value if '/' in value else Path(shutil.which(value) or '')
    if not path.is_file():
        raise ValueError('Missing capture executable: ' + value)
    return path.resolve()


def _command_identity(command, root, build):
    words = shlex.split(command) if isinstance(command, str) else list(command)
    if not words:
        raise ValueError('Compiler invocation identity is required')
    result = []
    for index, word in enumerate(words):
        path = _executable(word, root) if index == 0 else root / word
        if index and not path.is_file() and shutil.which(word):
            path = Path(shutil.which(word))
        if path.is_file():
            result.append({'path': _symbolic_path(path, root, build),
                           **coverage_toolchain_identity.executable_identity(path)})
        else:
            result.append({'literal': word})
    return result


def generation_checkpoint(root, build, compiler, flags, mojo, sources):
    root, build = Path(root).resolve(), Path(build).resolve()
    names = list(sources)
    if not names or len(names) != len(set(names)):
        raise ValueError('Generation requires distinct source identities')
    for name in names:
        if not name.endswith('.mojo'):
            raise ValueError('Generation source must be a Mojo module')
        relative_source(root, name)
    return {'schema': 'coverage-generation-v1', 'root_inputs': maintained_inputs(root, exclude=build),
            'python': sys.version, 'compiler': compiler, 'flags': flags,
            'compiler_command': _command_identity(mojo or ['.venv/bin/mojo'], root, build),
            'producer_arguments': ['run', *shlex.split(flags), 'coverage/build_cli.mojo', '@BUILD@', *names],
            'sources': names}


def begin_generation(root, build, compiler, flags, *, mojo=None, sources):
    """Checkpoint before loading/compiling the trusted producer, never after."""
    build = Path(build)
    build.mkdir(parents=True, exist_ok=True)
    (build / 'origins.ready').write_bytes(b'')
    path = build / 'generation-inputs.json'
    path.unlink(missing_ok=True)
    checkpoint = generation_checkpoint(root, build, compiler, flags, mojo, sources)
    path.write_bytes(canonical(checkpoint) + b'\n')
    return checkpoint


def execution_contract(root, build, inputs, *, mojo=None, capture_cache=None, suites=None):
    """Bind the maintained capture wrappers, compiler and exact run flags."""
    selected = (sorted(name for name in inputs if name.startswith('tests/test_')
                       and name.endswith('.mojo')) if suites is None else sorted(suites))
    if len(set(selected)) != len(selected) or any(name not in inputs for name in selected):
        raise ValueError('Capture suite inventory is invalid or not staged')
    cache = root / '.cache/native-coverage' if capture_cache is None else root / capture_cache
    return {'schema': 'coverage-execution-v1',
            'python': {'path': _symbolic_path(Path(sys.executable), root, build),
                       'sha256': file_sha256(Path(sys.executable).resolve())},
            'compiler': _command_identity(mojo or ['.venv/bin/mojo'], root, build),
            'cache': _symbolic_path(cache, root, build), 'suites': selected,
            'cc': os.environ.get('CC', 'cc'),
            'native_compiler': _command_identity(os.environ.get('CC', 'cc'), root, build),
            'profiles': ['raw', 'aot', 'aot-hits'],
            'capture_flags': ['run', '-I', '@BUILD@', '@SUITE@']}


def expected_capture_command(contract, suite, profile):
    if suite not in contract['suites'] or profile not in contract['profiles']:
        raise ValueError('Capture suite/profile is outside the sealed execution contract')
    runner = (['@ROOT@/tools/native_test_support.py', 'run'] if profile == 'raw'
              else ['@ROOT@/tools/coverage_hit_aot.py', '--profile', profile])
    compiler = [item.get('path', item.get('literal')) for item in contract['compiler']]
    return [contract['python']['path'], *runner, '--root', '@BUILD@',
            '--suite', '@BUILD@/' + suite, '--cache', contract['cache'], '--',
            *compiler, 'run', '-I', '@BUILD@', '@BUILD@/' + suite]


def validate_capture_command(command, envelope, root, build, capture=None, output=None):
    """Validate actual argv before launch; record only its checked canonical form."""
    root, build = Path(root).resolve(), Path(build).resolve()
    contract = envelope['receipt']['execution']
    if not command or not all(isinstance(word, str) for word in command):
        raise ValueError('Coverage capture command identity is required')
    try:
        source = Path(command[command.index('--suite') + 1])
        suite = (root / source).resolve().relative_to(build).as_posix()
    except (ValueError, IndexError):
        raise ValueError('Capture command does not identify a staged suite') from None
    profile = 'raw'
    if '--profile' in command:
        try:
            profile = command[command.index('--profile') + 1]
        except IndexError:
            raise ValueError('Missing capture execution profile') from None
    expected = expected_capture_command(contract, suite, profile)
    if len(command) != len(expected):
        raise ValueError('Capture command differs from its sealed execution contract')
    for index, (actual, wanted) in enumerate(zip(command, expected)):
        is_path = wanted.startswith(('@ROOT@', '@BUILD@', '/'))
        if index == 0:
            normalized = _symbolic_path(_executable(actual, root), root, build)
        elif is_path:
            normalized = _symbolic_path(root / actual, root, build)
        else:
            normalized = actual
        if normalized != wanted:
            raise ValueError('Capture command differs from its sealed execution contract')
    if os.environ.get('CC', 'cc') != contract['cc']:
        raise ValueError('Capture native-compiler setting differs from its sealed contract')
    stem = Path(suite).stem
    if capture is not None and Path(capture).name != stem + '.txt.gz':
        raise ValueError('Capture filename does not identify its sealed suite')
    if output is not None and Path(output).name != stem + '.out':
        raise ValueError('Capture stdout filename does not identify its sealed suite')
    return {'suite': suite, 'profile': profile, 'command': expected}


def _expand_path(value, root, build):
    for token, base in [('@ROOT@', root), ('@BUILD@', build)]:
        if value == token:
            return str(base)
        if value.startswith(token + '/'):
            return str(base / value[len(token) + 1:])
    return value


def check_capture_inputs(envelope, root, build):
    """Check sealed bytes before/after execution without reparsing all loops."""
    root, build = Path(root).resolve(), Path(build).resolve()
    receipt = envelope['receipt']
    if (maintained_inputs(root, exclude=build) != receipt['root_inputs']
            or maintained_inputs(build, staged=True)
            != {name: item['instrumented'] for name, item in receipt['inputs'].items()}
            or file_sha256(build / 'manifest.txt') != receipt['manifest_sha256']
            or file_sha256(build / 'origins.ready') != receipt['generation']['index_sha256']
            or file_sha256(build / 'generation-inputs.json') != receipt['generation']['checkpoint_sha256']):
        raise ValueError('Stale or modified capture input binding')
    expected_origins = {name + '.cov-origin': item['origin_sha256']
                        for name, item in receipt['generation']['modules'].items()}
    actual_origins = {path.relative_to(build).as_posix(): file_sha256(path)
                      for path in build.rglob('*.cov-origin')}
    if actual_origins != expected_origins:
        raise ValueError('Stale or modified capture generation origins')
    for name, active in [('tools/coverage_loop_proofs.py', ACTIVE_SOURCE_SHA256),
                         ('tools/cache_key.py', ACTIVE_INVENTORY_SHA256),
                         ('tools/coverage_toolchain_identity.py', ACTIVE_TOOLCHAIN_SHA256)]:
        if receipt['root_inputs'][name] != active:
            raise ValueError('Stale or modified executing capture verifier')
    contract = receipt['execution']
    command = [_expand_path(item['path'], root, build) if 'path' in item else item['literal']
               for item in contract['compiler']]
    current = execution_contract(root, build, receipt['inputs'], mojo=command,
                                 capture_cache=_expand_path(contract['cache'], root, build),
                                 suites=contract['suites'])
    if current != contract or receipt['python'] != sys.version:
        raise ValueError('Stale or modified capture compiler/execution identity')


def build_receipt(root, build, compiler, flags, *, mojo=None, capture_cache=None, suites=None):
    """Rederive proofs from a verified generation and maintained input closure."""
    root, build = Path(root).resolve(), Path(build).resolve()
    raw = (build / 'manifest.txt').read_bytes()
    records = manifest_records(raw)
    branches = {(record[1], int(record[2])) for record in records if record[0] == 'B'}
    modules = sorted({record[1] for record in records})
    root_inputs = maintained_inputs(root, exclude=build)
    tools = {name: root_inputs[name] for name in TOOL_INPUTS}
    if tools['tools/coverage_loop_proofs.py'] != ACTIVE_SOURCE_SHA256:
        raise ValueError('Stale or modified executing proof tool binding')
    if tools['tools/cache_key.py'] != ACTIVE_INVENTORY_SHA256:
        raise ValueError('Stale or modified executing inventory tool binding')
    if tools['tools/coverage_toolchain_identity.py'] != ACTIVE_TOOLCHAIN_SHA256:
        raise ValueError('Stale or modified executing toolchain identity binding')
    generation = generation_origins(root, build, raw, compiler, flags, mojo)
    staged_inputs = maintained_inputs(build, staged=True)
    inputs = {}
    for name, digest in staged_inputs.items():
        if name not in root_inputs:
            raise ValueError('Unmaintained executable input in stage: ' + name)
        expected = generation['modules'].get(name, {}).get('instrumented', root_inputs[name])
        if digest != expected:
            raise ValueError('Staged input differs from generation or passthrough source: ' + name)
        inputs[name] = {'source': root_inputs[name], 'instrumented': digest}
    for module in modules:
        if module + '.mojo' not in generation['modules']:
            raise ValueError('Manifest module has no generation origin: ' + module)
    proofs = []
    for module in modules:
        name = module + '.mojo'
        original = relative_source(root, name)
        if name not in inputs:
            raise ValueError('Missing instrumented module: ' + module)
        candidates = constant_loops(original.read_text(encoding='utf-8'))
        reviewed = reviewed_nonempty_loops(root, module, include_roots=(build,))
        if candidates.keys() & reviewed.keys():
            raise ValueError('Conflicting reviewed loop proof: ' + module)
        candidates.update(reviewed)
        for line in sorted(candidates):
            if (module, line) not in branches:
                continue  # Existing exclusions cannot become new proofs.
            if any(record[0] in {'C', 'M'} and record[1] == module
                   and int(record[2]) == line for record in records):
                raise ValueError('Loop proof conflicts with compound decision: ' + module)
            proofs.append({'module': module, **candidates[line],
                           'source_sha256': inputs[name]['source']})
    counts = _counts(records)
    counts['proven_impossible'] = len(proofs)
    counts['required_total'] = counts['potential_total'] - len(proofs)
    return {'schema': SCHEMA, 'python': sys.version,
            'compiler': compiler, 'flags': flags,
            'manifest_sha256': sha256(raw), 'tools': tools,
            'root_inputs': root_inputs, 'inputs': inputs, 'generation': generation,
            'execution': execution_contract(root, build, inputs, mojo=mojo,
                                            capture_cache=capture_cache, suites=suites),
            'proofs': proofs, 'denominator': counts}


def _load_json(path):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('Duplicate receipt key: ' + key)
            result[key] = value
        return result
    return json.loads(Path(path).read_text(encoding='utf-8'), object_pairs_hook=pairs)


def read_receipt(path):
    envelope = _load_json(path)
    if not isinstance(envelope, dict) or set(envelope) != {'receipt', 'sha256'}:
        raise ValueError('Malformed loop-proof receipt')
    receipt = envelope['receipt']
    if not isinstance(receipt, dict) or receipt.get('schema') != SCHEMA:
        raise ValueError('Unsupported loop-proof schema')
    if envelope['sha256'] != sha256(canonical(receipt)):
        raise ValueError('Loop-proof receipt digest mismatch')
    return envelope


def seal(root, build, compiler, flags, **settings):
    receipt = build_receipt(root, build, compiler, flags, **settings)
    envelope = {'receipt': receipt, 'sha256': sha256(canonical(receipt))}
    path = Path(build) / 'loop-proofs.json'
    path.write_bytes(canonical(envelope) + b'\n')
    return envelope


def verify(path, root, build, compiler, flags, **settings):
    saved = read_receipt(path)
    expected = build_receipt(root, build, compiler, flags, **settings)
    if canonical(saved['receipt']) != canonical(expected):
        raise ValueError('Stale or modified loop proof, source, tool, manifest, or compiler binding')
    return saved


def masked_manifest(raw, envelope):
    """Preserve all original entries except the explicit outcome masks."""
    receipt = envelope['receipt']
    if sha256(raw) != receipt['manifest_sha256']:
        raise ValueError('Loop-proof manifest binding mismatch')
    manifest_records(raw)
    masks = {(proof['module'], str(proof['line'])): proof for proof in receipt['proofs']}
    rows = ['P ' + SCHEMA + ' ' + envelope['sha256']]
    used = set()
    for line in raw.decode('utf-8').splitlines():
        fields = line.split()
        key = tuple(fields[1:3])
        if fields and fields[0] == 'B' and key in masks:
            proof = masks[key]
            line = ' '.join(['R', *key, proof['required'], proof['kind'], str(proof['cardinality'])])
            used.add(key)
        rows.append(line)
    if used != set(masks):
        raise ValueError('Loop proof does not identify one original branch')
    return ('\n'.join(rows) + '\n').encode('utf-8')


def capture_receipt_path(capture):
    return Path(str(capture) + '.proof.json')


def bind_capture(capture, output, envelope, command, *, root, build):
    """Called only after a successful, complete instrumented capture."""
    capture, output = Path(capture), Path(output)
    execution = validate_capture_command(command, envelope, root, build, capture, output)
    payload = {'schema': SCHEMA, 'proof_sha256': envelope['sha256'],
               'capture': capture.name, 'capture_sha256': file_sha256(capture),
               'output': output.name, 'output_sha256': file_sha256(output),
               **execution}
    capture_receipt_path(capture).write_bytes(canonical(payload) + b'\n')


def verify_captures(captures, envelope):
    for capture in captures:
        capture = Path(capture)
        binding = _load_json(capture_receipt_path(capture))
        expected_keys = {'schema', 'proof_sha256', 'capture', 'capture_sha256', 'output', 'output_sha256', 'command', 'suite', 'profile'}
        if not isinstance(binding, dict) or set(binding) != expected_keys:
            raise ValueError('Malformed coverage capture receipt: ' + capture.name)
        name = binding['output']
        if (not isinstance(binding['command'], list) or not binding['command']
                or not all(isinstance(argument, str) for argument in binding['command'])):
            raise ValueError('Missing coverage capture command identity')
        expected = expected_capture_command(envelope['receipt']['execution'],
                                            binding['suite'], binding['profile'])
        if binding['command'] != expected:
            raise ValueError('Modified capture command provenance')
        stem = Path(binding['suite']).stem
        if binding['capture'] != stem + '.txt.gz' or binding['output'] != stem + '.out':
            raise ValueError('Capture files do not identify the recorded suite')
        if not isinstance(name, str) or Path(name).name != name or name in {'', '.', '..'}:
            raise ValueError('Invalid coverage output identity')
        if (binding['schema'] != SCHEMA or binding['proof_sha256'] != envelope['sha256']
                or binding['capture'] != capture.name
                or binding['capture_sha256'] != file_sha256(capture)
                or binding['output_sha256'] != file_sha256(capture.parent / name)):
            raise ValueError('Stale or modified coverage capture: ' + capture.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['begin', 'seal', 'verify'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--flags', required=True)
    parser.add_argument('--mojo', required=True)
    parser.add_argument('--capture-cache')
    parser.add_argument('--suites', nargs='*')
    parser.add_argument('--sources', nargs='*')
    args = parser.parse_args()
    if args.mode == 'begin':
        begin_generation(args.root, args.build, args.compiler, args.flags,
                         mojo=args.mojo, sources=args.sources or [])
        print('Coverage generation checkpoint prepared')
        return
    if args.mode == 'seal':
        envelope = seal(args.root, args.build, args.compiler, args.flags,
                        mojo=args.mojo, capture_cache=args.capture_cache, suites=args.suites)
    else:
        envelope = verify(args.build / 'loop-proofs.json', args.root, args.build,
                          args.compiler, args.flags, mojo=args.mojo,
                          capture_cache=args.capture_cache, suites=args.suites)
    print('Loop proofs:', envelope['sha256'],
          json.dumps(envelope['receipt']['denominator'], sort_keys=True))


if __name__ == '__main__':
    main()
