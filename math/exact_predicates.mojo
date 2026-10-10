# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Bounded adaptive affine predicates for finite binary64 coordinates.

All predicates use original coordinates. A guarded arithmetic-error filter
handles ordinary data. Directed intervals refine uncertain results before
a final signed-dyadic-integer fallback.
Every integer has fixed storage; no predicate allocates an unbounded list.

A finite binary64 is a multiple of 2**-1074 with magnitude below 2**1024.
An affine difference is below 2**1025. The largest expression here compares
two squared plane distances: D1**2*N2 - D2**2*N1, of degree ten. Its lattice
is at least 2**-10740 and its magnitude is below 2**10270 (including all
three-dimensional sums). Thus 21010 bits suffice. The 21504-bit capacity
also leaves room for carry and alignment words. Each operation visits only
its active words. These helpers require finite inputs; callers validate at
their public boundary. Tolerances must also be finite and nonnegative.
"""

from math.scaled_products import _Scaled, _common_scale, _split
from std.math import inf, isfinite, ldexp
from std.memory import bitcast

comptime _CAPACITY = 672
comptime _P = SIMD[DType.float64, 4]


struct _Dyadic(ImplicitlyCopyable):
    """An exact signed integer times a power of two, with bounded storage."""

    var words: Array[UInt32, _CAPACITY]
    var count: Int
    var exponent: Int
    var sign: Int

    # Keep fixed-capacity initialization out of predicate callers to avoid
    # Mojo 1.1 AOT code-generation stalls.
    @inline(.never)
    def __init__(out self, value: Float64 = 0):
        self.words = Array[UInt32, _CAPACITY](fill=0)
        var bits = bitcast[DType.uint64](value)
        var fraction = bits & UInt64(0xFFFFFFFFFFFFF)
        var biased = Int((bits >> 52) & UInt64(0x7FF))
        if biased != 0:
            fraction |= UInt64(0x10000000000000)
        self.words[0] = UInt32(fraction & UInt64(0xFFFFFFFF))
        self.words[1] = UInt32(fraction >> 32)
        self.count = 2
        self.exponent = max(biased, 1) - 1075
        self.sign = 1 if bits >> 63 == 0 else -1
        self._trim()

    def __init__(out self, *, copy: Self):
        self.words = copy.words.copy()
        self.count = copy.count
        self.exponent = copy.exponent
        self.sign = copy.sign

    def _trim(mut self):
        while self.count > 0 and self.words[self.count - 1] == 0:
            self.count -= 1
        if self.count == 0:
            self.sign = 0
            self.exponent = 0
            return
        var low = 0
        while self.words[low] == 0:
            low += 1
        if low != 0:
            # The retained high word is nonzero, so low < self.count.
            for index in range(self.count - low):  # pragma: no branch
                self.words[index] = self.words[index + low]
            self.count -= low
            self.exponent += 32 * low

    def _size(self, exponent: Int) -> Int:
        if self.sign == 0:
            return 0
        var shift = self.exponent - exponent
        return self.count + shift // 32 + Int(shift % 32 != 0)

    def _word(self, index: Int, exponent: Int) -> UInt64:
        var shift = self.exponent - exponent
        var source = index - shift // 32
        var bits = shift % 32
        var result = UInt64(0)
        if source >= 0 and source < self.count:
            result = (UInt64(self.words[source]) << UInt64(bits)) & UInt64(
                0xFFFFFFFF
            )
        if bits != 0 and source > 0 and source <= self.count:
            result |= UInt64(self.words[source - 1]) >> UInt64(32 - bits)
        return result

    def _compare_abs(self, other: Self) -> Int:
        var exponent = min(self.exponent, other.exponent)
        var size = max(self._size(exponent), other._size(exponent))
        for index in range(size - 1, -1, -1):
            var a = self._word(index, exponent) if self.sign != 0 else UInt64(0)
            var b = other._word(index, exponent) if other.sign != 0 else UInt64(
                0
            )
            if a != b:
                return 1 if a > b else -1
        return 0

    def __neg__(self) -> Self:
        var result = self
        result.sign = -result.sign
        return result^

    def __add__(self, other: Self) -> Self:
        if self.sign == 0:
            return other
        if other.sign == 0:
            return self
        var result = Self()
        result.exponent = min(self.exponent, other.exponent)
        var size = max(
            self._size(result.exponent), other._size(result.exponent)
        )
        result.sign = self.sign
        if self.sign == other.sign:
            var carry = UInt64(0)
            # Both signs are nonzero; canonical counts and size are positive.
            for index in range(size):  # pragma: no branch
                var total = (
                    self._word(index, result.exponent)
                    + other._word(index, result.exponent)
                    + carry
                )
                result.words[index] = UInt32(total & UInt64(0xFFFFFFFF))
                carry = total >> 32
            result.words[size] = UInt32(carry)
            result.count = size + 1
        else:
            var order = self._compare_abs(other)
            if order == 0:
                return Self()
            if order < 0:
                result.sign = other.sign
            var borrow = UInt64(0)
            # Both canonical operands are nonzero, so size is positive.
            for index in range(size):  # pragma: no branch
                var a = self._word(index, result.exponent)
                var b = other._word(index, result.exponent)
                if order < 0:
                    var held = a
                    a = b
                    b = held
                b += borrow
                borrow = UInt64(a < b)
                result.words[index] = UInt32(
                    (UInt64(0x100000000) + a - b) & UInt64(0xFFFFFFFF)
                )
            result.count = size
        result._trim()
        return result^

    def __sub__(self, other: Self) -> Self:
        return self + (-other)

    def __mul__(self, other: Self) -> Self:
        var result = Self()
        if self.sign == 0 or other.sign == 0:
            return result^
        result.exponent = self.exponent + other.exponent
        result.sign = self.sign * other.sign
        result.count = self.count + other.count
        # The zero-sign guard proves the canonical left count is positive.
        for i in range(self.count):  # pragma: no branch
            var carry = UInt64(0)
            # The same guard proves the canonical right count is positive.
            for j in range(other.count):  # pragma: no branch
                # The maximum is (2**32-1)**2 + 2*(2**32-1).
                # It equals 2**64-1, so this accumulator cannot wrap.
                var total = (
                    UInt64(self.words[i]) * UInt64(other.words[j])
                    + UInt64(result.words[i + j])
                    + carry
                )
                result.words[i + j] = UInt32(total & UInt64(0xFFFFFFFF))
                carry = total >> 32
            result.words[i + other.count] = UInt32(carry)
        result._trim()
        return result^

    def _estimate(self) -> _Scaled[DType.float64]:
        if self.sign == 0:
            return _Scaled[DType.float64](0, 0)
        var high = UInt64(self.words[self.count - 1])
        var exponent = self.exponent + 32 * (self.count - 1)
        if self.count > 1:
            high = (high << 32) | UInt64(self.words[self.count - 2])
            exponent -= 32
        if self.count > 2:
            var shift = 0
            while high < UInt64(0x8000000000000000):
                high <<= 1
                shift += 1
            if shift != 0:
                high |= UInt64(self.words[self.count - 3]) >> UInt64(32 - shift)
                exponent -= shift
        return _split(Float64(self.sign) * Float64(high), exponent)


@fieldwise_init
struct _Interval(ImplicitlyCopyable):
    """A closed interval containing the exact result of an expression."""

    var low: Float64
    var high: Float64

    def __add__(self, other: Self) -> Self:
        return _outward(self.low + other.low, self.high + other.high)

    def __sub__(self, other: Self) -> Self:
        return _outward(self.low - other.high, self.high - other.low)

    def __mul__(self, other: Self) -> Self:
        var a = self.low * other.low
        var b = self.low * other.high
        var c = self.high * other.low
        var d = self.high * other.high
        if (
            not isfinite(a)
            or not isfinite(b)
            or not isfinite(c)
            or not isfinite(d)
        ):
            return Self(-inf[DType.float64](), inf[DType.float64]())
        return _outward(min(min(a, b), min(c, d)), max(max(a, b), max(c, d)))


def _up(value: Float64) -> Float64:
    """Return the adjacent greater binary64, including subnormal values."""
    if value == 0:
        return bitcast[DType.float64](UInt64(1))
    var bits = bitcast[DType.uint64](value)
    return bitcast[DType.float64](bits + 1 if value > 0 else bits - 1)


def _outward(low: Float64, high: Float64) -> _Interval:
    if not isfinite(low) or not isfinite(high):
        return _Interval(-inf[DType.float64](), inf[DType.float64]())
    return _Interval(-_up(-low), _up(high))


def _interval_difference(a: _P, b: _P) -> Array[_Interval, 3]:
    var result = Array[_Interval, 3](fill=_Interval(0, 0))
    # A coordinate difference always has exactly three components.
    for i in range(3):  # pragma: no branch
        result[i] = _outward(a[i] - b[i], a[i] - b[i])
    return result^


def _interval_cross(
    a: Array[_Interval, 3], b: Array[_Interval, 3]
) -> Array[_Interval, 3]:
    return [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]


def _interval_dot(a: Array[_Interval, 3], b: Array[_Interval, 3]) -> _Interval:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _exact_difference(a: _P, b: _P) -> Array[_Dyadic, 3]:
    return [
        _Dyadic(a[0]) - _Dyadic(b[0]),
        _Dyadic(a[1]) - _Dyadic(b[1]),
        _Dyadic(a[2]) - _Dyadic(b[2]),
    ]


def _exact_cross(
    a: Array[_Dyadic, 3], b: Array[_Dyadic, 3]
) -> Array[_Dyadic, 3]:
    return [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]


def _exact_dot(a: Array[_Dyadic, 3], b: Array[_Dyadic, 3]) -> _Dyadic:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _exact_normal(a: _P, b: _P, c: _P) -> Array[_Dyadic, 3]:
    return _exact_cross(_exact_difference(b, a), _exact_difference(c, a))


def _interval_normal(a: _P, b: _P, c: _P) -> Array[_Interval, 3]:
    return _interval_cross(
        _interval_difference(b, a), _interval_difference(c, a)
    )


@always_inline
def _ordinary_range(value: _P) -> Bool:
    """Keep each nonzero lane in [2**-100, 2**100], without scaling."""
    var bits = bitcast[DType.uint64](value) & UInt64(0x7FFFFFFFFFFFFFFF)
    return Bool(
        (
            bits.le(UInt64(0x4630000000000000))
            & (bits.eq(0) | bits.ge(UInt64(0x39B0000000000000)))
        ).reduce_and()
    )


@always_inline
def _fast_plane(a: _P, b: _P, c: _P, p: _P, tolerance: Float64) -> Int:
    """Certify a signed distance comparison, or return zero when uncertain.

    Let u be 2**-53. Every rounded nonzero affine difference is guarded
    in [2**-100, 2**100]. Zero differences are exact: finite binary64
    differences are integer multiples of the smallest subnormal. Thus
    every difference satisfies the usual relative-error model. Subsequent
    products, cancellations, squares, and bound arithmetic remain normal
    and finite. Rounded differences are multiples of 2**-152. Even with
    multiply-add contraction, cross products have quantum 2**-304,
    determinants have quantum 2**-456, and the degree-six margin has
    quantum 2**-912. No such nonzero value underflows. Degree-six
    magnitudes stay below 2**610.

    P is the six-term absolute determinant permanent. The zero-tolerance
    determinant has at most eight rounding factors per expanded monomial;
    64*u*P bounds its error, including rounding in P. For positive t, the
    exact margin is D**2-t**2*|N|**2. B=P**2+t**2*S bounds the absolute
    monomial sum, where S sums the squared cross-component permanents.
    Each expanded margin monomial has fewer than 32 rounding factors.
    The computed positive B is at least (1-u)**32 times its exact value.
    Consequently the margin error is below
    ((1+u)**32-1)/(1-u)**32 * B < 64*u*B. We use 512*u*B as a conservative
    bound. Both bound multipliers are exact powers of two. A bound is
    used only to certify a strict sign; uncertainty keeps the exact path.
    """
    var u = _P(b[0] - a[0], b[1] - a[1], b[2] - a[2], 0)
    var v = _P(c[0] - a[0], c[1] - a[1], c[2] - a[2], 0)
    var w = _P(p[0] - a[0], p[1] - a[1], p[2] - a[2], 0)
    if (
        not _ordinary_range(u)
        or not _ordinary_range(v)
        or not _ordinary_range(w)
    ):
        return 0
    var r0 = u[1] * v[2]
    var r1 = u[2] * v[1]
    var r2 = u[2] * v[0]
    var r3 = u[0] * v[2]
    var r4 = u[0] * v[1]
    var r5 = u[1] * v[0]
    var nx = r0 - r1
    var ny = r2 - r3
    var nz = r4 - r5
    var sx = abs(r0) + abs(r1)
    var sy = abs(r2) + abs(r3)
    var sz = abs(r4) + abs(r5)
    var determinant = (nx * w[0] + ny * w[1]) + nz * w[2]
    var permanent = (sx * abs(w[0]) + sy * abs(w[1])) + sz * abs(w[2])
    var error = Float64(7.105427357601002e-15) * permanent
    if determinant < -error:
        return -1
    if determinant <= error:
        return 0
    if tolerance == 0:
        return 1
    if tolerance < Float64(7.888609052210118e-31) or tolerance > Float64(
        1.2676506002282294e30
    ):
        return 0
    var norm = (nx * nx + ny * ny) + nz * nz
    var norm_permanent = (sx * sx + sy * sy) + sz * sz
    var squared_tolerance = tolerance * tolerance
    var margin = determinant * determinant - squared_tolerance * norm
    var bound = Float64(5.684341886080802e-14) * (
        permanent * permanent + squared_tolerance * norm_permanent
    )
    if margin > bound:
        return 1
    if margin < -bound:
        return -1
    return 0


def _orient3d(a: _P, b: _P, c: _P, p: _P) -> Int:
    """Return the exact sign of ((b-a) cross (c-a)) dot (p-a)."""
    var fast = _fast_plane(a, b, c, p, 0)
    if fast != 0:
        return fast
    var bound = _interval_dot(
        _interval_normal(a, b, c), _interval_difference(p, a)
    )
    if bound.low > 0:
        return 1
    if bound.high < 0:
        return -1
    return _exact_dot(_exact_normal(a, b, c), _exact_difference(p, a)).sign


def _plane_above(a: _P, b: _P, c: _P, p: _P, tolerance: Float64) -> Bool:
    """Test exact signed distance > a finite, nonnegative tolerance.

    The zero normal has no outside points. Equality is inside. No square
    root, normalized normal, rounded subtraction, or tolerance epsilon
    participates in the exact comparison.
    """
    var fast = _fast_plane(a, b, c, p, tolerance)
    if fast != 0:
        return fast > 0
    var normal = _interval_normal(a, b, c)
    var distance = _interval_dot(normal, _interval_difference(p, a))
    if distance.high <= 0:
        return False
    if distance.low > 0:
        if tolerance == 0:
            return True
        var t = _Interval(tolerance, tolerance)
        var margin = distance * distance - t * t * _interval_dot(normal, normal)
        if margin.low > 0:
            return True
        if margin.high < 0:
            return False
    var exact_normal = _exact_normal(a, b, c)
    var determinant = _exact_dot(exact_normal, _exact_difference(p, a))
    if determinant.sign <= 0:
        return False
    if tolerance == 0:
        return True
    var t = _Dyadic(tolerance)
    return (
        determinant * determinant
        - t * t * _exact_dot(exact_normal, exact_normal)
    ).sign > 0


def _collinear(a: _P, b: _P, c: _P) -> Bool:
    """Return whether the exact affine cross product is zero."""
    var normal = _interval_normal(a, b, c)
    # A 3D normal always has three components to inspect.
    for i in range(3):  # pragma: no branch
        if normal[i].low > 0 or normal[i].high < 0:
            return False
    var exact = _exact_normal(a, b, c)
    return exact[0].sign == 0 and exact[1].sign == 0 and exact[2].sign == 0


@always_inline
def _normal_estimate(a: _P, b: _P, c: _P) -> Array[Float64, 3]:
    """Return a certified scaled normal; zero means exact collinearity.

    Components share a power-of-two scale. The largest has magnitude in
    [1, 2], apart from rounding. For guarded, well-conditioned crosses,
    each component error is at most 32*u times the largest component,
    where u=2**-53. Unit-direction error, including ordinary Float64
    normalization, is below 128*u. A tiny estimated component need not
    have the exact sign. Callers must use predicates for orientation and
    distance decisions.
    Unsafe or ill-conditioned inputs keep the exact dyadic estimate.
    """
    var u = _P(b[0] - a[0], b[1] - a[1], b[2] - a[2], 0)
    var v = _P(c[0] - a[0], c[1] - a[1], c[2] - a[2], 0)
    if _ordinary_range(u) and _ordinary_range(v):
        var r0 = u[1] * v[2]
        var r1 = u[2] * v[1]
        var r2 = u[2] * v[0]
        var r3 = u[0] * v[2]
        var r4 = u[0] * v[1]
        var r5 = u[1] * v[0]
        var nx = r0 - r1
        var ny = r2 - r3
        var nz = r4 - r5
        var permanent = max(
            abs(r0) + abs(r1),
            max(abs(r2) + abs(r3), abs(r4) + abs(r5)),
        )
        var magnitude = max(abs(nx), max(abs(ny), abs(nz)))
        # Each cross monomial has at most four rounding factors, including
        # input subtraction. Its component error is <8*u*permanent.
        # This condition bounds it by 32*u*magnitude and proves that the
        # true cross is nonzero. Normalization adds <6*u to its direction
        # error, below 64*sqrt(3)*u + 6*u <128*u in total.
        if magnitude > 0 and permanent <= 4 * magnitude:
            var factor = ldexp(
                Float64(1), Int32(1 - _split(magnitude).exponent)
            )
            return [nx * factor, ny * factor, nz * factor]
    return _dyadic_normal_estimate(a, b, c)


@no_inline
def _dyadic_normal_estimate(a: _P, b: _P, c: _P) -> Array[Float64, 3]:
    """Keep the fixed-storage exact-normal fallback off the ordinary stack."""
    var normal = _exact_normal(a, b, c)
    var estimates: Array[_Scaled[DType.float64], 3] = [
        normal[0]._estimate(),
        normal[1]._estimate(),
        normal[2]._estimate(),
    ]
    return _common_scale(estimates)


def _difference_compare(a: Float64, b: Float64, c: Float64, d: Float64) -> Int:
    """Compare exact a-b and c-d without rounding either difference."""
    var result = _outward(a - b, a - b) - _outward(c - d, c - d)
    if result.low > 0:
        return 1
    if result.high < 0:
        return -1
    return (_Dyadic(a) - _Dyadic(b) - (_Dyadic(c) - _Dyadic(d))).sign


def _same_plane_distance_compare(a: _P, b: _P, c: _P, p: _P, q: _P) -> Int:
    """Compare signed distances of p and q from one oriented plane."""
    var bound = _interval_dot(
        _interval_normal(a, b, c), _interval_difference(p, q)
    )
    if bound.low > 0:
        return 1
    if bound.high < 0:
        return -1
    return _exact_dot(_exact_normal(a, b, c), _exact_difference(p, q)).sign


def _same_plane_absolute_distance_compare(
    a: _P, b: _P, c: _P, p: _P, q: _P
) -> Int:
    """Compare absolute distances of p and q from one nondegenerate plane."""
    var normal = _exact_normal(a, b, c)
    var first = _exact_dot(normal, _exact_difference(p, a))
    var second = _exact_dot(normal, _exact_difference(q, a))
    return first._compare_abs(second)


def _plane_distance_compare(
    a: _P, b: _P, c: _P, p: _P, d: _P, e: _P, f: _P, q: _P
) -> Int:
    """Compare signed distances from two nondegenerate oriented planes."""
    var first_normal = _exact_normal(a, b, c)
    var second_normal = _exact_normal(d, e, f)
    var first = _exact_dot(first_normal, _exact_difference(p, a))
    var second = _exact_dot(second_normal, _exact_difference(q, d))
    if first.sign != second.sign:
        return 1 if first.sign > second.sign else -1
    var margin = first * first * _exact_dot(
        second_normal, second_normal
    ) - second * second * _exact_dot(first_normal, first_normal)
    return first.sign * margin.sign


def _absolute_plane_distance_compare(
    a: _P, b: _P, c: _P, p: _P, d: _P, e: _P, f: _P, q: _P
) -> Int:
    """Compare absolute distances from two nondegenerate planes."""
    var first_normal = _exact_normal(a, b, c)
    var second_normal = _exact_normal(d, e, f)
    var first = _exact_dot(first_normal, _exact_difference(p, a))
    var second = _exact_dot(second_normal, _exact_difference(q, d))
    return (
        first * first * _exact_dot(second_normal, second_normal)
        - second * second * _exact_dot(first_normal, first_normal)
    ).sign


def _line_distance_compare(a: _P, b: _P, p: _P, q: _P) -> Int:
    """Compare squared distances from p and q to the nondegenerate line ab."""
    var edge = _exact_difference(b, a)
    var first = _exact_cross(edge, _exact_difference(p, a))
    var second = _exact_cross(edge, _exact_difference(q, a))
    return (_exact_dot(first, first) - _exact_dot(second, second)).sign


def _segment_distance_numerator(a: _P, b: _P, p: _P) -> _Dyadic:
    """Return squared segment distance times the shared squared edge length."""
    var edge = _exact_difference(b, a)
    var gap = _exact_difference(p, a)
    var length = _exact_dot(edge, edge)
    if length.sign == 0:
        return _exact_dot(gap, gap)
    var projection = _exact_dot(edge, gap)
    if projection.sign <= 0:
        return _exact_dot(gap, gap) * length
    if (projection - length).sign >= 0:
        gap = _exact_difference(p, b)
        return _exact_dot(gap, gap) * length
    var cross = _exact_cross(edge, gap)
    return _exact_dot(cross, cross)


def _segment_distance_compare(a: _P, b: _P, p: _P, q: _P) -> Int:
    """Compare squared distances to the closed segment, including its ends."""
    return (
        _segment_distance_numerator(a, b, p)
        - _segment_distance_numerator(a, b, q)
    ).sign
