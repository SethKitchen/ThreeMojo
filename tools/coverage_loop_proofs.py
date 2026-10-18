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
import importlib.util
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

_EXECUTED_MODULE_CODE = sys._getframe().f_code

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
    'tools/coverage_toolchain_identity.py', 'tools/coverage_process_group.py',
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


def file_sha256(path, *, _operation=None, _root=None):
    digest = hashlib.sha256()
    chunks = []
    if _operation is not None:
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
        cleanup._operation_check(_operation, _root)

    def checked_piece(piece):
        # Validate EOF too: a non-builtin empty value can equal iter's sentinel.
        if _operation is not None:
            cleanup._operation_check(_operation, _root)
            if type(piece) is not bytes:
                cleanup._operation_fail(_operation, ValueError('Non-byte coverage source stream'))
            chunks.append(piece)
        return piece

    try:
        with Path(path).open('rb') as stream:
            for piece in iter(lambda: checked_piece(stream.read(1 << 20)), b''):
                digest.update(piece)
        if _operation is not None:
            cleanup._observe_bytes(_root, Path(path).relative_to(_root).as_posix(),
                                   b''.join(chunks), _operation=_operation)
    except (OSError, ValueError, TypeError) as error:
        if _operation is not None:
            cleanup._operation_fail(_operation, error)
        raise
    return digest.hexdigest()


def relative_source(root, name, *, _operation=None):
    """Accept only existing, root-contained, ordinary relative source names."""
    if _operation is not None:
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
        cleanup._operation_check(_operation, root)
    try:
        relative = PurePosixPath(name)
        if (not name or relative.is_absolute() or '..' in relative.parts
                or relative.as_posix() != name or '\\' in name or ':' in name):
            raise ValueError('Invalid coverage source identity: ' + repr(name))
        path = root / name
        if not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError('Missing or escaped coverage source: ' + name)
        if _operation is not None:
            cleanup._operation_check(_operation, root)
        return path
    except (OSError, ValueError, TypeError) as error:
        if _operation is not None:
            cleanup._operation_fail(_operation, error)
        raise


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



# #333 transports only these reviewed theorem sites from exact main2d81.
# The complete current scalar/bound/API graph is admitted first. Pure row
# correspondence cannot itself grant a coverage mask or source receipt.
_TYPED_LOOP_MAIN_SHA256 = {'extensions/carla/curve_rounded_arc.mojo': '7bc84049fed26cb7b14b4fa4603ee36d55cdeb7055c62df50cf10d6a2ce90745',
 'extensions/carla/curve_rounded_line.mojo': '6741ad9d7434c08070de3c959cb49ac42939ac633d1dcd48c9f5cdfdaa719aed',
 'extensions/carla/curve_sample_dispatch.mojo': '91ede65bbc39ac57ca54239513b462d3c71e90cacd085b8bafb2bff514767a86',
 'extensions/carla/junction_bounds.mojo': 'd8b7a6de8e495ab16f0cbe9688459eb544ac9ef6c8ec0c44c952ed5b4743a615',
 'extensions/carla/lane_refinement.mojo': '13ae6d4658458a7d243597428eee762f9bbc40f8fe3507a47beac9ebd4ac1737',
 'extensions/carla/map.mojo': '0e2d282fcd6c70217e7413b7febe40619af070f7adbeaefa3fd56d95562c404b',
 'extensions/carla/opendrive.mojo': '9ff9b750af2c1c1a92fe3f3dfe1e49566e9d6f8c39a3576e0d4cf542bc8cdc28',
 'extensions/carla/rtree.mojo': 'be63ea929c25e0a55600d19568e5f8a117e2f712850ea3da0d977c39b002d460'}
_TYPED_LOOP_ROWS = {('extensions/carla/curve_rounded_arc', 228): (228, (), '_rounded_arc_context'),
 ('extensions/carla/curve_rounded_line', 93): (93, (), '_rounded_line_axis_context'),
 ('extensions/carla/curve_sample_dispatch', 126): (126, (), '_try_sample_dispatch_cuts'),
 ('extensions/carla/junction_bounds', 706): (706, (), '_lane_section_box_with_work'),
 ('extensions/carla/lane_refinement', 145): (146, (), '_axis_lane_minimum'),
 ('extensions/carla/lane_refinement', 726): (736, (), '_lane_certificate_dominates_cells'),
 ('extensions/carla/lane_refinement', 1289): (1299, (), '_continue_lane_certificate'),
 ('extensions/carla/lane_refinement', 1314): (1324, (), '_continue_lane_certificate'),
 ('extensions/carla/map', 1491): (1511, (), '_try_winner_seed'),
 ('extensions/carla/map', 2272): (2294, ('Map',), '_closest_lane_certificate_with_work'),
 ('extensions/carla/map', 2279): (2301, ('Map',), '_closest_lane_certificate_with_work'),
 ('extensions/carla/map', 2301): (2323, ('Map',), '_closest_lane_certificate_with_work'),
 ('extensions/carla/map', 2373): (2395, ('Map',), '_closest_lane_certificate_with_work'),
 ('extensions/carla/map', 2378): (2400, ('Map',), '_closest_lane_certificate_with_work'),
 ('extensions/carla/map', 2387): (2409, ('Map',), '_closest_lane_certificate_with_work'),
 ('extensions/carla/map', 2396): (2418, ('Map',), '_closest_lane_certificate_with_work'),
 ('extensions/carla/map', 4055): (4106, ('Map',), '_add_segment'),
 ('extensions/carla/opendrive', 450): (450, (), '_active'),
 ('extensions/carla/opendrive', 593): (593, (), '_border_widths'),
 ('extensions/carla/opendrive', 601): (601, (), '_border_widths'),
 ('extensions/carla/opendrive', 615): (615, (), '_border_widths'),
 ('extensions/carla/opendrive', 617): (617, (), '_border_widths'),
 ('extensions/carla/opendrive', 621): (621, (), '_border_widths'),
 ('extensions/carla/opendrive', 787): (787, (), '_lanes'),
 ('extensions/carla/rtree', 666): (666, ('_Rtree',), '_nearest_next')}


def _typed_loop_row(module, historical_line, expression, current):
    """Locate one unchanged loop in its exact reviewed declaration owner.

    The whole endpoint and inverse must be sealed. Match the complete ordered
    loop-statement inventory of the owner, not just a line or expression.
    Owners call this only after physical current graph admission.
    """
    from carla_lane_oracle import typed_boundary_contracts as typed
    from carla_lane_oracle import seed_count_contracts as seed
    item = _TYPED_LOOP_ROWS.get((module, historical_line))
    name = module + '.mojo'
    if item is None or not typed.is_current(name, current):
        return None
    previous = typed.historical_source(name, current)
    if sha256(previous.encode('utf-8')) != _TYPED_LOOP_MAIN_SHA256[name]:
        return None
    main_line, owner, function = item
    before, before_first, before_last = seed._function_span(previous, function, owner)
    after, after_first, after_last = seed._function_span(current, function, owner)
    old_statements, new_statements = _statements(before), _statements(after)
    expected = _statements('for value in ' + expression + ':\n    pass\n')
    if old_statements is None or new_statements is None or expected is None:
        return None
    def for_rows(statements, first):
        return [(first + row[0].start[0], tuple(token.string for token in row))
                for row in statements if row[0].string == 'for']
    old_rows = for_rows(old_statements, before_first)
    new_rows = for_rows(new_statements, after_first)
    if [words for _, words in old_rows] != [words for _, words in new_rows]:
        return None
    selected = [(index, words) for index, (line, words) in enumerate(old_rows)
                if line == main_line]
    if len(selected) != 1:
        return None
    index, words = selected[0]
    if len(words) < 5 or words[2] != 'in' or words[-1] != ':' or words[3:-1] != tuple(
            token.string for token in expected[0])[3:-1]:
        return None
    return new_rows[index][0]


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
            '42e4799761c82ebc1f51ed87c5e77d67c018bd5d310670cecb74d220c236e880',
    }, (
        (225, 'literal-range', 2, 2, 'range(2)', 'hair-upload-two-endpoints'),
        (231, 'literal-range', 3, 3, 'range(3)', 'hair-upload-three-channels'),
    )),
}


# PR760 local literal successor. The retained-groom theorem below is unchanged.
HAIR_LITERAL_SUCCESSOR = ({
    'extensions/humanoid/skeleton/head/hair/strands.mojo':
        '058c0e6fbfce95ee97c79247622185de968c8de5e0ad23240d667da13776404f',
}, (
    (229, 'literal-range', 2, 2, 'range(2)', 'hair-upload-two-endpoints'),
    (235, 'literal-range', 3, 3, 'range(3)', 'hair-upload-three-channels'),
))


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
        'f083d89edf192cdc70acc758e5cf7bdd563fe883303eb9543d430348e22a888f',
    'extensions/humanoid/skeleton/head/hair/shading.mojo':
        'eba4c66a1203e4dc67845ad874e50fa68653e1adb0c9c973cb2a29205d826ba9',
    'extensions/humanoid/skeleton/head/hair/strands.mojo':
        '42e4799761c82ebc1f51ed87c5e77d67c018bd5d310670cecb74d220c236e880',
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
    ('extensions/humanoid/skeleton/head/hair/strands', 221, 'reviewed-nonempty-range', None, 'range(len(self.groom))', 'hair-retained-nonempty-strands', ('extensions/humanoid/skeleton/head/hair/density.mojo', 'extensions/humanoid/skeleton/head/hair/groom.mojo', 'extensions/humanoid/skeleton/head/hair/shading.mojo', 'extensions/carla/agents_route.mojo', 'tests/test_carla_route_search.mojo'), ()),
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
    (221, 'hair-retained-nonempty-strands'): _HAIR_RETAINED_CENSUS,
}


# Historical table hashes remain review inputs. Only this exact successor may
# project Map to its predecessor, after checking the live dependency closure,
# premises and count-control fixture. Receipts always retain the live hash.
_MAP_SUCCESSOR_LINES = {
    1491: 1485, 2272: 2264, 2279: 2271, 2301: 2293,
    2373: 2365, 2378: 2370, 2387: 2379, 2396: 2388,
}


# The optional-guard edge deletes exactly nine more physical lines. These
# independently retained nonempty loops keep their original proof IDs and T.
_MAP_OPTIONAL_SUCCESSOR_LINES = {1491: 1476, 2272: 2255, 2279: 2262, 2301: 2284, 2373: 2356, 2378: 2361, 2387: 2370, 2396: 2379}


# The separate support and frontier edges retain these same eight theorems.
# Only exact reviewed endpoints activate their physical-line correspondence.
_MAP_SUPPORT_SUCCESSOR_LINES = {
    1491: 1464, 2272: 2243, 2279: 2250, 2301: 2272,
    2373: 2344, 2378: 2349, 2387: 2358, 2396: 2367,
}
_MAP_FRONTIER_SUCCESSOR_LINES = {
    1491: 1463, 2272: 2242, 2279: 2249, 2301: 2271,
    2373: 2343, 2378: 2348, 2387: 2357, 2396: 2366,
}


# The finite-score extraction adds 16 lines before the dyadic loop and a net
# 14 before all later rows. Refusal remains an ordinary measured branch.
_MAP_SCORE_SUCCESSOR_LINES = {
    1491: 1479, 2272: 2256, 2279: 2263, 2301: 2285,
    2373: 2357, 2378: 2362, 2387: 2371, 2396: 2380,
}


# The default station edge changes only its helper and two default callers.
# These sites were mapped individually through unchanged complete loop bodies;
# the helper's new branches remain measured normally. No blanket line offset.
_MAP_STATION_SUCCESSOR_LINES = {
    1491: 1508, 2272: 2287, 2279: 2294, 2301: 2316,
    2373: 2388, 2378: 2393, 2387: 2402, 2396: 2411,
}


# The per-segment deviation edge (#685) adds one stored field, one skip in
# the query's candidate admission and one constructor argument. Its exact
# inverse leaves every byte outside those three spans unchanged, including
# each loop header and body below. Each site was mapped individually: +3
# after the _Segment field, +7 after the query skip. No blanket offset.
_MAP_DEVIATION_SUCCESSOR_LINES = {
    1491: 1511, 2272: 2294, 2279: 2301, 2301: 2323,
    2373: 2395, 2378: 2400, 2387: 2409, 2396: 2418,
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


def _density_stdlib_unshadowed(root, *, _operation=None):
    """Refuse unreviewed project std resolver surfaces, including packages.

    SDK payloads are bound separately. The project's standard virtualenv and
    non-input caches are not include roots and must not veto the real SDK.
    A project directory symlink could hide an additional resolver surface;
    conservatively refuse it instead of following it outside the checked tree.
    """
    if _operation is not None:
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
        cleanup._operation_check(_operation, root)
    root = Path(root)
    if not root.is_dir():
        if _operation is not None:
            cleanup._operation_fail(_operation, ValueError('Missing coverage resolver root'))
        return False

    def unreadable(error):
        raise error

    try:
        for directory, folders, files in os.walk(root, onerror=unreadable):
            if _operation is not None:
                cleanup._operation_check(_operation, root)
            base = Path(directory)
            # Refuse alternate/unknown suffixes as well as .mojo, .mojoc and
            # .mojopkg. This includes Mojo's alternate source-file suffix.
            if any(name.casefold() == 'std' or name.casefold().startswith('std.')
                   for name in (*folders, *files)):
                if _operation is not None:
                    cleanup._operation_fail(_operation, ValueError('Shadowed coverage std resolver'))
                return False
            folders[:] = [name for name in folders if name not in cache_key.SKIP
                          and (base / name).relative_to(root) != Path('coverage/build')]
            if any((base / name).is_symlink() for name in folders):
                if _operation is not None:
                    cleanup._operation_fail(_operation, ValueError('Symlinked coverage resolver directory'))
                return False
    except (OSError, ValueError) as error:
        if _operation is not None:
            cleanup._operation_fail(_operation, error)
        return False
    if _operation is not None:
        cleanup._operation_check(_operation, root)
    return True


def repaired_density_loops(root, *, include_roots=(), _operation=None):
    """Admit local repaired loops, never their unsafe historical counterparts."""
    operation_args = {} if _operation is None else {'_operation': _operation}
    stream_args = {} if _operation is None else {'_operation': _operation, '_root': root}
    if _operation is not None:
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
        cleanup._operation_include_context(_operation, root, include_roots)
    try:
        if file_sha256(relative_source(root, DENSITY_SOURCE, **operation_args),
                       **stream_args) != DENSITY_AFTER_SHA256:
            return {}
    except (OSError, ValueError):
        return {}
    if not all(_density_stdlib_unshadowed(path, **operation_args)
               for path in (root, *include_roots)):
        return {}
    return {line: {
        'line': line, 'kind': kind, 'cardinality': 1,
        'minimum_cardinality': minimum,
        'maximum_cardinality': maximum, 'required': 'T', 'impossible': 'F',
        'expression': expression, 'proof_id': proof_id,
        'dependency_sha256': {DENSITY_SOURCE: DENSITY_AFTER_SHA256},
    } for line, kind, minimum, maximum, expression, proof_id in DENSITY_REPAIRED_RULES}


# Fixed physical density/groom import closure on the reviewed PR760 image.
# These bytes bind local domination proofs only, never whole CARLA admission.
DENSITY760_INPUTS = {'core/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'core/assets.mojo': '5d5394df10b330767970b8585f9707673fb1ee6ef0f269ec430b8e2ffa54f89b',
 'core/background.mojo': '0d43517034157e341071cd96448901e0483480053e26df93dca3521680446039',
 'core/binary.mojo': '2d3a5a121ebcd919fc987b5972eb1071100bdd9dc397695c789561cc275e59d7',
 'core/buffer_attribute.mojo': '8b0dfe3d758bf4e323805f5a3c513a3102f7fde86f7ebad418db3264295ceaed',
 'core/buffer_geometry.mojo': '9e09d806746e717207b5d20bff79369b5cc6357bcde1d9a609792c0095668176',
 'core/extent.mojo': '50f3c4fcc55b672ab1d42505cf70baeb3aae85ebf915927369246ab7e214a023',
 'core/fog.mojo': '8026f0db83e2eef31d0e63793f65a449cb9eebae917e081e950a851ab98ca66c',
 'core/gaussian_splat_utils.mojo': '63e4123f61a1e8ae6845b0eae449b5c173368bdf0ca691d7327255d33c8533b3',
 'core/geometry_store.mojo': 'c42cde4b1e8c5668b138d462a997ac23d36cfe9789cddd22eaee142a2cec6f06',
 'core/interleaved_buffer.mojo': '2d9b3760a4e0d9d227d38a91ef4917501ffecdedfdf60bf0e8ccacd0e60de597',
 'core/layers.mojo': 'ebc7a81fcc9f8b7d36ab3cecc46208f078797b7ac108317baaac9a9d44cacb7b',
 'core/morph.mojo': '8c84adfbad9405ae1f582ba6e3f6a9b39db14bbf8ac20e96bee1d03e9d6be47d',
 'core/object3d.mojo': '749062c89390981215d7f4d9fb60a4557291b734b19f93571d4e46e1996cb203',
 'core/order.mojo': '4c7a1e85fbb2ceffa9c6d59a4294517057b1580dfd7b0e2f07b1ec99b59096b7',
 'core/ordinal.mojo': '020ae821e6e4d6f596174a672f70876d43a13d5a397bd42ef1b2152ac736bb90',
 'core/scene.mojo': '4eb55a160cd53e4db34a51bc6fc48e7427cb10ffa4ffa72e191519dee76e8b20',
 'core/search.mojo': '1bc8bedd8b4d91ff3a455fa8232dc36fdfdeae0b7f61adf8d41ee16467b8df72',
 'core/user_data.mojo': 'bec1a6fb8cf0cc43536c0e347a5e302fa225988a47dcd5001b30fb9dd443d5a5',
 'extensions/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/anatomy/__init__.mojo': 'e07a6d503cb1d532b4dac54ceca76d6ff2b7bbddea0af02d17f55b64143ee1cf',
 'extensions/anatomy/soft_tissue.mojo': '7a72a46ef52f2d4a506b30eb405381a2e24760bfdb7e80a3b49bde1a29d1b91b',
 'extensions/humanoid/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/assets.mojo': '5bb7d4e755b00fb7f9170449fac3fb294b8a32be7397772cfec73fd1af0a0fd4',
 'extensions/humanoid/athleticism.mojo': '0cddb9a18fbd1de06a3af23fdba6bd6d76a0227c537277bf87ebc6b6aedc9541',
 'extensions/humanoid/genome.mojo': '6e76453b4bd8f3b1fc7a1575ceff46684aa3d4c333b4fed506dfc21ed68a5eca',
 'extensions/humanoid/sex.mojo': 'd31e08b1eb5e8301ae86d895b1f0e35e9242ea0e2e265227243c4231b406c342',
 'extensions/humanoid/side.mojo': '8e0d56aaa0b8a06cde796f440809daab81ff2ba5042c56f5474beaf5115cd2a9',
 'extensions/humanoid/skeleton/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/arm/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/arm/assembly.mojo': 'f62f2445d176dcb7135826a79fe03cf1ef1958717e9241fe6d083eadd034911f',
 'extensions/humanoid/skeleton/arm/bones/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/arm/bones/dimensions.mojo': 'fec01e7fcf2e22f572025a9aa25ee73787afe40a81af3d15895ed870eb220388',
 'extensions/humanoid/skeleton/arm/bones/geometry.mojo': 'b97e08430c780a0ee916aaa1137af5c64f2282de7330d34bd23e68f591c5903e',
 'extensions/humanoid/skeleton/arm/contents.mojo': '4abe4929a889fbb130217874c52a470fad109c0d29d85a3e6004a77eeb28f508',
 'extensions/humanoid/skeleton/arm/frame.mojo': 'a6a2fd6455f20e4e261fb43d4b6754d382da71dd060a79a19612cafc4f927546',
 'extensions/humanoid/skeleton/arm/hair/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/arm/hair/dimensions.mojo': '2117dae1a6b922403571c72f661ed270acef62589299c02daab143edd3d9188d',
 'extensions/humanoid/skeleton/arm/hair/geometry.mojo': '20d3ff217a0c2fca7da2e62c94d5a5369261f1eb613e210c4a9e4d9bb9ea54db',
 'extensions/humanoid/skeleton/arm/ligaments/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/arm/ligaments/dimensions.mojo': 'd6439c7dc5bff3066ca69d8e610162f9038cb65dcc3056da3d430ab11a401162',
 'extensions/humanoid/skeleton/arm/ligaments/geometry.mojo': 'efdc55cb634b732654bc268971c0fafde6baa2d502ba0d4f827ec63acb1018e3',
 'extensions/humanoid/skeleton/arm/lymph/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/arm/lymph/dimensions.mojo': '9c69c757e141106011074cc20ba0e0e90543ee7e2c767bf741f046ebf7b11a63',
 'extensions/humanoid/skeleton/arm/lymph/geometry.mojo': '77d88fb31f2fdb2b3e7f0492c5f8b3f833afa3ac82d9f2094294081460b538ab',
 'extensions/humanoid/skeleton/arm/muscles/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/arm/muscles/dimensions.mojo': 'daea51edd98ea1882e5f5b840ef43e93f3f4421b6e142ad2fd6d5c1ca5174a0b',
 'extensions/humanoid/skeleton/arm/muscles/geometry.mojo': '87c62ef12263a84408013142de1306ad3d682401d223121ee49a16a878bb1e26',
 'extensions/humanoid/skeleton/arm/nerves/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/arm/nerves/dimensions.mojo': '5f99788bd09e4eba09c04c10547b443af4640e58161dd2414340f2fa63b8fee5',
 'extensions/humanoid/skeleton/arm/nerves/geometry.mojo': 'f4c02994854f0cdabe88453f3a7c691bb44dab599157da776380ba0289340cb4',
 'extensions/humanoid/skeleton/arm/skin/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/arm/skin/dimensions.mojo': '65341dc934994f1401535fc732255739dae36ff4790389ca7808729064e92aa0',
 'extensions/humanoid/skeleton/arm/skin/geometry.mojo': '8b687cd8a8982e32f2fac500c2db809a3ada568c4fbc3903dfd081f9089a05a3',
 'extensions/humanoid/skeleton/arm/vessels/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/arm/vessels/dimensions.mojo': '720932e514410d8ed79f7bab028cda672a68b0380b11376b34356038faa4b6c9',
 'extensions/humanoid/skeleton/arm/vessels/geometry.mojo': 'a5f4cb9a6493d4ea73a5a50b4a146aa054452ca11a762922c2851771af35bc31',
 'extensions/humanoid/skeleton/complexion.mojo': '4000aa47c43c805097a54b96d226ae89d6341a6ca6c79436e80b7e8dbd56ad06',
 'extensions/humanoid/skeleton/dermis.mojo': 'bdfbe857828add673109c382a8478ad6ea7a47c495b8bbfd3b38a6844d0ff5f9',
 'extensions/humanoid/skeleton/field.mojo': 'c5c57466cc6bd576d56bddd948f5dcbc3330523b2375742c8a8f1ab687d40fa9',
 'extensions/humanoid/skeleton/foot/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/foot/assembly.mojo': '3cf5b178fa42b49feebf9336703caa990b43ed83dc2f0075d02292be77939df3',
 'extensions/humanoid/skeleton/foot/bones/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/foot/bones/dimensions.mojo': 'b6f21c7d225c013eab349961aee5c416322e6abb053b5e9cad69d006435a569a',
 'extensions/humanoid/skeleton/foot/bones/geometry.mojo': '3e04cf81d212e620db76470513e20180c45c97264b56a06343eb8d821137da6b',
 'extensions/humanoid/skeleton/foot/chain.mojo': 'd82355f0a6f6c4f3340f24689b9b1aa18f916fd57c8f030647c200dc52eb00bc',
 'extensions/humanoid/skeleton/foot/contents.mojo': '4ac91cacee468c5b8bad79ad8cdd8012995b51b31bbff3244dc1f09820e5af35',
 'extensions/humanoid/skeleton/foot/hair/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/foot/hair/dimensions.mojo': '15781d9f1f7961037b22d418823cf2d007002563a78edc4b84f4400311d3a018',
 'extensions/humanoid/skeleton/foot/hair/geometry.mojo': '2822843b766edb7f260a6a410635bcb39b57db0e5cea728177b0a1d431af6a38',
 'extensions/humanoid/skeleton/foot/ligaments/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/foot/ligaments/dimensions.mojo': 'e534d46121d26c543a7b506164c64ef54d2cc29caac636cef929d1eeff54f6d6',
 'extensions/humanoid/skeleton/foot/ligaments/geometry.mojo': '3082eb038e5acef71d037476c7ccf9aef9e23fe0a8be88640e4ac3468965d317',
 'extensions/humanoid/skeleton/foot/lymph/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/foot/lymph/dimensions.mojo': '822889f9bd9ca1e68714945c255d272747986037f8bf6d551d6e4c6c4e2f5b3a',
 'extensions/humanoid/skeleton/foot/lymph/geometry.mojo': '822b1a94865951aa34427c927e5d3185e8c777a2a53616999de6354830a32ef3',
 'extensions/humanoid/skeleton/foot/muscles/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/foot/muscles/dimensions.mojo': '06b1c0b7e304eed94682ffa8ba1b799bdce944f06f0804be9f25785d6c898d7b',
 'extensions/humanoid/skeleton/foot/muscles/geometry.mojo': '1e40ff03dd6516b9e391c428a9884ca8cff56d3df9cc08cdd3443d5d2aa28a0f',
 'extensions/humanoid/skeleton/foot/nerves/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/foot/nerves/dimensions.mojo': '6ae2a4a74534bf8d3ad32a1b4a2e4bbda71821af57793b17293169121e021908',
 'extensions/humanoid/skeleton/foot/nerves/geometry.mojo': '20cc857c207e46a1e423533839219e418eb0334a8db8f09fa036649456cce4aa',
 'extensions/humanoid/skeleton/foot/skin/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/foot/skin/dimensions.mojo': 'cac9654d6385da4c8fa44ec185fa7829de620f823ebe178a7485b69926f49cec',
 'extensions/humanoid/skeleton/foot/skin/geometry.mojo': 'ac8fc0d736a79aa68108f52dff5b68d06a5a71cf1c74902cf30ec8fa5ae46154',
 'extensions/humanoid/skeleton/foot/vessels/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/foot/vessels/dimensions.mojo': '22b582af30c0003ca1535d6573d44c54132cac6b47a8884df24adfde2f5058b8',
 'extensions/humanoid/skeleton/foot/vessels/geometry.mojo': '52acebbddd8e2ced61c9c141a8e23668162ebca4d581ec96f3cf5b70f63bcdb0',
 'extensions/humanoid/skeleton/hair_shafts.mojo': '1c8c1a21f439d4694bde79aff5d576a98d9d002ff2ac02b94010eaac6ac3311c',
 'extensions/humanoid/skeleton/hand/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/hand/assembly.mojo': '77f807c1ee34a766f7f79b6b4d04c5caf4310cc569b26e6441621db35146c408',
 'extensions/humanoid/skeleton/hand/bones/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/hand/bones/dimensions.mojo': 'ee3533bb1657418b005a7bd13451a510789beb726fa38e0add676d4d1d618461',
 'extensions/humanoid/skeleton/hand/bones/geometry.mojo': '93a3fa4a707f8fe950db466c0af19185fc9c13149021cd77a5512433c02ca2c4',
 'extensions/humanoid/skeleton/hand/contents.mojo': 'ce55447d577356c91dfa648ec4b2c28a6de4c00332859b9c8044df350e42aa56',
 'extensions/humanoid/skeleton/hand/hair/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/hand/hair/dimensions.mojo': '85a3ad55508026b86b8ace135c0209b415595a8955df9445cb0370cd51f66832',
 'extensions/humanoid/skeleton/hand/hair/geometry.mojo': 'ace0c7dd09bf1e0cb64c4d16b0a4421f53e6dc4139ba0b482b7cad483277aa83',
 'extensions/humanoid/skeleton/hand/ligaments/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/hand/ligaments/dimensions.mojo': 'dedee73703e5a13bd8de7c37989a1480e129a3c79e596cd405e400c3113daafa',
 'extensions/humanoid/skeleton/hand/ligaments/geometry.mojo': 'e12c1e40562e5a6a533668b0827ecdd34ed5dfd78b56e27b79cb12845b949fe3',
 'extensions/humanoid/skeleton/hand/lymph/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/hand/lymph/dimensions.mojo': '7f1b2197ba968af085e6cd42088447100eb33ec24fcd672efdf9ed33bb8dc7ab',
 'extensions/humanoid/skeleton/hand/lymph/geometry.mojo': 'f568f74defca05261750eabf717ad715689273911e07693f00819e48791f51aa',
 'extensions/humanoid/skeleton/hand/muscles/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/hand/muscles/dimensions.mojo': '774775c26d5852f240f1140415103765d60a2165fd459189833d578f6d5657bf',
 'extensions/humanoid/skeleton/hand/muscles/geometry.mojo': 'c69e380e22d6a6470a828569174692d778c943c44dc55fa076fde77405f2e0e7',
 'extensions/humanoid/skeleton/hand/nerves/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/hand/nerves/dimensions.mojo': 'f0082636513ae8306f9bde3cce54d8f3090d3170d5f81c420d66ea2819a7a978',
 'extensions/humanoid/skeleton/hand/nerves/geometry.mojo': 'a59e5b920dffc808c9f8b469c1a00db77829e77ac533599049e5c514948c9088',
 'extensions/humanoid/skeleton/hand/skin/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/hand/skin/dimensions.mojo': '329328b7896e02928f9d8afd319a2cbe380d65e6bc4ed06ea1b9d398d1276aa2',
 'extensions/humanoid/skeleton/hand/skin/geometry.mojo': '82531a82da3600f8887a8e1e3af7e3758d3d975bb036c8c976ef4d7a8d44af6a',
 'extensions/humanoid/skeleton/hand/vessels/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/hand/vessels/dimensions.mojo': 'f6182b369605e4dc0a3fb389c90cdff1a907f1eb5cc7d4d62fbd42ca978b7052',
 'extensions/humanoid/skeleton/hand/vessels/geometry.mojo': 'ae7b3fe2dd1f1b6eae62317876b135ec07f8d0588c6835b46fbe4885fc4c51bb',
 'extensions/humanoid/skeleton/head/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/head/assembly.mojo': '89c62abc454debdb2777e3698c2992185507a4c2b1c7674ecd22bf70a883f406',
 'extensions/humanoid/skeleton/head/bones/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/head/bones/dimensions.mojo': '8de999263d7cb6b807b6e1105e5bf9e774efdbcd0501546bac58af77415e0eba',
 'extensions/humanoid/skeleton/head/bones/geometry.mojo': '131afc719a4262c90defbd9c1c9c70dffe4382ee2f365fc57fe0bef96bbd12c5',
 'extensions/humanoid/skeleton/head/contents.mojo': '8963187c2c449394e9deeb5efeca8e9f781d6fe39525b74c878a2af2c7eb4e69',
 'extensions/humanoid/skeleton/head/eyes.mojo': 'ed845af70644d0408e6a295c1af5abcf4ef6ab16073a8ab29a2c9d5b258e542b',
 'extensions/humanoid/skeleton/head/face_model.mojo': '89f346b425a3f096e8ad46352f97cbf44299f3a0bd4713815af3b7e6a3322e6e',
 'extensions/humanoid/skeleton/head/frame.mojo': 'cc2ebb1a9d590ddd6072f509d8f9d59f41473f02128193bbf9f8b3de6f54795d',
 'extensions/humanoid/skeleton/head/hair/collider.mojo': 'da7bf07ec7f71bbb742e8af16de38d3b93bd3497446cf5f73ed1a1b8fe438a88',
 'extensions/humanoid/skeleton/head/hair/density.mojo': '88283971d77ae8f245e606887373bc57222c403f4e64af982bf2acdf4a97ef63',
 'extensions/humanoid/skeleton/head/hair/dimensions.mojo': '4dbcc1e61c5b8a748633d255b99f9167f55c7b822c7a7718e5b6b11ed860152b',
 'extensions/humanoid/skeleton/head/hair/geometry.mojo': '786d218c79da1097b930bc83d42ac9d3ae2cb4b4705d2c1318f824db251396ee',
 'extensions/humanoid/skeleton/head/hair/groom.mojo': '67f8ea34485c0f1a8b561dece38a933cdc5d0e6aea47d038196d68ee0b617fbd',
 'extensions/humanoid/skeleton/head/hair/styles.mojo': '2693b22bbca30f659de4c954479249680871c001959c03644d897f17ba5c5ea4',
 'extensions/humanoid/skeleton/head/ligaments/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/head/ligaments/dimensions.mojo': '4ff301c65e3c38639504f67f2ab32267a34c0e9f89768d5f30cafe97cf5a5779',
 'extensions/humanoid/skeleton/head/ligaments/geometry.mojo': 'a4da0a0a88d271c2198dca163b553b420987b76e0d61251f8b0482fc4d002586',
 'extensions/humanoid/skeleton/head/lymph/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/head/lymph/dimensions.mojo': '1606f3ac37769995f888646920da7ff2973c4f0fdf29f8d118348a8173101831',
 'extensions/humanoid/skeleton/head/lymph/geometry.mojo': 'e6735eeddeff098772e131af3f3c05c2e19e67f7d4d5802c9eb493bd7435df3c',
 'extensions/humanoid/skeleton/head/muscles/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/head/muscles/dimensions.mojo': '0fd568d8d36e0c7390f18b1d212853a6a643d9d86e2a358990f00fa369793c67',
 'extensions/humanoid/skeleton/head/muscles/geometry.mojo': '9805573beadd5dc11b5689902f29bcd403eb18dd62d6317a4292948f8724f74c',
 'extensions/humanoid/skeleton/head/nerves/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/head/nerves/dimensions.mojo': 'b8648d896b8d5d0700f81ee12232c5933b3f30909f65b25da42240946d5a44f7',
 'extensions/humanoid/skeleton/head/nerves/geometry.mojo': '0c794156f22d40b3224fb0e6b0f80943b1e777628e6a4a42fb07682898288fdf',
 'extensions/humanoid/skeleton/head/skin/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/head/skin/dimensions.mojo': 'fb1f420a98b05ce2a64224699b4dd5b1032654a096ffe9ce6e060d0fcee713be',
 'extensions/humanoid/skeleton/head/skin/geometry.mojo': '22d55d868986379a82bab45d351325d223c0f228cd60b2ea9eacdc58286cc385',
 'extensions/humanoid/skeleton/head/skin/mouth.mojo': '9c3bdb9b664e92a3a3e7fb93689be2ff7ca2b996de740bd750d7d31819eb406c',
 'extensions/humanoid/skeleton/head/skin/scan.mojo': '616033de36df47bc74ec0c0f91d38dff73ae1b8606ca42731dc97af9b8891eb7',
 'extensions/humanoid/skeleton/head/skin/tint.mojo': 'aefb817f97ca01316b9a9a22e30f855bd9bd20fdfc9573d6fcdd7eed5c30d170',
 'extensions/humanoid/skeleton/head/vessels/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/head/vessels/dimensions.mojo': '0f3bc9c28524be575a022bb1700eba4811c27410d270c7c80b5077425f1bf515',
 'extensions/humanoid/skeleton/head/vessels/geometry.mojo': '775662396994f5ccffac5b4b5f2102488118a5d7cf1373f1f36c01fae1bf7709',
 'extensions/humanoid/skeleton/isosurface.mojo': 'cf40c00847dbdb157273acc2163ba3c2f90875ac0b41ec67ea9d4828fb17ac75',
 'extensions/humanoid/skeleton/layer_set.mojo': '833ceb236d967cc0594cad8e7ccc97b13a874f73605ef103b32bf6c8776ced09',
 'extensions/humanoid/skeleton/leg/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/leg/assembly.mojo': '50593a0fbe48d64ccd33386d1ab1d5b2ad54482d758f78ccfc4b362b49a1cafd',
 'extensions/humanoid/skeleton/leg/contents.mojo': 'c2aef8fe7969cab99926bce30af9de3777294c96d8c526582739fa63e73be28b',
 'extensions/humanoid/skeleton/leg/femur/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/leg/femur/dimensions.mojo': '1bfcc887ee1f531108b2719c31d90d8b88f8650db75b32e3a628f991488dc4ba',
 'extensions/humanoid/skeleton/leg/femur/geometry.mojo': 'e6e99b707dff7ab24886a5ecbf4bf1ce15f7cd3ab617bf2117b392a671675691',
 'extensions/humanoid/skeleton/leg/fibula/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/leg/fibula/dimensions.mojo': 'b4c7848f100e1ebd5ba1010de6fc34bc77aa59b227010fd33c0d40b664e0fbaa',
 'extensions/humanoid/skeleton/leg/fibula/geometry.mojo': '50205b8c7e927732edac3e227f23d1e8d520f0eb4ceb04d0b91e8a2ca7fe93cc',
 'extensions/humanoid/skeleton/leg/hair/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/leg/hair/dimensions.mojo': 'e904d80577cd1727684064b1ed4b487ff29b795f50eab770ded4665831c9cacb',
 'extensions/humanoid/skeleton/leg/hair/geometry.mojo': '4653aab9209929c433617c94029f68d438cce5d0745fbd5dbfdb7a877bb9cef6',
 'extensions/humanoid/skeleton/leg/knee/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/leg/knee/dimensions.mojo': '6661d7cb0622e8f3e66044f0fe598ad9ae0a493654ccf0293313579fa2ec8297',
 'extensions/humanoid/skeleton/leg/knee/geometry.mojo': 'c7477b3213098d1c42ea4fb9fbb550f0c003f75512eb07ccd39721aca00ea38d',
 'extensions/humanoid/skeleton/leg/lymph/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/leg/lymph/dimensions.mojo': '34bb02ffa56e23a7f2651979fc4e52c0cf1c9bc329cf6f5c926f66a74076aa66',
 'extensions/humanoid/skeleton/leg/lymph/geometry.mojo': '98572a4ddfb99d136838dcbfa1e97b58dc2fee8ef6e2e66c4a0f4403aa8989b4',
 'extensions/humanoid/skeleton/leg/muscles/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/leg/muscles/dimensions.mojo': 'f947872e5d0f24ba923b445ff13970a56adc1299534a6cf5b48885173981117f',
 'extensions/humanoid/skeleton/leg/muscles/geometry.mojo': '7ba642cfe580bd55e882020e0e7449b1b02b105a4c968d4eb86c51f76fd81957',
 'extensions/humanoid/skeleton/leg/nerves/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/leg/nerves/dimensions.mojo': 'da35dd1c640e32ab76fe8af3ae59ea0d0f0fe1543a86f28b21f94d79e36cc833',
 'extensions/humanoid/skeleton/leg/nerves/geometry.mojo': 'b3ca7e7d49746d2fc1ea8fafa6aa8f971c0ce9f331bf2f2862cbb9a63f09b6a0',
 'extensions/humanoid/skeleton/leg/patella/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/leg/patella/dimensions.mojo': '0ff13ee04349990b58ee3b37f9b928ad36a9ffcf6237d6032f8d7de2aedd17ff',
 'extensions/humanoid/skeleton/leg/patella/geometry.mojo': '6aa9d6af356e5a506e45035b3a160548bfed17455560b8a4190af74cef8350e9',
 'extensions/humanoid/skeleton/leg/skin/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/leg/skin/dimensions.mojo': 'e85e7864d7a6e8d5c041ba8386c790938345502688f519717a1523f4076b9393',
 'extensions/humanoid/skeleton/leg/skin/geometry.mojo': '612bead9071cff56cb692fed1a2014211acfbd1264911f8e0ff34eb41c48f8f4',
 'extensions/humanoid/skeleton/leg/tibia/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/leg/tibia/dimensions.mojo': '0b35d66eff93164c478da515d5966a736a37f0aac8853837a5c5f31cd61e05dc',
 'extensions/humanoid/skeleton/leg/tibia/geometry.mojo': 'e366515e962e34e2c3ded867861693eb7b5152bc3bd93d4f4e70027b9a1b7eaf',
 'extensions/humanoid/skeleton/leg/vessels/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/leg/vessels/dimensions.mojo': '3a9b54cfa4eeeacbb1a04c8ce8952a46f5ca2d8405f69215832aecf37ea476a7',
 'extensions/humanoid/skeleton/leg/vessels/geometry.mojo': '53b51984fd16179981a4f964f7fd6435009d946c8b1103c1b66504cf75b3bb85',
 'extensions/humanoid/skeleton/limb/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/limb/skin.mojo': '3b93c4902fa4dfbb2bb984aa21dfd555036631b40e8d964e8b776a07414ac430',
 'extensions/humanoid/skeleton/loft.mojo': 'e752c764322629e463d4bda2ec1016fcf798dc783b8964e1d3c67380724083ab',
 'extensions/humanoid/skeleton/look.mojo': '3650c0efb4bbfd6ab72793cbb2485b633bb70e6e8413006ea8022a3c1a93dc89',
 'extensions/humanoid/skeleton/mesh_field.mojo': '2fae9883759be00f2d95eed70595bd4f3020773a96e821d88af86c45b5cd136d',
 'extensions/humanoid/skeleton/morph.mojo': 'ad45a84aecebd2ede894aaf3706ae14a79635e1df93156adb540662620c5d8ec',
 'extensions/humanoid/skeleton/pelvis/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/pelvis/assembly.mojo': 'a1db00e7da91785d4700751d2e23ab1a1359ff0176201c0a58390373dfd7785d',
 'extensions/humanoid/skeleton/pelvis/bones/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/pelvis/bones/dimensions.mojo': '13fd1ec5e495f42650355847245f508d41b37da75766e0bae9b398c31403b5f1',
 'extensions/humanoid/skeleton/pelvis/bones/geometry.mojo': 'da74a97a5bc3c9bca9d3cbdad9addeef1ec8f349c3b0858b89f88dde35e1ec12',
 'extensions/humanoid/skeleton/pelvis/contents.mojo': '43d95b7d5cfa1d784eeb36fdbf4916893b4283d6436417291deb6ffc1b89f10a',
 'extensions/humanoid/skeleton/pelvis/ligaments/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/pelvis/ligaments/dimensions.mojo': '07f981c8d999391e065f3bae371a6f89b4d29c6e1d061e75a7978e1b05908440',
 'extensions/humanoid/skeleton/pelvis/ligaments/geometry.mojo': 'a3de67d9e17fdf08f1dac600a86e10e2784679066b2b663bb402111cb2efe945',
 'extensions/humanoid/skeleton/pelvis/lower_body.mojo': '2fdd9e479823e2c35988e7321b6e723cbb367e854e410ba0423f80ce46d605eb',
 'extensions/humanoid/skeleton/pelvis/lymph/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/pelvis/lymph/dimensions.mojo': '70f1362e55c33f8ee148d7243c3678a18d798b8a2de9b4933aa4a90eb71678d0',
 'extensions/humanoid/skeleton/pelvis/lymph/geometry.mojo': '0adcc126f28e9ed4dc3043adeed75dc96e07fa1229d5a75010327c558a304c05',
 'extensions/humanoid/skeleton/pelvis/muscles/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/pelvis/muscles/dimensions.mojo': 'e0b25da2866e2ff54a9644e18b5c87c7cbe81d670bff0b2618d04e5ada054d50',
 'extensions/humanoid/skeleton/pelvis/muscles/geometry.mojo': '76422f29dea2b0ee59fa3de095a9a8bc488cf00b18107227d4ab5be064cb1535',
 'extensions/humanoid/skeleton/pelvis/nerves/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/pelvis/nerves/dimensions.mojo': '48e4f823a890ec63e6582774e803554389105476c58e03969abd64d8cd8b4211',
 'extensions/humanoid/skeleton/pelvis/nerves/geometry.mojo': 'c06bb0bd8c5f7042b584b96c230d9653dc0a1eec288e3ca1a09ae6de020b8f64',
 'extensions/humanoid/skeleton/pelvis/skin/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/pelvis/skin/dimensions.mojo': '0a41deec5cec4c2d5c8e938534df901a63aacf1cae2d0119523a019f3244751b',
 'extensions/humanoid/skeleton/pelvis/skin/geometry.mojo': '032066a91f40ecf521162aa1f98ca198baadcfc6fc59eb854f7a776cba63cdc0',
 'extensions/humanoid/skeleton/pelvis/vessels/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/pelvis/vessels/dimensions.mojo': 'e7fa736eccca74db021cbcd2a4dd816c4d72cd7b09661c38da6115eb0e1d347e',
 'extensions/humanoid/skeleton/pelvis/vessels/geometry.mojo': 'c6bc09e684ea9b75bf428e4df7e8159f096b422044f188f9e5a159f12662bdd7',
 'extensions/humanoid/skeleton/place.mojo': '5821df5eefffc821ee3a219620ebe44ba41f1cbd48ed6003ae4040a5fd180b6b',
 'extensions/humanoid/skeleton/sculpt.mojo': 'a345363e76110c3a7e962156ca2ef3395724667f0f41644586cb360e264dd365',
 'extensions/humanoid/skeleton/surface_nets.mojo': 'c41e146dca44bb7c2e9f05113a0e0d254b4257547e8c7930dc25d5ba8567c86e',
 'extensions/humanoid/skeleton/torso/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/torso/assembly.mojo': '1c82e6907e7c82478b0af19a45882340f34c5a1522814e2bfc5c4f8c38b5c4bd',
 'extensions/humanoid/skeleton/torso/body.mojo': '0658ea8977066bff64e7cfcb96711f1b88bb2debb7339abaaf22bed477a2d44d',
 'extensions/humanoid/skeleton/torso/bones/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/torso/bones/dimensions.mojo': '091efbf3f856a0d95ce1821316c448a240d8fd35fe811cf5f147d5e3a8333896',
 'extensions/humanoid/skeleton/torso/bones/geometry.mojo': 'd56c60e8875c95881311a1701f4b23e3e4036c1f0c60a566f7cc9175850f53db',
 'extensions/humanoid/skeleton/torso/contents.mojo': '6b7e25da899e5ef3c092216d4f7e40d57623fb38d2a51443ca4b7560ab9707d1',
 'extensions/humanoid/skeleton/torso/ligaments/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/torso/ligaments/dimensions.mojo': '1d3de688dd915e85bfdbd353799d950b4d4cb585e316ba118fed9fa209feb0e3',
 'extensions/humanoid/skeleton/torso/ligaments/geometry.mojo': '802c3a65993a5e85d2f374b0ea988d0f3dc406ffe8427b09a28fa0d35c034b45',
 'extensions/humanoid/skeleton/torso/lymph/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/torso/lymph/dimensions.mojo': '25495230d859a0df914d109ba132f9e8f2a919038525bc0a41808920e7c33b07',
 'extensions/humanoid/skeleton/torso/lymph/geometry.mojo': '1a4003f46bdc343725b982d49d4f3232593a2d9b3551be73c7ea7cd7316338a7',
 'extensions/humanoid/skeleton/torso/muscles/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/torso/muscles/dimensions.mojo': 'b37174a431e5afb705e0d820c8721d608e167ee2914cef8bdd5d4b1a8e725ec9',
 'extensions/humanoid/skeleton/torso/muscles/geometry.mojo': '5429ce4a2f1649d32781ad809371088f256f76dfc96c0b56f6c646ef6e9e9c9f',
 'extensions/humanoid/skeleton/torso/nerves/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/torso/nerves/dimensions.mojo': '5d54ea4d00a723cf51cf1e5e29cb259567c39715f503711c1e1e725df273dc33',
 'extensions/humanoid/skeleton/torso/nerves/geometry.mojo': 'bda5de30375bf8f3c74a18c7f48d611aefdebf627ae7f1d5477dc179a3b8f442',
 'extensions/humanoid/skeleton/torso/skin/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/torso/skin/dimensions.mojo': '33e3f30cdecfdc9ea615a984886ae01f8cd1aa0f4f86a4f0f5685581a088fd86',
 'extensions/humanoid/skeleton/torso/skin/geometry.mojo': '09148d5decdd93e67de2785afcb696f5333f817327f7d40765a3024205530654',
 'extensions/humanoid/skeleton/torso/sweep.mojo': '8ee430e8785effa1078ce22509580f60eb64c5c23e79c55145ba7cec2189891a',
 'extensions/humanoid/skeleton/torso/vessels/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/humanoid/skeleton/torso/vessels/dimensions.mojo': '444ffc36a5040f1edc66bc31bc8c79d94f6329f22bc0c7c21bae5b51b2991d70',
 'extensions/humanoid/skeleton/torso/vessels/geometry.mojo': 'ab01ddda0002f59e5bc7faa2a8800331720cd908fdf418b27be569765b7616cf',
 'extensions/humanoid/spec.mojo': '994d707324d994e1054b49bbb2181463727e7efb560ba66af9412ba1ec927224',
 'geometries/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'geometries/attribute_utils.mojo': '0a87276b9264a028a3220a667e39f8e96ff6fde7e41ed2c180e0aed7484ccda6',
 'geometries/surface.mojo': '8ff3246d240c90168470bde485496accca02d7096a53270c0d6ce442a4429e04',
 'geometries/utils.mojo': '459f32ecdd779c03d347b6c99f743a48a56028ab02b3f813181781eea3dcf548',
 'lights/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'lights/fresnel.mojo': '4c1a852d788c636603f75a3c459b6f43b0ec3a032d62b525c9fe9fc7cdfcada7',
 'lights/light.mojo': 'bc5654ee21e462cf9c86bc5eeffdd2ae7eaed91c3607a03312322e342d9108da',
 'lights/light_slot.mojo': '05dd9713ca0a410e23b8ffdae48a9f530cec9239efaa127f4fb43861ab129652',
 'lights/physical_layers.mojo': 'b97a85136309d66b1042de440bf4bc4571c64851b87fb2c4c4aa4fff1b17f649',
 'lights/shadow.mojo': 'e57aabcefe61cebaa8e57ae129f0cae3873215b7b1c0d2171c972d78d4015b81',
 'loaders/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'loaders/bytes.mojo': '5600d6d9ca117fc7c7c97a2e5d6a687adc8090627c34cf3181935245dae87c07',
 'loaders/js_text.mojo': '847797a811cd7ee54bdf833e1f6d3f8c2965e90e2491c71d04bf2488c6d2b971',
 'loaders/json.mojo': 'b6d44e6930f415f9b47eb7c48b26673a961746cff3a3125b8ac3f7ef9a1de417',
 'loaders/utf8.mojo': 'e0d5891d9d2954bd5c4329cda8a3492f4f6464b402b84489eae000cf8e0ce10a',
 'materials/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'materials/compute_ids.mojo': '215ccb1704fb7b30d8a0ad7ec14e839dc399f29f7c7ca29f0403f5c32e25a39e',
 'materials/material.mojo': '0722ad172e97c70cc530348a627eb52cde41c643cabef385423ee8ea6d8b77b9',
 'materials/nodes.mojo': '525920b0e48d73cd4329a51ed127e38c59972ebc48c8562c20ce2200b072c3ef',
 'math/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'math/arc_tangent.mojo': 'fde08cd180cb0e2bd94fca6196f86c4b318ef6f1a4ed8e588aaad848076ea8e5',
 'math/bezier.mojo': '4a4087e15d2472bcbeedd492c5a866039988cc1988029a5c28c828eedfb77034',
 'math/bounds.mojo': '712403832a9fc9bdcd835e68e1934dd4de37e8b218e418f797a717da3684ee25',
 'math/box_extent.mojo': 'd978c71d45c074acb0a6e36938b1f52f7b2bb6e822c95cf6b3ec4802223782c1',
 'math/catmull.mojo': 'd2584909e792fd6f503ea35b6e33fc0fcd801571b1260135ee6fb38df8c74ed2',
 'math/cross.mojo': '352f81c1fc781becc0cf88056ac39978b24926303e3784ff783bcabdf5bf67e5',
 'math/curve.mojo': '579839a0981c00cc9e188a0a57ff9f0c5822b09f3cd8ae6fa5b667d97d8ff5d9',
 'math/curve_checks.mojo': '9ad53ff5ed5a540a85ed4ed00860e8d9c1b537c67edda2a8d6f58b458ae5a8ef',
 'math/euler.mojo': '9645a80e2b0a7dcfeeb2fbf51a0030aab6b44f8603192b86aee533068dab7356',
 'math/finite.mojo': 'fc0bcbef9d5439f4ce6da4e10ac2c0a3a2a8022fb31f3426992408e25ac73f7b',
 'math/matrix3.mojo': 'b134fabd9dbf12f41c46724ccaa89582be5efbb929677a47c64af45c4d0a1e97',
 'math/matrix4.mojo': '206877d7335ed69e9055ec69b2ac09bd83b493456bfc43c1083ea235a1a44549',
 'math/matrix_determinant.mojo': 'c5b25179893fd2903dbda5de68914a50e662e3428107ef2c3424ef42cafcde19',
 'math/matrix_inverse.mojo': 'd833edd9d3705ba77e5000b75e6cd4852955e4d978bf0afdbc8efbafa61d42de',
 'math/norm.mojo': '941dbe97b3b6bc6d48af64a682f88970e12d387e8e896054cfc860d59eea9c3d',
 'math/path.mojo': 'e182834e6ecb1019ca882beeb2272053dfbbee263f4bfd45bcd35c5c53197f11',
 'math/polyline.mojo': 'c4ff928fc5278100da0df381e6ee79423ddd6ef7c3fc38dcfb11521ac73774c1',
 'math/quaternion.mojo': '2cf5b20029448204c1b984349e2e9e5f804ff7831d0506ab156ea7f88173c65d',
 'math/random.mojo': 'f8a00ee7d03897a7c35f2f23d157fb65ce2c2b3fde5e4c91f21e7a764fab1655',
 'math/ray.mojo': '5298756c8056364661902adb9a253b3c0e7d771641cc01e4781b85d3dc9a84a4',
 'math/ray_query.mojo': '48136d70da9f19e28fc30e1660416ba1c25bf8a545bafbbe16a904f8e26ff3eb',
 'math/remainder.mojo': 'b7575b2fde7a212433498422a121c66b12a85e7109614093bb783ad1cc043e58',
 'math/scaled_products.mojo': '8d16ee11a738e90a951943b786c1abcc7473286788392c447827240900ed16c5',
 'math/sine.mojo': '81580a510da8722ef96df0074937d139019234afc3f089584f534d6b556edcf9',
 'math/smoothstep.mojo': '1753a3342932f3c89eb5ebfb7f9ef5ee0a28530f447432b1bb179e3213ff8edb',
 'math/spherical_harmonics3.mojo': '2ca87fb3e0c23a5755e6c7d147a866d041d3bcef40ad3d35329a4dd559c5b8f4',
 'math/square_matrix.mojo': '04a9f011e814455c9d24a94c66df30b8137f7e9802a2a9b552b0d9bb05538c27',
 'math/triangle.mojo': 'f1facc4a319f3ee6614bc3c57896b82300826e0536640e73adc7d55573347f01',
 'math/triangle_normal.mojo': 'cdcf00131967b714f2518acd96fb28e874fa3006bfb52a242f3596c281e147bf',
 'math/utils.mojo': 'd32e99704324833af194084f0b1d646a894c63bdd0b8ce1baa0da8a287c1d690',
 'math/vector2.mojo': '2aa5cee2c09cfad3c3b2fa883db31efe47f82f30bac6565415ce6a9f18c8d125',
 'math/vector3.mojo': '39bd8f3d5102eb8d32f95fb0982b5886050c43031de416903d692e1c2c664b4a',
 'math/vector4.mojo': '44797637aae80c1e92c08592bc2a510e90e14e93d1c74bb4a01ca71034b10ee6',
 'objects/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'objects/clipping_group.mojo': 'abb69d042f7add2154e9efeb83df36a10788844803b57fc405c7092bdc8dc19e',
 'objects/gaussian_splat.mojo': '01fe94cc3159b21a70c104ea92a3631e57c217f19ad26f17bd2bd3ad3ff0f80f',
 'objects/instanced_mesh.mojo': '9992a151f9340c0211f5202594b6bec3d63e10940ae236e9ec0e4feafd888261',
 'objects/line.mojo': '3846559aebd946c4a5e73937fa488a14d2bdbfedf30102cb746456c86397ae27',
 'objects/line_segments2.mojo': 'fdff9f90123e0d3d8d3ca9b0aaf22e3b2c110c255d01a14927ce1fca8fa7d021',
 'objects/lod.mojo': '4829fbffecab2c13215a9918f30df7ea7c1471fb94d75b0a0815ccbbb1156899',
 'objects/mesh.mojo': '5e365168f48476146dc90c8bc9f3fec240be9c260b719925e7965e42d2de53b8',
 'objects/points.mojo': '42cdd945dc927e8bcf490824e9163188f50d8dcdd407970b7ccb234e9b91f737',
 'objects/skeleton.mojo': 'baff1a5346ae64d843d58802437e797c83686a5f11447684dd028febd0a98a5d',
 'objects/skinned_mesh.mojo': 'bf9a1d2aebf7c510a322d85e209f13e472f11bd4898c1c4ea5d507e5fde5a3fb',
 'objects/sprite.mojo': 'c257fd417a1394f9c4600e58e5994d3251b8f221efab993ab54b4458e869b225',
 'render/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'render/blend.mojo': '899f45b625a5c50af3960bf65042686ab4b6fb910e03cb142c9556847aedb271',
 'render/checksum.mojo': '796c60b76d945f7672c1595a06d86443224747cbddc07cdaf3fae90bdd3b4eff',
 'render/color_math.mojo': '37e57703f18f3ccd6c7f85ec4700ee2b2967e96b5451db2f7b3edf4be4d4d02b',
 'render/css_color.mojo': 'bcfa54778b83bf4056cbf15b7602f6a66e0a01c6778e87b75440fa667275e567',
 'render/cube_texture.mojo': '28c83baf52788ffb412328360ceef2397de1ec33489ee1516d447e3fc8d1f79c',
 'render/cube_texture_store.mojo': 'f052c06f7608058225486575e8584da3dda50ced69cf4834501360a73aebefde',
 'render/cube_uv.mojo': '8bd7e1dd5fb4eb131747759c7dfdb86f71ec2f77d4d99dd6735d924ae7756bbe',
 'render/float_image.mojo': '5554273bf9382d919b8cc8450ba406de99b220c4951f86e61721bc92c7aba357',
 'render/framebuffer.mojo': 'cc907b6c905ad936f68fca609a7ddcffcd2090977088170670c4b43bfa6ad6ef',
 'render/inflate.mojo': '7db92edc5ed721f4fb66a02195703fa4c7260607be732cb72070d33ac4d0c0a5',
 'render/linerule.mojo': '0d809e132f3019d04cef9734e9841dfbd0244aac738ed4d09bb40b9c45faf07e',
 'render/packing.mojo': 'e7b3b4158fb6992edad74bd0870b4509b79d6547785ec9285448b2467b98f083',
 'render/png.mojo': '75d9105e434ed286b207d55d27e90328a24a2ad9f4b8e6580f8de156256558c4',
 'render/raster_state.mojo': 'a8fc16d55ca53f4e36c333d99f3ce9eb110ea523aac33b90194c17a8f4fb1211',
 'render/srgb.mojo': '630ac4819cf3eb7bd546e8400ab8984452570110ee15db2898ae65cebae20b61',
 'render/tasks.mojo': 'efa65ccd751c3430f1fa875382748f6040733f802be4719b92ff239b510804d4',
 'render/texture.mojo': '3552ba623c9c6c8dd2ea0d7b6f4eb0aac924854086a0ddd9b90865e3f1978c15',
 'render/texture_buffer.mojo': 'a1977c2d14e15917b149280e4ae75a1c20e37a0b5939514d8daac50c3da7c7db',
 'render/texture_store.mojo': '78dfcc5c37879dd286272674096b13bad72efdefac769f85525790800f1fbd4b',
 'render/volume_texture.mojo': 'e599b4924490cdd8d828749ae4e25cea751f59bfa59198cd3350b5823bda52bf',
 'render/volume_texture_store.mojo': '105a32971b5e88c613ec3a350d9b2c99c27d19080c6c66fb9d42bd4be546c8b0',
 'tests/test_hair_density_bounds_controls.mojo': '2cfb0de9ac61d170beaa7e47fbcaf5c51c7db139ed373f4ab4f07af2fae9e11c',
 'tests/test_reconciled_hair_density.mojo': '2e0c703b365bc98d3d6fc4c8796d4133edf004eafb753262ca89cd6d639be3c4',
 'tools/carla_lane_oracle/pr760_arithmetic_stage.py': '03757bafb02fbb3908919839c18d5c2c443f46469aeb01393dee57ae22054359',
 'units/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'units/measure.mojo': 'b7531458ae7a74d6b9213f55672073137dbac41c2634787f7d6a78a16b526b85',
 'units/quantity.mojo': 'bb77541cdb757cd63b59ac01134c6a6ebce88863bee69c84ff77b8c03aff6223',
 'units/si.mojo': 'd149a23f2ee4a9bde17875615e7251285cb56af535716b66c7d8959c80f48c02'}
DENSITY760_RULES = (
    (131, 64, 262144, 'range(count)', 'density-validated-positive-cube-count'),
    (167, 1, None, 'range(len(groom))', 'density-partitioned-nonempty-groom'),
    (178, 1, None, 'range(samples)', 'density-checked-representable-positive-samples'),
    (245, 16, 256, 'range(self.resolution * 4)', 'density-query-validated-positive-step-count'),
)


def _density760_stage_identity(raw):
    """Reuse existing executing-code checks for the one pure inverse leaf."""
    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
    from carla_lane_oracle import pr760_arithmetic_stage as stage
    filename = Path(__file__).resolve().parent/'carla_lane_oracle/pr760_arithmetic_stage.py'
    cleanup.require(Path(stage.__file__).resolve() == filename,
                    'density inverse executing origin changed')
    compiled = compile(raw, str(filename), 'exec', dont_inherit=True, optimize=sys.flags.optimize)
    cleanup.require(cleanup._code_identity(stage._EXECUTED_MODULE_CODE)
                    == cleanup._code_identity(compiled), 'density inverse module code changed')
    defaults = cleanup._compiled_defaults(raw)
    for name, expected in cleanup._compiled_functions(raw, str(filename)).items():
        if name.startswith('<'):
            continue
        live = getattr(stage, name, None)
        actual = cleanup._live_function_code(live)
        cleanup.require(actual is not None and cleanup._code_identity(actual)
                        == cleanup._code_identity(expected), 'density inverse function changed: ' + name)
        cleanup._check_defaults(live, defaults.get(name), name)
    stage.verify_stage_data()


def density760_loops(root, *, include_roots=(), _operation=None):
    """Admit only four local validated density rows on one physical image."""
    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
    from carla_lane_oracle import pr760_arithmetic_stage as stage
    operation_args = {} if _operation is None else {'_operation': _operation}
    if _operation is not None:
        cleanup._operation_include_context(_operation, root, include_roots)
    try:
        # Historical and unknown endpoints keep their existing independent paths.
        raw = _coverage_observe_bytes(root, DENSITY_SOURCE,
            relative_source(root, DENSITY_SOURCE, **operation_args).read_bytes(),
            _operation=_operation)
        if sha256(raw) != DENSITY760_INPUTS[DENSITY_SOURCE]:
            return {}
        executing = cleanup.executing_checker_bindings()
        snapshots = {}
        for name, expected in DENSITY760_INPUTS.items():
            value = _coverage_observe_bytes(root, name,
                relative_source(root, name, **operation_args).read_bytes(), _operation=_operation)
            if sha256(value) != expected:
                return {}
            snapshots[name] = value
        leaf = 'tools/carla_lane_oracle/pr760_arithmetic_stage.py'
        _density760_stage_identity(snapshots[leaf])
        groom = 'extensions/humanoid/skeleton/head/hair/groom.mojo'
        if sha256(stage.predecessor_source(DENSITY_SOURCE, snapshots[DENSITY_SOURCE].decode()).encode()) != DENSITY_AFTER_SHA256:
            return {}
        if sha256(stage.predecessor_source(groom, snapshots[groom].decode()).encode()) != GUARDED_LOOP_SOURCE_SHA256[groom]:
            return {}
        paths = {name for name in snapshots if name.endswith('.mojo')}
        entries, source_image = cleanup._helper_entry_census(root, **operation_args)
        contexts = [(root, entries, source_image)]
        for location in include_roots:
            extra_entries, extra_image = cleanup._include_entry_context(
                location, source_image, **operation_args)
            contexts.append((location, extra_entries, extra_image))
        native_tests = {'tests/test_reconciled_hair_density.mojo',
                        'tests/test_hair_density_bounds_controls.mojo'}
        closure = cleanup.dependency_inventory(root, roots=(DENSITY_SOURCE, groom),
            entries=entries, _known=set(source_image), _snapshots=dict(source_image))
        if closure != paths - native_tests:
            return {}
        def resolver_ok():
            # Source coordinates never allow origin sidecars, even when the
            # same root is also listed as an include. Include-only sidecars
            # correspond to observed staged Mojo coordinates; the generation
            # owner authenticates their exact set and bytes before dispatch.
            return all(cleanup.resolver_unshadowed(location,
                paths if index == 0 else paths | {
                    name + '.cov-origin' for name in paths if name in image},
                **cleanup._render_lookup_args(paths, local_entries),
                math_entries=frozenset(('.', *local_entries)))
                for index, (location, local_entries, image) in enumerate(contexts))
        if not resolver_ok():
            return {}
        for name, value in snapshots.items():
            if _coverage_observe_bytes(root, name,
                    relative_source(root, name, **operation_args).read_bytes(), _operation=_operation) != value:
                return {}
        _density760_stage_identity(snapshots[leaf])
        for location, _, image in contexts:
            cleanup._helper_entry_census_finish(location, image, **operation_args)
        if cleanup.executing_checker_bindings() != executing or not resolver_ok():
            return {}
        return {line: {
            'line': line, 'kind': 'reviewed-nonempty-range', 'cardinality': 1,
            'minimum_cardinality': minimum, 'maximum_cardinality': maximum,
            'required': 'T', 'impossible': 'F', 'expression': expression,
            'proof_id': proof_id, 'dependency_sha256': dict(DENSITY760_INPUTS),
        } for line, minimum, maximum, expression, proof_id in DENSITY760_RULES}
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, AttributeError) as error:
        if _operation is not None:
            cleanup._operation_fail(_operation, error)
        return {}


# Separate producer theorem: every Float32 radius passes through the pinned
# min/max graph in cap_steps, yielding Int 2..64 under the bound Mojo SDK.
# The consumer adds one without overflow and never changes steps. Thus its
# range(1, steps + 1) is nonempty for every possible private caller input.
# Unlike an input-guard theorem, this needs no restricted caller census.
# Bind the complete producer/consumer and maintained exceptional-value control;
# fail closed on source changes or local/staged stdlib shadows. The receipt
# separately binds the exact compiler/SDK and still requires a runtime True hit.
# The #298 placed-corner successor changes the cap consumer, not this count
# theorem: its sole steps assignment still calls the same cap_steps expression,
# and range(1, steps + 1) never reassigns steps. Earlier work can raise, but a
# reached loop is nonempty. Bind each complete reviewed endpoint separately;
# new consumer branches remain counted and runtime True is still required.
STRAND_CAP_SOURCES = {
    'objects/__init__.mojo':
        '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
    'renderers/__init__.mojo':
        '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
    'renderers/renderer.mojo':
        'ad8d3a26292683ba744d20fa05f13491e31019540774002809bfad8ba3ae6bf5',
    'objects/line_segments2.mojo':
        '5680f188d71c88465be6f7d8173858221a57525663fb4c75d95721fcc2658e79',
    'tests/test_small_loop_witnesses.mojo':
        '8f768e04ecaebdb132cf359819be03cb039d5a546b823674c22ac06a1b790362',
}


STRAND_CAP_RENDERER_ENDPOINTS = {
    'ad8d3a26292683ba744d20fa05f13491e31019540774002809bfad8ba3ae6bf5': 3757,
    '08ce4d257874c1107305cc1abf45ec4ebd89a9b183902974085d507974410c45': 3886,
}


# Review the producer and consumer as one pair; old/new mixtures are unknown.
STRAND_CAP_PAIRED_SUCCESSOR = ({
    **STRAND_CAP_SOURCES,
    'renderers/renderer.mojo':
        '2491b99a982cd4bc49b3573d3c6db8313bfdd47372e693e932c03c27d0ff127d',
    'objects/line_segments2.mojo':
        'fdff9f90123e0d3d8d3ca9b0aaf22e3b2c110c255d01a14927ce1fca8fa7d021',
}, 4047)


# The Camera-order repair leaves the complete cap function and producer intact.
# Preserve the first PR760 pair as a separately accepted historical endpoint.
STRAND_CAP_CAMERA_ORDER_SUCCESSOR = ({
    **STRAND_CAP_PAIRED_SUCCESSOR[0],
    'renderers/renderer.mojo':
        'df552b5bc14d6cc5a0ef4cf919afaf66da620f431b0d4f5bb9c3a61538cb2b84',
}, 4047)


# Formatting only: generic Camera signature gains two physical lines.
STRAND_CAP_FORMATTED_SUCCESSOR = ({
    **STRAND_CAP_CAMERA_ORDER_SUCCESSOR[0],
    'renderers/renderer.mojo':
        '5cc066092d9b0302c60a6676459efc855e220dc319d1f88b5eb84df768f489f9',
}, 4049)


def _strand_cap_resolver_unshadowed(root):
    """Refuse alternate packages/modules at the producer's resolver surfaces."""
    root = Path(root)
    allowed = {'objects', 'renderers', 'objects/line_segments2.mojo',
               'objects/line_segments2.mojo.cov-origin'}

    def unreadable(error):
        raise error

    try:
        for directory, folders, files in os.walk(root, onerror=unreadable):
            base = Path(directory)
            folders[:] = [name for name in folders
                          if name not in cache_key.SKIP
                          and (base / name).relative_to(root) != Path('coverage/build')]
            for name in (*folders, *files):
                path = base / name
                relative = path.relative_to(root).as_posix()
                if path.is_symlink():
                    return False
                folded = name.casefold()
                if (base.relative_to(root).as_posix() in {'objects', 'renderers'}
                        and folded.startswith('__init__.')
                        and name not in {'__init__.mojo', '__init__.mojo.cov-origin'}):
                    return False
                if any(folded == stem or folded.startswith(stem + '.')
                       for stem in ('objects', 'renderers', 'line_segments2')):
                    if relative not in allowed:
                        return False
    except (OSError, ValueError):
        return False
    return True


def strand_cap_loops(root, *, include_roots=(), _operation=None):
    """Bind the nonempty strand-cap loop without suppressing its True edge."""
    operation_args = {} if _operation is None else {'_operation': _operation}
    stream_args = {} if _operation is None else {'_operation': _operation, '_root': root}
    if _operation is not None:
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
        cleanup._operation_include_context(_operation, root, include_roots)
    try:
        actual = {name: file_sha256(relative_source(root, name, **operation_args),
                                   **stream_args)
                  for name in STRAND_CAP_SOURCES}
        renderer = 'renderers/renderer.mojo'
        line = STRAND_CAP_RENDERER_ENDPOINTS.get(actual[renderer])
        expected = {**STRAND_CAP_SOURCES, renderer: actual[renderer]}
        if actual == STRAND_CAP_FORMATTED_SUCCESSOR[0]:
            line = STRAND_CAP_FORMATTED_SUCCESSOR[1]
        elif actual == STRAND_CAP_CAMERA_ORDER_SUCCESSOR[0]:
            line = STRAND_CAP_CAMERA_ORDER_SUCCESSOR[1]
        elif actual == STRAND_CAP_PAIRED_SUCCESSOR[0]:
            line = STRAND_CAP_PAIRED_SUCCESSOR[1]
        elif line is None or actual != expected:
            return {}
        if not all(
                _density_stdlib_unshadowed(path)
                and _strand_cap_resolver_unshadowed(path)
                for path in (root, *include_roots)):
            return {}
    except (OSError, ValueError):
        return {}
    return {line: {
        'line': line, 'kind': 'reviewed-nonempty-range', 'cardinality': 1,
        'minimum_cardinality': 2, 'maximum_cardinality': 64,
        'required': 'T', 'impossible': 'F',
        'expression': 'range(1, steps + 1)',
        'proof_id': 'strand-cap-bounded-count-2-to-64',
        'dependency_sha256': actual,
    }}


# These are the same five retained theorems on the exact cleanup endpoint.
# No new loop outcome is waived. The full source edge binds the loop body.
_CLEANUP_LOOP_ROWS = {
    ('extensions/carla/lane_refinement', 145): (146, '_axis_lane_minimum'),
    ('extensions/carla/lane_refinement', 726): (736, '_lane_certificate_dominates_cells'),
    ('extensions/carla/lane_refinement', 1289): (1299, '_continue_lane_certificate'),
    ('extensions/carla/lane_refinement', 1314): (1324, '_continue_lane_certificate'),
    ('extensions/carla/junction_bounds', 706): (706, '_lane_section_box_with_work'),
}


def _cleanup_current_bindings(root, *, include_roots=(), _operation=None):
    """Bind current cleanup dependencies of a transitive historical Map edge."""
    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
    operation_args = {} if _operation is None else {'_operation': _operation}
    stream_args = {} if _operation is None else {'_operation': _operation, '_root': root}
    cleanup._operation_check(_operation, root)
    cleanup._operation_include_context(_operation, root, include_roots)
    for name in cleanup.SOURCE_PATHS:
        path = relative_source(root, name, **operation_args)
        if file_sha256(path, **stream_args) != cleanup.BEFORE_SHA256[name]:
            # A partial/mixed/unknown current view cannot produce a receipt.
            return cleanup.proof_bindings(root, include_roots=include_roots, **operation_args)
    return {}


def _cleanup_loop_row(root, module, historical_line, expression):
    """Confirm the mapped loop expression and its exact top-level owner."""
    item = _CLEANUP_LOOP_ROWS.get((module, historical_line))
    if item is None:
        return None
    line, expected_owner = item
    statements = _statements(relative_source(root, module + '.mojo').read_text())
    if statements is None:
        return None
    owner = None
    for statement in statements:
        words = [token.string for token in statement]
        if statement[0].start[1] == 0:
            owner = words[1] if len(words) > 1 and words[0] == 'def' else None
        if statement[0].start[0] == line:
            if (owner != expected_owner or len(words) < 5 or words[0] != 'for'
                    or words[2] != 'in' or words[-1] != ':'):
                return None
            expected = _statements('for value in ' + expression + ':\n    pass\n')
            if expected is None or words[3:-1] != [token.string for token in expected[0]][3:-1]:
                return None
            return line
    return None


def _coverage_observe_bytes(root, name, value, *, _operation=None):
    if _operation is None:
        return value
    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
    return cleanup._observe_bytes(root, name, value, _operation=_operation)


def _coverage_observe_text(root, name, value, *, _operation=None):
    if _operation is None:
        return value
    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
    return cleanup._observe_text(root, name, value, _operation=_operation)


def _reviewed_dependency_hashes(root, bindings, *, include_roots=(), _operation=None):
    """Verify fixed historical bindings without admitting arbitrary successors."""
    operation_args = {} if _operation is None else {'_operation': _operation}
    if _operation is not None:
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
        cleanup._operation_check(_operation, root)
        cleanup._operation_include_context(_operation, root, include_roots)
    # A partial producer may contain a local reviewed theorem without its
    # unrelated sibling prerequisites. Absence is established by the frozen
    # producer census before any read; consumed or current admission failures
    # are never downgraded to a missing proof.
    if (_operation is not None and _operation._kind == 'generated_receipt'
            and _operation._state == 'pending'
            and not bindings.keys() <= _operation._receipt_source_digests.keys()):
        from carla_lane_oracle import typed_boundary_contracts as typed
        try:
            typed.verify_authority()
        except (ValueError, TypeError, KeyError, AttributeError) as error:
            cleanup._operation_fail(_operation, error)
        captured = _operation._receipt_source_digests
        # Exact current and intermediate successor endpoints keep their
        # existing admission path. Only historical bytes (or the explicitly
        # paired density repair) can make an absent sibling inapplicable.
        current = any(name in typed.EDGES and captured.get(name) == typed.EDGES[name]['after_sha256']
                      for name in bindings)
        historical = all(captured[name] == expected or (
            name == DENSITY_SOURCE and expected == DENSITY_BEFORE_SHA256
            and captured[name] == DENSITY_AFTER_SHA256)
            for name, expected in bindings.items() if name in captured)
        if not current and historical:
            return None
    actual = {}
    for name, expected in bindings.items():
        path = relative_source(root, name, **operation_args)
        raw = path.read_bytes()
        if _operation is not None:
            cleanup._observe_bytes(root, name, raw, _operation=_operation)
        digest = sha256(raw)
        physical_digest = digest
        from carla_lane_oracle import typed_boundary_contracts as typed
        if typed.is_current(name, raw):
            from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
            current_bindings = cleanup.proof_bindings(
                root, include_roots=include_roots, **operation_args)
            if (current_bindings.get(name) != physical_digest
                    or _coverage_observe_bytes(root, name, path.read_bytes(),
                        _operation=_operation) != raw):
                return None
            actual.update(current_bindings)
            # The current numerical/API graph was physically admitted above.
            # This exact inverse now supplies historical provenance only.
            checked = typed.historical_source(name, raw.decode('utf-8'))
            digest = sha256(checked.encode('utf-8'))
        if (name == DENSITY_SOURCE and expected == DENSITY_BEFORE_SHA256
                and digest == DENSITY_AFTER_SHA256):
            # Explicit paired admission for the four re-reviewed hair rows.
            if not all(_density_stdlib_unshadowed(path)
                       for path in (root, *include_roots)):
                return None
            actual[name] = physical_digest
            continue
        if digest != expected:
            from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
            if (name in cleanup.shared_helpers.SOURCE_PATHS
                    and expected == cleanup.shared_helpers.BEFORE_SHA256[name]
                    and digest == cleanup.shared_helpers.AFTER_SHA256[name]):
                # This local theorem keeps its original premise scope. The
                # exact inverse and actual provider prove the same arithmetic;
                # the complete Map proof separately binds its native test image.
                executing = cleanup.executing_checker_bindings()
                helper = cleanup.shared_helpers
                leaf = 'tools/carla_lane_oracle/shared_helper_contracts.py'
                leaf_raw = _coverage_observe_bytes(root, leaf,
                    relative_source(root, leaf, **operation_args).read_bytes(),
                    _operation=_operation)
                if sha256(leaf_raw) != executing[leaf]:
                    return None
                texts = {name: raw.decode('utf-8')}
                providers = {}
                provider_raw = {}
                for provider in helper.PROVIDER_PATHS[name]:
                    value = _coverage_observe_bytes(root, provider,
                        relative_source(root, provider, **operation_args).read_bytes(),
                        _operation=_operation)
                    provider_raw[provider] = value
                    providers[provider] = sha256(value)
                    texts[provider] = value.decode('utf-8')
                if helper.verify_correspondence(texts) != (name,):
                    return None
                for package, expected_package in helper.package_inputs((name, *providers)).items():
                    value = _coverage_observe_bytes(root, package,
                        relative_source(root, package, **operation_args).read_bytes(),
                        _operation=_operation)
                    if sha256(value) != expected_package:
                        return None
                    provider_raw[package] = value
                    providers[package] = expected_package
                resolver_paths = {name, *providers}
                if not all(cleanup.resolver_unshadowed(location, resolver_paths)
                           for location in (root, *include_roots)):
                    return None
                for provider, value in provider_raw.items():
                    if _coverage_observe_bytes(root, provider,
                            relative_source(root, provider, **operation_args).read_bytes(),
                            _operation=_operation) != value:
                        return None
                if _coverage_observe_bytes(root, name, path.read_bytes(),
                                           _operation=_operation) != raw:
                    return None
                if (_coverage_observe_bytes(root, leaf,
                        relative_source(root, leaf, **operation_args).read_bytes(),
                        _operation=_operation) != leaf_raw
                        or cleanup.executing_checker_bindings() != executing
                        or not all(cleanup.resolver_unshadowed(location, resolver_paths)
                                   for location in (root, *include_roots))):
                    return None
                actual.update(providers)
                actual[leaf] = executing[leaf]
                actual[name] = physical_digest
                continue
            if (name in cleanup.SOURCE_PATHS
                    and expected == cleanup.BEFORE_SHA256[name]
                    and digest == cleanup.AFTER_SHA256[name]):
                actual.update(cleanup.proof_bindings(
                    root, include_roots=include_roots, **operation_args))
                if _coverage_observe_bytes(root, name, path.read_bytes(),
                                           _operation=_operation) != raw:
                    return None
                actual[name] = physical_digest
                continue
            if (name != 'extensions/carla/map.mojo'
                    or expected != GUARDED_LOOP_SOURCE_SHA256[name]):
                return None
            from carla_lane_oracle import seed_count_contracts as seed_count
            if digest not in {seed_count.AFTER_SHA256, seed_count.OPTIONAL_AFTER_SHA256,
                                      seed_count.SUPPORT_AFTER_SHA256,
                                      seed_count.FRONTIER_AFTER_SHA256,
                                      seed_count.SCORE_AFTER_SHA256, seed_count.station.AFTER_SHA256,
                                      seed_count.deviation.AFTER_SHA256}:
                return None
            predecessor = seed_count.historical_source(root, **operation_args).encode('utf-8')
            if sha256(predecessor) != expected or _coverage_observe_bytes(
                    root, name, path.read_bytes(), _operation=_operation) != raw:
                return None
            if digest in {seed_count.station.AFTER_SHA256, seed_count.deviation.AFTER_SHA256}:
                actual.update(cleanup.station_proof_bindings(root, **operation_args))
            actual.update(_cleanup_current_bindings(root, include_roots=include_roots, **operation_args))
        actual[name] = physical_digest
    return actual


def _final_unowned_typed_loop_bindings(root, bindings, *, include_roots=()):
    """Fresh final topology/caller admission after current lexical transport.

    This helper is only for unowned standalone rows. Map/R-tree retain their
    existing owning operation and sticky finalization; no kind is broadened.
    """
    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
    fresh = cleanup.proof_bindings(root, include_roots=include_roots)
    if any(bindings.get(name) != digest for name,digest in fresh.items()):
        return False
    return all(sha256(relative_source(root,name).read_bytes()) == digest
               for name,digest in bindings.items())


def _historical_reviewed_nonempty_loops(root, module, *, include_roots=(), _operation=None):
    """Return only named source-reviewed nonempty iterator proofs.

    A mismatch retains both outcomes. Constants require a new source review;
    they are never derived from the current files or automatically refreshed.
    """
    operation_args = {} if _operation is None else {'_operation': _operation}
    if _operation is not None:
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
        cleanup._operation_check(_operation, root)
        cleanup._operation_include_context(_operation, root, include_roots)
    rule = REVIEWED_LOOP_RULES.get(module)
    if rule is None:
        return {}
    bindings, sites = rule
    try:
        if module == 'extensions/humanoid/skeleton/head/hair/strands':
            name = module + '.mojo'
            raw = _coverage_observe_bytes(root, name,
                relative_source(root, name, **operation_args).read_bytes(),
                _operation=_operation)
            if sha256(raw) == HAIR_LITERAL_SUCCESSOR[0][name]:
                bindings, sites = HAIR_LITERAL_SUCCESSOR
                if not all(_density_stdlib_unshadowed(path, **operation_args)
                           for path in (root, *include_roots)):
                    return {}
        if module == 'extensions/carla/rtree':
            # Fail closed on any newly introduced private frontier caller.
            # This is a fixed census, not inference about arbitrary callers.
            paths = cache_key.input_paths(Path(root))
            if _operation is not None:
                paths = tuple(paths)
                cleanup._operation_known_paths(root, frozenset(
                    path.as_posix() for path in paths if path.suffix == '.mojo'),
                    _operation=_operation)
            callers = {
                path.as_posix() for path in paths
                if path.suffix == '.mojo'
                and re.search(r'\b_nearest_(?:begin|next)\b',
                              _coverage_observe_text(root, path.as_posix(),
                                  relative_source(root, path.as_posix(), **operation_args).read_text(),
                                  _operation=_operation))
            }
            if callers != set(bindings):
                return {}
        actual = _reviewed_dependency_hashes(root, bindings, include_roots=include_roots, **operation_args)
        if actual is None:
            return {}
    except (OSError, ValueError, ImportError) as error:
        if _operation is not None and isinstance(error, (OSError, UnicodeError)):
            cleanup._operation_fail(_operation, error)
        return {}
    try:
        result = {}
        from carla_lane_oracle import typed_boundary_contracts as typed
        name = module + '.mojo'
        current = _coverage_observe_text(root, name,
            relative_source(root, name, **operation_args).read_text(), _operation=_operation)
        if sha256(current.encode('utf-8')) != actual[name]:
            return {}
        for line, kind, minimum, maximum, expression, proof_id in sites:
            if typed.is_current(name, current):
                line = _typed_loop_row(module, line, expression, current)
                if line is None:
                    return {}
            result[line] = {
                'line': line, 'kind': kind, 'cardinality': minimum,
                'maximum_cardinality': maximum, 'required': 'T', 'impossible': 'F',
                'expression': expression, 'proof_id': proof_id,
                'dependency_sha256': actual,
            }
        if (typed.is_current(name, current) and _operation is None
                and not _final_unowned_typed_loop_bindings(
                    root, actual, include_roots=include_roots)):
            return {}
        return result
    except (OSError, ValueError, ImportError, UnicodeError) as error:
        if _operation is not None and isinstance(error, (OSError, UnicodeError)):
            cleanup._operation_fail(_operation, error)
        return {}


def guarded_loop_proof(root, rule, *, include_roots=(), _operation=None):
    """Verify one explicit theorem without enabling its sibling rules."""
    operation_args = {} if _operation is None else {'_operation': _operation}
    if _operation is not None:
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
        cleanup._operation_check(_operation, root)
        cleanup._operation_include_context(_operation, root, include_roots)
    module, line, kind, maximum, expression, proof_id, extras, callers = rule
    bindings = {
        name: GUARDED_LOOP_SOURCE_SHA256[name]
        for name in (module + '.mojo', *extras)
    }
    try:
        actual_bindings = _reviewed_dependency_hashes(root, bindings, include_roots=include_roots, **operation_args)
        if actual_bindings is None:
            return None
        from carla_lane_oracle import typed_boundary_contracts as typed
        module_path = module + '.mojo'
        current = _coverage_observe_text(root, module_path,
            relative_source(root, module_path, **operation_args).read_text(),
            _operation=_operation)
        if sha256(current.encode('utf-8')) != actual_bindings[module_path]:
            return None
        typed_current = typed.is_current(module_path, current)
        if typed_current:
            line = _typed_loop_row(module, line, expression, current)
            if line is None:
                return None
        if (not typed_current and module == 'extensions/carla/map'
                and actual_bindings[module + '.mojo'] != bindings[module + '.mojo']):
            from carla_lane_oracle import seed_count_contracts as seed_count
            mapping = {
                seed_count.AFTER_SHA256: _MAP_SUCCESSOR_LINES,
                seed_count.OPTIONAL_AFTER_SHA256: _MAP_OPTIONAL_SUCCESSOR_LINES,
                seed_count.SUPPORT_AFTER_SHA256: _MAP_SUPPORT_SUCCESSOR_LINES,
                seed_count.FRONTIER_AFTER_SHA256: _MAP_FRONTIER_SUCCESSOR_LINES,
                seed_count.SCORE_AFTER_SHA256: _MAP_SCORE_SUCCESSOR_LINES,
                seed_count.station.AFTER_SHA256: _MAP_STATION_SUCCESSOR_LINES,
                seed_count.deviation.AFTER_SHA256: _MAP_DEVIATION_SUCCESSOR_LINES,
            }[actual_bindings[module + '.mojo']]
            line = mapping.get(line)
            if line is None:
                return None
        if (module + '.mojo' == DENSITY_SOURCE
                and actual_bindings[DENSITY_SOURCE] == DENSITY_AFTER_SHA256):
            line = _DENSITY_SUCCESSOR_LINES.get(line)
            if line is None:
                return None
        if (not typed_current and (module, line) in _CLEANUP_LOOP_ROWS
                and actual_bindings[module + '.mojo'] != bindings[module + '.mojo']):
            line = _cleanup_loop_row(root, module, line, expression)
            if line is None:
                return None
        if callers:
            # A private helper's local precondition is backed by the complete
            # maintained caller census. New calls or aliases fail closed.
            pattern = r'\b(?:' + '|'.join(re.escape(name) for name in callers) + r')\b'
            paths = tuple(cache_key.input_paths(Path(root)))
            if _operation is not None:
                cleanup._operation_known_paths(root, frozenset(
                    path.as_posix() for path in paths if path.suffix == '.mojo'),
                    _operation=_operation)
            actual = {
                path.as_posix() for path in paths
                if path.suffix == '.mojo'
                and re.search(pattern, _coverage_observe_text(root, path.as_posix(),
                    relative_source(root, path.as_posix(), **operation_args).read_text(),
                    _operation=_operation))
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
                # Only an exact local upload identity can exclude a collision.
                actual = {
                    path.as_posix() for path in cache_key.input_paths(Path(root))
                    if path.suffix == '.mojo'
                    and _hair_census_reference(names,
                                  relative_source(root, path.as_posix()).read_text())
                }
                if actual != set(expected):
                    return None
        if (typed_current and _operation is None
                and not _final_unowned_typed_loop_bindings(
                    root, actual_bindings, include_roots=include_roots)):
            return None
    except (OSError, ValueError, ImportError) as error:
        if _operation is not None and isinstance(error, (OSError, UnicodeError)):
            cleanup._operation_fail(_operation, error)
        return None
    cardinality = maximum if kind in {'literal-range', 'literal-list'} else 1
    return {
        'line': line, 'kind': kind, 'cardinality': cardinality,
        'maximum_cardinality': maximum, 'required': 'T', 'impossible': 'F',
        'expression': expression, 'proof_id': proof_id,
        'dependency_sha256': actual_bindings,
    }


# Independently reviewed final-only construction theorem. Successful same-owner
# _build_transform calls dominate all three Map._add_segment calls. Concrete
# Road.lane_transform rejects geometry_at < 0; info_index(empty) returns -1.
# Road._lane_record_boundaries appends each geometry to a fresh owned List
# unconditionally, and the consumer never mutates it. Thus 4055 retains T and
# cannot take the zero-iteration F edge. No numeric/ordering premise is used.
# Complete reviewed imports/types, guards, callers and list lifetime are pinned;
# this does not change or project any earlier proof envelope.
CONSTRUCTION_BOUNDARY_SOURCE_SHA256 = {'extensions/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'extensions/carla/__init__.mojo': '13bda95e7b80d111a65052af5508e95af88c7a17871fcf33f3eaf5dc75fd1a2d',
 'extensions/carla/curve_bounds.mojo': 'a57a5fa078fc6f36389a0abdce1eaa483a1cb7b7325688689a5602e8680ca3fb',
 'extensions/carla/curve_distance.mojo': '46176387129dd37a5887f3aeec7c96bbb386e4980063cb96f09619832cb09a79',
 'extensions/carla/curve_frozen_arc.mojo': 'fe4a9b4bca0cd23dc2a128fbcb9ff3b4604a870dc0b2b4ff4f8deeb766d2db50',
 'extensions/carla/curve_interval.mojo': 'ff6bf0d35b357047c609ea7cb6dbcbe535446cf4e315d9eac5f6c341ddbf1040',
 'extensions/carla/curve_minimizer_support.mojo': 'bdf79d12f2b3b784574fbd95e2e773ddeb29eb9586cf826c2b6142646341292e',
 'extensions/carla/curve_rounded_arc.mojo': '7bc84049fed26cb7b14b4fa4603ee36d55cdeb7055c62df50cf10d6a2ce90745',
 'extensions/carla/curve_rounded_line.mojo': '6741ad9d7434c08070de3c959cb49ac42939ac633d1dcd48c9f5cdfdaa719aed',
 'extensions/carla/curve_sample_dispatch.mojo': '91ede65bbc39ac57ca54239513b462d3c71e90cacd085b8bafb2bff514767a86',
 'extensions/carla/curve_sum2.mojo': '2f732d49a891c9b603ccf05fb74779ea79422d74b4c33723ffe40f99e6c54a67',
 'extensions/carla/curve_trig.mojo': '3715caa64a81433a615f82e1eea4aa50e6e719e7450316fccc9d318f6994c909',
 'extensions/carla/geo.mojo': '2b09610f1933d26281a7e018a1474bcb4a59daa63e01ef24528f342cc834a8a5',
 'extensions/carla/geometry.mojo': 'eb55cc639bb840e2cef06cdb6ad5b76a5b2af880c74813590585ec180092a45c',
 'extensions/carla/lane_box_cover.mojo': '1ed9978fb4ef7eef3a45c7503dbf5cced03ab1917f6fbf721c785e5a63cce251',
 'extensions/carla/lane_distance.mojo': '9d0aacab9fccb0a34f8d5c3a5edca1a1fd7ebcded961fc579ec6a44f3880497d',
 'extensions/carla/lane_geometry.mojo': '8e0917249d8c41233bcb801fac6455d614ed46a7fd8e7505c14259c2a5c81d91',
 'extensions/carla/lane_refinement.mojo': 'd6bb8cb266fa350491f71e92295e70bcbfc2566b34db02400b3a6cb5bb5a93ad',
 'extensions/carla/lane_value_bounds.mojo': '08978a7aa665aca4b82d41e1ff8b99451c647c0f8e7d6ee010fc6a6143f7959c',
 'extensions/carla/map.mojo': '37dcfb47476001ba8633a2c9dbb78b2d5f83bc069a0c4551d32ca6fdbb4c60bf',
 'extensions/carla/map_search.mojo': '53c5a1369203b2f57c915f4cacfe2935360bd6f4a676934f1a5dc67df69956a3',
 'extensions/carla/map_validation.mojo': 'c8457abae67e989ae6de1131e3d30c8f101a0ae6fee9ec4f0afabc0f67be7bef',
 'extensions/carla/math.mojo': 'e02aa0a1d41c17403120ebe1bd4672c2d5a41bb81aac66f1abb7e9a1cb42d147',
 'extensions/carla/polynomial.mojo': 'ccbb296800e9b493b0617506b05e51d7ed6ee8ea594b9460bb6c7ff359a0d354',
 'extensions/carla/road.mojo': 'd9b6f60ae0b0b2fe38ef8dbe797a759f3de5e72dc8fb97bff15ca5dfff251db0',
 'extensions/carla/road_info.mojo': '60460851e8884dd89271357a07fa8e127979d68a43c7f4e5962907d1634e12cb',
 'extensions/carla/rtree.mojo': 'be63ea929c25e0a55600d19568e5f8a117e2f712850ea3da0d977c39b002d460',
 'extensions/carla/speed_limits.mojo': '1e95ebc085e03a44e4daaef20a94b724dedc4240a2099227e82be54d32b045f6',
 'extensions/carla/spiral_domain_proof.mojo': '89a8760eee14ff17c682ac69657eb62391e5dfd7e6e1e11fa8a931f8595e9252',
 'extensions/carla/spiral_grouped_lane.mojo': '5da09d64a7e3c44139ddc59d0a636ff124470a48834fc81bb05c677c7147694b',
 'extensions/carla/spiral_grouped_roundoff_proof.mojo': 'ab0016a54e8a0d2d2dc8235e5954c111f1738ce08868d1c6fc30d454811d7a57',
 'extensions/carla/spiral_moment_proof.mojo': 'f42f436b6e616e39bc2cda70491abf2e441aa40d5d8d1aa7f7ecffe3d0b0d5ac',
 'extensions/carla/spiral_moment_table.mojo': '1c5a3a21216eaecb42b3947ccb5ec0479d8a120c714d79ebe25f11da5f1096c8',
 'extensions/carla/spiral_moment_table_data.mojo': '63b07b8aa1567ad3e1c8b09a71e5619073e5255b4dc6f733d4ef6bf6b7088c8c',
 'extensions/carla/spiral_roundoff_proof.mojo': '66903c0cfba3315c46e8f48c9af0b3c118db4194236a7e4fe3e893a986c90b0c',
 'extensions/carla/transform.mojo': 'c74c11819f95870d45cf37e7aa013fd72bc9673a4088c3e657efaa6b22999e56',
 'loaders/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'loaders/js_number.mojo': '286770b03443ffd560185d6b543a50d9938d5cf6d548cf615b6ebe41d1ef5101',
 'loaders/xml.mojo': '560daaf80b836fe72069a3100747c38096674219980662d3587e72ed2a480458',
 'math/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'math/bounds.mojo': '1078b7303170bc239ea0aed1d844ebe4e386636198e7b993ab554d9653583c1c',
 'math/box_extent.mojo': '7ddcdc6d53201a1cbe491cc4a54534231e8ce86ccaf76332bd4f85aee5f8b3f7',
 'math/euler.mojo': '8ada9d383b6ca2fa3b8082e40a069e70943bfa78497c6fa9668f050799a424f3',
 'math/matrix3.mojo': '39cce8a87f30062b530b3573a669005d17f09fbec2939dba1857bed19c604b19',
 'math/matrix4.mojo': '2e1cfe2cbe4394a2242e162bbe4c7ef20ab746386ff6224358a6d3de611ad28e',
 'math/matrix_determinant.mojo': 'c5b25179893fd2903dbda5de68914a50e662e3428107ef2c3424ef42cafcde19',
 'math/matrix_inverse.mojo': '34dd50cb00f3efe560ae73b1f0be8d2a399d045e1f9db699ce507b6da6ec09ee',
 'math/norm.mojo': '5275636f99048885fcc308bfa92fde3d52c5a8eefb48f616f59f8f31a0b5cbb1',
 'math/quaternion.mojo': '328aac299f3591af2fec898b924d64190a53d8558a118289c5633f56f9a13d26',
 'math/random.mojo': 'f8a00ee7d03897a7c35f2f23d157fb65ce2c2b3fde5e4c91f21e7a764fab1655',
 'math/remainder.mojo': 'b7575b2fde7a212433498422a121c66b12a85e7109614093bb783ad1cc043e58',
 'math/scaled_products.mojo': 'b504f18cff7df27bff4fbf92fbed7aa4868518f1b1507ea1331540d7e6f0afbb',
 'math/segment.mojo': 'f8f42b8b4a0be8ac7aca2e9070b114d7f207ece2ea228ace1e5bef101b6bc1db',
 'math/smoothstep.mojo': '816816e8897adc10c742ea22e2193b9273635040bc0c6ffbc7c1c9d8594be20b',
 'math/triangle.mojo': '365317ef7f1a1bd04adc3442430cc874f26691ea0f9c51243578de304e3f3ee3',
 'math/triangle_normal.mojo': '8e2d7c30411e44b3eb3fd8151b86a2da5f1a285d2a6e169a3b54b786284b3caa',
 'math/utils.mojo': '8e2279cec8879b18969fc9c02ac9cc22fe20e14fdd57360e2a6805822ed80947',
 'math/vector2.mojo': '6bc3b252c04e5fe6a562a09e85e69d49bff738aa354cf5856a5613fb89af36e5',
 'math/vector3.mojo': '4ce87f711940cd7920bd7ffb76d8e34f8a9fe6bf4dff1562b12d9cea3cb735bf',
 'units/__init__.mojo': '5f3ace6c2d6162c4a542666c21a966d54d5b98b8d4982794ea5bfbbcc4f52479',
 'units/quantity.mojo': 'bb77541cdb757cd63b59ac01134c6a6ebce88863bee69c84ff77b8c03aff6223',
 'units/si.mojo': '4225e1be95a48a234e38169cef21289e3f9e6f00760be01456d8f826b497979e'}
CONSTRUCTION_BOUNDARY_LINE = 4055


def _construction_boundary_callers(root, *, _operation=None):
    """Resolve Map references, not a repository-wide same-name count.

    Every member reference outside the pinned Map is unvalidated. Bare calls
    can instead resolve to a unique module-level function (e.g. humanoid loft's
    List[_Ellipse]/LoftSample function). Imports, aliases, method declarations,
    unknown spellings/syntax and unresolved names fail closed. The local
    declaration cannot replace the concrete Map method or establish its proof.
    """
    from carla_lane_oracle import source_contracts, sum2_guard_contracts
    operation_args = {} if _operation is None else {'_operation': _operation}
    paths = cache_key.input_paths(Path(root))
    if _operation is not None:
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
        cleanup._operation_check(_operation, root)
        paths = tuple(paths)
        cleanup._operation_known_paths(root, frozenset(
            path.as_posix() for path in paths if path.suffix == '.mojo'),
            _operation=_operation)
    for path in paths:
        if path.suffix != '.mojo' or path.as_posix() == 'extensions/carla/map.mojo':
            continue
        text = relative_source(root, path.as_posix(), **operation_args).read_text()
        if _operation is not None:
            cleanup._observe_text(root, path.as_posix(), text, _operation=_operation)
        if '_add_segment' not in text:
            continue
        tokens = [token for token in source_contracts.tokens(text)
                  if token.type not in (tokenize.COMMENT, tokenize.NL,
                                        tokenize.ENDMARKER)]
        # Conservative safety condition, not a reflective-call resolver.
        # Unresolved string-based spellings cannot establish a static caller.
        if any(token.type == tokenize.STRING and '_add_segment' in token.string
               for token in tokens):
            return False
        refs = [index for index, token in enumerate(tokens)
                if token.type == tokenize.NAME and token.string == '_add_segment']
        if not refs:  # Ordinary comments do not resolve a callable.
            continue
        # Exact lexical owner excludes a method or nested/conditional binding.
        sum2_guard_contracts.declaration(text, '_add_segment', ())
        declarations = 0
        for index in refs:
            previous = tokens[index - 1].string if index else ''
            following = tokens[index + 1].string if index + 1 < len(tokens) else ''
            if previous == 'def':
                declarations += 1
            elif previous == '.' or following != '(':
                return False
        if declarations != 1:
            return False
    return True


def _typed_construction_boundary_loops(root, current, *, include_roots=(), _operation=None):
    """Re-admit the nonempty-list theorem for the exact typed current graph.

    Successful same-owner _build_transform still calls the concrete private
    Road implementation and rejects a missing geometry before success. The
    boundary producer still appends that geometry into a fresh owned list.
    Numerical value changes and new early refusals do not weaken this fact.
    """
    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
    from carla_lane_oracle import typed_boundary_contracts as typed
    operation_args = {} if _operation is None else {'_operation': _operation}
    bindings = cleanup.proof_bindings(root, include_roots=include_roots, **operation_args)
    name = 'extensions/carla/map.mojo'
    if (bindings.get(name) != sha256(current.encode('utf-8'))
            or not typed.is_current(name, current)):
        return {}
    line = _typed_loop_row('extensions/carla/map', CONSTRUCTION_BOUNDARY_LINE,
                           'boundaries', current)
    if line is None:
        return {}
    # Preserve the actual whole-maintained-source caller census. A pure
    # historical view cannot hide a new caller, alias, package, or std shadow.
    try:
        for location in (root, *include_roots):
            if (not _density_stdlib_unshadowed(location, **operation_args)
                    or not _construction_boundary_callers(location, **operation_args)):
                raise ValueError('typed constructor caller or stdlib premise changed')
    except (OSError, UnicodeError, ValueError) as error:
        # An applicable typed theorem consumed this premise in the shared
        # owned operation. Its rejection must also revoke sibling Map rows.
        if _operation is not None:
            cleanup._operation_fail(_operation, error)
        return {}
    if (_operation is None and not _final_unowned_typed_loop_bindings(
            root, bindings, include_roots=include_roots)):
        return {}
    # The receipt has disjoint executing-checker and source-input domains.
    # Recheck both physical images. A checker copy is not a source observation;
    # the owner separately retains this consumed premise through finalization.
    try:
        executing = cleanup.executing_checker_bindings(root)
        cleanup.require(all(bindings.get(path) == digest
                            for path, digest in executing.items()),
                        'construction receipt checker image changed')
    except (OSError, UnicodeError, ValueError, TypeError, KeyError, IndexError, AttributeError) as error:
        cleanup._operation_fail(_operation, error)
    for path, expected in bindings.items():
        if path in executing:
            continue
        raw = _coverage_observe_bytes(root, path,
            relative_source(root, path, **operation_args).read_bytes(),
            _operation=_operation)
        if sha256(raw) != expected:
            return {}
    return {line: {
        'line': line, 'kind': 'reviewed-nonempty-iterator', 'cardinality': 1,
        'minimum_cardinality': 1, 'maximum_cardinality': None,
        'required': 'T', 'impossible': 'F', 'expression': 'boundaries',
        'proof_id': 'construction-geometry-boundary-list',
        'dependency_sha256': bindings,
    }}


def construction_boundary_loops(root, *, include_roots=(), _operation=None):
    """Admit only the exact final endpoint and the reviewed typed call graph."""
    operation_args = {} if _operation is None else {'_operation': _operation}
    stream_args = {} if _operation is None else {'_operation': _operation, '_root': root}
    if _operation is not None:
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
        cleanup._operation_check(_operation, root)
        cleanup._operation_include_context(_operation, root, include_roots)
    try:
        from carla_lane_oracle import typed_boundary_contracts as typed
        name = 'extensions/carla/map.mojo'
        current = _coverage_observe_text(root, name,
            relative_source(root, name, **operation_args).read_text(),
            _operation=_operation)
        if typed.is_current(name, current):
            return _typed_construction_boundary_loops(
                root, current, include_roots=include_roots, **operation_args)
        actual = {name: file_sha256(relative_source(root, name, **operation_args), **stream_args)
                  for name in CONSTRUCTION_BOUNDARY_SOURCE_SHA256}
        from carla_lane_oracle import seed_count_contracts
        # Preserve the immutable frontier table and verify the complete new
        # source/data edge before admitting its identical constructor theorem.
        expected = dict(CONSTRUCTION_BOUNDARY_SOURCE_SHA256)
        # Each reviewed score-family endpoint has its own exact boundary line.
        lines = {seed_count_contracts.SCORE_AFTER_SHA256: 4069,
                 seed_count_contracts.station.AFTER_SHA256: 4099,
                 seed_count_contracts.deviation.AFTER_SHA256: 4106}
        station = actual[seed_count_contracts.MODULE] in {
            seed_count_contracts.station.AFTER_SHA256, seed_count_contracts.deviation.AFTER_SHA256}
        score = actual[seed_count_contracts.MODULE] in lines
        line = CONSTRUCTION_BOUNDARY_LINE
        if score:
            expected[seed_count_contracts.MODULE] = actual[seed_count_contracts.MODULE]
            line = lines[actual[seed_count_contracts.MODULE]]
        # An inapplicable constructor theorem must not attempt current admission.
        # Historical guarded theorems are still verified independently below.
        if actual[seed_count_contracts.MODULE] != expected[seed_count_contracts.MODULE]:
            return {}
        cleanup_bindings = {}
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
        # Only the exact separately verified helper extractions may bypass the
        # historical admission fallback. Any other changed constructor premise
        # must retain its failed-operation semantics, including historical Road.
        if any(actual[name] != expected[name] and not (
                name in cleanup.shared_helpers.SOURCE_PATHS
                and expected[name] == cleanup.shared_helpers.BEFORE_SHA256[name]
                and actual[name] == cleanup.shared_helpers.AFTER_SHA256[name]) and not (
                name in cleanup.scaled_float32.SOURCE_PATHS
                and expected[name] == cleanup.scaled_float32.BEFORE_SHA256[name]
                and actual[name] == cleanup.scaled_float32.AFTER_SHA256[name])
               for name in expected):
            cleanup_bindings = cleanup.proof_bindings(root, include_roots=include_roots, **operation_args)
            edges = cleanup.verified_edges(root, include_roots=include_roots, **operation_args)
            for name, edge in edges.items():
                if name in expected and expected[name] == edge['before_sha256']:
                    expected[name] = edge['after_sha256']
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
        helper_bindings = cleanup.shared_helper_proof_bindings(
            root, paths=('extensions/carla/curve_distance.mojo', 'loaders/xml.mojo'),
            include_roots=include_roots, **operation_args)
        for name in cleanup.shared_helpers.SOURCE_PATHS:
            if (name in expected and helper_bindings.get(name)
                    == cleanup.shared_helpers.AFTER_SHA256[name]):
                if expected[name] != cleanup.shared_helpers.BEFORE_SHA256[name]:
                    return {}
                expected[name] = cleanup.shared_helpers.AFTER_SHA256[name]
        scaled_bindings = cleanup.scaled_float32_proof_bindings(
            root, include_roots=include_roots, **operation_args)
        for name in cleanup.scaled_float32.SOURCE_PATHS:
            if scaled_bindings.get(name) == cleanup.scaled_float32.AFTER_SHA256[name]:
                if expected.get(name) != cleanup.scaled_float32.BEFORE_SHA256[name]:
                    return {}
                expected[name] = cleanup.scaled_float32.AFTER_SHA256[name]
        if actual != expected:
            return {}
        helper_closure = ({'loaders/utf8.mojo'} if helper_bindings.get('loaders/xml.mojo')
                          == cleanup.shared_helpers.AFTER_SHA256['loaders/xml.mojo'] else set())
        if seed_count_contracts.dependency_inventory(root, **operation_args) != set(actual) | helper_closure:
            return {}
        # Preserve the final endpoint's independently bound source/data edge.
        if score:
            seed_count_contracts.verify_score(root, **operation_args)
            actual.update(seed_count_contracts.SCORE_TESTS)
            if station:
                from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
                actual.update(cleanup.station_proof_bindings(root, **operation_args))
        else:
            seed_count_contracts.verify_frontier(root)
        record = seed_count_contracts.read_record(root, **operation_args)
        actual.update(cleanup_bindings)
        actual.update(helper_bindings)
        actual.update(scaled_bindings)
        actual[seed_count_contracts.MIGRATION] = seed_count_contracts.MIGRATION_SHA256
        for group in ('historical_records', 'unchanged_correctness_tests',
                      'after_correctness_tests'):
            actual.update(record[group])
        # Include generated-source roots when validating a receipt, and forbid
        # local std shadows changing List/Int semantics at either resolution root.
        for location in (root, *include_roots):
            if (not _density_stdlib_unshadowed(location, **operation_args)
                    or not _construction_boundary_callers(location, **operation_args)):
                return {}
    except (OSError, ValueError, ImportError, UnicodeError) as error:
        if _operation is not None and isinstance(error, (OSError, UnicodeError)):
            cleanup._operation_fail(_operation, error)
        return {}
    return {line: {
        'line': line,
        'kind': 'reviewed-nonempty-iterator', 'cardinality': 1,
        'minimum_cardinality': 1, 'maximum_cardinality': None,
        'required': 'T', 'impossible': 'F', 'expression': 'boundaries',
        'proof_id': 'construction-geometry-boundary-list',
        'dependency_sha256': actual,
    }}


def _receipt_reviewed_nonempty_loops(root, module, *, include_roots, _operation):
    """The direct generated receipt alone lends its immutable image to rows."""
    from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
    cleanup._operation_include_context(_operation, root, include_roots)
    cleanup.require(_operation._kind == 'generated_receipt'
                    and sys._getframe(1) is _operation._owner_frame,
                    'generated row wrapper lacks its direct owner')
    return reviewed_nonempty_loops(root, module, include_roots=include_roots, _operation=_operation)


def reviewed_nonempty_loops(root, module, *, include_roots=(), _operation=None):
    """Keep historical rules and independently admit each new exact theorem."""
    owns_operation = False
    coherence_errors = ()
    bounded = include_roots == () and module in ('extensions/carla/map', 'extensions/carla/rtree')
    if bounded or _operation is not None:
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
        coherence_errors = (cleanup._OperationCoherenceError,)
    try:
        if _operation is not None:
            cleanup._operation_include_context(_operation, root, include_roots)
            cleanup.require(_operation._kind == 'generated_receipt', 'foreign generated row owner')
        elif bounded:
            kind = 'map_loops' if module == 'extensions/carla/map' else 'rtree_loops'
            _operation, owns_operation = cleanup._operation_enter(
                root, kind, module=module, include_roots=include_roots)
        operation_args = {} if _operation is None else {'_operation': _operation}
        result = _historical_reviewed_nonempty_loops(root, module, include_roots=include_roots, **operation_args)
        if module == 'renderers/renderer':
            result.update(strand_cap_loops(root, include_roots=include_roots, **operation_args))
        if module == 'extensions/carla/map':
            result.update(construction_boundary_loops(root, include_roots=include_roots, **operation_args))
        if module + '.mojo' == DENSITY_SOURCE:
            result.update(repaired_density_loops(root, include_roots=include_roots, **operation_args))
            result.update(density760_loops(root, include_roots=include_roots, **operation_args))
        for rule in GUARDED_LOOP_RULES:
            if rule[0] != module:
                continue
            proof = guarded_loop_proof(root, rule, include_roots=include_roots, **operation_args)
            if proof is None:
                continue
            if proof['line'] in result:
                raise ValueError('Conflicting reviewed loop proof: ' + module)
            result[proof['line']] = proof
        if owns_operation:
            _operation.finish(root)
        return result
    except coherence_errors:
        return {}
    finally:
        if owns_operation:
            _operation.close()


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
    _receipt_seed = {'schema': SCHEMA, 'python': sys.version,
        'compiler': compiler, 'flags': flags, 'manifest_sha256': sha256(raw),
        'tools': tools, 'root_inputs': root_inputs, 'inputs': inputs, 'generation': generation,
        'execution': execution_contract(root, build, inputs, mojo=mojo,
                                        capture_cache=capture_cache, suites=suites)}
    cleanup = None
    if importlib.util.find_spec('carla_lane_oracle') is None:
        # Standalone plain receipts need no CARLA semantic authority. A known
        # reviewed source may never silently become a plain-only receipt.
        reviewed_modules = (set(REVIEWED_LOOP_RULES)
                            | {row[0] for row in GUARDED_LOOP_RULES}
                            | {'renderers/renderer', 'extensions/carla/map',
                               DENSITY_SOURCE.removesuffix('.mojo')})
        if reviewed_modules & {name.removesuffix('.mojo') for name in generation['modules']}:
            raise ValueError('Reviewed loop authority is unavailable')
    else:
        # A present but broken authority installation is an error, not fallback.
        from carla_lane_oracle import full_audit_cleanup_contracts as cleanup
    _plain_seed = canonical(_receipt_seed) if cleanup is None else None
    _operation = (None if cleanup is None else
                  cleanup._receipt_operation_enter(root, build, _receipt_seed))
    try:
        if _operation is None:
            check_capture_inputs({'receipt': json.loads(_plain_seed)}, root, build)
            if not all(_density_stdlib_unshadowed(location) for location in (root, build)):
                raise ValueError('Plain receipt resolver surface changed')
        else:
            _operation._receipt_inputs_check()
        proofs = []
        for module in modules:
            name = module + '.mojo'
            original = relative_source(root, name)
            if name not in inputs:
                raise ValueError('Missing instrumented module: ' + module)
            text = original.read_text(encoding='utf-8')
            if _operation is None:
                source_raw = original.read_bytes()
                with io.TextIOWrapper(io.BytesIO(source_raw), encoding='utf-8', newline=None) as reader:
                    observed_text = reader.read()
                if (sha256(source_raw) != json.loads(_plain_seed)['root_inputs'][name]
                        or text != observed_text):
                    raise ValueError('Plain receipt consumed source differs from generation: ' + name)
            else:
                text = cleanup._observe_text(root, name, text,
                                             _operation=_operation, mode='physical')
            candidates = constant_loops(text)
            reviewed = ({} if _operation is None else
                        _receipt_reviewed_nonempty_loops(root, module, include_roots=(build,),
                                                         _operation=_operation))
            if _operation is not None:
                cleanup._operation_check(_operation, root)
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
                               'source_sha256': (json.loads(_plain_seed)['root_inputs'][name]
                                   if _operation is None else inputs[name]['source'])})
        counts = _counts(records)
        counts['proven_impossible'] = len(proofs)
        counts['required_total'] = counts['potential_total'] - len(proofs)
        if _operation is None:
            if canonical(_receipt_seed) != _plain_seed:
                raise ValueError('Plain receipt seed changed after consumption')
            result = {**json.loads(_plain_seed), 'proofs': proofs, 'denominator': counts}
            check_capture_inputs({'receipt': result}, root, build)
            if not all(_density_stdlib_unshadowed(location) for location in (root, build)):
                raise ValueError('Plain receipt resolver surface changed')
        else:
            result = {**json.loads(_operation._receipt_seed), 'proofs': proofs, 'denominator': counts}
            _operation.finish(root)
        return result
    except BaseException as error:
        if _operation is not None:
            _operation._invalidate(error)
        raise
    finally:
        if _operation is not None:
            _operation.close()


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


def _hair_census_reference(names, text):
    """Keep unknown hair references; exclude only a proven local upload name."""
    pattern = r'\b(?:' + '|'.join(re.escape(name) for name in names) + r')\b'
    if not re.search(pattern, text):
        return False
    if (names != ('_shadow_depths', '_upload')
            or re.search(r'\b_shadow_depths\b', text)):
        return True
    import keyword
    from carla_lane_oracle import source_contracts, sum2_guard_contracts
    try:
        tokens = source_contracts.tokens(text)
        # Python 3.12 exposes f-string parts separately. Their fields are not
        # supported local-name evidence, even when the literal part is empty.
        fstring_types = {getattr(tokenize, name, -1) for name in
                         ('FSTRING_START', 'FSTRING_MIDDLE', 'FSTRING_END')}
        if any(token.type == tokenize.ERRORTOKEN or token.type in fstring_types or
               (token.type in (tokenize.COMMENT, tokenize.STRING)
                and re.search(r'\b_upload\b', token.string)) for token in tokens):
            return True
        tokens = [token for token in tokens
                  if token.type not in (tokenize.COMMENT, tokenize.NL,
                                        tokenize.ENDMARKER)]
        # A star import can replace the binding without spelling its name.
        importing = False
        for token in tokens:
            if token.type == tokenize.NEWLINE:
                importing = False
            elif token.type == tokenize.NAME and token.string == 'import':
                importing = True
            elif importing and token.string == '*':
                return True
        declaration = sum2_guard_contracts.declaration(text, '_upload', ())
        stream = [token for token in source_contracts.tokens(declaration)
                  if token.type not in (tokenize.COMMENT, tokenize.NL,
                                        tokenize.ENDMARKER)]
        stream = stream[:next(index for index, token in enumerate(stream)
                              if token.type == tokenize.NEWLINE)]
        position = 0

        def at(value):
            return position < len(stream) and stream[position].string == value

        def take(value):
            nonlocal position
            if not at(value):
                raise ValueError('unsupported local upload syntax')
            position += 1

        def identifier():
            nonlocal position
            if (position >= len(stream) or stream[position].type != tokenize.NAME
                    or keyword.iskeyword(stream[position].string)):
                raise ValueError('unsupported local upload identifier')
            position += 1

        def type_name(depth=0):
            if depth > 8:
                raise ValueError('unsupported local upload type nesting')
            identifier()
            while at('.'):
                take('.')
                identifier()
            if at('['):
                take('[')
                type_name(depth + 1)
                while at(','):
                    take(',')
                    type_name(depth + 1)
                take(']')

        # declaration() binds the unique lexical owner, but retains decorators
        # and does not validate a signature. Admit only this narrow grammar.
        take('def')
        take('_upload')
        if at('['):
            take('[')
            while True:
                identifier()
                take(':')
                identifier()
                while at('.'):
                    take('.')
                    identifier()
                if not at(','):
                    break
                take(',')
            take(']')
        take('(')
        if not at(')'):
            while True:
                identifier()
                if at(':'):
                    take(':')
                    type_name()
                if not at(','):
                    break
                take(',')
        take(')')
        if at('raises'):
            take('raises')
        if at('->'):
            take('->')
            type_name()
        take(':')
        if position != len(stream):
            return True
        declarations = 0
        for index, token in enumerate(tokens):
            if token.type != tokenize.NAME or token.string != '_upload':
                continue
            previous = tokens[index - 1].string if index else ''
            if previous == 'def':
                declarations += 1
                continue
            if previous in {'.', 'fn', 'struct', 'trait', 'class', 'alias',
                            'var', 'comptime', 'mut', 'out', 'ref',
                            'import', 'from', 'as'}:
                return True
            position = index + 1
            stream = tokens
            if at('['):
                take('[')
                while True:
                    identifier()
                    while at('.'):
                        take('.')
                        identifier()
                    if not at(','):
                        break
                    take(',')
                take(']')
            take('(')
        return declarations != 1
    except (ValueError, StopIteration):
        return True


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
