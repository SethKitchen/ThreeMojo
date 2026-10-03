# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Local scalar trigonometry with matching CARLA expression enclosures.

These helpers define the scalar expression that the lane query bounds. They
are not a replacement for the repository's global math or host libm. The
interval derivatives are derivatives of the stored polynomials and reduction
formulas. They do not substitute ideal sine derivatives for a polynomial.
"""

from extensions.carla.curve_interval import _Interval, _Jet, _JetExpression
from std.math import atan, atan2, cos, floor, inf, isfinite, isnan, sin
from std.memory import bitcast

comptime _PHASE_LIMIT = Float64(1048576.0)
comptime _HALF_PI = Float64(1.5707963267948966)
comptime _PI = Float64(3.141592653589793)
comptime _QUARTER_PI = Float64(0.7853981633974483)
comptime _INV_HALF_PI = Float64(0.6366197723675814)
# fdlibm's two-part pi/2 split. The high part has 33 significant bits.
# Its product by every quadrant integer in the supported domain is exact.
comptime _HALF_PI_HIGH = Float64(1.57079632673412561417)
comptime _HALF_PI_LOW = Float64(6.07710050650619224932e-11)
comptime _ATAN_REDUCE = Float64(0.41421356237309503)

comptime _SIN_COEFFICIENTS: Array[Float64, 11] = [
    1.0,
    -0.16666666666666666,
    0.008333333333333333,
    -0.0001984126984126984,
    2.7557319223985893e-06,
    -2.505210838544172e-08,
    1.6059043836821613e-10,
    -7.647163731819816e-13,
    2.8114572543455206e-15,
    -8.22063524662433e-18,
    1.9572941063391263e-20,
]

comptime _COS_COEFFICIENTS: Array[Float64, 11] = [
    1.0,
    -0.5,
    0.041666666666666664,
    -0.001388888888888889,
    2.48015873015873e-05,
    -2.755731922398589e-07,
    2.08767569878681e-09,
    -1.1470745597729725e-11,
    4.779477332387385e-14,
    -1.5619206968586225e-16,
    4.110317623312165e-19,
]

comptime _ATAN_COEFFICIENTS: Array[Float64, 22] = [
    1.0,
    -0.3333333333333333,
    0.2,
    -0.14285714285714285,
    0.1111111111111111,
    -0.09090909090909091,
    0.07692307692307693,
    -0.06666666666666667,
    0.058823529411764705,
    -0.05263157894736842,
    0.047619047619047616,
    -0.043478260869565216,
    0.04,
    -0.037037037037037035,
    0.034482758620689655,
    -0.03225806451612903,
    0.030303030303030304,
    -0.02857142857142857,
    0.02702702702702703,
    -0.02564102564102564,
    0.024390243902439025,
    -0.023255813953488372,
]


def _sign_bit(value: Float64) -> Bool:
    return (bitcast[DType.uint64](value) >> 63) != 0


def _scalar_polynomial[
    n: Int
](coefficients: Array[Float64, n], x: Float64) -> Float64:
    var result = coefficients[n - 1]
    var i = n - 2
    while i >= 0:
        result = result * x + coefficients[i]
        i -= 1
    return result


def _jet_polynomial[n: Int](coefficients: Array[Float64, n], x: _Jet) -> _Jet:
    return _expression_polynomial(coefficients, x)


def _expression_polynomial[n: Int, derivatives: Bool](
    coefficients: Array[Float64, n], x: _JetExpression[derivatives]
) -> _JetExpression[derivatives]:
    comptime Expression = _JetExpression[derivatives]
    var result = Expression.constant(coefficients[n - 1])
    var i = n - 2
    while i >= 0:
        result = result * x + Expression.constant(coefficients[i])
        i -= 1
    return result


@no_inline
def _curve_sincos(value: Float64) -> Tuple[Float64, Float64]:
    if not isfinite(value):
        return (sin(value), cos(value))
    if abs(value) > _PHASE_LIMIT:
        # The enclosure is [-1,1], not an assumed libm error allowance.
        return (
            min(max(sin(value), -1.0), 1.0),
            min(max(cos(value), -1.0), 1.0),
        )
    var quadrant = Int(floor(value * _INV_HALF_PI + 0.5))
    var high = Float64(quadrant) * _HALF_PI_HIGH
    var low = Float64(quadrant) * _HALF_PI_LOW
    var reduced = (value - high) - low
    var square = reduced * reduced
    var sine = reduced * _scalar_polynomial(
        materialize[_SIN_COEFFICIENTS](), square
    )
    var cosine = _scalar_polynomial(materialize[_COS_COEFFICIENTS](), square)
    var mode = quadrant & 3
    if mode == 0:
        return (sine, cosine)
    if mode == 1:
        return (cosine, -sine)
    if mode == 2:
        return (-sine, -cosine)
    return (-cosine, sine)


def _curve_sin(value: Float64) -> Float64:
    return _curve_sincos(value)[0]


def _curve_cos(value: Float64) -> Float64:
    return _curve_sincos(value)[1]


@no_inline
def _curve_atan(value: Float64) -> Float64:
    if isnan(value):
        return atan(value)
    var magnitude = abs(value)
    var inverse = magnitude > 1.0
    if inverse:
        magnitude = 1.0 / magnitude
    var shifted = magnitude > _ATAN_REDUCE
    if shifted:
        magnitude = (magnitude - 1.0) / (magnitude + 1.0)
    var result = magnitude * _scalar_polynomial(
        materialize[_ATAN_COEFFICIENTS](), magnitude * magnitude
    )
    if shifted:
        result = _QUARTER_PI + result
    if inverse:
        result = _HALF_PI - result
    if _sign_bit(value):
        result = -result
    return result


@no_inline
def _curve_atan2(y: Float64, x: Float64) -> Float64:
    if isnan(x) or isnan(y):
        return atan2(y, x)
    if y == 0.0:
        var result = _PI if _sign_bit(x) else 0.0
        return -result if _sign_bit(y) else result
    if x == 0.0:
        return -_HALF_PI if _sign_bit(y) else _HALF_PI
    var ax = abs(x)
    var ay = abs(y)
    if ax == inf[DType.float64]() and ay == inf[DType.float64]():
        var result = _PI - _QUARTER_PI if _sign_bit(x) else _QUARTER_PI
        return -result if _sign_bit(y) else result
    if ax >= ay:
        var result = _curve_atan(y / x)
        if x > 0.0:
            return result
        return (_PI if y > 0.0 else -_PI) + result
    var result = _curve_atan(x / y)
    return (_HALF_PI if y > 0.0 else -_HALF_PI) - result


def _polynomial_derivative[
    n: Int
](coefficients: Array[Float64, n], x: Float64) -> Float64:
    var value = coefficients[n - 1]
    var derivative = 0.0
    var i = n - 2
    while i >= 0:
        derivative = derivative * x + value
        value = value * x + coefficients[i]
        i -= 1
    return derivative


def _sincos_derivative(value: Float64) -> Tuple[Float64, Float64]:
    if not isfinite(value) or abs(value) > _PHASE_LIMIT:
        # Only a compatibility orientation outside the bounded polynomial
        # domain. The query enclosure has no finite derivative there.
        return (cos(value), -sin(value))
    var quadrant = Int(floor(value * _INV_HALF_PI + 0.5))
    var high = Float64(quadrant) * _HALF_PI_HIGH
    var low = Float64(quadrant) * _HALF_PI_LOW
    var reduced = (value - high) - low
    var square = reduced * reduced
    var sine = _scalar_polynomial(materialize[_SIN_COEFFICIENTS](), square)
    sine += (
        2.0
        * square
        * _polynomial_derivative(materialize[_SIN_COEFFICIENTS](), square)
    )
    var cosine = (
        2.0
        * reduced
        * _polynomial_derivative(materialize[_COS_COEFFICIENTS](), square)
    )
    var mode = quadrant & 3
    if mode == 0:
        return (sine, cosine)
    if mode == 1:
        return (cosine, -sine)
    if mode == 2:
        return (-sine, -cosine)
    return (-cosine, sine)


def _atan_derivative(value: Float64) -> Float64:
    var magnitude = abs(value)
    var derivative = 1.0
    var inverse = magnitude > 1.0
    if inverse:
        var original = magnitude
        magnitude = 1.0 / magnitude
        derivative = -magnitude / original
    if magnitude > _ATAN_REDUCE:
        var denominator = magnitude + 1.0
        magnitude = (magnitude - 1.0) / denominator
        derivative *= 2.0 / (denominator * denominator)
    var square = magnitude * magnitude
    var polynomial = _scalar_polynomial(
        materialize[_ATAN_COEFFICIENTS](), square
    )
    polynomial += (
        2.0
        * square
        * _polynomial_derivative(materialize[_ATAN_COEFFICIENTS](), square)
    )
    derivative *= polynomial
    return -derivative if inverse else derivative


def _atan2_derivative(
    y: Float64, x: Float64, dy: Float64, dx: Float64
) -> Float64:
    if x == 0.0 and y == 0.0:
        return 0.0
    if abs(x) >= abs(y):
        var ratio = y / x
        return _atan_derivative(ratio) * (dy / x - ratio * (dx / x))
    var ratio = x / y
    return -_atan_derivative(ratio) * (dx / y - ratio * (dy / y))


def _curve_sinc(value: Float64) -> Float64:
    if abs(value) <= _QUARTER_PI:
        return _scalar_polynomial(
            materialize[_SIN_COEFFICIENTS](), value * value
        )
    return _curve_sin(value) / value


def _sinc_derivative(value: Float64) -> Float64:
    if abs(value) <= _QUARTER_PI:
        return (
            2.0
            * value
            * _polynomial_derivative(
                materialize[_SIN_COEFFICIENTS](), value * value
            )
        )
    return (_sincos_derivative(value)[0] - _curve_sinc(value)) / value


def _sinc_jet(value: _Jet) -> _Jet:
    var domain = value.rounded_value().absolute()
    if domain.high <= _QUARTER_PI:
        return _jet_polynomial(materialize[_SIN_COEFFICIENTS](), value * value)
    var trigonometric = _sincos_jet(value)[0] / value
    if domain.low > _QUARTER_PI:
        return trigonometric
    var polynomial = _jet_polynomial(
        materialize[_SIN_COEFFICIENTS](), value * value
    )
    return _uncertain(
        polynomial.rounded_value().hull(trigonometric.rounded_value())
    )


def _sincos_branch(value: _Jet, quadrant: Int) -> Tuple[_Jet, _Jet]:
    return _sincos_branch_expression(value, quadrant)


def _sincos_branch_expression[derivatives: Bool](
    value: _JetExpression[derivatives], quadrant: Int
) -> Tuple[_JetExpression[derivatives], _JetExpression[derivatives]]:
    comptime Expression = _JetExpression[derivatives]
    # Products of constants are the same stored scalar values as the helper.
    # The derivative therefore includes only the variable subtraction and
    # the polynomial, not an ideal trigonometric identity.
    var high = Float64(quadrant) * _HALF_PI_HIGH
    var low = Expression.constant(Float64(quadrant)) * Expression.constant(
        _HALF_PI_LOW
    )
    var reduced = (value - Expression.constant(high)) - low
    var square = reduced * reduced
    var sine = reduced * _expression_polynomial(
        materialize[_SIN_COEFFICIENTS](), square
    )
    var cosine = _expression_polynomial(materialize[_COS_COEFFICIENTS](), square)
    var mode = quadrant & 3
    if mode == 0:
        return (sine, cosine)
    if mode == 1:
        return (cosine, -sine)
    if mode == 2:
        return (-sine, -cosine)
    return (-cosine, sine)


def _uncertain(value: _Interval) -> _Jet:
    return _Jet(value, _Interval.whole(), _Interval.whole(), 0.0)


def _uncertain_expression[derivatives: Bool](
    value: _Interval
) -> _JetExpression[derivatives]:
    return _JetExpression[derivatives](
        value, _Interval.whole(), _Interval.whole(), 0.0
    )


def _sincos_jet(value: _Jet) -> Tuple[_Jet, _Jet]:
    return _sincos_expression(value)


def _sincos_expression[derivatives: Bool](
    value: _JetExpression[derivatives]
) -> Tuple[_JetExpression[derivatives], _JetExpression[derivatives]]:
    comptime Expression = _JetExpression[derivatives]
    var domain = value.rounded_value()
    if not domain.is_finite():
        return (
            _uncertain_expression[derivatives](_Interval.whole()),
            _uncertain_expression[derivatives](_Interval.whole()),
        )
    if domain.magnitude() > _PHASE_LIMIT:
        if domain.low > _PHASE_LIMIT or domain.high < -_PHASE_LIMIT:
            var unknown = _uncertain_expression[derivatives](
                _Interval(-1.0, 1.0)
            )
            return (unknown, unknown)
        return (
            _uncertain_expression[derivatives](_Interval.whole()),
            _uncertain_expression[derivatives](_Interval.whole()),
        )
    var selection = (
        value * Expression.constant(_INV_HALF_PI) + Expression.constant(0.5)
    ).rounded_value()
    var low = Int(floor(selection.low))
    var high = Int(floor(selection.high))
    if low == high:
        return _sincos_branch_expression(value, low)
    if high - low > 4:
        # Polynomial output differs from exact [-1,1] by its arithmetic.
        # Evaluate possible branches only after further domain subdivision.
        return (
            _uncertain_expression[derivatives](_Interval.whole()),
            _uncertain_expression[derivatives](_Interval.whole()),
        )
    var source = Expression.variable(domain.low, domain.high)
    var result = _sincos_branch_expression(source, low)
    var sine = result[0].rounded_value()
    var cosine = result[1].rounded_value()
    var quadrant = low + 1
    while quadrant <= high:
        var piece = _sincos_branch_expression(source, quadrant)
        sine = sine.hull(piece[0].rounded_value())
        cosine = cosine.hull(piece[1].rounded_value())
        quadrant += 1
    # Quadrant changes are real branches in the scalar polynomial. No
    # smooth derivative is asserted across their rounded join.
    return (
        _uncertain_expression[derivatives](sine),
        _uncertain_expression[derivatives](cosine),
    )


def _constant_sincos_jet(heading: Float64) -> Tuple[_Jet, _Jet]:
    # The caller proves this stored heading is independent of road s.
    # Each allowed compiled graph supplies one fixed scalar coefficient in
    # the rounded output enclosure. Derivatives of that coefficient are zero;
    # its uncertainty stays in the value interval, not a fictitious varying
    # scalar error. Different scalar call sites can choose different values.
    # Generic singleton/zero-derivative jets do not establish this provenance.
    var result = _sincos_jet(_Jet.constant(heading))
    if not isfinite(heading) or abs(heading) > _PHASE_LIMIT:
        return result
    var zero = _Interval.point(0.0)
    return (
        _Jet(result[0].rounded_value(), zero, zero, 0.0),
        _Jet(result[1].rounded_value(), zero, zero, 0.0),
    )


def _atan_branch(value: _Jet, inverse: Bool, shifted: Bool) -> _Jet:
    var magnitude = value
    if inverse:
        magnitude = _Jet.constant(1.0) / magnitude
    if shifted:
        magnitude = (magnitude - _Jet.constant(1.0)) / (
            magnitude + _Jet.constant(1.0)
        )
    var result = magnitude * _jet_polynomial(
        materialize[_ATAN_COEFFICIENTS](), magnitude * magnitude
    )
    if shifted:
        result = _Jet.constant(_QUARTER_PI) + result
    if inverse:
        result = _Jet.constant(_HALF_PI) - result
    return result


def _atan_jet(value: _Jet) -> _Jet:
    var domain = value.rounded_value()
    if not domain.is_finite():
        return _uncertain(_Interval(-_HALF_PI, _HALF_PI))
    if domain.low < 0.0 and domain.high > 0.0:
        # The sign join is continuous but rounded scalar evaluations are
        # bounded separately. Its derivative is not used to prune.
        var left = _atan_jet(_Jet.variable(0.0, -domain.low))
        var right = _atan_jet(_Jet.variable(0.0, domain.high))
        return _uncertain((-left.rounded_value()).hull(right.rounded_value()))
    var negative = domain.high <= 0.0
    var source = -value if negative else value
    var positive = source.rounded_value()
    var inverse = positive.low >= 1.0 and positive.high > 1.0
    if positive.low < 1.0 and positive.high > 1.0:
        var before = _atan_jet(_Jet.variable(positive.low, 1.0))
        var after = _atan_jet(_Jet.variable(1.0, positive.high))
        var bound = before.rounded_value().hull(after.rounded_value())
        return _uncertain(-bound if negative else bound)
    var reduced = _Jet.constant(1.0) / source if inverse else source
    var reduction = reduced.rounded_value()
    if reduction.low <= _ATAN_REDUCE and reduction.high > _ATAN_REDUCE:
        # Both recipes cover this fixed source interval. This is finite
        # work, including when the endpoint equals the branch threshold.
        var one = _atan_branch(source, inverse, False).rounded_value()
        var two = _atan_branch(source, inverse, True).rounded_value()
        var bound = one.hull(two)
        return _uncertain(-bound if negative else bound)
    var result = _atan_branch(source, inverse, reduction.low > _ATAN_REDUCE)
    return -result if negative else result


def _atan2_jet(y: _Jet, x: _Jet) -> _Jet:
    var dx = x.rounded_value()
    var dy = y.rounded_value()
    if not dx.is_finite() or not dy.is_finite():
        return _uncertain(_Interval(-_PI, _PI))
    if dy.is_point(0.0) and not dx.contains(0.0):
        if dx.low > 0.0:
            return y
        if _sign_bit(dy.low) != _sign_bit(dy.high):
            return _uncertain(_Interval(-_PI, _PI))
        var angle = -_PI if _sign_bit(dy.low) else _PI
        return _Jet.constant(angle)
    if dx.is_point(0.0) and not dy.contains(0.0):
        return _Jet.constant(-_HALF_PI if dy.high < 0.0 else _HALF_PI)
    var bx = dx.absolute()
    var by = dy.absolute()
    if bx.low >= by.high and not dx.contains(0.0):
        var result = _atan_jet(y / x)
        if dx.low > 0.0:
            return result
        if dy.low > 0.0:
            return _Jet.constant(_PI) + result
        if dy.high < 0.0:
            return _Jet.constant(-_PI) + result
        # The negative-axis winding cut contains both one-sided headings.
        return _uncertain(_Interval(-_PI, _PI))
    if by.low > bx.high and not dy.contains(0.0):
        var result = _atan_jet(x / y)
        if dy.low > 0.0:
            return _Jet.constant(_HALF_PI) - result
        return _Jet.constant(-_HALF_PI) - result
    if dx.contains(0.0) or dy.contains(0.0):
        # An internal stationary tangent has no single continuous heading.
        return _uncertain(_Interval(-_PI, _PI))
    var one = _atan_jet(y / x)
    if dx.high < 0.0:
        one = _Jet.constant(_PI if dy.low > 0.0 else -_PI) + one
    var two = _Jet.constant(
        _HALF_PI if dy.low > 0.0 else -_HALF_PI
    ) - _atan_jet(x / y)
    # Include both scalar recipes where the magnitude comparison changes.
    return _uncertain(one.rounded_value().hull(two.rounded_value()))
