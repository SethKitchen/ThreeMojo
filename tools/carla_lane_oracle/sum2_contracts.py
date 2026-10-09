#!/usr/bin/env python3
# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
"""Narrow semantic contracts for the reviewed canonical stored-term Sum2 graph.

The literal declarations below are the reviewed mathematical/compiler source
checkpoint, not an automatically refreshed digest. AST equality binds the
original recurrence and arithmetic leaf. Complete lexical contracts retain
the environment guard, keyword subscripts, callers and decorators; dependency
and qualifier token gates separately cover the surrounding modules. This
checker never executes Mojo and cannot qualify native code generation.
"""
import ast
import copy
if __package__:
    from . import sum2_guard_contracts as guards
else:
    import sum2_guard_contracts as guards
import json
from pathlib import Path

if __package__:
    from .ideal_projection import verify_projection
else:
    from ideal_projection import verify_projection

# Initial accepted arithmetic checkpoint. The guarded and final format/doc
# source bindings are preserved in sum2-correspondence-migration.json.
REVIEWED_HELPER_SHA256 = '41995592963bae61a2b690b465bdad6c759b02ddbe98141ba5da30d0df5d5c8e'

HELPER = '''
from extensions.carla.curve_interval import _Interval
from std.math import inf, isfinite


@no_inline
def _sum2_update(
    total: Float64, correction: Float64, term: Float64
) -> Tuple[Float64, Float64]:
    # Knuth TwoSum. The six separately rounded additions/subtractions recover
    # the exact residual of total + term, including gradual underflow.
    var high = total + term
    var virtual_term = high - total
    var virtual_total = high - virtual_term
    var total_error = total - virtual_total
    var term_error = term - virtual_term
    var residual = total_error + term_error
    return (high, correction + residual)


def _sum2_error(
    magnitude: Float64, inherited: Float64, count: Int
) -> Float64:
    # For every point in the complete input domain, magnitude bounds the sum
    # of absolute stored terms and inherited bounds their total input error.
    # Sum2: |computed - exact sum(stored terms)| <= u*|sum| + gamma_(n-1)^2*M.
    # We conservatively use |sum| <= M. The guarded range keeps the ordinary
    # partial sum, correction and every TwoSum subtraction below overflow.
    if (
        count < 1
        or count > 1073741824
        or not isfinite(magnitude)
        or magnitude < 0.0
        or magnitude > 8.452712498170644e270
        or not isfinite(inherited)
        or inherited < 0.0
    ):
        return inf[DType.float64]()
    if magnitude == 0.0:
        return inherited
    if count == 1:
        return inherited
    var u = _Interval.point(1.1102230246251565e-16)
    var nu = _Interval.point(Float64(count - 1)) * u
    var gamma = nu / (_Interval.point(1.0) - nu)
    return (
        _Interval.point(inherited)
        + (u + gamma * gamma) * _Interval.point(magnitude)
    ).high
'''

SCALAR = '''
def _lane_spiral(geometry: RoadGeometry, d: Float64) -> DirectedPoint:
    var k0 = geometry.curvature_start
    var rate = (
        geometry.curvature_end - geometry.curvature_start
    ) / geometry.length
    var reach = max(abs(k0), abs(k0 + rate * d))
    var pieces = 1 + Int(ceil(d * (1.0 + reach)))
    var step = d / Float64(pieces)
    var nodes = materialize[_GL_NODES]()
    var weights = materialize[_GL_WEIGHTS]()
    # Accumulate displacement before adding the origin. Repeatedly
    # rounding a large world origin would discard small quadrature terms.
    var x = Float64(0.0)
    var y = Float64(0.0)
    var x_correction = Float64(0.0)
    var y_correction = Float64(0.0)
    for piece in range(pieces):  # pragma: no branch
        var start = step * Float64(piece)
        for i in range(5):  # pragma: no branch
            var t = start + step * 0.5 * (1.0 + nodes[i])
            var theta = geometry.heading + t * (k0 + 0.5 * rate * t)
            # Non-inlined Sum2 calls materialize the complete products.
            # A named intermediate alone would not prevent contraction.
            var next_x = _sum2_update(
                x, x_correction, step * 0.5 * weights[i] * cos(theta)
            )
            var next_y = _sum2_update(
                y, y_correction, step * 0.5 * weights[i] * sin(theta)
            )
            x = next_x[0]
            x_correction = next_x[1]
            y = next_y[0]
            y_correction = next_y[1]
    return DirectedPoint(
        geometry.x + (x + x_correction),
        geometry.y + (y + y_correction),
        0.0,
        geometry.heading + d * (k0 + 0.5 * rate * d),
    )


'''

ENVELOPE = '''
def _sum2_envelope_error(
    term: _ValueJet, count: Int, origin: Float64
) -> Float64:
    if count < 1 or count > 320 or not isfinite(origin):
        return inf[DType.float64]()
    if (
        not term.value.is_finite()
        or not isfinite(term.error)
        or term.error < 0.0
    ):
        return inf[DType.float64]()
    var n = _Interval.point(Float64(count))
    var absolute_sum = n * _Interval.point(term.rounded_value().magnitude())
    var inherited = n * _Interval.point(term.error)
    var error = _sum2_error(absolute_sum.high, inherited.high, count)
    if not isfinite(error):
        return inf[DType.float64]()
    var ideal_magnitude = (n * _Interval.point(term.value.magnitude())).high
    var accumulated = _ValueJet(
        _Interval(-ideal_magnitude, ideal_magnitude),
        _Interval.whole(),
        _Interval.whole(),
        error,
    )
    var translated = _ValueJet.constant(origin) + accumulated
    if not translated.rounded_value().is_finite():
        return inf[DType.float64]()
    return translated.error


'''


ELIGIBILITY = '''
def _try_spiral_roundoff_envelope(
    geometry: RoadGeometry, d: _Jet, pieces: Int
) -> Optional[Tuple[Float64, Float64]]:
    # The caller supplies the original clamped distance Jet and fixed count.
    # This does not enlarge the existing moment model's heading/k0 domain.
    if (
        geometry.kind != SPIRAL
        or geometry.heading != 0.0
        or geometry.curvature_start != 0.0
    ):
        return None
    if (
        pieces < 1
        or pieces > 64
        or not isfinite(geometry.length)
        or geometry.length <= 0.0
    ):
        return None
    if (
        not isfinite(geometry.x)
        or not isfinite(geometry.y)
        or not isfinite(geometry.curvature_end)
    ):
        return None
    var rate_value = (
        geometry.curvature_end - geometry.curvature_start
    ) / geometry.length
    if not isfinite(rate_value):
        return None
    var domain = d.rounded_value()
    if (
        not domain.is_finite()
        or domain.low <= 0.0
        or domain.high >= geometry.length
    ):
        return None
    if not d.value.is_finite() or not isfinite(d.error) or d.error < 0.0:
        return None
    var distance = _ValueJet(
        d.value, _Interval.whole(), _Interval.whole(), d.error
    )
    var nodes = materialize[_GL_NODES]()
    var weights = materialize[_GL_WEIGHTS]()
    var node_low = 1.0 + nodes[0]
    var node_high = node_low
    var weight_low = weights[0]
    var weight_high = weight_low
    for i in range(1, 5):
        var node = 1.0 + nodes[i]
        node_low = min(node_low, node)
        node_high = max(node_high, node)
        weight_low = min(weight_low, weights[i])
        weight_high = max(weight_high, weights[i])
    var step = distance / _ValueJet.constant(Float64(pieces))
    var start = step * _envelope_constant(0.0, Float64(pieces - 1))
    var t = start + step * _ValueJet.constant(0.5) * _envelope_constant(
        node_low, node_high
    )
    var theta = _ValueJet.constant(geometry.heading) + t * (
        _ValueJet.constant(geometry.curvature_start)
        + _ValueJet.constant(0.5) * _ValueJet.constant(rate_value) * t
    )
    # The complete original rounded phase-selection graph must select zero.
    # No ideal beta*d*d estimate replaces the node-specific rounding graph.
    var phase = theta.rounded_value()
    if not phase.is_finite() or phase.magnitude() > _PHASE_LIMIT:
        return None
    var selection = (
        theta * _ValueJet.constant(_INV_HALF_PI) + _ValueJet.constant(0.5)
    ).rounded_value()
    if (
        not selection.is_finite()
        or floor(selection.low) != 0.0
        or floor(selection.high) != 0.0
    ):
        return None
    var trig = _sincos_expression(theta)
    var factor = (
        step
        * _ValueJet.constant(0.5)
        * _envelope_constant(weight_low, weight_high)
    )
    var x = factor * trig[1]
    var y = factor * trig[0]
    var x_error = _sum2_envelope_error(x, 5 * pieces, geometry.x)
    var y_error = _sum2_envelope_error(y, 5 * pieces, geometry.y)
    if not isfinite(x_error) or not isfinite(y_error):
        return None
    return (x_error, y_error)
'''

def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify_binding(tree, name, allowed_definition=None, allowed_import=None):
    """Reject every lexical binding form that could replace a reviewed helper."""
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            require(not any(alias.name == '*' for alias in node.names),
                    'wildcard import can shadow reviewed helper: ' + name)
            if node is not allowed_import:
                require(not any((alias.asname or alias.name) == name for alias in node.names),
                        'reviewed helper import alias shadows: ' + name)
        elif isinstance(node, ast.Import):
            require(not any((alias.asname or alias.name.split('.')[0]) == name
                            for alias in node.names),
                    'reviewed helper module alias shadows: ' + name)
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            require(node.name != name or node is allowed_definition,
                    'reviewed helper declaration shadows: ' + name)
        elif isinstance(node, ast.Name) and isinstance(node.ctx, (ast.Store, ast.Del)):
            require(node.id != name, 'reviewed helper assignment shadows: ' + name)
        elif isinstance(node, ast.arg):
            require(node.arg != name, 'reviewed helper parameter shadows: ' + name)
        elif isinstance(node, ast.ExceptHandler):
            require(node.name != name, 'reviewed helper exception binding shadows: ' + name)


def verify(root):
    # Lazy import avoids a checker-module cycle; no source is executed.
    if __package__:
        from . import check_sampled_values as c
    else:
        import check_sampled_values as c
    names = ('curve_sum2', 'lane_geometry', 'curve_bounds', 'spiral_roundoff_proof')
    texts = {name: (root / ('extensions/carla/' + name + '.mojo')).read_text()
             for name in names}
    guard_result = guards.verify(root)
    # Validate actual selector producers before restoring the exact historical
    # eligibility helper for the retained complete-function comparison.
    if __package__:
        from . import selection_finiteness_contracts as selection
    else:
        import selection_finiteness_contracts as selection
    texts['spiral_roundoff_proof'] = selection.predecessor_text(
        root, 'extensions/carla/spiral_roundoff_proof.mojo')

    trees = {name: c.syntax_tree(text) for name, text in texts.items()
             if name != 'curve_sum2'}
    # The complete lexical contract above retains all keyword-subscripts and
    # decorators. Separately relate the unchanged arithmetic leaf/recurrence
    # to the initial station-reviewed declarations using actual token spans.
    previous = c.syntax_tree(HELPER)
    update = c.unique_function(c.syntax_tree(guards.declaration(
        texts['curve_sum2'], '_sum2_update')), '_sum2_update')
    expected_update = c.unique_function(previous, '_sum2_update')
    require(c.dump(update) == c.dump(expected_update), 'Sum2 recurrence changed')
    leaf = c.unique_function(c.syntax_tree(guards.declaration(
        texts['curve_sum2'], '_sum2_error_checked')), '_sum2_error_checked')
    leaf.name = '_sum2_error'
    require(c.dump(leaf) == c.dump(c.unique_function(previous, '_sum2_error')),
            'Sum2 checked arithmetic leaf changed')
    for module, name, expected in (
            ('lane_geometry', '_lane_spiral', SCALAR),
            ('spiral_roundoff_proof', '_sum2_envelope_error', ENVELOPE),
            ('spiral_roundoff_proof', '_try_spiral_roundoff_envelope', ELIGIBILITY)):
        actual = copy.deepcopy(c.unique_function(trees[module], name))
        if name == '_lane_spiral':
            require(c.dump(actual.body[0]) == c.dump(ast.parse(
                '_require_sum2_environment()').body[0]), 'scalar environment check moved')
            actual.body.pop(0)
        wanted = c.unique_function(c.syntax_tree(expected), name)
        require(c.dump(actual) == c.dump(wanted),
                'Sum2 complete caller graph changed: ' + name)
    # Require the exact direct import inventory and reject all shadow forms.
    for module, helpers in (
            ('lane_geometry', ('_sum2_update', '_require_sum2_environment')),
            ('curve_bounds', ('_sum2_error_checked', '_sum2_supported_environment')),
            ('spiral_roundoff_proof', ('_sum2_error',))):
        matches = [node for node in trees[module].body
                   if isinstance(node, ast.ImportFrom)
                   and node.module == 'extensions.carla.curve_sum2']
        require(len(matches) == 1 and
                [(alias.name, alias.asname) for alias in matches[0].names] ==
                [(name, None) for name in helpers],
                'Sum2 direct helper import changed: ' + module)
        for helper in helpers:
            verify_binding(trees[module], helper, allowed_import=matches[0])
    pins = json.loads((root / 'tools/carla_lane_oracle/spiral-moment-pins.json').read_text())
    interval = (root / 'extensions/carla/curve_interval.mojo').read_text()
    interval_tree = c.syntax_tree(interval)
    half = c.unique_function(interval_tree, '_stored_half')
    half_imports = [node for node in trees['curve_bounds'].body
                    if isinstance(node, ast.ImportFrom)
                    and any(alias.name == '_stored_half' or alias.asname == '_stored_half'
                            for alias in node.names)]
    require(len(half_imports) == 1
            and half_imports[0].module == 'extensions.carla.curve_interval'
            and [(alias.name, alias.asname) for alias in half_imports[0].names
                 if alias.name == '_stored_half' or alias.asname == '_stored_half']
                == [('_stored_half', None)], 'stored-half direct import changed')
    verify_binding(trees['curve_bounds'], '_stored_half', allowed_import=half_imports[0])
    verify_binding(interval_tree, '_stored_half', allowed_definition=half)
    projection = verify_projection(pins['ideal_projection']['legacy_normalized_source'],
        c.unique_function(trees['curve_bounds'], '_spiral_expression'), half)
    return {'status': 'PASS', 'recurrence_operations': 6, 'correction_additions': 1,
            'scalar_axes': 2, 'initialization': 'positive zero',
            'term_count': '5 * pieces', 'bound': 'E + (u + gamma_(n-1)^2) M',
            'arithmetic_premises': 'nearest rounding, gradual underflow, rounded terms, no reassociation or intermediate overflow',
            'ideal_projection': projection, 'environment_guard': guard_result,
            'native_codegen_qualified': False}
