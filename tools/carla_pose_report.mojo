# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Differentiate the stored town lane centers and write the pose report.

The derivatives are mpmath's central difference at 80 decimal places. Sine,
cosine and arctangent use the stored polynomials. Display text is 45 digits.

    mojo run -I . tools/carla_pose_report.mojo

writes `pose-results.json` under `out/carla-lane-oracle`, or under
`CARLA_LANE_ORACLE_OUTPUT`, and prints the same JSON.
"""

from std.math import sqrt
from std.os import getenv, makedirs
from std.os.path import exists, realpath
from std.pathlib import Path

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._json_tools import JsonWriter
from tools._json_value import JsonTree
from tools._python_float import parse_float


comptime _SCALE = 640
"""Bits below the binary point in a fixed-point value."""
comptime _DIFF_BITS = 279
"""mpmath's central-difference step at 80 decimal places is 2^-279."""


@fieldwise_init
struct Fix(Copyable, Movable):
    """A number stored as numerator / 2^640, rounded to nearest, ties to even.
    """

    var n: BigInt
    """The scaled numerator."""


@fieldwise_init
struct Pair(Copyable, Movable):
    """Sine and cosine of one phase."""

    var sine: Fix
    var cosine: Fix


struct Row(Copyable, Movable):
    """One parabola sample, in fixed point."""

    var u: Fix
    var v: Fix
    var s: Fix
    var tu: Fix
    var tv: Fix

    def __init__(out self, u: Fix, v: Fix, s: Fix, tu: Fix, tv: Fix):
        self.u = u.copy()
        self.v = v.copy()
        self.s = s.copy()
        self.tu = tu.copy()
        self.tv = tv.copy()


def repository_root(start: String) raises -> String:
    """Return the repository that contains the lane-oracle constants.

    Args:
        start: A directory inside the repository, or the repository itself.

    Returns:
        The repository root.

    Raises:
        Error: If the walk does not find the constants file.
    """
    var directory = start
    while True:
        if exists(directory + "/tools/carla_lane_oracle/constants.json"):
            return directory
        var slash = directory.rfind("/")
        if slash <= 0:
            raise Error("cannot find the lane-oracle constants")
        var parent = String(directory[byte=:slash])
        directory = parent


def output_directory(root: String, output_env: String) -> String:
    """Return the directory that receives the pose report.

    Args:
        root: The repository root.
        output_env: `CARLA_LANE_ORACLE_OUTPUT`, or empty when it is unset.

    Returns:
        The environment value, or `root/out/carla-lane-oracle`.
    """
    if output_env.byte_length() == 0:
        return root + "/out/carla-lane-oracle"
    return output_env


def _round_shift(numer: BigInt, shift: Int) -> BigInt:
    """Return numer / 2^shift, rounded to nearest, ties to even."""
    if shift <= 0:
        return numer.copy()
    var quot = numer >> shift
    var rem = numer - (quot << shift)
    var half = BigInt.power_of_two(shift - 1)
    if rem > half or (rem == half and quot.is_odd()):
        return quot + BigInt(1)
    return quot^


def _round_div(numer: BigInt, denom: BigInt) raises -> BigInt:
    """Return numer / denom, rounded to nearest, ties to even."""
    var parts = numer.divmod(denom)
    var quot = parts[0].copy()
    var rem = parts[1].copy()
    var twice = rem + rem
    if twice > denom or (twice == denom and quot.is_odd()):
        return quot + BigInt(1)
    return quot^


def fix_int(value: Int) -> Fix:
    """Return an integer in fixed point.

    Args:
        value: The integer.

    Returns:
        The fixed-point value.
    """
    return Fix(BigInt(value) << _SCALE)


def fix_fraction(value: Fraction) raises -> Fix:
    """Round an exact fraction to fixed point.

    Args:
        value: The fraction.

    Returns:
        The fixed-point value.

    Raises:
        Error: If the rounding division fails.
    """
    return Fix(_round_div(value.numerator << _SCALE, value.denominator))


def fix_float(text: String) raises -> Fix:
    """Round the exact value of a Python float literal.

    Args:
        text: The literal, as Python's `float` reads it.

    Returns:
        The fixed-point value.

    Raises:
        Error: If the literal is not a float.
    """
    return fix_fraction(Fraction.from_float(parse_float(text)))


def fix_add(a: Fix, b: Fix) -> Fix:
    """Return a + b."""
    return Fix(a.n + b.n)


def fix_neg(a: Fix) -> Fix:
    """Return -a."""
    return Fix(-a.n)


def fix_sub(a: Fix, b: Fix) -> Fix:
    """Return a - b."""
    return fix_add(a, fix_neg(b))


def fix_mul(a: Fix, b: Fix) -> Fix:
    """Return a * b, rounded back onto the grid."""
    return Fix(_round_shift(a.n * b.n, _SCALE))


def fix_div(a: Fix, b: Fix) raises -> Fix:
    """Return a / b.

    Raises:
        Error: If the divisor is zero.
    """
    if b.n.is_zero():
        raise Error("fixed-point division by zero")
    return Fix(_round_div(a.n << _SCALE, b.n))


def fix_text(value: Fix) raises -> String:
    """Return 45-digit text for a fixed-point value.

    Args:
        value: The value.

    Returns:
        The decimal text.

    Raises:
        Error: If the digits cannot be formed.
    """
    if value.n.is_zero():
        return "0.0"
    return nstr(Fraction.of(value.n.copy(), BigInt.power_of_two(_SCALE)), 45)


def _min_fixed(dps: Int) -> Int:
    """Return mpmath's default `min_fixed` for `dps` digits."""
    var third = -(dps // 3)
    if third < -5:
        return third
    return -5


def _ten_le(exponent: Int, numer: BigInt, denom: BigInt) raises -> Bool:
    """Return whether 10^exponent <= numer/denom."""
    if exponent >= 0:
        return (BigInt(10) ** exponent) * denom <= numer
    return denom <= numer * (BigInt(10) ** (-exponent))


def _floor_log10(numer: BigInt, denom: BigInt) raises -> Int:
    """Return floor(log10(numer/denom))."""
    var bits = numer.bit_length() - denom.bit_length()
    var exponent = bits * 30103 // 100000
    if _ten_le(exponent, numer, denom):
        while _ten_le(exponent + 1, numer, denom):
            exponent += 1
    else:
        while not _ten_le(exponent, numer, denom):
            exponent -= 1
    return exponent


def _place_digits(
    text: String, count: Int, exponent: Int
) -> Tuple[String, Int]:
    """Fit `text` to `count` digits and adjust the exponent."""
    if text.byte_length() > count:
        var extra = text.byte_length() - count
        var trimmed = String(text[byte=:count])
        return (trimmed^, exponent + extra)
    if text.byte_length() < count:
        var padded = "0" * (count - text.byte_length()) + text
        return (padded^, exponent)
    return (String(text), exponent)


def _round_significant(digits: String, dps: Int) -> Tuple[String, Int]:
    """Round `digits` to `dps` places. The integer is 1 when the exponent grows.
    """
    var marker = String(digits[byte = dps : dps + 1])
    var round_up = (
        marker == "5"
        or marker == "6"
        or marker == "7"
        or marker == "8"
        or marker == "9"
    )
    if not round_up:
        var kept = String(digits[byte=:dps])
        return (kept^, 0)
    var raw = String(digits[byte=:dps]).as_bytes()
    var values = List[Int]()
    for index in range(len(raw)):
        values.append(Int(raw[index]) - 48)
    var cursor = len(values) - 1
    while cursor >= 0 and values[cursor] == 9:
        values[cursor] = 0
        cursor -= 1
    if cursor >= 0:
        values[cursor] += 1
        var out = String()
        for value in values:
            out += chr(value + 48)
        return (out^, 0)
    var carried = String("1")
    var zeros = dps - 1
    while zeros > 0:
        carried += "0"
        zeros -= 1
    return (carried^, 1)


def _strip_zeros(text: String) -> String:
    """Drop trailing zeros and keep one digit after a final point."""
    var end = text.byte_length()
    var raw = text.as_bytes()
    while end > 0 and Int(raw[end - 1]) == 48:
        end -= 1
    var kept = String(text[byte=:end])
    if kept.byte_length() == 0:
        return "0"
    var last = String(kept[byte = kept.byte_length() - 1 : kept.byte_length()])
    if last == ".":
        kept += "0"
    return kept^


def nstr(value: Fraction, dps: Int) raises -> String:
    """Return `mpmath.nstr` of an exact fraction.

    Args:
        value: The exact value.
        dps: The number of significant digits.

    Returns:
        The decimal text.

    Raises:
        Error: If a power or a quotient cannot be formed.
    """
    if value.is_zero():
        return "0.0"
    var sign = String("-") if value.numerator.negative else String()
    var numer = abs(value.numerator)
    var denom = value.denominator.copy()
    var exponent = _floor_log10(numer, denom)
    var count = dps + 3
    var power = count - 1 - exponent
    var digits_int: BigInt
    if power >= 0:
        digits_int = (numer * (BigInt(10) ** power)) // denom
    else:
        digits_int = numer // (denom * (BigInt(10) ** (-power)))
    var placed = _place_digits(digits_int.to_string(), count, exponent)
    var rounded = _round_significant(placed[0], dps)
    exponent = placed[1] + rounded[1]
    var digits = rounded[0]
    var split = 1
    if _min_fixed(dps) < exponent and exponent < dps:
        if exponent < 0:
            var padded = "0" * (-exponent) + digits
            digits = padded
        else:
            split = exponent + 1
        exponent = 0
    var whole = String(digits[byte=:split])
    var frac = String(digits[byte=split:])
    var body = _strip_zeros(whole + "." + frac)
    if exponent == 0:
        return sign + body
    if exponent > 0:
        return sign + body + "e+" + String(exponent)
    return sign + body + "e" + String(exponent)


def _isqrt(value: BigInt) raises -> BigInt:
    """Return floor(sqrt(value))."""
    if value.is_zero():
        return BigInt(0)
    if value.negative:
        raise Error("square root of a negative integer")
    var x = BigInt.power_of_two((value.bit_length() + 1) // 2)
    while True:
        var y = (x + value // x) >> 1
        if y >= x:
            return x^
        x = y^


def sqrt_text(value: Fix) raises -> String:
    """Return 45-digit text for the square root of a non-negative value.

    Args:
        value: The squared length.

    Returns:
        The decimal text.

    Raises:
        Error: If the value is negative.
    """
    if value.n.is_zero():
        return "0.0"
    if value.n.negative:
        raise Error("square root of a negative value")
    var root = _isqrt(value.n)
    return nstr(Fraction.of(root, BigInt.power_of_two(_SCALE // 2)), 45)


def _atan_unit(z: Fix) raises -> Fix:
    """Return atan(z) for 0 <= z <= 1."""
    var total = Fix(BigInt(0))
    var power = z.copy()
    var square = fix_mul(z, z)
    for k in range(400):
        var term = fix_div(power, fix_int(2 * k + 1))
        if k % 2 == 1:
            term = fix_neg(term)
        total = fix_add(total, term)
        power = fix_mul(power, square)
    return total^


def _pi(one: Fix) raises -> Fix:
    """Return pi from Machin's formula."""
    var fifth = fix_div(one, fix_int(5))
    var inv = fix_div(one, fix_int(239))
    return fix_mul(
        fix_int(4),
        fix_sub(fix_mul(fix_int(4), _atan_unit(fifth)), _atan_unit(inv)),
    )


def _atan(z: Fix, pi: Fix) raises -> Fix:
    """Return atan(z). A half-angle reduction keeps the series short."""
    if z.n.negative:
        return fix_neg(_atan(fix_neg(z), pi))
    if z.n > fix_int(1).n:
        return fix_sub(
            fix_div(pi, fix_int(2)), _atan(fix_div(fix_int(1), z), pi)
        )
    var half = fix_div(fix_int(1), fix_int(2))
    if z.n > half.n:
        var reduced = fix_div(fix_sub(z, fix_int(1)), fix_add(z, fix_int(1)))
        return fix_add(fix_div(pi, fix_int(4)), _atan(reduced, pi))
    return _atan_unit(z)


def _atan2(y: Fix, x: Fix, pi: Fix) raises -> Fix:
    """Return atan2(y, x)."""
    if x.n > BigInt(0):
        return _atan(fix_div(y, x), pi)
    if x.n < BigInt(0) and not y.n.negative:
        return fix_add(_atan(fix_div(y, x), pi), pi)
    if x.n < BigInt(0) and y.n.negative:
        return fix_sub(_atan(fix_div(y, x), pi), pi)
    if y.n > BigInt(0):
        return fix_div(pi, fix_int(2))
    if y.n.negative:
        return fix_neg(fix_div(pi, fix_int(2)))
    return Fix(BigInt(0))


def _parse_rational(text: String) raises -> Fraction:
    """Read `n` or `n/d`."""
    var slash = text.find("/")
    if slash < 0:
        return Fraction(BigInt.parse(text))
    var top = String(text[byte=:slash])
    var bottom = String(text[byte = slash + 1 :])
    return Fraction.of(BigInt.parse(top), BigInt.parse(bottom))


def _coefficients(text: String, name: String) raises -> List[Fix]:
    """Read one comptime float array as fixed-point `float` values."""
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
    var values = List[Fix]()
    for part in body.split(","):
        var token = String(String(part).strip())
        if token.byte_length() == 0:
            continue
        values.append(fix_float(token))
    if len(values) == 0:
        raise Error("missing " + name)
    return values^


def _rational(tree: JsonTree, node: Int, name: String) raises -> Fraction:
    """Read one exact rational constant."""
    var member = tree.get(node, name)
    return _parse_rational(
        tree.string_value(tree.get(member, "exact_rational"))
    )


def _poly(coefficients: List[Fix], x: Fix) raises -> Fix:
    """Evaluate a polynomial, highest coefficient first."""
    var last = len(coefficients) - 1
    var value = coefficients[last].copy()
    var index = last - 1
    while index >= 0:
        value = fix_add(fix_mul(value, x), coefficients[index].copy())
        index -= 1
    return value^


def _sincos(
    phase: Fix,
    sine: List[Fix],
    cosine: List[Fix],
    inv: Fix,
    high: Fix,
    low: Fix,
) raises -> Pair:
    """Return the stored split-reduction sine and cosine."""
    var quadrant = (
        fix_add(fix_mul(phase, inv), fix_div(fix_int(1), fix_int(2)))
    ).n >> _SCALE
    var q = quadrant.to_int()
    var qf = fix_int(q)
    var reduced = fix_sub(fix_sub(phase, fix_mul(qf, high)), fix_mul(qf, low))
    var square = fix_mul(reduced, reduced)
    var sn = fix_mul(reduced, _poly(sine, square))
    var cs = _poly(cosine, square)
    var mode = q % 4
    if mode < 0:
        mode += 4
    if mode == 0:
        return Pair(sn^, cs^)
    if mode == 1:
        return Pair(cs^, fix_neg(sn))
    if mode == 2:
        return Pair(fix_neg(sn), fix_neg(cs))
    return Pair(fix_neg(cs), sn^)


def _arctan_poly(
    x: Fix, coefficients: List[Fix], half_pi: Fix, quarter_pi: Fix, reduce: Fix
) raises -> Fix:
    """Return the stored arctangent polynomial."""
    var sign = False
    var y = x.copy()
    if y.n.negative:
        sign = True
        y = fix_neg(y)
    var inverted = y.n > fix_int(1).n
    if inverted:
        y = fix_div(fix_int(1), y)
    var shifted = y.n > reduce.n
    if shifted:
        y = fix_div(fix_sub(y, fix_int(1)), fix_add(y, fix_int(1)))
    var value = fix_mul(y, _poly(coefficients, fix_mul(y, y)))
    if shifted:
        value = fix_add(quarter_pi, value)
    if inverted:
        value = fix_sub(half_pi, value)
    if sign:
        return fix_neg(value)
    return value^


def _moment(
    nodes: List[Fraction], weights: List[Fraction], count: Int, power: Int
) raises -> Fraction:
    """Return one Gauss moment."""
    var total = Fraction(0)
    var n = Fraction(count)
    var two = Fraction(2)
    for station in range(count):
        for index in range(5):
            var node = nodes[index].copy()
            var weight = weights[index].copy()
            var base = (Fraction(station) + (node / two)) / n
            total = total + weight * (base**power)
    return total / (two * n)


def _float_fractions(text: String, name: String) raises -> List[Fraction]:
    """Read one coefficient array as exact float fractions."""
    var at = text.find("comptime " + name)
    if at < 0:
        raise Error("missing " + name)
    var rest = String(text[byte=at:])
    var eq = rest.find("=")
    var after = String(rest[byte=eq:])
    var open = after.find("[")
    var close = after.find("]")
    var body = String(after[byte = open + 1 : close])
    var values = List[Fraction]()
    for part in body.split(","):
        var token = String(String(part).strip())
        if token.byte_length() == 0:
            continue
        values.append(Fraction.from_float(parse_float(token)))
    return values^


def _store(mut values: List[Fraction], index: Int, value: Fraction):
    """Replace one polynomial coefficient."""
    values[index] = value.copy()


def _shoulder_fractions(
    trig: String,
    nodes: List[Fraction],
    weights: List[Fraction],
    half_rate: Fraction,
    lane: Fraction,
) raises -> Tuple[List[Fix], List[Fix]]:
    """Build the shoulder polynomials from exact fractions, then snap them."""
    var sine = _float_fractions(trig, "_SIN_COEFFICIENTS")
    var cosine = _float_fractions(trig, "_COS_COEFFICIENTS")
    var x = List[Fraction]()
    var y = List[Fraction]()
    for _index in range(44):
        x.append(Fraction(0))
        y.append(Fraction(0))
    _store(y, 0, Fraction(100))
    for j in range(11):
        var even = half_rate ** (2 * j)
        var odd = even * half_rate
        _store(
            x,
            4 * j + 1,
            x[4 * j + 1]
            + cosine[j] * even * _moment(nodes, weights, 12, 4 * j),
        )
        _store(
            y,
            4 * j + 3,
            y[4 * j + 3]
            + sine[j] * odd * _moment(nodes, weights, 12, 4 * j + 2),
        )
        _store(x, 4 * j + 2, x[4 * j + 2] + lane * sine[j] * odd)
        _store(y, 4 * j, y[4 * j] - lane * cosine[j] * even)
    var x_fix = List[Fix]()
    var y_fix = List[Fix]()
    for index in range(44):
        x_fix.append(fix_fraction(x[index]))
        y_fix.append(fix_fraction(y[index]))
    return (x_fix^, y_fix^)


def _step() -> Fix:
    """Return mpmath's central-difference step, 2^-279."""
    return Fix(BigInt.power_of_two(_SCALE - _DIFF_BITS))


def _spiral_x(
    q: Fix,
    px: List[Fix],
    a: Fix,
    sine: List[Fix],
    cosine: List[Fix],
    inv: Fix,
    high: Fix,
    low: Fix,
) raises -> Fix:
    """Return the lane -1 spiral x at station q."""
    var pair = _sincos(fix_mul(a, fix_mul(q, q)), sine, cosine, inv, high, low)
    return fix_sub(
        _poly(px, q), fix_mul(fix_div(fix_int(5), fix_int(2)), pair.sine)
    )


def _spiral_y(
    q: Fix,
    py: List[Fix],
    a: Fix,
    sine: List[Fix],
    cosine: List[Fix],
    inv: Fix,
    high: Fix,
    low: Fix,
) raises -> Fix:
    """Return the lane -1 spiral y at station q."""
    var pair = _sincos(fix_mul(a, fix_mul(q, q)), sine, cosine, inv, high, low)
    return fix_add(
        _poly(py, q), fix_mul(fix_div(fix_int(5), fix_int(2)), pair.cosine)
    )


def _derive(low_value: Fix, high_value: Fix, step: Fix) raises -> Fix:
    """Return (f(x+h) - f(x-h)) / (2h) from the two samples."""
    return fix_div(fix_sub(high_value, low_value), fix_add(step, step))


def _offset(q: Fix, normalized: Bool, hundredth: Fix) raises -> Fix:
    """Return the lane offset at station q."""
    if normalized:
        return fix_sub(
            fix_fraction(Fraction.of(BigInt(15), BigInt(4))),
            fix_mul(hundredth, fix_sub(q, fix_int(20))),
        )
    var first = fix_div(
        fix_add(
            fix_fraction(Fraction.of(BigInt(13), BigInt(4))),
            fix_mul(hundredth, q),
        ),
        fix_int(2),
    )
    var second = fix_add(
        fix_div(fix_int(1), fix_int(2)),
        fix_mul(hundredth, fix_sub(q, fix_int(20))),
    )
    return fix_neg(fix_add(first, second))


def _center(
    q: Fix,
    left: Row,
    right: Row,
    base: Int,
    heading: Fix,
    origin_x: Int,
    origin_y: Int,
    normalized: Bool,
    hundredth: Fix,
    sine: List[Fix],
    cosine: List[Fix],
    inv: Fix,
    high: Fix,
    low: Fix,
    half_pi: Fix,
    quarter_pi: Fix,
    reduce: Fix,
    arc: List[Fix],
) raises -> Pair:
    """Return the CARLA x and y of one interpolated center."""
    var station = fix_sub(q, fix_int(base))
    var span = fix_sub(right.s, left.s)
    var mix = fix_div(fix_sub(right.s, station), span)
    var other = fix_sub(fix_int(1), mix)
    var u = fix_add(fix_mul(mix, left.u), fix_mul(other, right.u))
    var v = fix_add(fix_mul(mix, left.v), fix_mul(other, right.v))
    var tu = fix_add(fix_mul(mix, left.tu), fix_mul(other, right.tu))
    var tv = fix_add(fix_mul(mix, left.tv), fix_mul(other, right.tv))
    var theta = fix_add(
        heading, _arctan_poly(fix_div(tv, tu), arc, half_pi, quarter_pi, reduce)
    )
    var along = _sincos(heading, sine, cosine, inv, high, low)
    var turned = _sincos(theta, sine, cosine, inv, high, low)
    var offset = _offset(q, normalized, hundredth)
    var x = fix_add(
        fix_add(fix_int(origin_x), fix_mul(u, along.cosine)),
        fix_add(fix_neg(fix_mul(v, along.sine)), fix_mul(offset, turned.sine)),
    )
    var y = fix_sub(
        fix_add(
            fix_add(fix_int(origin_y), fix_mul(u, along.sine)),
            fix_mul(v, along.cosine),
        ),
        fix_mul(offset, turned.cosine),
    )
    return Pair(x^, y^)


def _table(length: Int, normalized: Bool) raises -> List[Row]:
    """Return one parabola chord table, using Python float association."""
    var count = Int(Float64(length) / parse_float("0.5"))
    if count < 5:
        count = 5
    var step = 1.0 / Float64(count)
    if not normalized:
        step = step * Float64(length)
    var scale = parse_float("10") if normalized else parse_float("1")
    var bend = parse_float("2") if normalized else parse_float("0.02")
    var position = 0.0
    var last_u = 0.0
    var last_v = 0.0
    var last_s = 0.0
    var rows = List[Row]()
    rows.append(
        Row(
            fix_int(0),
            fix_int(0),
            fix_int(0),
            fix_float(String("10") if normalized else String("1")),
            fix_int(0),
        )
    )
    for _index in range(count):
        position = position + step
        var u = position * scale
        var v = position * (position * bend)
        var tu = scale
        var tv = position * (parse_float("2") * bend)
        var du = u - last_u
        var dv = v - last_v
        var ds = sqrt(du * du + dv * dv)
        last_s = last_s + ds
        last_u = u
        last_v = v
        rows.append(
            Row(
                fix_fraction(Fraction.from_float(u)),
                fix_fraction(Fraction.from_float(v)),
                fix_fraction(Fraction.from_float(last_s)),
                fix_fraction(Fraction.from_float(tu)),
                fix_fraction(Fraction.from_float(tv)),
            )
        )
        if last_s > Float64(length):
            break
    return rows^


def _write_angles(
    mut writer: JsonWriter, dx: Fix, dy: Fix, dz: Fix, reverse: Bool, pi: Fix
) raises:
    """Write one angle record's six members."""
    var speed = fix_add(fix_mul(dx, dx), fix_mul(dy, dy))
    var yaw = fix_mul(fix_neg(_atan2(dy, dx, pi)), fix_div(fix_int(180), pi))
    var horizontal = Fix(_isqrt(speed.n) << (_SCALE // 2))
    # horizontal is only used inside atan2; the printed speed is separate.
    var pitch = fix_mul(
        fix_neg(_atan2(dz, horizontal, pi)), fix_div(fix_int(180), pi)
    )
    if reverse:
        yaw = fix_add(yaw, fix_int(180))
        pitch = fix_sub(fix_int(360), pitch)
    writer.key("dx_ODR")
    writer.string(fix_text(dx))
    writer.key("dy_ODR")
    writer.string(fix_text(dy))
    writer.key("dz")
    writer.string(fix_text(dz))
    writer.key("horizontal_speed")
    writer.string(sqrt_text(speed))
    writer.key("yaw_degrees")
    writer.string(fix_text(yaw))
    writer.key("pitch_degrees")
    writer.string(fix_text(pitch))


def _sample_block(
    mut writer: JsonWriter,
    rows: List[Row],
    station: Int,
    base: Int,
    heading: Fix,
    origin_x: Int,
    origin_y: Int,
    normalized: Bool,
    reverse: Bool,
    hundredth: Fix,
    thousandth: Fix,
    sine: List[Fix],
    cosine: List[Fix],
    inv: Fix,
    high: Fix,
    low: Fix,
    half_pi: Fix,
    quarter_pi: Fix,
    reduce: Fix,
    arc: List[Fix],
    step: Fix,
    pi: Fix,
) raises:
    """Write one sampled-parabola pose, including the active chord."""
    var distance = Float64(station - base)
    var index = 0
    for cursor in range(len(rows) - 1):
        var next_s = Fraction.of(
            rows[cursor + 1].s.n.copy(), BigInt.power_of_two(_SCALE)
        ).to_float()
        if next_s >= distance:
            index = cursor
            break
    var left = rows[index].copy()
    var right = rows[index + 1].copy()
    var q = fix_int(station)
    var low_q = fix_sub(q, step)
    var high_q = fix_add(q, step)
    var dx = _derive(
        _center(
            low_q,
            left,
            right,
            base,
            heading,
            origin_x,
            origin_y,
            normalized,
            hundredth,
            sine,
            cosine,
            inv,
            high,
            low,
            half_pi,
            quarter_pi,
            reduce,
            arc,
        ).sine,
        _center(
            high_q,
            left,
            right,
            base,
            heading,
            origin_x,
            origin_y,
            normalized,
            hundredth,
            sine,
            cosine,
            inv,
            high,
            low,
            half_pi,
            quarter_pi,
            reduce,
            arc,
        ).sine,
        step,
    )
    var dy = _derive(
        _center(
            low_q,
            left,
            right,
            base,
            heading,
            origin_x,
            origin_y,
            normalized,
            hundredth,
            sine,
            cosine,
            inv,
            high,
            low,
            half_pi,
            quarter_pi,
            reduce,
            arc,
        ).cosine,
        _center(
            high_q,
            left,
            right,
            base,
            heading,
            origin_x,
            origin_y,
            normalized,
            hundredth,
            sine,
            cosine,
            inv,
            high,
            low,
            half_pi,
            quarter_pi,
            reduce,
            arc,
        ).cosine,
        step,
    )
    var dz = fix_mul(thousandth, fix_int(station - 30))
    _write_angles(writer, dx, dy, dz, reverse, pi)
    var place = _center(
        q,
        left,
        right,
        base,
        heading,
        origin_x,
        origin_y,
        normalized,
        hundredth,
        sine,
        cosine,
        inv,
        high,
        low,
        half_pi,
        quarter_pi,
        reduce,
        arc,
    )
    writer.key("active_sample_index")
    writer.integer(index)
    writer.key("active_sample_s")
    writer.begin_array()
    writer.string(fix_text(left.s))
    writer.string(fix_text(right.s))
    writer.end()
    writer.key("center_CARLA")
    writer.begin_array()
    writer.string(fix_text(place.sine))
    writer.string(fix_text(fix_neg(place.cosine)))
    writer.end()


def reports(root: String) raises -> String:
    """Return the pose report JSON, including the final newline.

    Args:
        root: The repository root.

    Returns:
        The report text.

    Raises:
        Error: If a constant or a coefficient cannot be read.
    """
    var trig = Path(root + "/extensions/carla/curve_trig.mojo").read_text()
    var sine = _coefficients(trig, "_SIN_COEFFICIENTS")
    var cosine = _coefficients(trig, "_COS_COEFFICIENTS")
    var arc = _coefficients(trig, "_ATAN_COEFFICIENTS")
    var tree = JsonTree()
    var document = tree.parse(
        Path(root + "/tools/carla_lane_oracle/constants.json").read_text()
    )
    var nodes = List[Fraction]()
    var weights = List[Fraction]()
    for index in range(5):
        nodes.append(
            _rational(tree, document, "one_plus_node_" + String(index))
        )
        weights.append(_rational(tree, document, "weight_" + String(index)))
    var rate = _rational(tree, document, "spiral_rate")
    var lane = (
        _rational(tree, document, "lane_width_-1")
        + _rational(tree, document, "lane_width_-2") / Fraction(2)
        - _rational(tree, document, "lane_offset")
    )
    var polys = _shoulder_fractions(
        trig, nodes, weights, rate / Fraction(2), lane
    )
    var px = polys[0].copy()
    var py = polys[1].copy()
    var a = fix_fraction(rate / Fraction(2))
    var inv = fix_float("0.6366197723675814")
    var high = fix_float("1.57079632673412561417")
    var low = fix_float("6.07710050650619224932e-11")
    var half_pi = fix_float("1.5707963267948966")
    var quarter_pi = fix_float("0.7853981633974483")
    var reduce = fix_float("0.41421356237309503")
    var hundredth = fix_float("0.01")
    var thousandth = fix_float("0.002")
    var pi = _pi(fix_int(1))
    var step = _step()
    var writer = JsonWriter()
    writer.begin_object()
    writer.key("road1_section1_lane-1_s50")
    writer.begin_object()
    _write_angles(
        writer, fix_int(1), fix_neg(fix_float("0.025")), fix_int(0), False, pi
    )
    writer.end()
    writer.key("road5_lane-1_s10")
    writer.begin_object()
    var q = fix_int(10)
    var dx = _derive(
        _spiral_x(fix_sub(q, step), px, a, sine, cosine, inv, high, low),
        _spiral_x(fix_add(q, step), px, a, sine, cosine, inv, high, low),
        step,
    )
    var dy = _derive(
        _spiral_y(fix_sub(q, step), py, a, sine, cosine, inv, high, low),
        _spiral_y(fix_add(q, step), py, a, sine, cosine, inv, high, low),
        step,
    )
    _write_angles(writer, dx, dy, fix_float("0.02"), False, pi)
    writer.end()
    writer.key("road5_lane1_s40")
    writer.begin_object()
    _sample_block(
        writer,
        _table(12, False),
        40,
        35,
        fix_float("0.6"),
        35,
        112,
        False,
        True,
        hundredth,
        thousandth,
        sine,
        cosine,
        inv,
        high,
        low,
        half_pi,
        quarter_pi,
        reduce,
        arc,
        step,
        pi,
    )
    writer.end()
    writer.key("road5_lane-2_s50")
    writer.begin_object()
    _sample_block(
        writer,
        _table(10, True),
        50,
        47,
        fix_float("0.7"),
        46,
        118,
        True,
        False,
        hundredth,
        thousandth,
        sine,
        cosine,
        inv,
        high,
        low,
        half_pi,
        quarter_pi,
        reduce,
        arc,
        step,
        pi,
    )
    writer.end()
    writer.key("road5_lane0_s0")
    writer.begin_object()
    _write_angles(writer, fix_int(1), fix_int(0), fix_float("0.02"), False, pi)
    writer.end()
    writer.end()
    return writer.text() + "\n"


def publish(directory: String, output_env: String) raises -> String:
    """Write `pose-results.json` and return its text.

    Args:
        directory: A directory inside the repository.
        output_env: `CARLA_LANE_ORACLE_OUTPUT`, or empty when it is unset.

    Returns:
        The report text.

    Raises:
        Error: If the report cannot be built or written.
    """
    var root = repository_root(directory)
    var output = output_directory(root, output_env)
    var text = reports(root)
    makedirs(output, exist_ok=True)
    Path(output + "/pose-results.json").write_text(text)
    return text


def main() raises:
    """Write the pose report and print it."""
    var text = publish(realpath("."), getenv("CARLA_LANE_ORACLE_OUTPUT", ""))
    print(text, end="")
