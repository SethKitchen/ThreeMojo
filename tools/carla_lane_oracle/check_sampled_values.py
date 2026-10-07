#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Read-only source correspondence for derivative-elided sampled bounds.

No Mojo execution. Uses only the Python standard library; no Mojo parser or compiler is run.
Numeric grouping, branches, imports and retained value/error operations are
checked against the full-Jet source. Primitive changes require renewed review.
"""
import argparse
import ast
import copy
import hashlib
import io
import json
from pathlib import Path
import re
import tokenize

try:
    from source_contracts import verify_group, verify_qualifiers
except ModuleNotFoundError:
    from tools.carla_lane_oracle.source_contracts import verify_group, verify_qualifiers

ROOT = Path(__file__).resolve().parents[2]
PRIMITIVE_GRAPH_SHA256 = 'e2e0257a0f42a95bac586638fc5d532f4bc69b882127201bbf343006f2143484'
REFERENCE_MODULE_GRAPHS = {
    "curve_bounds.mojo": "51f99d745612d217762d8f39bde1ded5b269d239f05cb765532de631cc64791f",
    "curve_trig.mojo": "4ca47db55caa96ba9ad6c6f43fa65d30a8fefe419f555d46a1a948a2fc606ecc",
    "curve_interval.mojo": "32b7bce9ad0b996fa87a7bc63ff0c905065751d164f7d673342234716523fd8e"
}
SHARED_GRAPHS = {
    "curve_trig.mojo:_expression_polynomial": "031856283e36ac8dbaef6e455eb6a1502c0c465f70ba809ace51ec5782abb04a",
    "curve_trig.mojo:_jet_polynomial": "9a773f471ac8ac236f808d0f072ac5372315a3dd2683b16c41899a1b56cfd470",
    "curve_trig.mojo:_sincos_expression": "89921637fc52fad38092e2c283d238287b3f33035dcc0a33a2b07fddc6042509",
    "curve_trig.mojo:_sincos_branch_expression": "8ba6cc52dff85cbca95fa9c58142de28140c97d711911bd1f437b11ca2bc857f",
    "curve_trig.mojo:_sincos_branch": "a99d1be1594ceeea7edf3709312217af35035b590dd621c57c3e6bdf97a26a8a",
    "curve_trig.mojo:_sincos_jet": "f76f149a0ee85c2e5e3b1dc6b1d8a9cd68a053582fbe4c9d8e562b1848c91b3f",
    "curve_trig.mojo:_uncertain_expression": "c883bc5e3e7046309b145f178f73848cecc20013551852a80f993f793c1ff00f",
    "curve_trig.mojo:_uncertain": "e32b28fd29a051ebb13cb14f22cc61a12f137124cc9b9938adf113e606baa21e",
    "curve_bounds.mojo:_sample_index": "91a5c643d73e15e2b5d3838fff658dc2986e0b28852a0c66ceacdd84e71ca01e",
    "curve_bounds.mojo:_intersect_ideal_bounds": "0f6d271eb25f2e19f9cfd4c4f8f93691f4452cb50ac5303d7ff898398f8deda3",
    "curve_bounds.mojo:_lane_jet": "c1d76e057272bbb71d1066e4669a3b7d0e5e87c4497e9d96abf21edc007e2f85",
    "curve_bounds.mojo:_lane_jet_model": "470c29ee518a71ecc8c6bce3268d38da93d8c27770b9bdf6e6c82989a1032ab0",
    "curve_bounds.mojo:_lane_jet_model_proof": "17eea195f5bcd6e90781bbc3370f16e5404b67620aad1807b24101ceaebd7218",
    "curve_bounds.mojo:_reference_jet_capture": "0ebd93d524b35c30cdd27fabc23dd40f1a53241477b0689c37b07b18bce5ad05"
}
NAMES = {
    '_polynomial_jet': '_polynomial_value',
    '_unknown_point': '_unknown_value_point',
    '_geometry_distance': '_value_geometry_distance',
    '_sample_blend_jet': '_sample_blend_value',
    '_sample_jet': '_sample_value',
    '_atan_branch': '_atan_value_branch',
    '_atan_jet': '_atan_value',
    '_atan2_jet': '_atan2_value',
    '_jet_polynomial': '_expression_polynomial',
    '_uncertain': '_uncertain_value',
    '_Jet': '_ValueJet',
    '_sinc_jet': '_sinc_value',
    '_sincos_jet': '_sincos_expression',
    '_arc_offset_jet': '_arc_offset_value',
    '_constant_sincos_jet': '_constant_sincos_value',
    '_union_points': '_union_value_points',
}
COPIES = ('_atan_branch', '_atan_jet', '_atan2_jet', '_polynomial_jet',
          '_unknown_point', '_geometry_distance', '_sample_blend_jet', '_sample_jet')
IMPORTS = '''from extensions.carla.curve_interval import (
    _stored_difference,
    _stored_half,
    _stored_blend_error,
    _Interval,
    _ValueJet,
    _without_derivatives,
)
from extensions.carla.curve_bounds import (
    _sample_index,
    _intersect_ideal_bounds,
    _lane_jet,
)
from extensions.carla.curve_trig import (
    _expression_polynomial,
    _uncertain_expression,
    _sincos_expression,
    _PI,
    _HALF_PI,
    _QUARTER_PI,
    _ATAN_REDUCE,
    _ATAN_COEFFICIENTS,
    _SIN_COEFFICIENTS,
    _PHASE_LIMIT,
    _sign_bit,
    _curve_cos,
    _curve_sin,
    _curve_atan2,
)
from extensions.carla.geometry import (
    RoadGeometry,
    PARAM_POLY3,
    POLY3,
    LINE,
    ARC,
    SPIRAL,
)
from std.math import isfinite
from extensions.carla.polynomial import CubicPolynomial
from extensions.carla.road import Road
from extensions.carla.road_info import info_index
from math.vector3 import Vector3
'''


class CheckError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def function(text, name):
    matches = list(re.finditer(r'(?m)^def ' + re.escape(name) + r'[\[(]', text))
    require(len(matches) == 1, 'missing or ambiguous function: ' + name)
    match = matches[0]
    end = re.search(r'(?m)^(?:def |@)', text[match.end():])
    return text[match.start():match.end()+end.start() if end else len(text)]


def translated(text):
    # Replace NAME tokens at original offsets, preserving fragment indentation
    # and every string literal. This also handles renamed identifiers of
    # different lengths without reconstructing partial source statements.
    lines = text.splitlines(keepends=True)
    offsets = [0]
    for line in lines:
        offsets.append(offsets[-1] + len(line))
    changes = []
    for item in tokenize.generate_tokens(io.StringIO(text).readline):
        if item.type == tokenize.NAME and item.string in NAMES:
            start = offsets[item.start[0]-1] + item.start[1]
            end = offsets[item.end[0]-1] + item.end[1]
            changes.append((start, end, NAMES[item.string]))
    for start, end, word in reversed(changes):
        text = text[:start] + word + text[end:]
    return text


def syntax_tree(text):
    # Keywords are removed lexically, never from string literals. Native
    # structs map to Python classes only for AST inspection; their generic
    # parameters, traits, fields, types, decorators and statements stay bound.
    tokens = []
    for item in tokenize.generate_tokens(io.StringIO(text).readline):
        if item.type == tokenize.NAME and item.string in ('var', 'mut', 'out', 'ref', 'comptime', 'raises'):
            continue
        word = 'class' if item.type == tokenize.NAME and item.string == 'struct' else item.string
        tokens.append((item.type, word))
    # Represent Mojo type-parameter declarations as bound lexical metadata,
    # rather than requiring Python3.12's unrelated generic-function grammar.
    metadata = {}
    index = 0
    while index + 2 < len(tokens):
        if (tokens[index][0] == tokenize.NAME and tokens[index][1] in ('def', 'class')
                and tokens[index + 1][0] == tokenize.NAME and tokens[index + 2][1] == '['):
            depth = 1
            end = index + 3
            while end < len(tokens) and depth:
                depth += (tokens[end][1] == '[') - (tokens[end][1] == ']')
                end += 1
            require(depth == 0, 'unclosed Mojo generic declaration')
            items = [(tokenize.tok_name[t], value) for t, value in tokens[index + 3:end - 1]
                     if t not in (tokenize.NL, tokenize.COMMENT)]
            if items and items[-1][1] == ',':
                items.pop()
            key = (tokens[index][1], tokens[index + 1][1])
            require(key not in metadata, 'ambiguous generic declaration')
            metadata[key] = items
            del tokens[index + 2:end]
        index += 1
    tree = ast.parse(tokenize.untokenize(tokens))
    for (kind, name), parameters in metadata.items():
        node_type = ast.FunctionDef if kind == 'def' else ast.ClassDef
        matches = [n for n in ast.walk(tree) if isinstance(n, node_type) and n.name == name]
        require(len(matches) == 1, 'ambiguous parsed generic declaration')
        matches[0]._mojo_type_parameters = parameters
    return tree


def normalized_node(node):
    if isinstance(node, ast.AST):
        fields = [(key, normalized_node(value)) for key, value in ast.iter_fields(node)
                  if value is not None and not (key == 'type_params' and not value)]
        if hasattr(node, '_mojo_type_parameters'):
            fields.append(('mojo_type_parameters', node._mojo_type_parameters))
        return (type(node).__name__, fields)
    if isinstance(node, list):
        return [normalized_node(value) for value in node]
    return node


def dump(node):
    # Ignore absent optional AST fields that newer Python versions introduce,
    # while binding all actual fields, types and explicit Mojo generics.
    return json.dumps(normalized_node(node), separators=(',', ':'), ensure_ascii=True)


def graph(text):
    return dump(syntax_tree(text))


def unique_function(tree, name):
    found = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == name]
    require(len(found) == 1, 'missing or ambiguous function: ' + name)
    return found[0]


def primitive_graph(text):
    tree = syntax_tree(text)
    found = [n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == '_JetExpression']
    require(len(found) == 1, 'unsupported primitive declaration')
    # Actual top-level aliases, not matching text that could live in a comment.
    for name, enabled in (('_Jet', True), ('_ValueJet', False)):
        aliases = [n for n in tree.body if isinstance(n, ast.Assign) and
                   any(isinstance(t, ast.Name) and t.id == name for t in n.targets)]
        require(len(aliases) == 1 and len(aliases[0].targets) == 1,
                'missing or ambiguous actual alias: ' + name)
        expected = ast.parse('_JetExpression[' + str(enabled) + ']', mode='eval').body
        require(dump(aliases[0].value) == dump(expected),
                'actual derivative alias changed: ' + name)
    return hashlib.sha256(dump(found[0]).encode()).hexdigest()



def reviewed_reference_tree(text):
    """Retain the historical reference graph after one exact additive refusal.

    Default False preserves every existing call. True may return unknown
    before the unchanged GL fallback; it cannot perform unreserved work.
    The production tokens and grouped True caller are bound separately.
    """
    tree = syntax_tree(text)
    node = unique_function(tree, '_lane_jet_model_proof')
    require(dump(node.args.args[-1]) == dump(ast.arg(
        arg='require_reuse', annotation=ast.Name(id='Bool', ctx=ast.Load()))),
        'try-only parameter changed')
    require(dump(node.args.defaults[-1]) == dump(ast.Constant(value=False)),
            'try-only default must preserve historical callers')
    matches = [item for item in node.body if isinstance(item, ast.If)
               and dump(item.test) == dump(ast.Name(id='reused', ctx=ast.Load()))]
    require(len(matches) == 1 and len(matches[0].orelse) == 1
            and isinstance(matches[0].orelse[0], ast.If),
            'try-only refusal missing from reuse/fallback edge')
    branch = matches[0].orelse[0]
    expected = ast.parse('if require_reuse: return _unknown_point()').body[0]
    require(dump(branch.test) == dump(expected.test)
            and dump(branch.body) == dump(expected.body) and bool(branch.orelse),
            'try-only refusal changed')
    require(sum(isinstance(item, ast.Name) and item.id == 'require_reuse'
                for item in ast.walk(node)) == 1,
            'try-only flag has an unreviewed use')
    matches[0].orelse = branch.orelse
    node.args.args.pop()
    node.args.defaults.pop()
    return tree


def verify(root):
    paths = {name: root/'extensions/carla'/name for name in
             ('curve_bounds.mojo', 'curve_trig.mojo', 'curve_interval.mojo', 'lane_value_bounds.mojo')}
    texts = {name: path.read_text() for name, path in paths.items()}
    bounds, trig, target = (texts[name] for name in
                            ('curve_bounds.mojo', 'curve_trig.mojo', 'lane_value_bounds.mojo'))
    # Deliberately conservative closure: imports, aliases, all helper setup,
    # branch dispatch and every shared operation in all three reference
    # modules are bound. Any dependency change needs renewed source review.
    require(set(REFERENCE_MODULE_GRAPHS) == {'curve_bounds.mojo', 'curve_trig.mojo', 'curve_interval.mojo'},
            'wrong reference-module closure')
    for filename, expected_hash in REFERENCE_MODULE_GRAPHS.items():
        reference_graph = (dump(reviewed_reference_tree(texts[filename]))
                           if filename == 'curve_bounds.mojo' else graph(texts[filename]))
        actual = hashlib.sha256(reference_graph.encode()).hexdigest()
        require(actual == expected_hash, 'reference module changed; renewed review required: ' + filename)
    require(primitive_graph(texts['curve_interval.mojo']) == PRIMITIVE_GRAPH_SHA256,
            'Jet primitive graph changed; renewed derivative-independence review required')
    # Complete stored helper/interval closure and lexical qualifiers are
    # independent of the unchanged primitive-class AST hash.
    try:
        verify_group(root, 'stored_arithmetic')
        verify_group(root, 'canonical_accumulation')
        try:
            import sum2_contracts
        except ModuleNotFoundError:
            from tools.carla_lane_oracle import sum2_contracts
        sum2_contracts.verify(root)
    except ValueError as error:
        raise CheckError(str(error)) from error
    interval_tree = syntax_tree(texts['curve_interval.mojo'])
    for helper in ('_stored_difference', '_stored_half', '_stored_blend_error',
                   '_without_derivatives'):
        for node in ast.walk(unique_function(interval_tree, helper)):
            require(not (isinstance(node, ast.Attribute) and
                        node.attr in ('first', 'second', 'derivatives')),
                    'derivative-field/flag read in stored helper: ' + helper)
    target_tree = syntax_tree(target)
    reference_trees = {'curve_bounds.mojo': reviewed_reference_tree(bounds), 'curve_trig.mojo': syntax_tree(trig)}
    for key, expected_hash in SHARED_GRAPHS.items():
        filename, name = key.split(':', 1)
        node = unique_function(reference_trees[filename], name)
        actual = hashlib.sha256(dump(node).encode()).hexdigest()
        require(actual == expected_hash, 'shared generic or full-Jet bridge changed: ' + key)
    for node in ast.walk(target_tree):
        require(not (isinstance(node, ast.Attribute) and node.attr in ('first', 'second', 'derivatives', 'sqrt')),
                'derivative-field/flag read or sqrt in value-only graph')
    try:
        for filename, text in texts.items():
            verify_qualifiers(root, filename, text)
    except ValueError as error:
        raise CheckError(str(error)) from error
    actual_imports = [dump(n) for n in target_tree.body if isinstance(n, ast.ImportFrom)]
    expected_imports = [dump(n) for n in ast.parse(IMPORTS).body]
    require(actual_imports == expected_imports, 'sampled graph imports changed')
    expected = {}
    for name in COPIES:
        old = function(trig if name.startswith('_atan') else bounds, name)
        new = translated(old)
        if name == '_sample_blend_jet':
            # Remove only these two complete assignments, never value/error.
            for field in ('first', 'second'):
                pattern = r'(?m)^\s*result\s*\.\s*' + field + r'\s*=\s*_intersect_ideal_bounds\s*\(result\s*\.\s*' + field + r'\s*,\s*ideal\s*\.\s*' + field + r'\s*\)\s*\n'
                new, count = re.subn(pattern, '\n', new, count=1)
                require(count == 1, 'derivative intersection shape changed')
        expected[NAMES[name]] = new
    expected['_uncertain_value'] = '''def _uncertain_value(value: _Interval) -> _ValueJet:
    return _uncertain_expression[False](value)
'''
    # Project complete parsed declarations, never raw prefix/tail slices.
    def reference(filename, name):
        node = unique_function(syntax_tree(translated(function(texts[filename], name))), NAMES.get(name, name))
        node.decorator_list = copy.deepcopy(unique_function(reference_trees[filename], name).decorator_list)
        return copy.deepcopy(node)

    def declaration(source):
        return syntax_tree(source).body[0]

    def shape(nodes):
        """Each complete top-level statement has an explicit reviewed role."""
        result = []
        for node in nodes:
            if isinstance(node, ast.Assign):
                result.append('assign:' + ast.unparse(node.targets[0]))
            elif isinstance(node, ast.AnnAssign):
                result.append('annotate:' + ast.unparse(node.target))
            elif isinstance(node, ast.If):
                result.append('if:' + ast.unparse(node.test))
            elif isinstance(node, ast.Return):
                result.append('return')
            else:
                result.append(type(node).__name__)
        return result

    union = declaration('''def _union_value_points(
        one: Tuple[_ValueJet, _ValueJet, _ValueJet],
        two: Tuple[_ValueJet, _ValueJet, _ValueJet],
    ) -> Tuple[_ValueJet, _ValueJet, _ValueJet]:
        pass
''')
    old = reference('curve_bounds.mojo', '_union_points')
    require(shape(old.body) == ['return'], 'union complete body shape changed')
    union.body = old.body
    expected['_union_value_points'] = union

    sampled = declaration('''def _reference_sampled_value(
        geometry: RoadGeometry, distance: _ValueJet, translation: Vector3
    ) -> Tuple[_ValueJet, _ValueJet, _ValueJet]:
        if geometry.kind != POLY3 and geometry.kind != PARAM_POLY3:
            return _unknown_value_point()
''')
    old = reference('curve_bounds.mojo', '_reference_jet_capture')
    require(shape(old.body) == [
        'assign:d', 'if:geometry.kind == LINE', 'if:geometry.kind == ARC',
        'if:geometry.kind == SPIRAL', 'if:len(geometry.samples) < 2',
        'assign:domain', 'assign:low', 'assign:high', 'if:high - low > 1',
        'assign:first', 'if:low == high', 'return',
    ], 'complete reference dispatcher layout changed')
    # Remove precisely the three complete non-sampled branches. The new
    # leading guard rejects those kinds; the independent broad wrapper
    # provides the full-Jet SPIRAL bridge. All 12 statements are accounted for.
    sampled.body += [old.body[0]] + old.body[4:]
    expected['_reference_sampled_value'] = sampled

    for name, filename in (('_sinc_jet', 'curve_trig.mojo'),
                           ('_arc_offset_jet', 'curve_bounds.mojo')):
        expected[NAMES[name]] = reference(filename, name)

    constant = reference('curve_trig.mojo', '_constant_sincos_jet')
    require(shape(constant.body) == ['assign:result',
        'if:not isfinite(heading) or abs(heading) > _PHASE_LIMIT',
        'assign:zero', 'return'], 'constant heading layout changed')
    require(dump(constant.body[2]) == dump(ast.parse('zero = _Interval.point(0.0)').body[0]),
            'constant heading derivative constructor changed')
    constant.body[2] = ast.parse('unknown = _Interval.whole()').body[0]
    returned = constant.body[3].value
    require(isinstance(returned, ast.Tuple) and len(returned.elts) == 2,
            'constant heading result shape changed')
    for index, item in enumerate(returned.elts):
        required = ast.parse('_ValueJet(result[' + str(index) +
            '].rounded_value(), zero, zero, 0.0)', mode='eval').body
        require(dump(item) == dump(required), 'constant heading field projection changed')
        # Only derivative constructor fields change. Coefficient enclosure,
        # exact-zero scalar error, result ordering and guards are retained.
        item.args[1:3] = [ast.Name(id='unknown', ctx=ast.Load()),
                          ast.Name(id='unknown', ctx=ast.Load())]
    expected['_constant_sincos_value'] = constant

    expected['_sampled_lane_value_bound'] = '''def _sampled_lane_value_bound(
        road: Road, section: Int, lane: Int, low: Float64, high: Float64
    ) raises -> Tuple[_ValueJet, _ValueJet, _ValueJet]:
        return _lane_value_bound_impl[False](road, section, lane, low, high)
'''
    expected['_lane_value_bound'] = '''def _lane_value_bound(
        road: Road, section: Int, lane: Int, low: Float64, high: Float64
    ) raises -> Tuple[_ValueJet, _ValueJet, _ValueJet]:
        var at = info_index(road.info.geometries, low)
        if at >= 0 and road.info.geometries[at].geometry.kind == SPIRAL:
            var full = _lane_jet(road, section, lane, low, high)
            return (_without_derivatives(full[0]), _without_derivatives(full[1]),
                    _without_derivatives(full[2]))
        return _lane_value_bound_impl[True](road, section, lane, low, high)
'''
    lane = declaration('''def _lane_value_bound_impl[all_geometry: Bool](
        road: Road, section: Int, lane: Int, low: Float64, high: Float64,
    ) raises -> Tuple[_ValueJet, _ValueJet, _ValueJet]:
        var translation = Vector3(0, 0, 0)
''')
    old = reference('curve_bounds.mojo', '_lane_jet_model_proof')
    # This private value-only specialization has no cached proof argument.
    # Remove only the exact new refusal branch whose proof condition is false
    # for that route. The full cached-proof caller remains separately bound.
    require(dump(old.body[0]) == dump(ast.parse("""if proof and not _sum2_supported_environment():
    return _unknown_value_point()
""").body[0]), 'cached-proof environment refusal changed or moved')
    old.body.pop(0)
    require(shape(old.body) == [
        'assign:geometry_at', 'assign:elevation_at', 'assign:offset_at',
        'if:geometry_at < 0 or elevation_at < 0 or offset_at < 0',
        'if:info_index(road.info.geometries, high) != geometry_at or info_index(road.info.elevations, high) != elevation_at or info_index(road.info.lane_offsets, high) != offset_at',
        'assign:s', 'assign:offset', 'assign:lanes', 'assign:lane_id',
        'assign:negative', 'assign:sign', 'if:lane_id.value != 0',
        'assign:offset', 'assign:record', 'if:capture',
        'if:record.geometry.kind == ARC', 'if:record.geometry.kind == LINE',
        'annotate:reused', 'if:not capture', 'annotate:point', 'if:reused',
        'assign:trig', 'return',
    ], 'complete lane dispatcher layout changed')
    require(dump(old.body[14]) == dump(ast.parse('''if capture:
        captured.record_at = geometry_at
        captured.low = low
        captured.high = high
''').body[0]), 'capture bookkeeping projection changed')
    # 0..13: all record checks/width traversal/elevation setup are retained.
    # 14: the exact capture-only assignments above are deleted.
    # 15..16: complete ARC/LINE branches move under all_geometry, in order.
    # 17..20: complete proof/capture dispatch is replaced by a sampled call.
    # This replacement is justified only by _reference_sampled_value's kind
    # guard and the separately bound SPIRAL full-Jet wrapper, never by a
    # claim that the proof branch is value-independent. Whole reference
    # modules bind every removed proof statement and its dependencies.
    # 21..22: original trig and final output are retained, without slicing.
    lane.body += old.body[:14]
    lane.body += [ast.If(test=ast.Name(id='all_geometry', ctx=ast.Load()),
                        body=old.body[15:17], orelse=[])]
    lane.body += ast.parse('''point = _reference_sampled_value(
        record.geometry, _stored_difference(s, _ValueJet.constant(record.s)), translation)
''').body + old.body[21:]
    expected['_lane_value_bound_impl'] = lane
    functions = {n.name for n in target_tree.body if isinstance(n, ast.FunctionDef)}
    require(functions == set(expected), 'missing or extra sampled helper')
    for node in target_tree.body:
        require(isinstance(node, (ast.ImportFrom, ast.FunctionDef)) or
                (isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str)),
                'unexpected top-level execution in sampled graph')
    for name, source in expected.items():
        wanted = (unique_function(syntax_tree(source), name)
                  if isinstance(source, str) else source)
        if name in {NAMES[n] for n in COPIES}:
            original = next(n for n in COPIES if NAMES[n] == name)
            filename = 'curve_trig.mojo' if original.startswith('_atan') else 'curve_bounds.mojo'
            # Decorators are part of the actual declarations, not dropped by
            # a text slice starting at def. Current copies have none.
            wanted.decorator_list = unique_function(reference_trees[filename], original).decorator_list
        actual = unique_function(target_tree, name)
        require(dump(wanted) == dump(actual),
                'sampled helper diverged: ' + name)
    return {'status': 'PASS', 'repo_root': str(root.resolve()), 'copied_functions': 8, 'dispatch_functions': 6, 'additional_source_pairs': 3, 'shared_generic_and_bridge_functions': len(SHARED_GRAPHS),
            'complete_reference_modules': len(REFERENCE_MODULE_GRAPHS),
            'primitive_graph_sha256': PRIMITIVE_GRAPH_SHA256,
            'source_sha256': {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in paths.items()},
            'scope': 'Complete explicit sampled/ARC/LINE correspondence and SPIRAL bridge with stored-arithmetic closure; source binding is not mathematical/runtime qualification. Separate eligibility/translation/support source gate, native/codegen/budget/coverage/performance remain required'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo-root', type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        result = verify(args.repo_root.resolve())
    except (CheckError, OSError, SyntaxError, ValueError) as error:
        print('FAIL:', error)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
