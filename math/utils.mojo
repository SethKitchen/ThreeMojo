# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Scalar helpers, from three.js `src/math/MathUtils.js`.

three.js's `degToRad` and `radToDeg` are not here: an `Angle` converts
itself. `smoothstep` is in `math.smoothstep`, where both rasterizers
already read it.

The random numbers come from a `SeededRandom`, three.js's Mulberry32
generator, so that a sequence is the same on every run and every
platform. three.js's unseeded `randFloat` reads `Math.random`; a caller
here keeps a generator and asks it.

Differences from three.js 0.180.0: periodic helpers reduce exact binary
inputs before rounding. They avoid an overflowing period or add-divisor
step, retain small phases, and clamp Euclidean endpoint rounding toward
zero. See the Math wiki page for the finite and exceptional contracts.
"""
from core.ordinal import ordinal_valid, require_valid, require_positive

from math.quaternion import Quaternion
from math.random import mulberry32_step
from math.remainder import remainder_float64
from math.sine import fraction
from math.smoothstep import smoothstep
from std.math import cos, exp, floor, isfinite, sin
from std.memory import bitcast
from units.si import Angle, Duration, SECOND


def clamp(value: Float32, low: Float32, high: Float32) -> Float32:
    """Return `value` limited to the range from `low` to `high`.

    Args:
        value: The value.
        low: The smallest answer.
        high: The largest answer.

    Returns:
        The value within the range.
    """
    return max(low, min(high, value))


def clamp(value: Float64, low: Float64, high: Float64) -> Float64:
    """Return `value` limited to the range from `low` to `high`.

    Args:
        value: The value.
        low: The smallest answer.
        high: The largest answer.

    Returns:
        The value within the range.
    """
    return max(low, min(high, value))


def clamp(value: Int, low: Int, high: Int) -> Int:
    """Return `value` limited to the range from `low` to `high`.

    Error: Never.

    Args:
        value: The value.
        low: The smallest answer.
        high: The largest answer.

    Returns:
        The value within the range.

    """
    return max(low, min(high, value))


def clamp_lower_first(value: Float32, low: Float32, high: Float32) -> Float32:
    """Return `value` limited by the lower bound before the upper bound.

    Keep the order `min(max(value, low), high)`. Under the pinned
    arithmetic, a NaN value with finite ordered bounds returns `low`.
    `clamp` tests the upper bound first and returns `high` for that case.

    Args:
        value: The value.
        low: The lower bound.
        high: The upper bound.

    Returns:
        The result of the ordered lower-bound and upper-bound operations.
    """
    return min(max(value, low), high)


def clamp_lower_first(value: Float64, low: Float64, high: Float64) -> Float64:
    """Return `value` limited by the lower bound before the upper bound.

    Keep the order `min(max(value, low), high)`. Under the pinned
    arithmetic, a NaN value with finite ordered bounds returns `low`.
    `clamp` tests the upper bound first and returns `high` for that case.

    Args:
        value: The value.
        low: The lower bound.
        high: The upper bound.

    Returns:
        The result of the ordered lower-bound and upper-bound operations.
    """
    return min(max(value, low), high)


def edge_index(index: Int, count: Int) -> Int:
    """Return an index held inside a row or a column.

    An index before zero reads the first place. An index at `count` or
    past it reads the last place.

    Error: Never.

    Args:
        index: The requested index.
        count: How many places there are. One or more.

    Returns:
        The index from zero through `count - 1`.

    """
    return clamp(index, 0, count - 1)


def clamped_texel(column: Int, row: Int, width: Int, height: Int) -> Int:
    """Return a texel's place in a row-major image, held inside the image.

    A column or a row before zero reads the first place. One at the
    width or the height, or past it, reads the last place.

    Error: Never.

    Args:
        column: The column.
        row: The row.
        width: How many columns. One or more.
        height: How many rows. One or more.

    Returns:
        The place `row * width + column`, with both indexes held inside
        the image.

    """
    return edge_index(row, height) * width + edge_index(column, width)


def min3(x: Float32, y: Float32, z: Float32) -> Float32:
    """Return the smallest of three numbers.

    The second and third are compared, then that result with the first.

    Args:
        x: The first number.
        y: The second number.
        z: The third number.

    Returns:
        The smallest.
    """
    return min(x, min(y, z))


def min3(x: Float64, y: Float64, z: Float64) -> Float64:
    """Return the smallest of three numbers.

    The second and third are compared, then that result with the first.

    Args:
        x: The first number.
        y: The second number.
        z: The third number.

    Returns:
        The smallest.
    """
    return min(x, min(y, z))


def min3(x: Int, y: Int, z: Int) -> Int:
    """Return the smallest of three whole numbers.

    The second and third are compared, then that result with the first.

    Args:
        x: The first number.
        y: The second number.
        z: The third number.

    Returns:
        The smallest.
    """
    return min(x, min(y, z))


def max3(x: Float32, y: Float32, z: Float32) -> Float32:
    """Return the largest of three numbers.

    The second and third are compared, then that result with the first.

    Args:
        x: The first number.
        y: The second number.
        z: The third number.

    Returns:
        The largest.
    """
    return max(x, max(y, z))


def max3(x: Float64, y: Float64, z: Float64) -> Float64:
    """Return the largest of three numbers.

    The second and third are compared, then that result with the first.

    Args:
        x: The first number.
        y: The second number.
        z: The third number.

    Returns:
        The largest.
    """
    return max(x, max(y, z))


def max3(x: Int, y: Int, z: Int) -> Int:
    """Return the largest of three whole numbers.

    The second and third are compared, then that result with the first.

    Args:
        x: The first number.
        y: The second number.
        z: The third number.

    Returns:
        The largest.
    """
    return max(x, max(y, z))


def lerp(x: Float32, y: Float32, t: Float32) -> Float32:
    """Return the value a fraction `t` of the way from `x` to `y`.

    Args:
        x: The start.
        y: The end.
        t: The fraction.

    Returns:
        `(1 - t) x + t y`.
    """
    return (1 - t) * x + t * y


def mix_delta(start: Float32, end: Float32, t: Float32) -> Float32:
    """Return `start` moved toward `end` by `t`.

    The difference is formed first, then scaled, then added. `lerp`
    multiplies each end before the sum.

    Args:
        start: The value at zero.
        end: The value at one.
        t: The fraction.

    Returns:
        `start + (end - start) * t`.
    """
    return start + (end - start) * t


def mix_delta(start: Float64, end: Float64, t: Float64) -> Float64:
    """Return `start` moved toward `end` by `t`.

    The difference is formed first, then scaled, then added.

    Args:
        start: The value at zero.
        end: The value at one.
        t: The fraction.

    Returns:
        `start + (end - start) * t`.
    """
    return start + (end - start) * t


def mix_bilinear(
    a: Float32,
    b: Float32,
    c: Float32,
    d: Float32,
    across: Float32,
    down: Float32,
) -> Float32:
    """Return four samples blended, across then down.

    Args:
        a: The sample at the low column and low row.
        b: The sample at the high column and low row.
        c: The sample at the low column and high row.
        d: The sample at the high column and high row.
        across: How far from the low column toward the high column.
        down: How far from the low row toward the high row.

    Returns:
        The blend. Each edge is mixed by `across`, then the two results
        by `down`.
    """
    var top = mix_delta(a, b, across)
    var bottom = mix_delta(c, d, across)
    return mix_delta(top, bottom, down)


def mix_bilinear(
    a: Float64,
    b: Float64,
    c: Float64,
    d: Float64,
    across: Float64,
    down: Float64,
) -> Float64:
    """Return four samples blended, across then down.

    Args:
        a: The sample at the low column and low row.
        b: The sample at the high column and low row.
        c: The sample at the low column and high row.
        d: The sample at the high column and high row.
        across: How far from the low column toward the high column.
        down: How far from the low row toward the high row.

    Returns:
        The blend. Each edge is mixed by `across`, then the two results
        by `down`.
    """
    var top = mix_delta(a, b, across)
    var bottom = mix_delta(c, d, across)
    return mix_delta(top, bottom, down)


def mix_trilinear[
    dtype: DType, width: Int
](
    c000: SIMD[dtype, width],
    c100: SIMD[dtype, width],
    c010: SIMD[dtype, width],
    c110: SIMD[dtype, width],
    c001: SIMD[dtype, width],
    c101: SIMD[dtype, width],
    c011: SIMD[dtype, width],
    c111: SIMD[dtype, width],
    x: SIMD[dtype, 1],
    y: SIMD[dtype, 1],
    z: SIMD[dtype, 1],
) -> SIMD[dtype, width]:
    """Return eight samples blended, across, then down, then deep.

    Parameters:
        dtype: The sample type.
        width: How many lanes each sample holds.

    Args:
        c000: The sample at the low column, low row and low layer.
        c100: The sample at the high column, low row and low layer.
        c010: The sample at the low column, high row and low layer.
        c110: The sample at the high column, high row and low layer.
        c001: The sample at the low column, low row and high layer.
        c101: The sample at the high column, low row and high layer.
        c011: The sample at the low column, high row and high layer.
        c111: The sample at the high column, high row and high layer.
        x: How far from the low column toward the high column.
        y: How far from the low row toward the high row.
        z: How far from the low layer toward the high layer.

    Returns:
        The blend. Each edge is mixed by `x`, then those results by
        `y`, then those results by `z`.
    """
    var x00 = c000 + (c100 - c000) * x
    var x10 = c010 + (c110 - c010) * x
    var x01 = c001 + (c101 - c001) * x
    var x11 = c011 + (c111 - c011) * x
    var y0 = x00 + (x10 - x00) * y
    var y1 = x01 + (x11 - x01) * y
    return y0 + (y1 - y0) * z


def interleaved_gradient_noise(x: Float32, y: Float32) -> Float32:
    """Return Jimenez's interleaved gradient noise.

    three.js's `interleavedGradientNoise`: the fraction of `52.9829189`
    times the fraction of `x * 0.06711056 + y * 0.00583715`.

    Args:
        x: The column, in pixels.
        y: The row, in pixels.

    Returns:
        A number from zero up to one.
    """
    var inner = fraction(x * Float32(0.06711056) + y * Float32(0.00583715))
    return fraction(Float32(52.9829189) * inner)


def rec709_luminance(r: Float32, g: Float32, b: Float32) -> Float32:
    """Return rec. 709 luminance to four decimal places.

    three.js's `colorToLuminance`. `luminance_of` uses the longer weights.

    Args:
        r: Red.
        g: Green.
        b: Blue.

    Returns:
        `0.2126 r + 0.7152 g + 0.0722 b`.
    """
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def rec709_luminance(r: Float64, g: Float64, b: Float64) -> Float64:
    """Return rec. 709 luminance to four decimal places.

    three.js's `colorToLuminance`. `luminance_of` uses the longer weights.

    Args:
        r: Red.
        g: Green.
        b: Blue.

    Returns:
        `0.2126 r + 0.7152 g + 0.0722 b`.
    """
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def js_round(value: Float32) -> Float32:
    """Return `value` rounded to the nearest whole number, a half up.

    JavaScript's `Math.round`: -2.5 gives -2. The fraction is compared,
    so a `Float32` just below a half does not round up.

    Args:
        value: The number.

    Returns:
        The whole number.
    """
    var whole = floor(value)
    return whole + Float32(1) if value - whole >= 0.5 else whole


def js_round(value: Float64) -> Float64:
    """Return `value` rounded to the nearest whole number, a half up.

    JavaScript's `Math.round`: -2.5 gives -2.

    Args:
        value: The number.

    Returns:
        The whole number.
    """
    var whole = floor(value)
    return whole + 1 if value - whole >= 0.5 else whole


def js_round_int(value: Float64) -> Int:
    """Return `value` rounded to the nearest whole number, a half up.

    JavaScript's `Math.round`, stored as an `Int`. -2.5 gives -2.

    Error: Never.

    Args:
        value: The number.

    Returns:
        The whole number.

    """
    return Int(js_round(value))


def saturate(value: Float32) -> Float32:
    """Return `value` held from zero to one.

    GLSL's `saturate`.

    Args:
        value: The value.

    Returns:
        The value within zero and one.
    """
    return clamp(value, 0, 1)


def clamp_unit(value: Float32) -> Float32:
    """Return `value` held from minus one to one.

    An `acos` or `asin` argument uses this hold.

    Error: Never.

    Args:
        value: The value.

    Returns:
        The value within minus one and one.

    """
    return clamp(value, -1, 1)


def clamp_unit(value: Float64) -> Float64:
    """Return `value` held from minus one to one.

    An `acos` or `asin` argument uses this hold.

    Error: Never.

    Args:
        value: The value.

    Returns:
        The value within minus one and one.

    """
    return clamp(value, -1.0, 1.0)


def nearest_distance(value: Float64) -> Float64:
    """Return how far `value` lies from the nearest whole number.

    The answer is zero at a whole number and one half halfway between.

    Args:
        value: The number.

    Returns:
        The distance, from zero to one half.
    """
    return abs(value - floor(value + 0.5))


def glsl_mod(x: Float32, y: Float32) -> Float32:
    """Return GLSL's `mod`: `x` minus `y` times the floor of their ratio.

    Args:
        x: The value.
        y: The modulus.

    Returns:
        The remainder.
    """
    return x - y * floor(x / y)


def glsl_sign(x: Float32) -> Float32:
    """Return GLSL's `sign`.

    Args:
        x: The number.

    Returns:
        One when `x` is positive, minus one when it is negative, and zero
        for zero and NaN.
    """
    if x > 0:
        return 1
    if x < 0:
        return -1
    return 0


def glsl_sign(x: Float64) -> Float64:
    """Return GLSL's `sign`.

    Args:
        x: The number.

    Returns:
        One when `x` is positive, minus one when it is negative, and zero
        for zero and NaN.
    """
    if x > 0:
        return 1
    if x < 0:
        return -1
    return 0


def inverse_lerp(x: Float32, y: Float32, value: Float32) -> Float32:
    """Return the fraction of the way `value` lies from `x` to `y`.

    Args:
        x: The start.
        y: The end.
        value: The value.

    Returns:
        The fraction, or zero when the ends are equal, as in three.js.
    """
    if x == y:
        return 0
    return (value - x) / (y - x)


def map_linear(
    value: Float32, a1: Float32, a2: Float32, b1: Float32, b2: Float32
) -> Float32:
    """Map a value from one range to another.

    Args:
        value: The value in the first range.
        a1: The first range's start.
        a2: The first range's end.
        b1: The second range's start.
        b2: The second range's end.

    Returns:
        The value at the same fraction of the second range.
    """
    return b1 + (value - a1) * (b2 - b1) / (a2 - a1)


def damp(x: Float32, y: Float32, rate: Float32, delta: Duration) -> Float32:
    """Move `x` toward `y` at a rate that does not depend on the frame
    rate.

    Args:
        x: The current value.
        y: The target.
        rate: How fast, per second. Larger is faster.
        delta: The time since the last step.

    Returns:
        The damped value.
    """
    return lerp(x, y, 1 - exp(-rate * delta.to(SECOND)))


def euclidean_modulo(n: Float32, m: Float32) -> Float32:
    """Return a remainder with the divisor's sign and a strict range.

    Args:
        n: The dividend.
        m: The divisor.

    Returns:
        For finite operands and nonzero `m`, a result with the sign of `m`
        and magnitude below `abs(m)`. Round the exact mathematical result
        to Float32. If rounding reaches `m`, use its adjacent value toward
        zero. Exact multiples return zero with the sign of `m`. A zero
        divisor or either nonfinite operand returns NaN.
    """
    if not isfinite(n) or not isfinite(m) or m == 0:
        return bitcast[DType.float32](UInt32(0x7FC00000))
    var sign = bitcast[DType.uint32](m) & 0x80000000
    var remainder = remainder_float64(abs(Float64(n)), abs(Float64(m)))
    if remainder == 0:
        return bitcast[DType.float32](sign)
    if (n < 0) != (m < 0):
        remainder = abs(Float64(m)) - remainder
    var magnitude = Float32(remainder)
    if magnitude >= abs(m):
        magnitude = bitcast[DType.float32](
            (bitcast[DType.uint32](m) & 0x7FFFFFFF) - 1
        )
    return bitcast[DType.float32](bitcast[DType.uint32](magnitude) | sign)


def pingpong(x: Float32, length: Float32 = 1) -> Float32:
    """Return a triangular wave with an exact finite binary period.

    Args:
        x: The input.
        length: The peak. A positive finite value gives the usual wave.

    Returns:
        For positive finite `length` and finite `x`, a rounded value from
        zero to `length`, including positive zero at each period boundary.
        A negative length keeps three.js's extension from `2 * length` to
        `length`. That extension can overflow to negative infinity. A zero
        length or either nonfinite operand returns NaN.
    """
    if not isfinite(x) or not isfinite(length) or length == 0:
        return bitcast[DType.float32](UInt32(0x7FC00000))
    var peak = abs(Float64(length))
    var period = 2 * peak
    var remainder = remainder_float64(abs(Float64(x)), period)
    # Fold the magnitude directly. Subtracting a small phase from the
    # peak and then subtracting again would erase that phase.
    var folded = min(remainder, period - remainder)
    if length < 0:
        return Float32(folded - period)
    return Float32(folded)


def smootherstep(x: Float32, low: Float32, high: Float32) -> Float32:
    """Return Ken Perlin's smootherstep: a rise from zero to one with a
    flat first and second derivative at each end.

    Args:
        x: The value.
        low: Where the rise starts.
        high: Where the rise ends.

    Returns:
        A number from zero to one.
    """
    if x <= low:
        return 0
    if x >= high:
        return 1
    var t = (x - low) / (high - low)
    return t * t * t * (t * (t * 6 - 15) + 10)


def smooth_step(x: Float32, low: Float32, high: Float32) -> Float32:
    """Return three.js's `smoothstep(x, min, max)`, with its argument
    order.

    Args:
        x: The value.
        low: Where the rise starts.
        high: Where the rise ends.

    Returns:
        A number from zero to one.
    """
    return smoothstep(low, high, x)


def is_power_of_two(value: Int) -> Bool:
    """Return True if `value` is a positive power of two.

    Args:
        value: The number.

    Returns:
        Whether one bit of it is set.
    """
    return value > 0 and (value & (value - 1)) == 0


def ceil_power_of_two(value: Int) raises -> Int:
    """Return the smallest power of two at least `value`.

    Args:
        value: A positive number.

    Returns:
        The power of two.

    Raises:
        Error: If the value is not positive or its ceiling does not fit in Int.
    """
    require_positive(
        value, "Only a positive number has a power of two above it"
    )
    var power = 1
    while power < value:
        if power > Int.MAX // 2:
            raise Error("The power of two above this value does not fit in Int")
        power <<= 1
    return power


def floor_power_of_two(value: Int) raises -> Int:
    """Return the largest power of two at most `value`.

    Args:
        value: A positive number.

    Returns:
        The power of two.

    Raises:
        Error: If the value is not positive.
    """
    require_positive(
        value, "Only a positive number has a power of two below it"
    )
    var power = 1
    # Divide the bound first so the comparison cannot overflow.
    while power <= value // 2:
        power <<= 1
    return power


struct SeededRandom(Copyable, Movable):
    """The Mulberry32 generator of three.js's `seededRandom`.

    One generator gives the same numbers from the same seed, on every
    platform.
    """

    var state: UInt32

    def __init__(out self, seed: Int):
        """Create a generator.

        Args:
            seed: The seed. Only its low 32 bits are kept.
        """
        self.state = UInt32(seed & 0xFFFFFFFF)

    def next(mut self) -> Float64:
        """Return the next number.

        Returns:
            A number from zero up to, not including, one.
        """
        return mulberry32_step(self.state)

    def float_in(mut self, low: Float32, high: Float32) -> Float32:
        """Return a number in a range. three.js: `randFloat`.

        Args:
            low: The smallest.
            high: The top, not reached.

        Returns:
            A finite value in `[low, high)` for finite bounds with
            `low < high`. Equal finite bounds return `low`. Each call
            advances the generator once. Other bounds keep IEEE arithmetic.
        """
        var sample = Float32(self.next())
        var span = high - low
        var value = low + sample * span
        if isfinite(low) and isfinite(high) and low <= high:
            if low == high:
                return low
            if not isfinite(span):
                # Opposite signs can overflow the width while every point
                # in the interval is finite. The weighted endpoints cannot.
                value = (1 - sample) * low + sample * high
            if value >= high:
                # A rounded draw or sum can reach the exclusive endpoint.
                var bits = bitcast[DType.uint32](high)
                if high == 0:
                    bits = 0x80000001
                elif high > 0:
                    bits -= 1
                else:
                    bits += 1
                return bitcast[DType.float32](bits)
        return value

    def float_spread(mut self, spread: Float32) -> Float32:
        """Return a number within half a spread of zero. three.js:
        `randFloatSpread`.

        Args:
            spread: The width of the range.

        Returns:
            The number.
        """
        return spread * (0.5 - Float32(self.next()))

    def int_in(mut self, low: Int, high: Int) -> Int:
        """Return a whole number in a range, both ends included.
        three.js: `randInt`.

        Args:
            low: The smallest.
            high: The largest.

        Returns:
            The number.
        """
        return low + Int(floor(self.next() * Float64(high - low + 1)))


def generate_uuid(mut generator: SeededRandom) -> String:
    """Return a version 4 uuid, three.js's `generateUUID`, from four draws
    of the generator in three.js's order and with its byte layout.

    three.js draws from `Math.random`; this draws from a generator, so the
    same seed gives the same uuid.

    Args:
        generator: Where the numbers come from.

    Returns:
        Thirty-two lowercase hexadecimal digits in groups of 8, 4, 4, 4 and
        12, with the version digit 4 and the variant bits 10.
    """
    var words = List[Int]()
    for _ in range(4):  # pragma: no branch
        words.append(Int(generator.next() * 4294967295.0))
    var d0 = words[0]
    var d1 = words[1]
    var d2 = words[2]
    var d3 = words[3]
    var picks: List[Int] = [
        d0 & 0xFF,
        (d0 >> 8) & 0xFF,
        (d0 >> 16) & 0xFF,
        (d0 >> 24) & 0xFF,
        -1,
        d1 & 0xFF,
        (d1 >> 8) & 0xFF,
        -1,
        ((d1 >> 16) & 0x0F) | 0x40,
        (d1 >> 24) & 0xFF,
        -1,
        (d2 & 0x3F) | 0x80,
        (d2 >> 8) & 0xFF,
        -1,
        (d2 >> 16) & 0xFF,
        (d2 >> 24) & 0xFF,
        d3 & 0xFF,
        (d3 >> 8) & 0xFF,
        (d3 >> 16) & 0xFF,
        (d3 >> 24) & 0xFF,
    ]
    var digits = "0123456789abcdef"
    var out = String()
    for index in range(len(picks)):  # pragma: no branch
        var pick = picks[index]
        if pick < 0:
            out += "-"
        else:
            out += String(digits[byte = pick >> 4 : (pick >> 4) + 1])
            out += String(digits[byte = pick & 15 : (pick & 15) + 1])
    return out


@fieldwise_init
struct ProperEulerOrder(Equatable, ImplicitlyCopyable, Writable):
    """Which axes three proper Euler angles turn about, three.js's order
    string for `setQuaternionFromProperEuler`, as a type rather than a bare
    int. A proper order turns about one axis, a second, then the first
    again.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the six proper orders.

        Returns:
            Whether it is `XYX`, `YZY`, `ZXZ`, `XZX`, `YXY` or `ZYZ`.
        """
        return ordinal_valid(self.value, 5)


comptime PROPER_XYX = ProperEulerOrder(0)
comptime PROPER_YZY = ProperEulerOrder(1)
comptime PROPER_ZXZ = ProperEulerOrder(2)
comptime PROPER_XZX = ProperEulerOrder(3)
comptime PROPER_YXY = ProperEulerOrder(4)
comptime PROPER_ZYZ = ProperEulerOrder(5)


def quaternion_from_proper_euler(
    a: Angle, b: Angle, c: Angle, order: ProperEulerOrder
) raises -> Quaternion:
    """Return the rotation of three proper Euler angles, three.js's
    `setQuaternionFromProperEuler`.

    Args:
        a: The turn about the first axis.
        b: The turn about the second axis.
        c: The second turn about the first axis.
        order: Which axes.

    Returns:
        The rotation.

    Raises:
        Error: If the order is not one of the six. three.js warns and
            leaves the quaternion unchanged.
    """
    require_valid(
        order.is_valid(),
        "A proper Euler order is XYX, YZY, ZXZ, XZX, YXY or ZYZ",
    )
    var c2 = cos(b.value / 2)
    var s2 = sin(b.value / 2)
    var c13 = cos((a.value + c.value) / 2)
    var s13 = sin((a.value + c.value) / 2)
    var c1_3 = cos((a.value - c.value) / 2)
    var s1_3 = sin((a.value - c.value) / 2)
    var c3_1 = cos((c.value - a.value) / 2)
    var s3_1 = sin((c.value - a.value) / 2)
    if order == PROPER_XYX:
        return Quaternion(c2 * s13, s2 * c1_3, s2 * s1_3, c2 * c13)
    if order == PROPER_YZY:
        return Quaternion(s2 * s1_3, c2 * s13, s2 * c1_3, c2 * c13)
    if order == PROPER_ZXZ:
        return Quaternion(s2 * c1_3, s2 * s1_3, c2 * s13, c2 * c13)
    if order == PROPER_XZX:
        return Quaternion(c2 * s13, s2 * s3_1, s2 * c3_1, c2 * c13)
    if order == PROPER_YXY:
        return Quaternion(s2 * c3_1, c2 * s13, s2 * s3_1, c2 * c13)
    return Quaternion(s2 * s3_1, s2 * c3_1, c2 * s13, c2 * c13)


@fieldwise_init
struct ComponentType(Equatable, ImplicitlyCopyable, Writable):
    """Which typed array a number is stored in, for `normalize` and
    `denormalize`, as a type rather than a bare int. three.js reads it off
    the array's constructor.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the seven component types.

        Returns:
            Whether it is one of the `*_COMPONENT` constants.
        """
        return ordinal_valid(self.value, 6)


comptime FLOAT32_COMPONENT = ComponentType(0)
comptime UINT32_COMPONENT = ComponentType(1)
comptime UINT16_COMPONENT = ComponentType(2)
comptime UINT8_COMPONENT = ComponentType(3)
comptime INT32_COMPONENT = ComponentType(4)
comptime INT16_COMPONENT = ComponentType(5)
comptime INT8_COMPONENT = ComponentType(6)


def _component_scale(component: ComponentType) raises -> Float64:
    """Return the stored number that stands for one.

    Args:
        component: The component type.

    Returns:
        The largest value of the integer type, or one for a float.

    Raises:
        Error: If the component type is not one of the seven.
    """
    require_valid(component.is_valid(), "Invalid component type")
    var scales: List[Float64] = [
        1.0,
        4294967295.0,
        65535.0,
        255.0,
        2147483647.0,
        32767.0,
        127.0,
    ]
    return scales[component.value]


def denormalize(value: Float64, component: ComponentType) raises -> Float64:
    """Return the number a normalized stored value stands for, three.js's
    `denormalize`: zero to one for an unsigned type, minus one to one for a
    signed one, the value itself for a float.

    Args:
        value: The stored value.
        component: The type it is stored as.

    Returns:
        The number.

    Raises:
        Error: If the component type is not one of the seven.
    """
    var scale = _component_scale(component)
    var signed = component.value >= INT32_COMPONENT.value
    var out = value / scale
    return max(out, -1.0) if signed else out


def normalize(value: Float64, component: ComponentType) raises -> Float64:
    """Return the stored value that stands for a number, three.js's
    `normalize`: the number times the type's largest value, rounded a half
    up, or the number itself for a float. Not clamped, as in three.js.

    Args:
        value: The number.
        component: The type to store it as.

    Returns:
        The stored value.

    Raises:
        Error: If the component type is not one of the seven.
    """
    var scale = _component_scale(component)
    if component == FLOAT32_COMPONENT:
        return value
    var scaled = value * scale
    var whole = floor(scaled)
    return whole + 1.0 if scaled - whole >= 0.5 else whole
