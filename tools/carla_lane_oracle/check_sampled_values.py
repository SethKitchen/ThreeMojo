#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Read-only source correspondence for derivative-elided sampled bounds.

Copied declarations are sliced, renamed, and classified by the Mojo text gate.
The syntax correspondence still uses the Python standard library. Numeric grouping,
branches, imports and retained value/error operations are checked against the
full-Jet source. Primitive changes require renewed review.
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
import ast
import hashlib
# #333 explicit historical provenance views; current inputs remain operation-owned.
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


def _sampled_text(mode, text, name='', index=None, replacement=None):
    """Slice, rename, or dump one declaration with the Mojo text gate."""
    import os
    import subprocess
    import tempfile
    root = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(root / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='sampled-text-') as directory:
        path = Path(directory) / 'source.mojo'
        path.write_text(text)
        command = ['sh', str(root / 'tools' / 'tool.sh'), mojo,
                   'carla_sampled_text', mode, str(path)]
        if name:
            command.extend(['--name', name])
        if index is not None:
            command.extend(['--index', str(index)])
        if replacement is not None:
            repl = Path(directory) / 'replacement.mojo'
            repl.write_text(replacement)
            command.extend(['--with', str(repl)])
        result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        for prefix in ('sampled value gate: ', 'sampled jet gate: '):
            if message.startswith(prefix):
                message = message[len(prefix):]
        raise CheckError(message)
    return result.stdout


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
    # The declaration count is a token check. The class hash below stays on
    # the Python syntax tree.
    _sampled_text('--primitive-declaration', text)
    require(len(found) == 1, 'unsupported primitive declaration')
    _sampled_text('--primitive-aliases', text)
    return hashlib.sha256(dump(found[0]).encode()).hexdigest()



def reviewed_reference_tree(text, root=ROOT, *, _operation=None):
    """Retain the historical reference graph after one exact additive refusal.

    Default False preserves every existing call. True may return unknown
    before the unchanged GL fallback; it cannot perform unreserved work.
    The production tokens and grouped True caller are bound separately.
    """
    try:
        try:
            import full_audit_cleanup_contracts as full_audit
        except ModuleNotFoundError:
            from tools.carla_lane_oracle import full_audit_cleanup_contracts as full_audit
        text = full_audit.reviewed_text(root, 'extensions/carla/curve_bounds.mojo', text, _operation=_operation)
    except (ValueError, OSError) as error:
        raise CheckError('reference module changed; renewed review required: curve_bounds.mojo: ' + str(error)) from error
    # The reviewed no-counter-alias successor changes only optional admission.
    # Reconstruct its exact historical helper before the original projection;
    # every original reference graph digest remains unchanged.
    try:
        try:
            import envelope_budget_contracts as budget
        except ModuleNotFoundError:
            from tools.carla_lane_oracle import envelope_budget_contracts as budget
        previous = budget.historical_function(text, root=root)
    except ValueError as error:
        raise CheckError('reference module changed; renewed review required: curve_bounds.mojo: ' + str(error)) from error
    try:
        try:
            from ideal_projection import _try_only_gate
        except ModuleNotFoundError:
            from tools.carla_lane_oracle.ideal_projection import _try_only_gate
        _try_only_gate(text)
    except ValueError as error:
        raise CheckError(str(error)) from error
    tree = syntax_tree(_sampled_text(
        '--replace-function', _sampled_text('--strip-try-only', text),
        '_try_lane_envelope_capture', replacement=previous))
    return tree


def _source_digests(blobs):
    """Return SHA-256 hex digests of observed bytes, in order."""
    import os
    import subprocess
    import tempfile
    framed = b''.join(
        str(len(raw)).encode('ascii') + b'\n' + raw for raw in blobs)
    repo = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(repo / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='sampled-source-sha-') as directory:
        path = Path(directory) / 'frame.bin'
        path.write_bytes(framed)
        result = subprocess.run(
            ['sh', str(repo / 'tools' / 'tool.sh'), mojo,
             'carla_source_sha256', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        raise ValueError(message)
    digests = json.loads(result.stdout)
    if len(digests) != len(blobs):
        raise ValueError('sampled source frame changed')
    return digests


def _sampled_result(root, shared, modules, primitive, sources, successors):
    """Return the sampled-value result in historical field order."""
    import ast
    import os
    import subprocess
    import tempfile
    payload = json.dumps({
        'root': root, 'shared': shared, 'modules': modules,
        'primitive': primitive, 'sources': sources,
        'successors': successors,
    }, separators=(',', ':'))
    repo = Path(__file__).resolve().parents[2]
    mojo = os.environ.get('MOJO', str(repo / '.venv' / 'bin' / 'mojo'))
    with tempfile.TemporaryDirectory(prefix='sampled-value-result-') as directory:
        path = Path(directory) / 'result.json'
        path.write_text(payload)
        result = subprocess.run(
            ['sh', str(repo / 'tools' / 'tool.sh'), mojo,
             'carla_sampled_value_result', str(path)],
            capture_output=True, text=True)
    if result.returncode != 0:
        lines = [line.strip() for line in result.stderr.splitlines()
                 if line.strip() and 'Crashpad' not in line]
        message = lines[-1] if lines else result.stdout.strip()
        prefix = 'KeyError: '
        if message.startswith(prefix):
            raise KeyError(ast.literal_eval(message[len(prefix):])) from None
        raise ValueError(message)
    return json.loads(result.stdout)


@source.lexical_memo_scope()
def verify(root):
    if __package__:
        from . import full_audit_cleanup_contracts as audit
    else:
        import full_audit_cleanup_contracts as audit
    _operation, owns = audit._operation_enter(root, 'sampled')
    try:
        paths = {name: root/'extensions/carla'/name for name in
                 ('curve_bounds.mojo', 'curve_trig.mojo', 'curve_interval.mojo', 'lane_value_bounds.mojo')}
        texts = {name: _typed_source.historical_text(root, path, _typed_source._observe_text(root, (path).relative_to(root).as_posix(), path.read_text(), _operation=_operation), _operation=_operation) for name, path in paths.items()}
        bounds, trig, target = (texts[name] for name in
                                ('curve_bounds.mojo', 'curve_trig.mojo', 'lane_value_bounds.mojo'))
        # Deliberately conservative closure: imports, aliases, all helper setup,
        # branch dispatch and every shared operation in all three reference
        # modules are bound. Any dependency change needs renewed source review.
        try:
            if __package__:
                from . import ideal_projection
            else:
                import ideal_projection
            ideal_projection.moment_guard('--names', {
                'names': list(REFERENCE_MODULE_GRAPHS),
                'expected': ['curve_bounds.mojo', 'curve_trig.mojo',
                             'curve_interval.mojo'],
                'message': 'wrong reference-module closure',
            })
        except ValueError as error:
            raise CheckError(str(error)) from error
        for filename, expected_hash in REFERENCE_MODULE_GRAPHS.items():
            reference_graph = (dump(reviewed_reference_tree(texts[filename], root, _operation=_operation))
                               if filename == 'curve_bounds.mojo' else graph(texts[filename]))
            actual = hashlib.sha256(reference_graph.encode()).hexdigest()
            require(actual == expected_hash, 'reference module changed; renewed review required: ' + filename)
        require(primitive_graph(texts['curve_interval.mojo']) == PRIMITIVE_GRAPH_SHA256,
                'Jet primitive graph changed; renewed derivative-independence review required')
        # Complete stored helper/interval closure and lexical qualifiers are
        # independent of the unchanged primitive-class AST hash.
        try:
            verify_group(root, 'stored_arithmetic', _operation=_operation)
            verify_group(root, 'canonical_accumulation', _operation=_operation)
            try:
                import sum2_contracts
            except ModuleNotFoundError:
                from tools.carla_lane_oracle import sum2_contracts
            sum2_contracts.verify(root, _operation=_operation)
        except ValueError as error:
            raise CheckError(str(error)) from error
        _sampled_text('--helper-fields', texts['curve_interval.mojo'])
        target_tree = syntax_tree(target)
        reference_trees = {'curve_bounds.mojo': reviewed_reference_tree(bounds, root, _operation=_operation), 'curve_trig.mojo': syntax_tree(trig)}
        for key, expected_hash in SHARED_GRAPHS.items():
            filename, name = key.split(':', 1)
            node = unique_function(reference_trees[filename], name)
            actual = hashlib.sha256(dump(node).encode()).hexdigest()
            require(actual == expected_hash, 'shared generic or full-Jet bridge changed: ' + key)
        _sampled_text('--value-fields', target)
        try:
            for filename, text in texts.items():
                verify_qualifiers(root, filename, text, _operation=_operation)
        except ValueError as error:
            raise CheckError(str(error)) from error
        _sampled_text('--value-imports', target)
        expected = {}
        for name in COPIES:
            old = _sampled_text(
                '--extract', trig if name.startswith('_atan') else bounds, name)
            new = _sampled_text('--rename', old)
            if name == '_sample_blend_jet':
                # Remove only these two complete assignments, never value/error.
                for field in ('first', 'second'):
                    new = _sampled_text('--drop-intersection', new, field)
            filename = 'curve_trig.mojo' if name.startswith('_atan') else 'curve_bounds.mojo'
            expected[NAMES[name]] = _sampled_text('--decorators', texts[filename], name) + new
        expected['_uncertain_value'] = '''def _uncertain_value(value: _Interval) -> _ValueJet:
        return _uncertain_expression[False](value)
    '''
        # Project complete parsed declarations, never raw prefix/tail slices.
        def renamed_source(filename, name):
            return _sampled_text(
                '--rename', _sampled_text('--extract', texts[filename], name))

        def with_decorators(filename, original, text):
            return _sampled_text('--decorators', texts[filename], original) + text

        old = renamed_source('curve_bounds.mojo', '_union_points')
        _sampled_text('--check-roles', old, 'union')
        expected['_union_value_points'] = _sampled_text('--project-union', old)

        old = renamed_source('curve_bounds.mojo', '_reference_jet_capture')
        _sampled_text('--check-roles', old, 'reference')
        # Remove precisely the three complete non-sampled branches. The new
        # leading guard rejects those kinds; the independent broad wrapper
        # provides the full-Jet SPIRAL bridge. All 12 statements are accounted for.
        expected['_reference_sampled_value'] = _sampled_text('--project-reference', old)

        for name, filename in (('_sinc_jet', 'curve_trig.mojo'),
                               ('_arc_offset_jet', 'curve_bounds.mojo')):
            expected[NAMES[name]] = with_decorators(
                filename, name, renamed_source(filename, name))

        constant = renamed_source('curve_trig.mojo', '_constant_sincos_jet')
        _sampled_text('--check-roles', constant, 'constant')
        require(_sampled_text('--body-dump', constant, index=2) == dump(ast.parse(
            'zero = _Interval.point(0.0)').body[0]),
                'constant heading derivative constructor changed')
        elements = json.loads(_sampled_text('--return-pair', constant, index=3))
        for index, _item in enumerate(elements):
            required = ast.parse('_ValueJet(result[' + str(index) +
                '].rounded_value(), zero, zero, 0.0)', mode='eval').body
            require(elements[index] == dump(required), 'constant heading field projection changed')
        # Only derivative constructor fields change. Coefficient enclosure,
        # exact-zero scalar error, result ordering and guards are retained.
        expected['_constant_sincos_value'] = with_decorators(
            'curve_trig.mojo', '_constant_sincos_jet',
            _sampled_text('--project-constant', constant))

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
        old = renamed_source('curve_bounds.mojo', '_lane_jet_model_proof')
        # This private value-only specialization has no cached proof argument.
        # Remove only the exact new refusal branch whose proof condition is false
        # for that route. The full cached-proof caller remains separately bound.
        require(_sampled_text('--body-dump', old, index=0) == dump(ast.parse("""if proof and not _sum2_supported_environment():
        return _unknown_value_point()
    """).body[0]), 'cached-proof environment refusal changed or moved')
        _sampled_text('--check-roles', old, 'lane')
        require(_sampled_text('--body-dump', old, index=15) == dump(ast.parse('''if capture:
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
        expected['_lane_value_bound_impl'] = _sampled_text('--project-lane', old)
        _sampled_text('--top-level', target, ','.join(sorted(expected)))
        for name, source in expected.items():
            # Decorators stay on the copied text. The syntax tree is the
            # independent comparison with the sampled module.
            wanted = unique_function(syntax_tree(source), name)
            actual = unique_function(target_tree, name)
            require(dump(wanted) == dump(actual),
                    'sampled helper diverged: ' + name)
        current_edges = audit.typed_successor_edges(root, _operation=_operation)
        observed = [audit._observe_bytes(
            root, path.relative_to(root).as_posix(), path.read_bytes(),
            _operation=_operation) for path in paths.values()]
        digests = _source_digests(observed)
        physical_sources = {
            name: digest for name, digest in zip(paths, digests)}
        if owns:
            _operation.finish(root)
        return _sampled_result(
            str(root.resolve()), len(SHARED_GRAPHS),
            len(REFERENCE_MODULE_GRAPHS), PRIMITIVE_GRAPH_SHA256,
            physical_sources, current_edges)
    finally:
        if owns:
            _operation.close()


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
    # The CLI uses the canonical registered module, so its public verifier
    # can own one physical capture just like an imported invocation.
    from check_sampled_values import main as _owned_main
    raise SystemExit(_owned_main())
