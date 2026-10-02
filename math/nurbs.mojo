# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Non-uniform rational B-splines, from three.js
`examples/jsm/curves/NURBSUtils.js`, `NURBSCurve.js`, `NURBSSurface.js`
and `NURBSVolume.js`.

A NURBS curve of degree `p` is a weighted blend of control points. The
knot vector says where along the parameter each control point starts and
stops to count: a curve of `n` control points has `n + p + 1` knots. Each
control point carries a weight `w` as its fourth number, and a point of
the curve is the blend of `(w x, w y, w z, w)`, divided by its own fourth
number. The functions follow three.js's `NURBSUtils` and the algorithms of
Piegl and Tiller's *The NURBS Book*, with conditioned arithmetic.

## Curves, surfaces and volumes

`NURBSCurve` is a `SpaceCurve`, so arc lengths and frames come from
`math.space_curve`. Its tangent is exact, from the first derivative.
`NURBSSurface` is a `ParametricSurface`, so `geometries.parametric`
builds a mesh of it, as three.js's `ParametricGeometry` does in its
example. `NURBSVolume` gives a point for three parameters.

## Where this differs from three.js

three.js takes the knots and the control points on trust. This refuses
knots that fall anywhere, knots that are not finite, and a count of knots
that does not match the control points and the degree. Those make
three.js read past the end of its arrays.

Object evaluators refuse parameters outside the closed unit interval, an
undefined homogeneous denominator, and a nonfinite projected result. Zero
and negative control weights remain valid at defined points. Surface and
volume methods can raise, including their Float32 narrowing boundaries.
Knot arithmetic avoids overflow in finite, wide spans without changing
stored knots. Binomial coefficients use a symmetric product recurrence.

Weighted derivatives above the polynomial degree are zero in every component.
three.js fills the extra rows with a weight of one. This port uses zero,
so constant curves have zero tangents and higher derivatives stay correct.

three.js's `NURBSCurve` maps `t` onto the knots from `startKnot` to
`endKnot` for a point, and onto all of the knots for a tangent. So a
curve given a start or an end knot has its tangents in the wrong place.
This keeps that, because the tangent is what three.js gives.
"""

from geometries.parametric import ParametricSurface
from math.curve_checks import check_curve_parameter
from math.space_curve import Point3, SpaceCurve, normalized3, point3
from math.vector3 import Vector3
from math.vector4 import Vector4
from std.math import inf, isfinite

# A control point in homogeneous form: `x`, `y`, `z` and the weight `w`.
comptime Point4 = SIMD[DType.float64, 4]


def point4(v: Vector4) -> Point4:
    """Return a control point in doubles.

    Args:
        v: The control point, its weight fourth.

    Returns:
        The same four numbers.
    """
    return Point4(Float64(v.x), Float64(v.y), Float64(v.z), Float64(v.w))


def find_span(p: Int, u: Float64, knots: List[Float64]) -> Int:
    """Return the knot span `u` falls in, three.js's `findSpan`.

    Args:
        p: The degree.
        u: The parameter.
        knots: The knot vector, rising.

    Returns:
        The span, from `p` through `n - 1`, where `n` is the number of
        control points.
    """
    var n = len(knots) - p - 1
    if u >= knots[n]:
        return n - 1
    if u <= knots[p]:
        return p
    var low = p
    var high = n
    var mid = (low + high) // 2
    while u < knots[mid] or u >= knots[mid + 1]:
        if u < knots[mid]:
            high = mid
        else:
            low = mid
        mid = (low + high) // 2
    return mid


def _knot_ratio(a: Float64, b: Float64, high: Float64, low: Float64) -> Float64:
    """Divide two knot differences without overflowing either subtraction."""
    var width = high - low
    if width == 0:
        # A collapsed interval contributes zero in the B-spline recurrence.
        return 0.0
    var difference = a - b
    if isfinite(width) and isfinite(difference):
        return difference / width
    return (a * 0.5 - b * 0.5) / (high * 0.5 - low * 0.5)


def _knot_divide(value: Float64, high: Float64, low: Float64) -> Float64:
    """Divide by a knot difference without overflowing the subtraction."""
    var width = high - low
    if width == 0:
        # A collapsed interval contributes zero in the B-spline recurrence.
        return 0.0
    if isfinite(width):
        return value / width
    return (value * 0.5) / (high * 0.5 - low * 0.5)


def basis_functions(
    span: Int, u: Float64, p: Int, knots: List[Float64]
) -> List[Float64]:
    """Return the `p + 1` basis functions that are not zero at `u`,
    three.js's `calcBasisFunctions`.

    Args:
        span: The span `find_span` gives.
        u: The parameter.
        p: The degree.
        knots: The knot vector.

    Returns:
        The values of the basis functions.
    """
    var n = List[Float64](length=p + 1, fill=0.0)
    n[0] = 1.0
    for j in range(1, p + 1):
        var saved = 0.0
        for r in range(j):  # pragma: no branch
            # `j` is one or more, so this runs.
            var high = knots[span + r + 1]
            var low = knots[span + r + 1 - j]
            var previous = n[r]
            n[r] = saved + previous * _knot_ratio(high, u, high, low)
            saved = previous * _knot_ratio(u, low, high, low)
        n[j] = saved
    return n^


def bspline_point(
    p: Int, knots: List[Float64], points: List[Point4], u: Float64
) -> Point4:
    """Return the weighted point of a B-spline at `u`, three.js's
    `calcBSplinePoint`: `(w x, w y, w z, w)`, not yet divided.

    Args:
        p: The degree.
        knots: The knot vector.
        points: The control points, each with its weight fourth.
        u: The parameter.

    Returns:
        The weighted point.
    """
    var span = find_span(p, u, knots)
    var n = basis_functions(span, u, p, knots)
    var c = Point4(0)
    for j in range(p + 1):  # pragma: no branch
        # The degree is zero or more, so this runs.
        var point = points[span - p + j]
        var nj = n[j]
        var wnj = point[3] * nj
        c[0] += point[0] * wnj
        c[1] += point[1] * wnj
        c[2] += point[2] * wnj
        c[3] += point[3] * nj
    return c


def basis_function_derivatives(
    span: Int, u: Float64, p: Int, n: Int, knots: List[Float64]
) -> List[List[Float64]]:
    """Return the basis functions at `u` and their derivatives up to the
    `n`th, three.js's `calcBasisFunctionDerivatives`.

    Args:
        span: The span `find_span` gives.
        u: The parameter.
        p: The degree.
        n: The highest derivative, at most `p`.
        knots: The knot vector.

    Returns:
        Row `k` holds the `k`th derivatives of the `p + 1` functions.
    """
    var zero = List[Float64](length=p + 1, fill=0.0)
    var ders = List[List[Float64]]()
    for _ in range(n + 1):  # pragma: no branch
        # `n` is zero or more, so this runs.
        ders.append(zero.copy())
    var ndu = List[List[Float64]]()
    for _ in range(p + 1):  # pragma: no branch
        # The degree is zero or more, so this runs.
        ndu.append(zero.copy())
    ndu[0][0] = 1.0
    for j in range(1, p + 1):
        var saved = 0.0
        for r in range(j):  # pragma: no branch
            # `j` is one or more, so this runs.
            var high = knots[span + r + 1]
            var low = knots[span + r + 1 - j]
            var previous = ndu[r][j - 1]
            ndu[r][j] = saved + previous * _knot_ratio(high, u, high, low)
            saved = previous * _knot_ratio(u, low, high, low)
        ndu[j][j] = saved
    for j in range(p + 1):  # pragma: no branch
        # The degree is zero or more, so this runs.
        ders[0][j] = ndu[j][p]
    for r in range(p + 1):  # pragma: no branch
        # The degree is zero or more, so this runs.
        var s1 = 0
        var s2 = 1
        var a = List[List[Float64]]()
        for _ in range(p + 1):  # pragma: no branch
            # The degree is zero or more, so this runs.
            a.append(zero.copy())
        a[0][0] = 1.0
        for k in range(1, n + 1):
            var d = 0.0
            var rk = r - k
            var pk = p - k
            if r >= k:
                a[s2][0] = _knot_divide(
                    a[s1][0], knots[span + rk + 1], knots[span + rk - pk]
                )
                d = a[s2][0] * ndu[rk][pk]
            var j1 = 1 if rk >= -1 else -rk
            var j2 = k - 1 if r - 1 <= pk else p - r
            for j in range(j1, j2 + 1):
                a[s2][j] = _knot_divide(
                    a[s1][j] - a[s1][j - 1],
                    knots[span + rk + j + 1],
                    knots[span + rk + j - pk],
                )
                d += a[s2][j] * ndu[rk + j][pk]
            if r <= pk:
                a[s2][k] = _knot_divide(
                    -a[s1][k - 1], knots[span + r + 1], knots[span + r - pk]
                )
                d += a[s2][k] * ndu[r][pk]
            ders[k][r] = d
            var swap = s1
            s1 = s2
            s2 = swap
    for k in range(1, n + 1):
        for j in range(p + 1):  # pragma: no branch
            # The degree is zero or more, so this runs.
            # Apply the falling factors to each value. An Int factorial can
            # overflow, and a separately overflowing Float64 factorial would
            # turn an exact zero derivative into NaN.
            for factor in range(p - k + 1, p + 1):  # pragma: no branch
                # The derivative order is at least one here.
                ders[k][j] *= Float64(factor)
    return ders^


def bspline_derivatives(
    p: Int, knots: List[Float64], points: List[Point4], u: Float64, nd: Int
) -> List[Point4]:
    """Return the weighted point of a B-spline at `u` and its derivatives
    up to the `nd`th, three.js's `calcBSplineDerivatives`.

    Args:
        p: The degree.
        knots: The knot vector.
        points: The control points, each with its weight fourth.
        u: The parameter.
        nd: The highest derivative wanted.

    Returns:
        `nd + 2` weighted points. Those past the degree are zero in all
        four components, including the homogeneous weight derivative.
    """
    var du = nd if nd < p else p
    var ck = List[Point4]()
    var span = find_span(p, u, knots)
    var nders = basis_function_derivatives(span, u, p, du, knots)
    var pw = List[Point4](capacity=len(points))
    for i in range(len(points)):  # pragma: no branch
        # A spline has one control point at least, so this runs.
        var point = points[i]
        var w = point[3]
        point[0] *= w
        point[1] *= w
        point[2] *= w
        pw.append(point)
    for k in range(du + 1):  # pragma: no branch
        # `du` is zero or more, so this runs.
        var point = pw[span - p] * nders[k][0]
        for j in range(1, p + 1):
            point += pw[span - p + j] * nders[k][j]
        ck.append(point)
    for _ in range(du + 1, nd + 2):  # pragma: no branch
        # `du` is at most `nd`, so this runs once at least.
        ck.append(Point4(0))
    return ck^


def _binomial_step(
    digits: List[UInt64], factor: Int, divisor: Int
) -> List[UInt64]:
    """Multiply and divide an exact coefficient held in 34 base-2**32 limbs."""
    var product = List[UInt64](length=34, fill=0)
    var multiplier = UInt64(factor)
    for offset in range(2):  # pragma: no branch
        var limb = (multiplier >> UInt64(32 * offset)) & 0xFFFFFFFF
        var carry = UInt64(0)
        for index in range(34 - offset):  # pragma: no branch
            var value = digits[index] * limb + product[index + offset] + carry
            product[index + offset] = value & 0xFFFFFFFF
            carry = value >> 32
    # The remainder stays below divisor <= Int.MAX / 2. Its next shift fits
    # UInt64, including when the divisor itself needs more than one limb.
    var remainder = UInt64(0)
    for index in range(33, -1, -1):  # pragma: no branch
        var quotient = UInt64(0)
        for bit in range(31, -1, -1):  # pragma: no branch
            remainder = (remainder << 1) | ((product[index] >> UInt64(bit)) & 1)
            if remainder >= UInt64(divisor):
                remainder -= UInt64(divisor)
                quotient |= UInt64(1) << UInt64(bit)
        product[index] = quotient
    return product^


def _coefficient_overflows(digits: List[UInt64]) -> Bool:
    """Compare an exact nonnegative coefficient with Float64.MAX's integer."""
    if digits[33] != 0 or digits[32] != 0:
        return True
    if digits[31] != 0xFFFFFFFF:
        return False
    if digits[30] != 0xFFFFF800:
        return digits[30] > 0xFFFFF800
    for index in range(30):  # pragma: no branch
        if digits[index] != 0:
            return True
    return False


def _coefficient_float(digits: List[UInt64]) -> Float64:
    """Round a bounded integer once, to nearest-even, or return true overflow.
    """
    if _coefficient_overflows(digits):
        return inf[DType.float64]()
    var highest = 0
    for index in range(34):  # pragma: no branch
        if digits[index] != 0:
            highest = index
    var bits = highest * 32
    var leading = digits[highest]
    while leading != 0:
        bits += 1
        leading >>= 1
    var shift = max(0, bits - 53)
    var significand = UInt64(0)
    for bit in range(bits - 1, shift - 1, -1):
        significand = (significand << 1) | (
            (digits[bit // 32] >> UInt64(bit % 32)) & 1
        )
    if shift != 0:
        var guard = (digits[(shift - 1) // 32] >> UInt64((shift - 1) % 32)) & 1
        var sticky = UInt64(0)
        for bit in range(shift - 1):
            sticky |= (digits[bit // 32] >> UInt64(bit % 32)) & 1
        significand += guard & (sticky | (significand & 1))
    var value = Float64(significand)
    for _ in range(shift):
        value *= 2.0
    return value


def _exact_binomial(k: Int, count: Int) -> Float64:
    """Resolve a near-overflow binomial with a bounded exact integer recurrence.
    """
    var digits = List[UInt64](length=34, fill=0)
    digits[0] = 1
    for j in range(1, count + 1):
        # Before multiplication the integer fits in 1024 bits; its factor
        # fits in 63 bits. The 1088-bit workspace therefore cannot overflow.
        digits = _binomial_step(digits, k - count + j, j)
        if _coefficient_overflows(digits):
            return inf[DType.float64]()
    return _coefficient_float(digits)


def k_over_i(k: Int, i: Int) -> Float64:
    """Return the binomial coefficient `k` over `i`, three.js's
    `calcKoverI`.

    Args:
        k: The top number.
        i: The bottom number, from zero through `k`.

    Returns:
        `k! / (i! (k - i)!)`, or positive infinity if the coefficient
        exceeds Float64. Symmetric inputs use the same recurrence.
    """
    var count = min(i, k - i)
    var coefficient = 1.0
    for j in range(1, count + 1):
        coefficient *= Float64(k - count + j) / Float64(j)
        # Resolve the last binade exactly: accumulated rounding must not turn
        # a representable coefficient into infinity, or hide true overflow.
        # Symmetry makes every factor at least two. The recurrence reaches
        # this guard within 1024 steps, so roundoff cannot span a binade.
        if coefficient >= 8.988465674311579e307:
            return _exact_binomial(k, count)
    return coefficient


def rational_curve_derivatives(pders: List[Point4]) -> List[Point3]:
    """Return the derivatives of a rational curve from those of its
    weighted form, three.js's `calcRationalCurveDerivatives`.

    Args:
        pders: The weighted point and its derivatives.

    Returns:
        The point and its derivatives, divided through.
    """
    var nd = len(pders)
    var ck = List[Point3](capacity=nd)
    for k in range(nd):
        var v = point3(pders[k][0], pders[k][1], pders[k][2])
        for i in range(1, k + 1):
            if pders[i][3] != 0:
                v -= ck[k - i] * (k_over_i(k, i) * pders[i][3])
        ck.append(v / pders[0][3])
    return ck^


def nurbs_derivatives(
    p: Int, knots: List[Float64], points: List[Point4], u: Float64, nd: Int
) -> List[Point3]:
    """Return a NURBS curve's point at `u` and its derivatives up to the
    `nd`th, three.js's `calcNURBSDerivatives`.

    Args:
        p: The degree.
        knots: The knot vector.
        points: The control points, each with its weight fourth.
        u: The parameter.
        nd: The highest derivative wanted.

    Returns:
        The point, then its derivatives. The list has `nd + 2` entries,
        matching `bspline_derivatives`, including one extra derivative.
    """
    return rational_curve_derivatives(
        bspline_derivatives(p, knots, points, u, nd)
    )


def surface_point(
    p: Int,
    q: Int,
    knots1: List[Float64],
    knots2: List[Float64],
    points: List[List[Point4]],
    u: Float64,
    v: Float64,
) -> Point3:
    """Return the point of a NURBS surface at `(u, v)`, three.js's
    `calcSurfacePoint`.

    Args:
        p: The degree along `u`.
        q: The degree along `v`.
        knots1: The knots along `u`.
        knots2: The knots along `v`.
        points: The control points, one row per step of `u`.
        u: The first parameter.
        v: The second parameter.

    Returns:
        The point.
    """
    return _project(_surface_homogeneous(p, q, knots1, knots2, points, u, v))


def _surface_homogeneous(
    p: Int,
    q: Int,
    knots1: List[Float64],
    knots2: List[Float64],
    points: List[List[Point4]],
    u: Float64,
    v: Float64,
) -> Point4:
    """Return the weighted surface point before projection."""
    var uspan = find_span(p, u, knots1)
    var vspan = find_span(q, v, knots2)
    var nu = basis_functions(uspan, u, p, knots1)
    var nv = basis_functions(vspan, v, q, knots2)
    var temp = List[Point4]()
    for l in range(q + 1):  # pragma: no branch
        # The degree is zero or more, so this runs.
        var sum = Point4(0)
        for k in range(p + 1):  # pragma: no branch
            # The degree is zero or more, so this runs.
            var point = points[uspan - p + k][vspan - q + l]
            var w = point[3]
            point[0] *= w
            point[1] *= w
            point[2] *= w
            sum += point * nu[k]
        temp.append(sum)
    var sw = Point4(0)
    for l in range(q + 1):  # pragma: no branch
        # The degree is zero or more, so this runs.
        sw += temp[l] * nv[l]
    return sw


def volume_point(
    p: Int,
    q: Int,
    r: Int,
    knots1: List[Float64],
    knots2: List[Float64],
    knots3: List[Float64],
    points: List[List[List[Point4]]],
    u: Float64,
    v: Float64,
    w: Float64,
) -> Point3:
    """Return the point of a NURBS volume at `(u, v, w)`, three.js's
    `calcVolumePoint`.

    Args:
        p: The degree along `u`.
        q: The degree along `v`.
        r: The degree along `w`.
        knots1: The knots along `u`.
        knots2: The knots along `v`.
        knots3: The knots along `w`.
        points: The control points, indexed by `u`, then `v`, then `w`.
        u: The first parameter.
        v: The second parameter.
        w: The third parameter.

    Returns:
        The point.
    """
    return _project(
        _volume_homogeneous(p, q, r, knots1, knots2, knots3, points, u, v, w)
    )


def _volume_homogeneous(
    p: Int,
    q: Int,
    r: Int,
    knots1: List[Float64],
    knots2: List[Float64],
    knots3: List[Float64],
    points: List[List[List[Point4]]],
    u: Float64,
    v: Float64,
    w: Float64,
) -> Point4:
    """Return the weighted volume point before projection."""
    var uspan = find_span(p, u, knots1)
    var vspan = find_span(q, v, knots2)
    var wspan = find_span(r, w, knots3)
    var nu = basis_functions(uspan, u, p, knots1)
    var nv = basis_functions(vspan, v, q, knots2)
    var nw = basis_functions(wspan, w, r, knots3)
    var sw = Point4(0)
    for m in range(r + 1):  # pragma: no branch
        # The degree is zero or more, so this runs.
        for l in range(q + 1):  # pragma: no branch
            # The degree is zero or more, so this runs.
            var sum = Point4(0)
            for k in range(p + 1):  # pragma: no branch
                # The degree is zero or more, so this runs.
                var point = points[uspan - p + k][vspan - q + l][wspan - r + m]
                var weight = point[3]
                point[0] *= weight
                point[1] *= weight
                point[2] *= weight
                sum += point * nu[k]
            sw += (sum * nw[m]) * nv[l]
    return sw


def _checked_knots(
    degree: Int, knots: List[Float64], points: Int
) raises -> List[Float64]:
    """Return the knots, if a spline of `points` control points and the
    given degree can have them.

    Args:
        degree: The degree.
        knots: The knot vector.
        points: How many control points run along it.

    Returns:
        A copy of the knots.

    Raises:
        Error: If the degree is negative or not below the point count,
            a knot is nonfinite, the knots fall, their count is incorrect,
            or the active knot interval has zero width.
    """
    if degree < 0:
        raise Error("A NURBS degree cannot be negative")
    if points < 1:
        raise Error("A NURBS spline needs one control point at least")
    if degree >= points:
        raise Error("A NURBS degree must be below its control point count")
    # Subtract from the existing length instead of adding caller counts.
    if len(knots) <= points or len(knots) - points - 1 != degree:
        raise Error(
            "A NURBS spline needs as many knots as its control points and"
            " its degree and one more"
        )
    for index in range(len(knots)):  # pragma: no branch
        # There is one knot at least, so this runs.
        if not isfinite(knots[index]):
            raise Error("A NURBS knot must be finite")
        if index > 0 and knots[index] < knots[index - 1]:
            raise Error("NURBS knots cannot fall")
    if knots[degree] >= knots[points]:
        raise Error("A NURBS active knot interval must have positive width")
    return knots.copy()


def _checked_point(point: Vector4) raises -> Point4:
    """Return a control point in doubles, if its numbers are finite.

    Args:
        point: The control point.

    Returns:
        The point.

    Raises:
        Error: If one of its numbers is not finite.
    """
    var out = point4(point)
    for axis in range(4):  # pragma: no branch
        if not isfinite(out[axis]):
            raise Error("A NURBS control point must be finite")
    return out


def _mapped_between(t: Float64, first: Float64, last: Float64) -> Float64:
    """Map a unit parameter between finite endpoints without wide differences.
    """
    if t == 0:
        return first
    if t == 1:
        return last
    var width = last - first
    if isfinite(width):
        return first + t * width
    return (1.0 - t) * first + t * last


def _mapped(t: Float64, knots: List[Float64]) -> Float64:
    """Return `t` carried onto the whole run of a knot vector."""
    return _mapped_between(t, knots[0], knots[len(knots) - 1])


def _project(h: Point4) -> Point3:
    """Divide coordinates directly, without an overflowing reciprocal weight."""
    return point3(h[0] / h[3], h[1] / h[3], h[2] / h[3])


def _checked_finite(p: Point3) raises -> Point3:
    """Refuse a nonfinite projected point or derivative."""
    for axis in range(3):  # pragma: no branch
        if not isfinite(p[axis]):
            raise Error("A NURBS projected result must be finite")
    return p


def _checked_project(h: Point4) raises -> Point3:
    """Refuse an undefined homogeneous denominator or projected point."""
    if h[3] == 0 or not isfinite(h[3]):
        raise Error(
            "A NURBS homogeneous denominator must be finite and nonzero"
        )
    return _checked_finite(_project(h))


def _checked_vector(p: Point3) raises -> Vector3:
    """Refuse coordinates outside Float32 before narrowing to a Vector3."""
    for axis in range(3):  # pragma: no branch
        if abs(p[axis]) > 3.4028234663852886e38:
            raise Error("A NURBS point must fit in Float32")
    return Vector3(Float32(p[0]), Float32(p[1]), Float32(p[2]))


struct NURBSCurve(SpaceCurve):
    """A NURBS curve in space, three.js's `NURBSCurve`."""

    var degree: Int
    var knots: List[Float64]
    var control_points: List[Point4]
    var start_knot: Int
    var end_knot: Int

    def __init__(
        out self,
        degree: Int,
        knots: List[Float64],
        control_points: List[Vector4],
        start_knot: Optional[Int] = None,
        end_knot: Optional[Int] = None,
    ) raises:
        """Create a curve.

        Args:
            degree: The degree, zero or more.
            knots: The knot vector: as many knots as control points, plus
                the degree, plus one, never falling.
            control_points: The control points, each with its weight in
                `w`.
            start_knot: The knot `t` of zero maps to. The first unless
                said otherwise.
            end_knot: The knot `t` of one maps to. The last unless said
                otherwise. This index can equal or precede `start_knot`.

        Raises:
            Error: If the knots do not fit the degree and the points, a
                number is not finite, or a start or end knot is not one
                of the knots.
        """
        var points = List[Point4](capacity=len(control_points))
        for index in range(len(control_points)):
            points.append(_checked_point(control_points[index]))
        self.knots = _checked_knots(degree, knots, len(points))
        self.degree = degree
        self.control_points = points^
        self.start_knot = start_knot.or_else(0)
        self.end_knot = end_knot.or_else(len(knots) - 1)
        if self.start_knot < 0 or self.start_knot >= len(knots):
            raise Error("A NURBS start knot must be one of the knots")
        if self.end_knot < 0 or self.end_knot >= len(knots):
            raise Error("A NURBS end knot must be one of the knots")

    def point3(self, t: Float64) raises -> Point3:
        """Return the point of the curve at `t`, three.js's `getPoint`.

        Args:
            t: Where on the curve, from zero at the start knot to one at
                the end knot.

        Returns:
            The point.

        Raises:
            Error: If `t` is outside zero through one, a homogeneous denominator
                is zero or nonfinite, or a projected result is nonfinite.
        """
        check_curve_parameter(t)
        var u = _mapped_between(
            t, self.knots[self.start_knot], self.knots[self.end_knot]
        )
        var h = bspline_point(self.degree, self.knots, self.control_points, u)
        return _checked_project(h)

    def tangent3(self, t: Float64) raises -> Point3:
        """Return the unit direction at `t`, three.js's `getTangent`, from
        the exact first derivative. Its positive scale is not formed.

        Args:
            t: Where on the curve, from zero at the first knot to one at
                the last. See the module docstring.

        Returns:
            The direction, or zero where the curve stops.

        Raises:
            Error: If `t` is outside zero through one, a homogeneous denominator
                is zero or nonfinite, or a projected result is nonfinite.
        """
        check_curve_parameter(t)
        var u = _mapped(t, self.knots)
        var homogeneous = bspline_point(
            self.degree, self.knots, self.control_points, u
        )
        var position = _checked_project(homogeneous)
        if self.degree == 0:
            return point3(0, 0, 0)
        var span = find_span(self.degree, u, self.knots)
        var basis = basis_functions(span, u, self.degree - 1, self.knots)
        # Differentiate the homogeneous control polygon. A common positive
        # scale and the degree do not change the final unit direction.
        # Keep the active-span scale inside each quotient, before a derivative
        # can underflow or overflow in the original knot units.
        var width = self.knots[span + 1] - self.knots[span]
        if not isfinite(width):
            width = self.knots[span + 1] * 0.5 - self.knots[span] * 0.5
        var coordinate_scale = max(
            abs(position[0]), max(abs(position[1]), abs(position[2]))
        )
        var weight_scale = 0.0
        for j in range(self.degree + 1):  # pragma: no branch
            var control = self.control_points[span - self.degree + j]
            weight_scale = max(weight_scale, abs(control[3]))
            for axis in range(3):  # pragma: no branch
                coordinate_scale = max(coordinate_scale, abs(control[axis]))
        if coordinate_scale == 0:
            return point3(0, 0, 0)
        # A common coordinate/weight scale keeps control differences finite.
        # A valid homogeneous denominator ensures the weight scale is nonzero.
        var scaled_position = position / coordinate_scale
        var change = Point4(0)
        for j in range(self.degree):  # pragma: no branch
            # The degree-zero case returned above.
            var index = span - self.degree + j
            var first = self.control_points[index]
            var last = self.control_points[index + 1]
            first[3] /= weight_scale
            last[3] /= weight_scale
            for axis in range(3):  # pragma: no branch
                first[axis] = (first[axis] / coordinate_scale) * first[3]
                last[axis] = (last[axis] / coordinate_scale) * last[3]
            var factor = basis[j] * _knot_ratio(
                width,
                0,
                self.knots[index + self.degree + 1],
                self.knots[index + 1],
            )
            change += (last - first) * factor
        var derivative = _checked_finite(
            point3(change[0], change[1], change[2])
            - scaled_position * change[3]
        )
        # Division by the homogeneous weight affects only this direction's sign.
        if homogeneous[3] < 0:
            derivative = -derivative
        var scale = max(
            abs(derivative[0]), max(abs(derivative[1]), abs(derivative[2]))
        )
        if scale == 0:
            return derivative
        return normalized3(derivative / scale)


struct NURBSSurface(Copyable, Movable, ParametricSurface):
    """A NURBS surface, three.js's `NURBSSurface`."""

    var degree1: Int
    var degree2: Int
    var knots1: List[Float64]
    var knots2: List[Float64]
    var control_points: List[List[Point4]]

    def __init__(
        out self,
        degree1: Int,
        degree2: Int,
        knots1: List[Float64],
        knots2: List[Float64],
        control_points: List[List[Vector4]],
    ) raises:
        """Create a surface.

        Args:
            degree1: The degree along `u`, zero or more.
            degree2: The degree along `v`, zero or more.
            knots1: The knots along `u`.
            knots2: The knots along `v`.
            control_points: One row per control point along `u`, each as
                long as the control points along `v`, each point with its
                weight in `w`.

        Raises:
            Error: If the knots do not fit the degrees and the rows, a row
                is the wrong length, or a number is not finite.
        """
        var rows = len(control_points)
        self.knots1 = _checked_knots(degree1, knots1, rows)
        var columns = len(control_points[0])
        self.knots2 = _checked_knots(degree2, knots2, columns)
        self.degree1 = degree1
        self.degree2 = degree2
        self.control_points = List[List[Point4]]()
        for i in range(rows):  # pragma: no branch
            # `_checked_knots` refused no rows, so this runs.
            if len(control_points[i]) != columns:
                raise Error("Every row of a NURBS surface must be as long")
            var row = List[Point4]()
            for j in range(columns):  # pragma: no branch
                # `_checked_knots` refused an empty row, so this runs.
                row.append(_checked_point(control_points[i][j]))
            self.control_points.append(row^)

    def point64(self, t1: Float64, t2: Float64) raises -> Point3:
        """Return the point of the surface at `(t1, t2)`, in doubles.

        Args:
            t1: How far along the first direction, zero to one.
            t2: How far along the second direction, zero to one.

        Returns:
            The point.

        Raises:
            Error: If a parameter is outside zero through one, a homogeneous
                denominator is zero or nonfinite, or a projected result is nonfinite.
        """
        check_curve_parameter(t1)
        check_curve_parameter(t2)
        return _checked_project(
            _surface_homogeneous(
                self.degree1,
                self.degree2,
                self.knots1,
                self.knots2,
                self.control_points,
                _mapped(t1, self.knots1),
                _mapped(t2, self.knots2),
            )
        )

    def point(self, u: Float32, v: Float32) raises -> Vector3:
        """Return the point of the surface at `(u, v)`, three.js's
        `getPoint`.

        Args:
            u: How far along the first direction, zero to one.
            v: How far along the second direction, zero to one.

        Returns:
            The point, in meters.

        Raises:
            Error: If a parameter or projection is invalid, or a coordinate
                cannot fit in Float32.
        """
        var p = self.point64(Float64(u), Float64(v))
        return _checked_vector(p)


struct NURBSVolume(Copyable, Movable):
    """A NURBS volume, three.js's `NURBSVolume`."""

    var degree1: Int
    var degree2: Int
    var degree3: Int
    var knots1: List[Float64]
    var knots2: List[Float64]
    var knots3: List[Float64]
    var control_points: List[List[List[Point4]]]

    def __init__(
        out self,
        degree1: Int,
        degree2: Int,
        degree3: Int,
        knots1: List[Float64],
        knots2: List[Float64],
        knots3: List[Float64],
        control_points: List[List[List[Vector4]]],
    ) raises:
        """Create a volume.

        Args:
            degree1: The degree along `u`, zero or more.
            degree2: The degree along `v`, zero or more.
            degree3: The degree along `w`, zero or more.
            knots1: The knots along `u`.
            knots2: The knots along `v`.
            knots3: The knots along `w`.
            control_points: The control points, indexed by `u`, then `v`,
                then `w`, each with its weight in `w`.

        Raises:
            Error: If the knots do not fit the degrees and the points, the
                points are not a full box, or a number is not finite.
        """
        var n1 = len(control_points)
        self.knots1 = _checked_knots(degree1, knots1, n1)
        var n2 = len(control_points[0])
        self.knots2 = _checked_knots(degree2, knots2, n2)
        var n3 = len(control_points[0][0])
        self.knots3 = _checked_knots(degree3, knots3, n3)
        self.degree1 = degree1
        self.degree2 = degree2
        self.degree3 = degree3
        self.control_points = List[List[List[Point4]]]()
        for i in range(n1):  # pragma: no branch
            # `_checked_knots` refused no points, so each loop runs.
            if len(control_points[i]) != n2:
                raise Error("A NURBS volume's control points must fill a box")
            var plane = List[List[Point4]]()
            for j in range(n2):  # pragma: no branch
                if len(control_points[i][j]) != n3:
                    raise Error(
                        "A NURBS volume's control points must fill a box"
                    )
                var row = List[Point4]()
                for k in range(n3):  # pragma: no branch
                    row.append(_checked_point(control_points[i][j][k]))
                plane.append(row^)
            self.control_points.append(plane^)

    def point64(self, t1: Float64, t2: Float64, t3: Float64) raises -> Point3:
        """Return the point of the volume at `(t1, t2, t3)`, in doubles.

        Args:
            t1: How far along the first direction, zero to one.
            t2: How far along the second direction, zero to one.
            t3: How far along the third direction, zero to one.

        Returns:
            The point.

        Raises:
            Error: If a parameter is outside zero through one, a homogeneous
                denominator is zero or nonfinite, or a projected result is nonfinite.
        """
        check_curve_parameter(t1)
        check_curve_parameter(t2)
        check_curve_parameter(t3)
        return _checked_project(
            _volume_homogeneous(
                self.degree1,
                self.degree2,
                self.degree3,
                self.knots1,
                self.knots2,
                self.knots3,
                self.control_points,
                _mapped(t1, self.knots1),
                _mapped(t2, self.knots2),
                _mapped(t3, self.knots3),
            )
        )

    def point(self, t1: Float32, t2: Float32, t3: Float32) raises -> Vector3:
        """Return the point of the volume at `(t1, t2, t3)`, three.js's
        `getPoint`.

        Args:
            t1: How far along the first direction, zero to one.
            t2: How far along the second direction, zero to one.
            t3: How far along the third direction, zero to one.

        Returns:
            The point, in meters.

        Raises:
            Error: If a parameter or projection is invalid, or a coordinate
                cannot fit in Float32.
        """
        var p = self.point64(Float64(t1), Float64(t2), Float64(t3))
        return _checked_vector(p)
