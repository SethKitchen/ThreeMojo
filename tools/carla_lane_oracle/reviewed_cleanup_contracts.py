# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Narrow source successor for reviewed CARLA control-flow cleanups.

The retained migration records describe their historical sources. This record
binds exactly three successors and preserves every other dependency. Source
integrity does not establish native behavior, coverage, or floating-point mode.
"""
import hashlib
import json
import tokenize

try:
    import source_contracts as source
    import frozen_arc_producer_contracts as frozen
    import coverage_invariant_contracts as invariant
except ModuleNotFoundError:
    from tools.carla_lane_oracle import source_contracts as source
    from tools.carla_lane_oracle import frozen_arc_producer_contracts as frozen
    from tools.carla_lane_oracle import coverage_invariant_contracts as invariant
try:
    import cache_key_contracts as cache_key
except ModuleNotFoundError:
    from tools.carla_lane_oracle import cache_key_contracts as cache_key


try:
    import accepted_successor_contracts as accepted
except ModuleNotFoundError:
    from tools.carla_lane_oracle import accepted_successor_contracts as accepted

MIGRATION = 'tools/carla_lane_oracle/reviewed-cleanup-migration.json'
MIGRATION_SHA256 = '01753344fe01d885eb3bbaf253815bca01816c57c09b6e7cc1c3a233808b42a9'
SOURCE_PATHS = tuple('extensions/carla/' + name + '.mojo' for name in
                     ('curve_rounded_line', 'curve_rounded_arc', 'junction_bounds'))
# A fixture that invokes the protected guard must carry its complete inputs.
PREMISE_PATHS = ('extensions/carla/road_info.mojo', 'extensions/carla/curve_trig.mojo')
PROTECTED_INPUTS = (*cache_key.PROTECTED_INPUTS, *accepted.PROTECTED_INPUTS, MIGRATION, 'tools/carla_lane_oracle/runtime-source-pins.json',
                    *SOURCE_PATHS, *PREMISE_PATHS, *frozen.PROTECTED_INPUTS,
                    *invariant.PROTECTED_INPUTS,
                    'tools/carla_lane_oracle/coverage-followup-migration.json',
                    'tools/carla_lane_oracle/raw-cut-inverse-migration.json',
                    'tools/carla_lane_oracle/moment-finiteness-contract.json',
                    'tools/carla_lane_oracle/envelope-budget-contract.json',
                    'tests/test_carla_raw_cut_successor.mojo',
                    'tests/test_carla_envelope_budget_dominance.mojo',
                    'extensions/carla/spiral_moment_proof.mojo',
                    'tools/carla_lane_oracle/lane-order-migration.json',
                    'tests/test_carla_lane_order_successor.mojo',
                    'tools/carla_lane_oracle/selection-finiteness-contract.json',
                    'tests/test_spiral_selection_finite_contract.mojo',
                    'tests/_reference_roundoff_selection.mojo',
                    'tests/_reference_grouped_selection.mojo',
                    'extensions/carla/spiral_roundoff_proof.mojo')


def require(condition, message):
    if not condition:
        raise ValueError('reviewed cleanup source contract: ' + message)


def read_record(root):
    payload = (root/MIGRATION).read_bytes()
    require(hashlib.sha256(payload).hexdigest() == MIGRATION_SHA256,
            'unreviewed migration record')
    record = json.loads(payload, object_pairs_hook=source.unique_keys)
    require(type(record['schema']) is int and record['schema'] == 1,
            'unsupported migration schema')
    require(set(record['sources']) == set(SOURCE_PATHS), 'wrong successor set')
    require(set(record['premise_dependencies']) == set(PREMISE_PATHS),
            'wrong premise dependency set')
    previous = root/'tools/carla_lane_oracle/winner-sign-query-migration.json'
    require(hashlib.sha256(previous.read_bytes()).hexdigest() ==
            record['prior_winner_sign_migration_sha256'],
            'historical winner/sign record changed')
    return record


def words(text):
    return [token.string for token in source.tokens(text) if token.type not in
            (tokenize.COMMENT, tokenize.NL, tokenize.NEWLINE, tokenize.INDENT,
             tokenize.DEDENT, tokenize.ENDMARKER)]


def ordered(text, fragments, label):
    actual = words(text)
    previous = -1
    for fragment in fragments:
        expected = words(fragment)
        matches = [i for i in range(len(actual)-len(expected)+1)
                   if actual[i:i+len(expected)] == expected]
        require(len(matches) == 1 and matches[0] > previous, label)
        previous = matches[0]


def verify_premises(root):
    # Import here so the enclosing guard can call this verifier without a
    # module initialization cycle. Its lexical parser checks actual owners.
    try:
        import sum2_guard_contracts as guard
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import sum2_guard_contracts as guard
    line = (root/SOURCE_PATHS[0]).read_text()
    arc = (root/SOURCE_PATHS[1]).read_text()
    junction = (root/SOURCE_PATHS[2]).read_text()
    line_context = guard.declaration(line, '_rounded_line_axis_context', ())
    ordered(line_context, (
        'road._check_lane(section, lane)',
        'if len(road.info.geometries) != 1: return None',
        'not _RoundedBox.bounds(low, high).known',
        'if info_index(road.info.geometries, low) != 0: return None',
        'or info_index(road.info.lane_offsets, high) != offset_at',
        'or info_index(road.info.elevations, high) != elevation_at',
        'if width_at < 0 or info_index(widths, high) != width_at: return None',
    ), 'LINE singleton/domain/low lookup and multi-record profile premises')
    arc_context = guard.declaration(arc, '_rounded_arc_context', ())
    ordered(arc_context, (
        'road._check_lane(section, lane)',
        'if len(road.info.geometries) != 1: return None',
        'if not _RoundedBox.bounds(low, high).known or high > road.length: return None',
        'if info_index(road.info.geometries, low) != 0: return None',
        'if len(road.info.lane_offsets) != 1 or len(road.info.elevations) != 1: return None',
        'info_index(road.info.lane_offsets, low) != 0',
        'or info_index(road.info.elevations, low) != 0',
        'if len(widths) != 1: return None',
        'if info_index(widths, low) != 0: return None',
    ), 'ARC singleton/domain/low lookup premises')
    bounds = guard.declaration(arc, 'bounds', ('_RoundedBox',))
    ordered(bounds, ('_rounded_operand(low)', '_rounded_operand(high)',
                     'and low <= high'), 'ordered finite domain premise')
    center = guard.declaration(arc, 'center', ('_RoundedArc',))
    ordered(center, (
        'if not half.known: return [unknown, unknown, unknown]',
        'var selector = _rounded_madd('
        'half, _RoundedBox.point(_INV_HALF_PI), _RoundedBox.point(0.5))',
        'if not selector.known or selector.low < 0.0 or selector.high >= 1.0: '
        'return [unknown, unknown, unknown]',
        'var square = half * half',
    ), 'quarter implication requires the same accepted selector hull')
    outward = guard.declaration(junction, '_outward_float', ())
    ordered(outward, (
        'var result = Float32(value)',
        'var outside: Bool',
        'if lower: outside = Float64(result) > value',
        'else: outside = Float64(result) < value',
        'if outside:',
        'UInt32(0x80000001) if lower else UInt32(1)',
        'if (result > 0.0) == lower: bits -= 1 else: bits += 1',
        'result = bitcast[DType.float32](bits)',
    ), 'outward conversion direction and adjacent-word premises')



# Only the two explicit reviewed constant sets have a stored-word contract.
# Every other token, including indentation and statement boundaries, stays bound.
TRIG_PATH = 'extensions/carla/curve_trig.mojo'
TRIG_TOKEN_SHA256 = '523d5700201b957152eaa79ae6cce9ca8cb9a2a0098d5b105584667360a6de7f'
TRIG_WORD_SHA256 = 'f2337e89e88234a7a275e1be6398d672abd05210e5b37098e2e3bd39212c3807'


def _stored_word_sha256(text, arrays, scalars):
    try:
        import spiral_moments as moments
    except ModuleNotFoundError:
        from tools.carla_lane_oracle import spiral_moments as moments
    declarations = moments.ideal_projection.module_statements(text)
    canonical = {}
    for name in sorted(set(arrays) | scalars):
        matches = [item for item in declarations
                   if item[:2] == [('NAME', 'comptime'), ('NAME', name)]]
        require(len(matches) == 1, 'missing or ambiguous stored-word declaration: ' + name)
        if name in arrays:
            words = moments.parse_array(text, name, arrays[name])
        else:
            declaration = matches[0]
            prefix = [('NAME', 'comptime'), ('NAME', name), ('OP', '='),
                      ('NAME', 'Float64'), ('OP', '(')]
            require(declaration[:len(prefix)] == prefix and declaration[-1] == ('OP', ')'),
                    'unsupported complete stored-word scalar: ' + name)
            literal = moments.literal_from_tokens(declaration[len(prefix):-1],
                                                   'scalar literal: ' + name)
            words = [moments.decimal_word(literal)]
        canonical[name] = [(tokenize.NAME, 'STORED_WORD_DECLARATION'),
                           (tokenize.NAME, name),
                           (tokenize.STRING, json.dumps(words))]
    kept, statement, depth = [], [], 0
    for item in source.tokens(text):
        if item.type in (tokenize.COMMENT, tokenize.NL, tokenize.ENDMARKER):
            continue
        if item.type == tokenize.INDENT:
            depth += 1
        elif item.type == tokenize.DEDENT:
            depth -= 1
        if item.type == tokenize.NEWLINE:
            # Declaration matching is restricted to real top-level statements.
            # A module declaration after a function shares this logical line
            # with DEDENT tokens. Preserve those structural tokens verbatim.
            leading = 0
            while leading < len(statement) and statement[leading][0] == tokenize.DEDENT:
                leading += 1
            declaration = statement[leading:]
            if (depth == 0 and len(declaration) >= 2
                    and declaration[0] == (tokenize.NAME, 'comptime')
                    and declaration[1][0] == tokenize.NAME
                    and declaration[1][1] in canonical):
                statement = statement[:leading] + canonical[declaration[1][1]]
            kept.extend(statement)
            kept.append((item.type, item.string))
            statement = []
        else:
            statement.append((item.type, item.string))
    kept.extend(statement)
    return hashlib.sha256(json.dumps(kept, separators=(',', ':')).encode()).hexdigest()



def trig_word_sha256(text):
    return _stored_word_sha256(text,
        {'_COS_COEFFICIENTS': 11, '_SIN_COEFFICIENTS': 11},
        {'_PHASE_LIMIT', '_INV_HALF_PI', '_HALF_PI_HIGH', '_HALF_PI_LOW'})


GEOMETRY_PATH = 'extensions/carla/geometry.mojo'
GEOMETRY_TOKEN_SHA256 = 'a1979bd37d0ea725f452e0a0a269c7aaef3cda485b291e8fe79b49b35850adcb'
GEOMETRY_WORD_SHA256 = 'fb42552072a0166ca3ca94016b39ba98a6645e4091751e4b5b67e199139e96f0'


def geometry_word_sha256(text):
    return _stored_word_sha256(text, {'_GL_NODES': 5, '_GL_WEIGHTS': 5}, set())


def verify_dependency(path, text, expected):
    if source.token_sha256(text) == expected:
        return
    # A fixed whole-module fingerprint admits only equivalent stored words.
    # Historical pins remain unchanged; other dependencies retain exact tokens.
    if path == TRIG_PATH and expected == TRIG_TOKEN_SHA256:
        matches = trig_word_sha256(text) == TRIG_WORD_SHA256
    elif path == GEOMETRY_PATH and expected == GEOMETRY_TOKEN_SHA256:
        matches = geometry_word_sha256(text) == GEOMETRY_WORD_SHA256
    else:
        matches = False
    require(matches, 'unchanged premise dependency changed: ' + path)


def verify(root):
    record = read_record(root)
    for filename, key in (
            ('runtime-source-pins.json', 'runtime_pins_after_sha256'),
            ('sum2-guard-pins.json', 'guard_pins_after_sha256')):
        if filename == 'runtime-source-pins.json':
            frozen.verify_runtime_pin_successor(root, record[key])
            continue
        payload = invariant.predecessor_pins(root, filename)
        require(hashlib.sha256(payload).hexdigest() == record[key],
                'unreviewed dependency pin successor: ' + filename)
    for path, transition in record['sources'].items():
        require(source.token_sha256(accepted.predecessor_text(root, path) if path in accepted.SOURCE_PATHS else (root/path).read_text()) ==
                transition['after_token_sha256'], 'unreviewed complete successor: ' + path)
    for path, expected in record['premise_dependencies'].items():
        verify_dependency(path, (root/path).read_text(), expected['token_sha256'])
    verify_premises(root)
    frozen.verify(root)
    invariant.verify(root)
    return record
