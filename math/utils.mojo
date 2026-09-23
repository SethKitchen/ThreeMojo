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
"""

from math.quaternion import Quaternion
from math.smoothstep import smoothstep
from std.math import cos, exp, floor, sin
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
    """Return the remainder of `n / m`, always with the sign of `m`.

    Args:
        n: The dividend.
        m: The divisor.

    Returns:
        A value from zero up to, not including, `m`.
    """
    return ((n % m) + m) % m


def pingpong(x: Float32, length: Float32 = 1) -> Float32:
    """Return a value that runs from zero to `length` and back.

    Args:
        x: The input.
        length: The peak.

    Returns:
        A value from zero to `length`.
    """
    return length - abs(euclidean_modulo(x, length * 2) - length)


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
        Error: If the value is not positive.
    """
    if value <= 0:
        raise Error("Only a positive number has a power of two above it")
    var power = 1
    while power < value:
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
    if value <= 0:
        raise Error("Only a positive number has a power of two below it")
    var power = 1
    while power * 2 <= value:
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
        self.state = self.state + 0x6D2B79F5
        var t = self.state
        t = (t ^ (t >> 15)) * (t | 1)
        t ^= t + (t ^ (t >> 7)) * (t | 61)
        return Float64(t ^ (t >> 14)) / 4294967296.0

    def float_in(mut self, low: Float32, high: Float32) -> Float32:
        """Return a number in a range. three.js: `randFloat`.

        Args:
            low: The smallest.
            high: The top, not reached.

        Returns:
            The number.
        """
        return low + Float32(self.next()) * (high - low)

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
        return self.value >= 0 and self.value <= 5


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
    if not order.is_valid():
        raise Error("A proper Euler order is XYX, YZY, ZXZ, XZX, YXY or ZYZ")
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
        return self.value >= 0 and self.value <= 6


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
    if not component.is_valid():
        raise Error("Invalid component type")
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
