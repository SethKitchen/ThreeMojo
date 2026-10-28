# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed Sum2 caller graphs.

The recurrence and the checked leaf match the arithmetic checkpoint.
The scalar spiral keeps the environment call and the reviewed body.
The envelope and the roundoff predecessor match their checkpoints.
"""

from tests._python_tokens import _tokenize
from tools._sampled_value_copies import _body_statements, _normalize, _span


comptime _HELPER = """
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
"""
comptime _SCALAR = """
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


"""
comptime _ENVELOPE = """
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


"""
comptime _ELIGIBILITY = """
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
"""


def _fail(message: String) raises:
    """Raise a Sum2 caller-graph error.

    Args:
        message: The failure text.

    Raises:
        Error: A reviewed Sum2 graph changed.
    """
    raise Error(message)


def _tokens(source: String) raises -> Tuple[List[Int], List[String]]:
    """Tokenize `source`.

    Args:
        source: Module source.

    Returns:
        The token kinds and texts.

    Raises:
        Error: The source cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    return (kinds^, texts^)


def _function(source: String, name: String) raises -> String:
    """Return the normalized text of `name`, from `def` through the body.

    Args:
        source: The module source.
        name: The function name.

    Returns:
        The normalized function.

    Raises:
        Error: The function is missing or has no body.
    """
    var tokens = _tokens(source)
    var span = _span(tokens[0], tokens[1], name)
    return _normalize(tokens[0], tokens[1], span[0], span[1], False)


def _rows(source: String, name: String) raises -> List[String]:
    """Return the normalized body statements of `name`.

    Args:
        source: The module source.
        name: The function name.

    Returns:
        Each direct body statement.

    Raises:
        Error: The function is missing or has no body.
    """
    var tokens = _tokens(source)
    return _body_statements(tokens[0], tokens[1], name, False)


def _same(
    actual: String,
    actual_name: String,
    expected: String,
    expected_name: String,
    message: String,
) raises:
    """Require two functions to have the same normalized text.

    Args:
        actual: The module under test.
        actual_name: The function under test.
        expected: The checkpoint module.
        expected_name: The checkpoint function.
        message: The failure text.

    Raises:
        Error: The functions differ or cannot be read.
    """
    if _function(actual, actual_name) != _function(expected, expected_name):
        _fail(message)


def sum2_caller_graphs(
    sum2: String, lane: String, roundoff: String, predecessor: String
) raises:
    """Require the reviewed Sum2 caller graphs.

    Args:
        sum2: The `curve_sum2` module.
        lane: The reviewed `lane_geometry` module.
        roundoff: The live `spiral_roundoff_proof` module.
        predecessor: The recorded roundoff predecessor module.

    Raises:
        Error: A recurrence, leaf, scalar body, envelope, or eligibility
        graph changed.
    """
    if sum2.find("@no_inline\ndef _sum2_update(") < 0:
        _fail("Sum2 recurrence changed")
    _same(
        sum2, "_sum2_update", _HELPER, "_sum2_update", "Sum2 recurrence changed"
    )
    var leaf = _function(sum2, "_sum2_error_checked").replace(
        "_sum2_error_checked", "_sum2_error"
    )
    if leaf != _function(_HELPER, "_sum2_error"):
        _fail("Sum2 checked arithmetic leaf changed")
    var live_rows = _rows(lane, "_lane_spiral")
    var want_rows = _rows(_SCALAR, "_lane_spiral")
    if len(live_rows) == 0 or live_rows[0] != "_require_sum2_environment ( )":
        _fail("scalar environment check moved")
    var lane_ok = len(live_rows) == len(want_rows) + 1
    var index = 0
    while lane_ok and index < len(want_rows):
        if live_rows[index + 1] != want_rows[index]:
            lane_ok = False
        index += 1
    if not lane_ok:
        _fail("Sum2 complete caller graph changed: _lane_spiral")
    _same(
        roundoff,
        "_sum2_envelope_error",
        _ENVELOPE,
        "_sum2_envelope_error",
        "Sum2 complete caller graph changed: _sum2_envelope_error",
    )
    _same(
        predecessor,
        "_try_spiral_roundoff_envelope",
        _ELIGIBILITY,
        "_try_spiral_roundoff_envelope",
        "Sum2 complete caller graph changed: _try_spiral_roundoff_envelope",
    )
