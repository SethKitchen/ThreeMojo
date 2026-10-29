# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bound the rounded town lane operations with exact rational intervals.

Each operation receives an interval for the exact stored expression and an
absolute error for executed Float64 arithmetic. Endpoints and errors snap
outward onto the 2^-160 grid. Round-to-nearest unit roundoff is 2^-53, and
each elementary operation also allows 2^-1075 for gradual underflow. FTZ/DAZ
is unsupported. Quadrature terms are materialized before the Sum2 recurrence.

    mojo run -I . tools/carla_rounding_bound.mojo

writes `rounding-results.json` under `out/carla-lane-oracle`, or under
`CARLA_LANE_ORACLE_OUTPUT`, and prints the same report without the per-count
rows. The bytes match the reviewed Python rounding report.
"""

from std.os import getenv, makedirs
from std.os.path import exists, realpath
from std.pathlib import Path

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._json_tools import JsonWriter
from tools._json_tree import JsonTree
from tools._lane_reports import repository_root, output_directory, nstr, isqrt
from tools._python_float import parse_float


comptime _GRID = 160
"""Bits of the outward rounding grid, 2^-160."""
comptime _HALF_PI_HIGH = "1.57079632673412561417"
"""The high half of the split pi/2 constant."""
comptime _HALF_PI_LOW = "6.07710050650619224932e-11"
"""The low half of the split pi/2 constant."""


@fieldwise_init
struct Bound(Copyable, Movable):
    """An outward grid interval and an absolute error, in units of 2^-160."""

    var lo: BigInt
    """The low endpoint times 2^160."""
    var hi: BigInt
    """The high endpoint times 2^160."""
    var e: BigInt
    """The absolute error times 2^160."""


@fieldwise_init
struct CountRow(Copyable, Movable):
    """One quadrature count in the shoulder report."""

    var count: Int
    """The node count."""
    var s_upper: String
    """The widened station upper bound."""
    var max_phase_error: String
    """The largest phase error."""
    var max_trig_error: String
    """The largest sine or cosine error."""
    var x_error: String
    """The x coordinate error."""
    var y_error: String
    """The y coordinate error."""
    var z_error: String
    """The z coordinate error."""
    var distance: String
    """The squared-distance error."""


@fieldwise_init
struct EndpointRow(Copyable, Movable):
    """One arc-endpoint exclusion row."""

    var quadrant: Int
    """The sine/cosine quadrant."""
    var division: Bool
    """True when sinc is a quotient."""
    var lower: String
    """The executed squared-distance lower bound."""
    var x_error: String
    """The x error."""
    var y_error: String
    """The y error."""


struct Cache:
    """Constants snapped the way `B(constant)` snaps them."""

    var zero: Bound
    var one: Bound
    var half: Bound
    var half_rate: Bound
    var grade: Bound
    var lane: Bound
    var spiral_x: Bound
    var spiral_y: Bound
    var arc_k: Bound
    var arc_radius: Bound
    var offset: Bound
    var nodes: List[Bound]
    var weights: List[Bound]
    var sine: List[Bound]
    var cosine: List[Bound]

    def __init__(
        out self,
        zero: Bound,
        one: Bound,
        half: Bound,
        half_rate: Bound,
        grade: Bound,
        lane: Bound,
        spiral_x: Bound,
        spiral_y: Bound,
        arc_k: Bound,
        arc_radius: Bound,
        offset: Bound,
        var nodes: List[Bound],
        var weights: List[Bound],
        var sine: List[Bound],
        var cosine: List[Bound],
    ):
        self.zero = zero.copy()
        self.one = one.copy()
        self.half = half.copy()
        self.half_rate = half_rate.copy()
        self.grade = grade.copy()
        self.lane = lane.copy()
        self.spiral_x = spiral_x.copy()
        self.spiral_y = spiral_y.copy()
        self.arc_k = arc_k.copy()
        self.arc_radius = arc_radius.copy()
        self.offset = offset.copy()
        self.nodes = nodes^
        self.weights = weights^
        self.sine = sine^
        self.cosine = cosine^


def _require(condition: Bool, message: String) raises:
    """Raise `message` when `condition` is false."""
    if not condition:
        raise Error(message)


def _parse_rational(text: String) raises -> Fraction:
    """Read `n` or `n/d` as a fraction."""
    var slash = text.find("/")
    if slash < 0:
        return Fraction(BigInt.parse(text))
    var top = String(text[byte=:slash])
    var bottom = String(text[byte = slash + 1 :])
    return Fraction.of(BigInt.parse(top), BigInt.parse(bottom))


def _rational(tree: JsonTree, node: Int, name: String) raises -> Fraction:
    """Read one `exact_rational` member."""
    var member = tree.item(node, name)
    var text = tree.text(tree.item(member, "exact_rational"))
    return _parse_rational(text)


def _coefficients(text: String, name: String) raises -> List[Fraction]:
    """Read one comptime Float64 array as exact `Fraction(float)` values."""
    var at = text.find("comptime " + name)
    if at < 0:
        raise Error("missing " + name)
    var rest = String(text[byte=at:])
    var eq = rest.find("=")
    if eq < 0:
        raise Error("missing " + name)
    var after = String(rest[byte=eq:])
    var open = after.find("[")
    var close = after.find("]")
    if open < 0 or close < open:
        raise Error("missing " + name)
    var body = String(after[byte = open + 1 : close])
    var values = List[Fraction]()
    for part in body.split(","):
        var token = String(String(part).strip())
        if token.byte_length() == 0:
            continue
        values.append(Fraction.from_float(parse_float(token)))
    if len(values) == 0:
        raise Error("missing " + name)
    return values^


def _fraction_text(value: Fraction) -> String:
    """Return `n` or `n/d`, as `str(Fraction)` does."""
    var text = value.numerator.to_string()
    if value.denominator != BigInt(1):
        text += "/"
        text += value.denominator.to_string()
    return text^


def _down(value: Fraction) raises -> BigInt:
    """Return floor(value * 2^160)."""
    return (value.numerator << _GRID) // value.denominator


def _up(value: Fraction) raises -> BigInt:
    """Return ceil(value * 2^160)."""
    return -_down(-value)


def _max_abs(a: BigInt, b: BigInt) -> BigInt:
    """Return the larger absolute value."""
    var left = abs(a)
    var right = abs(b)
    if left >= right:
        return left^
    return right^


def _min_abs(a: BigInt, b: BigInt) -> BigInt:
    """Return the smaller absolute value."""
    var left = abs(a)
    var right = abs(b)
    if left <= right:
        return left^
    return right^


def _ceil_shift(numer: BigInt, shift: Int) -> BigInt:
    """Return ceil(numer / 2^shift) for a non-negative numer."""
    var quot = numer >> shift
    if (quot << shift) != numer:
        return quot + BigInt(1)
    return quot^


def _ceil_div(numer: BigInt, den: BigInt) raises -> BigInt:
    """Return ceil(numer / den) for a non-negative numer and positive den."""
    var parts = numer.divmod(den)
    var quot = parts[0].copy()
    if parts[1].is_zero():
        return quot^
    return quot + BigInt(1)


def _error_pow2(mag: BigInt, prop: BigInt, shift: Int) -> BigInt:
    """Snap `prop/2^shift + u*(mag/2^160 + prop/2^shift) + 2^-1075` upward."""
    var numer = (
        (prop << (1075 - shift))
        + (mag << 862)
        + (prop << (1022 - shift))
        + BigInt(1)
    )
    return _ceil_shift(numer, 915)


def _error_fraction(mag: BigInt, prop: Fraction) raises -> BigInt:
    """Snap `prop + u*(mag/2^160 + prop) + 2^-1075` upward."""
    var p = prop.numerator.copy()
    var q = prop.denominator.copy()
    var numer = (p << 1075) + ((mag * q) << 862) + (p << 1022) + q
    return _ceil_div(numer, q << 915)


def from_int(value: Int) -> Bound:
    """Return an exact integer bound with zero error.

    Args:
        value: The integer.

    Returns:
        The bound.
    """
    var n = BigInt(value) << _GRID
    return Bound(n.copy(), n^, BigInt(0))


def from_fraction(value: Fraction) raises -> Bound:
    """Return `B(value)`: the endpoint snapped down and zero error.

    Args:
        value: The exact value.

    Returns:
        The bound.

    Raises:
        Error: If the snap cannot divide.
    """
    var n = _down(value)
    return Bound(n.copy(), n^, BigInt(0))


def from_interval(low: Fraction, high: Fraction) raises -> Bound:
    """Return `B(low, high)` with zero error.

    Args:
        low: The low endpoint.
        high: The high endpoint.

    Returns:
        The bound, snapped outward.

    Raises:
        Error: If a snap cannot divide.
    """
    return Bound(_down(low), _up(high), BigInt(0))


def add_bounds(a: Bound, b: Bound) -> Bound:
    """Return `a + b` with one Float64 addition's error.

    Args:
        a: The left bound.
        b: The right bound.

    Returns:
        The sum.
    """
    var lo = a.lo + b.lo
    var hi = a.hi + b.hi
    var err = _error_pow2(_max_abs(lo, hi), a.e + b.e, 160)
    return Bound(lo^, hi^, err^)


def neg_bound(a: Bound) -> Bound:
    """Return `-a`. The error is unchanged.

    Args:
        a: The bound.

    Returns:
        The negation.
    """
    return Bound(-a.hi, -a.lo, a.e.copy())


def sub_bound(a: Bound, b: Bound) -> Bound:
    """Return `a - b`.

    Args:
        a: The left bound.
        b: The right bound.

    Returns:
        The difference.
    """
    return add_bounds(a, neg_bound(b))


def mul_bounds(a: Bound, b: Bound) -> Bound:
    """Return `a * b` with one Float64 multiplication's error.

    Args:
        a: The left bound.
        b: The right bound.

    Returns:
        The product.
    """
    var p0 = a.lo * b.lo
    var p1 = a.lo * b.hi
    var p2 = a.hi * b.lo
    var p3 = a.hi * b.hi
    var low = p0.copy()
    var high = p0.copy()
    if p1 < low:
        low = p1.copy()
    if p1 > high:
        high = p1.copy()
    if p2 < low:
        low = p2.copy()
    if p2 > high:
        high = p2.copy()
    if p3 < low:
        low = p3.copy()
    if p3 > high:
        high = p3.copy()
    var lo = low >> _GRID
    var hi: BigInt
    if high.negative:
        hi = -((-high) >> _GRID)
    else:
        hi = _ceil_shift(high, _GRID)
    var mag = _max_abs(lo, hi)
    var prop = (
        _max_abs(a.lo, a.hi) * b.e + _max_abs(b.lo, b.hi) * a.e + a.e * b.e
    )
    var err = _error_pow2(mag, prop, 320)
    return Bound(lo^, hi^, err^)


def divide_bounds(a: Bound, b: Bound) raises -> Bound:
    """Return `a / b` with one Float64 division's error.

    Args:
        a: The numerator.
        b: The denominator.

    Returns:
        The quotient.

    Raises:
        Error: If the denominator interval or its error reaches zero.
    """
    if not ((b.lo * b.hi) > BigInt(0)):
        raise Error("division domain contains zero")
    var gap_end = _min_abs(b.lo, b.hi)
    if not (b.e < gap_end):
        raise Error("division error reaches zero")
    var q0 = Fraction.of(a.lo.copy(), b.lo.copy())
    var q1 = Fraction.of(a.lo.copy(), b.hi.copy())
    var q2 = Fraction.of(a.hi.copy(), b.lo.copy())
    var q3 = Fraction.of(a.hi.copy(), b.hi.copy())
    var low = q0.copy()
    var high = q0.copy()
    if q1 < low:
        low = q1.copy()
    if q1 > high:
        high = q1.copy()
    if q2 < low:
        low = q2.copy()
    if q2 > high:
        high = q2.copy()
    if q3 < low:
        low = q3.copy()
    if q3 > high:
        high = q3.copy()
    var lo = _down(low)
    var hi = _up(high)
    var gap = gap_end - b.e
    var numer = a.e * gap_end + _max_abs(a.lo, a.hi) * b.e
    var prop = Fraction.of(numer, gap_end * gap)
    var err = _error_fraction(_max_abs(lo, hi), prop)
    return Bound(lo^, hi^, err^)


def divide_constant(a: Bound, divisor: Int) raises -> Bound:
    """Return `a / divisor` for a positive integer divisor.

    Args:
        a: The bound.
        divisor: The positive integer.

    Returns:
        The quotient.

    Raises:
        Error: If `divisor` is not positive.
    """
    if divisor <= 0:
        raise Error("nonpositive divisor")
    var n = BigInt(divisor)
    var lo = a.lo // n
    var hi = -((-a.hi) // n)
    var prop = Fraction.of(a.e.copy(), n << _GRID)
    var err = _error_fraction(_max_abs(lo, hi), prop)
    return Bound(lo^, hi^, err^)


def _sum2_error(
    magnitude: Fraction, inherited: Fraction, count: Int
) raises -> Fraction:
    """Return the independent Sum2 majorant."""
    var max_count = 1 << 30
    if count < 1 or count > max_count:
        raise Error("unsupported Sum2 count")
    var limit = Fraction(BigInt.power_of_two(900))
    if magnitude < Fraction(0) or magnitude > limit or inherited < Fraction(0):
        raise Error("unsupported Sum2 majorant")
    if magnitude.is_zero() or count == 1:
        return inherited.copy()
    var nu = BigInt(count - 1)
    var unit = BigInt.power_of_two(53)
    var gamma = Fraction.of(nu.copy(), unit - nu)
    var extra = (
        Fraction.of(BigInt(1), unit.copy()) + gamma * gamma
    ) * magnitude
    return inherited + extra


def sum2_terms(terms: List[Bound]) raises -> Bound:
    """Enclose a materialized Sum2 of `terms`.

    Args:
        terms: The materialized terms. The list must not be empty.

    Returns:
        The sum and its Sum2 error, snapped outward.

    Raises:
        Error: If `terms` is empty or the count is outside the reviewed range.
    """
    if len(terms) == 0:
        raise Error("empty Sum2 term sequence")
    var low = BigInt(0)
    var high = BigInt(0)
    var inherited = BigInt(0)
    var magnitude = BigInt(0)
    for index in range(len(terms)):
        low = low + terms[index].lo
        high = high + terms[index].hi
        inherited = inherited + terms[index].e
        magnitude = magnitude + _max_abs(terms[index].lo, terms[index].hi)
        magnitude = magnitude + terms[index].e
    var grid = BigInt.power_of_two(_GRID)
    var err = _up(
        _sum2_error(
            Fraction.of(magnitude.copy(), grid.copy()),
            Fraction.of(inherited.copy(), grid.copy()),
            len(terms),
        )
    )
    return Bound(low^, high^, err^)


def _radius(numer: BigInt, denom: BigInt) raises -> String:
    """Return nstr(sqrt(numer/denom), 45) through a scaled integer square root.
    """
    var scaled = (numer * (BigInt(10) ** 240)) // denom
    return nstr(Fraction.of(isqrt(scaled), BigInt(10) ** 120), 45)


def _grid_text(numer: BigInt) raises -> String:
    """Return nstr of numer/2^160."""
    return nstr(Fraction.of(numer, BigInt.power_of_two(_GRID)), 45)


def _bump(current: BigInt, candidate: BigInt) -> BigInt:
    """Return the larger integer."""
    if candidate > current:
        return candidate.copy()
    return current.copy()


def poly(coefficients: List[Bound], x: Bound) -> Bound:
    """Evaluate a polynomial by Horner, highest coefficient first.

    Args:
        coefficients: The coefficients from the constant term upward.
        x: The argument.

    Returns:
        The polynomial value.
    """
    var last = len(coefficients) - 1
    var value = coefficients[last].copy()
    var index = last - 1
    while index >= 0:
        value = add_bounds(
            mul_bounds(value, x.copy()), coefficients[index].copy()
        )
        index -= 1
    return value^


def sincos(
    theta: Bound, quadrant: Int, sine: List[Bound], cosine: List[Bound]
) raises -> Tuple[Bound, Bound]:
    """Return the split-reduction sine and cosine for one quadrant.

    Args:
        theta: The phase.
        quadrant: The quadrant index. Negative values wrap as Python's `%` does.
        sine: The sine coefficients, constant term first.
        cosine: The cosine coefficients, constant term first.

    Returns:
        Sine and cosine for `quadrant % 4`.

    Raises:
        Error: If a coefficient snap cannot divide.
    """
    var turns = Fraction(quadrant)
    var high = from_fraction(
        turns * Fraction.from_float(parse_float(_HALF_PI_HIGH))
    )
    var low = from_fraction(
        turns.copy() * Fraction.from_float(parse_float(_HALF_PI_LOW))
    )
    var reduced = sub_bound(sub_bound(theta, high), low)
    var square = mul_bounds(reduced.copy(), reduced.copy())
    var sn = mul_bounds(reduced, poly(sine, square.copy()))
    var cs = poly(cosine, square)
    var mode = quadrant % 4
    if mode == 0:
        return (sn^, cs^)
    if mode == 1:
        return (cs^, neg_bound(sn))
    if mode == 2:
        return (neg_bound(sn), neg_bound(cs))
    return (neg_bound(cs), sn^)


def load_cache(root: String) raises -> Cache:
    """Load the town constants and the sine and cosine coefficients.

    Args:
        root: The repository root.

    Returns:
        Bounds snapped the way the Python report snaps them.

    Raises:
        Error: If a constant or a coefficient cannot be read.
    """
    var tree = JsonTree()
    var document = tree.parse(
        Path(root + "/tools/fixtures/carla_lane_constants.json").read_text()
    )
    var trig = Path(root + "/extensions/carla/curve_trig.mojo").read_text()
    var sine_values = _coefficients(trig, "_SIN_COEFFICIENTS")
    var cosine_values = _coefficients(trig, "_COS_COEFFICIENTS")
    var lane = (
        _rational(tree, document, "lane_width_-1")
        + (_rational(tree, document, "lane_width_-2") / Fraction(2))
        - _rational(tree, document, "lane_offset")
    )
    var half = from_fraction(Fraction.of(BigInt(1), BigInt(2)))
    var rate = from_fraction(_rational(tree, document, "spiral_rate"))
    var half_rate = mul_bounds(half.copy(), rate)
    var nodes = List[Bound]()
    var weights = List[Bound]()
    var sine = List[Bound]()
    var cosine = List[Bound]()
    for index in range(5):
        nodes.append(
            from_fraction(
                _rational(tree, document, "one_plus_node_" + String(index))
            )
        )
        weights.append(
            from_fraction(_rational(tree, document, "weight_" + String(index)))
        )
    for index in range(len(sine_values)):
        sine.append(from_fraction(sine_values[index].copy()))
    for index in range(len(cosine_values)):
        cosine.append(from_fraction(cosine_values[index].copy()))
    return Cache(
        from_int(0),
        from_int(1),
        half,
        half_rate,
        from_fraction(_rational(tree, document, "elevation_b")),
        from_fraction(lane),
        from_fraction(_rational(tree, document, "spiral_x")),
        from_fraction(_rational(tree, document, "spiral_y")),
        from_fraction(_rational(tree, document, "arc_k")),
        from_fraction(_rational(tree, document, "arc_radius")),
        from_fraction(Fraction.of(BigInt(7), BigInt(4))),
        nodes^,
        weights^,
        sine^,
        cosine^,
    )


def _upper(count: Int) raises -> Fraction:
    """Return min(20, max(0, count-1) + 1e-12)."""
    var base = count - 1
    if base < 0:
        base = 0
    var widened = Fraction(base) + Fraction.of(BigInt(1), BigInt(10) ** 12)
    var limit = Fraction(20)
    if widened < limit:
        return widened^
    return limit^


def _check(
    count: Int, cache: Cache
) raises -> Tuple[CountRow, BigInt, BigInt, BigInt, BigInt]:
    """Return one shoulder count and its coordinate and distance errors."""
    var upper = _upper(count)
    var domain = from_interval(Fraction(0), upper.copy())
    var step = divide_constant(domain.copy(), count)
    var half_step = mul_bounds(step.copy(), cache.half.copy())
    var x_terms = List[Bound]()
    var y_terms = List[Bound]()
    var max_phase = BigInt(0)
    var max_trig = BigInt(0)
    for station in range(count):
        var start = mul_bounds(step.copy(), from_int(station))
        for node in range(5):
            var t = add_bounds(
                start.copy(),
                mul_bounds(half_step.copy(), cache.nodes[node].copy()),
            )
            var inner = add_bounds(
                cache.zero.copy(),
                mul_bounds(cache.half_rate.copy(), t.copy()),
            )
            var theta = add_bounds(cache.zero.copy(), mul_bounds(t, inner))
            var pair = sincos(theta.copy(), 0, cache.sine, cache.cosine)
            var factor = mul_bounds(
                half_step.copy(), cache.weights[node].copy()
            )
            x_terms.append(mul_bounds(factor.copy(), pair[1].copy()))
            y_terms.append(mul_bounds(factor, pair[0].copy()))
            max_phase = _bump(max_phase, theta.e.copy())
            max_trig = _bump(max_trig, pair[0].e.copy())
            max_trig = _bump(max_trig, pair[1].e.copy())
    _require(len(x_terms) == 5 * count, "wrong Sum2 node count")
    _require(len(y_terms) == 5 * count, "wrong Sum2 node count")
    var x = add_bounds(cache.spiral_x.copy(), sum2_terms(x_terms))
    var y = add_bounds(cache.spiral_y.copy(), sum2_terms(y_terms))
    var phase_inner = add_bounds(
        cache.zero.copy(), mul_bounds(cache.half_rate.copy(), domain.copy())
    )
    var phase = add_bounds(
        cache.zero.copy(), mul_bounds(domain.copy(), phase_inner)
    )
    var arm = sincos(phase, 0, cache.sine, cache.cosine)
    var px = add_bounds(x, mul_bounds(cache.lane.copy(), arm[0].copy()))
    var py = sub_bound(y, mul_bounds(cache.lane.copy(), arm[1].copy()))
    var z0 = mul_bounds(domain.copy(), cache.zero.copy())
    var z1 = add_bounds(cache.zero.copy(), z0)
    var z2 = mul_bounds(domain.copy(), z1)
    var z3 = add_bounds(cache.grade.copy(), z2)
    var z4 = mul_bounds(domain.copy(), z3)
    var z = add_bounds(cache.one.copy(), z4)
    var x_error = px.e.copy()
    var y_error = py.e.copy()
    var z_error = z.e.copy()
    var dx = sub_bound(px, from_int(10))
    var dy = sub_bound(neg_bound(py), from_int(105))
    var dz = sub_bound(z, cache.zero.copy())
    var distance = add_bounds(
        add_bounds(mul_bounds(dx.copy(), dx), mul_bounds(dy.copy(), dy)),
        mul_bounds(dz.copy(), dz),
    )
    var row = CountRow(
        count,
        nstr(upper, 45),
        _grid_text(max_phase),
        _grid_text(max_trig),
        _grid_text(x_error.copy()),
        _grid_text(y_error.copy()),
        _grid_text(z_error.copy()),
        _grid_text(distance.e.copy()),
    )
    return (row^, x_error^, y_error^, z_error^, distance.e.copy())


def _below(numer: BigInt, numer_limit: Int, denom_limit: Int) raises -> Bool:
    """Return whether numer/2^160 is below numer_limit/denom_limit."""
    return Fraction.of(numer, BigInt.power_of_two(_GRID)) < Fraction.of(
        BigInt(numer_limit), BigInt(denom_limit)
    )


def _radial(cache: Cache) -> Bound:
    """Return `(radius + offset) * curvature`."""
    return mul_bounds(
        add_bounds(cache.arc_radius.copy(), cache.offset.copy()),
        cache.arc_k.copy(),
    )


def _arc_interior(cache: Cache) raises -> Tuple[String, String, String]:
    """Return the interior arc coordinate errors and the squared-distance error.
    """
    var d = from_interval(Fraction(0), Fraction(31))
    var turn = mul_bounds(d.copy(), cache.arc_k.copy())
    var half = mul_bounds(turn, cache.half.copy())
    var phase = add_bounds(cache.zero.copy(), half.copy())
    var factor = mul_bounds(_radial(cache), d)
    var square = mul_bounds(half.copy(), half.copy())
    var chord = mul_bounds(factor, poly(cache.sine, square))
    var origin = sincos(cache.zero.copy(), 0, cache.sine, cache.cosine)
    var turned = sincos(phase, 0, cache.sine, cache.cosine)
    var x = add_bounds(
        add_bounds(
            from_int(60), mul_bounds(cache.offset.copy(), origin[0].copy())
        ),
        mul_bounds(chord.copy(), turned[1].copy()),
    )
    var y = add_bounds(
        sub_bound(
            cache.zero.copy(), mul_bounds(cache.offset.copy(), origin[1].copy())
        ),
        mul_bounds(chord, turned[0].copy()),
    )
    var x_error = x.e.copy()
    var y_error = y.e.copy()
    var dx = sub_bound(x, from_int(70))
    var dy = sub_bound(neg_bound(y), from_int(10))
    var distance = add_bounds(
        mul_bounds(dx.copy(), dx), mul_bounds(dy.copy(), dy)
    )
    var worst = x_error.copy()
    if y_error > worst:
        worst = y_error.copy()
    _require(_below(worst, 1, 10**12), "arc coordinate error exceeds bound")
    _require(
        _below(distance.e.copy(), 4, 10**12),
        "arc distance error exceeds bound",
    )
    return (
        _grid_text(x_error),
        _grid_text(y_error),
        _grid_text(distance.e.copy()),
    )


def _axis_lower(coordinate: Bound, query: Int) raises -> Fraction:
    """Return the squared-distance contribution of one exact integer query."""
    var grid = BigInt.power_of_two(_GRID)
    var q = Fraction(query)
    var lo = Fraction.of(coordinate.lo - coordinate.e, grid.copy()) - q
    var hi = Fraction.of(coordinate.hi + coordinate.e, grid) - q.copy()
    if (lo * hi) > Fraction(0):
        var lo2 = lo * lo
        var hi2 = hi * hi
        if lo2 < hi2:
            return lo2^
        return hi2^
    return Fraction(0)


def _arc_endpoints(cache: Cache) raises -> List[EndpointRow]:
    """Return the four arc-endpoint exclusion rows."""
    var d = from_interval(
        Fraction(31), Fraction.from_float(parse_float("31.41592653589793"))
    )
    var half = mul_bounds(
        mul_bounds(d.copy(), cache.arc_k.copy()), cache.half.copy()
    )
    var phase = add_bounds(cache.zero.copy(), half.copy())
    var factor = mul_bounds(_radial(cache), d)
    var origin = sincos(cache.zero.copy(), 0, cache.sine, cache.cosine)
    var hs = origin[0].copy()
    var hc = origin[1].copy()
    var rows = List[EndpointRow]()
    for index in range(4):
        var quadrant = 0
        if index >= 2:
            quadrant = -1
        var use_division = index % 2 == 1
        var pair = sincos(half.copy(), quadrant, cache.sine, cache.cosine)
        var sinc: Bound
        if use_division:
            sinc = divide_bounds(pair[0].copy(), half.copy())
        else:
            var square = mul_bounds(half.copy(), half.copy())
            sinc = poly(cache.sine, square)
        var chord = mul_bounds(factor.copy(), sinc)
        var turned = sincos(phase.copy(), quadrant, cache.sine, cache.cosine)
        var x = add_bounds(
            add_bounds(
                from_int(60), mul_bounds(cache.offset.copy(), hs.copy())
            ),
            mul_bounds(chord.copy(), turned[1].copy()),
        )
        var plain = add_bounds(
            sub_bound(
                cache.zero.copy(), mul_bounds(cache.offset.copy(), hc.copy())
            ),
            mul_bounds(chord, turned[0].copy()),
        )
        var y = neg_bound(plain)
        var x_error = x.e.copy()
        var y_error = y.e.copy()
        var lower = _axis_lower(x, 70) + _axis_lower(y, 10)
        _require(lower > Fraction(100), "arc endpoint exclusion failed")
        rows.append(
            EndpointRow(
                quadrant,
                use_division,
                nstr(lower, 45),
                _grid_text(x_error),
                _grid_text(y_error),
            )
        )
    return rows^


def _string_list(mut writer: JsonWriter, values: List[String]):
    """Write an array of strings."""
    writer.begin_array()
    for index in range(len(values)):
        writer.string(values[index].copy())
    writer.end()


def _emit(
    include_counts: Bool,
    endpoints: List[EndpointRow],
    interior_x: String,
    interior_y: String,
    interior_d: String,
    rows: List[CountRow],
    max_x: String,
    max_y: String,
    max_z: String,
    max_d: String,
    shoulder: String,
    arc_text: String,
    unit: String,
    tiny: String,
) -> String:
    """Write one JSON report. `include_counts` inserts the per-count rows."""
    var writer = JsonWriter()
    writer.begin_object()
    writer.key("arc_endpoint_exclusion")
    writer.begin_array()
    for index in range(len(endpoints)):
        writer.begin_object()
        writer.key("quadrant")
        writer.integer(endpoints[index].quadrant)
        writer.key("sinc_division")
        writer.boolean(endpoints[index].division)
        writer.key("executed_D2_lower_bound")
        writer.string(endpoints[index].lower.copy())
        writer.key("coordinate_error_bounds")
        var errors = List[String]()
        errors.append(endpoints[index].x_error.copy())
        errors.append(endpoints[index].y_error.copy())
        _string_list(writer, errors)
        writer.end()
    writer.end()
    writer.key("arc_interior")
    writer.begin_object()
    writer.key("s_domain")
    writer.string("[0,31]")
    writer.key("coordinate_errors")
    var interior = List[String]()
    interior.append(interior_x.copy())
    interior.append(interior_y.copy())
    _string_list(writer, interior)
    writer.key("D2_arithmetic_error")
    writer.string(interior_d.copy())
    writer.key("certified_coordinate_bound")
    writer.string("1e-12")
    writer.key("certified_D2_bound")
    writer.string("4e-12")
    writer.end()
    writer.key("outward_rounding_grid")
    writer.string("2^-160")
    writer.key("unit_roundoff")
    writer.string(unit.copy())
    writer.key("additive_underflow_allowance_per_operation")
    writer.string(tiny.copy())
    writer.key("underflow_mode")
    writer.string("gradual only; FTZ/DAZ unsupported")
    writer.key("spiral_accumulation")
    writer.string("materialized Sum2; E + (u + gamma_(n-1)^2) M")
    writer.key("max_coordinate_errors")
    var maxima = List[String]()
    maxima.append(max_x.copy())
    maxima.append(max_y.copy())
    maxima.append(max_z.copy())
    _string_list(writer, maxima)
    writer.key("max_D2_arithmetic_error")
    writer.string(max_d.copy())
    writer.key("certified_coordinate_bound")
    writer.string("1e-12")
    writer.key("certified_D2_bound")
    writer.string("5e-11")
    writer.key("loose_original_coordinate_bound")
    writer.string("1e-11")
    writer.key("loose_original_D2_bound")
    writer.string("8.9000000000002e-9")
    writer.key("notes")
    var notes = List[String]()
    notes.append(
        "Count neighborhoods are widened by 1e-12 in s. A reach/count"
        + " argument bounds any count-boundary displacement by less than"
        + " this width."
    )
    notes.append(
        "The maximum coordinate bound applies to each executed point,"
        + " not only sampled points. All value intervals and error"
        + " computations are rational."
    )
    notes.append(
        "The exact real distance of the rounded point has no larger"
        + " error than the included separately rounded D² computation."
    )
    _string_list(writer, notes)
    if include_counts:
        writer.key("counts")
        writer.begin_array()
        for index in range(len(rows)):
            writer.begin_object()
            writer.key("count")
            writer.integer(rows[index].count)
            writer.key("s_upper")
            writer.string(rows[index].s_upper.copy())
            writer.key("max_phase_error")
            writer.string(rows[index].max_phase_error.copy())
            writer.key("max_trig_error")
            writer.string(rows[index].max_trig_error.copy())
            writer.key("coordinate_errors")
            var coordinates = List[String]()
            coordinates.append(rows[index].x_error.copy())
            coordinates.append(rows[index].y_error.copy())
            coordinates.append(rows[index].z_error.copy())
            _string_list(writer, coordinates)
            writer.key("D2_arithmetic_error")
            writer.string(rows[index].distance.copy())
            writer.end()
        writer.end()
    writer.key("rounded_minimizer_radius")
    writer.begin_object()
    writer.key("shoulder")
    writer.string(shoulder.copy())
    writer.key("arc")
    writer.string(arc_text.copy())
    writer.key("meaning")
    writer.string(
        "Every exact global minimizer of the executed rounded-point"
        + " distance lies in this radius around the smooth"
        + " stored-expression minimum. This is an enclosure, not a claim"
        + " of a unique rounded minimizer. The representable-s comparison"
        + " slack is below 1e-25 and is absorbed by the strict outward"
        + " margins."
    )
    writer.end()
    writer.end()
    return writer.text()


def reports(root: String) raises -> Tuple[String, String]:
    """Return the rounding report and the summary without per-count rows.

    Args:
        root: The repository root.

    Returns:
        The file text and the summary text. Each text ends with a newline.

    Raises:
        Error: If a constant is missing or a certified bound fails.
    """
    var cache = load_cache(root)
    var endpoints = _arc_endpoints(cache)
    var interior = _arc_interior(cache)
    var rows = List[CountRow]()
    var max_x = BigInt(0)
    var max_y = BigInt(0)
    var max_z = BigInt(0)
    var max_d = BigInt(0)
    for count in range(1, 24):
        var sample = _check(count, cache)
        max_x = _bump(max_x, sample[1].copy())
        max_y = _bump(max_y, sample[2].copy())
        max_z = _bump(max_z, sample[3].copy())
        max_d = _bump(max_d, sample[4].copy())
        rows.append(sample[0].copy())
    _require(
        _below(max_x.copy(), 1, 10**12), "coordinate error exceeds bound"
    )
    _require(
        _below(max_y.copy(), 1, 10**12), "coordinate error exceeds bound"
    )
    _require(
        _below(max_z.copy(), 1, 10**12), "coordinate error exceeds bound"
    )
    _require(_below(max_d.copy(), 5, 10**11), "distance error exceeds bound")
    var unit = _fraction_text(Fraction.of(BigInt(1), BigInt.power_of_two(53)))
    var tiny = _fraction_text(Fraction.of(BigInt(1), BigInt.power_of_two(1075)))
    var shoulder = _radius(
        BigInt(4) * BigInt(5) * (BigInt(10) ** 14),
        (BigInt(10) ** 11) * BigInt.parse("181329999999999"),
    )
    var arc_text = _radius(
        BigInt(16) * BigInt(1000), BigInt.parse("912499999999998")
    )
    var x_text = _grid_text(max_x)
    var y_text = _grid_text(max_y)
    var z_text = _grid_text(max_z)
    var d_text = _grid_text(max_d)
    var interior_x = interior[0].copy()
    var interior_y = interior[1].copy()
    var interior_d = interior[2].copy()
    var file = _emit(
        True,
        endpoints,
        interior_x,
        interior_y,
        interior_d,
        rows,
        x_text,
        y_text,
        z_text,
        d_text,
        shoulder,
        arc_text,
        unit,
        tiny,
    )
    var summary = _emit(
        False,
        endpoints,
        interior_x,
        interior_y,
        interior_d,
        rows,
        x_text,
        y_text,
        z_text,
        d_text,
        shoulder,
        arc_text,
        unit,
        tiny,
    )
    return (file + "\n", summary + "\n")


def publish(
    directory: String, output_env: String
) raises -> Tuple[String, String]:
    """Write `rounding-results.json` and return the file and summary texts.

    Args:
        directory: A directory inside the repository.
        output_env: `CARLA_LANE_ORACLE_OUTPUT`, or empty when it is unset.

    Returns:
        The file text and the summary text.

    Raises:
        Error: If the report cannot be built or written.
    """
    var root = repository_root(directory)
    var output = output_directory(root, output_env)
    var produced = reports(root)
    makedirs(output, exist_ok=True)
    var file = produced[0]
    var summary = produced[1]
    Path(output + "/rounding-results.json").write_text(file)
    return (file, summary^)


def main() raises:
    """Write the rounding report and print the summary."""
    var produced = publish(
        realpath("."), getenv("CARLA_LANE_ORACLE_OUTPUT", "")
    )
    print(produced[1], end="")
