# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Float arithmetic with the results of the Python oracles it replaces.

A ported reference script must print the same digits as the Python script
did. Three differences between Mojo and CPython matter:

- CPython's `math` functions call the C library. Mojo's `std.math` has its
  own `exp` and `log`, which differ in the last digits. The functions here
  call the C library, as CPython does.
- CPython 3.12's `sum` adds floats with Neumaier's compensation. `py_sum`
  does the same.
- Mojo folds a constant expression such as `30.0 * (pi / 180.0)` exactly,
  and CPython rounds `pi / 180` first. `radians` rounds as CPython does.

A reference script must also be built with `--fp-mode contract=off`, because
Mojo fuses `a + b * c` into one rounding by default. A tool that must give
the same bytes in a default build, as the converters and their tests do,
rounds each product that feeds a sum with `product` instead.
"""

from std.benchmark import black_box
from std.ffi import c_int, external_call
from std.math import fma, frexp, inf, isinf, isnan, ldexp, nan, pi, sqrt
from std.memory import bitcast

# The smallest positive normal double, `DBL_MIN` in C.
comptime _DBL_MIN = 2.2250738585072014e-308


def exp(x: Float64) -> Float64:
    """Return e to the power x, as the C library computes it.

    Args:
        x: The exponent.

    Returns:
        The result of the C library's `exp`.
    """
    return external_call["exp", Float64](x)


def log(x: Float64) -> Float64:
    """Return the natural logarithm, as the C library computes it.

    Args:
        x: A positive number.

    Returns:
        The result of the C library's `log`.
    """
    return external_call["log", Float64](x)


def sin(x: Float64) -> Float64:
    """Return the sine, as the C library computes it.

    Args:
        x: An angle in radians.

    Returns:
        The result of the C library's `sin`.
    """
    return external_call["sin", Float64](x)


def cos(x: Float64) -> Float64:
    """Return the cosine, as the C library computes it.

    Args:
        x: An angle in radians.

    Returns:
        The result of the C library's `cos`.
    """
    return external_call["cos", Float64](x)


def tan(x: Float64) -> Float64:
    """Return the tangent, as the C library computes it.

    Args:
        x: An angle in radians.

    Returns:
        The result of the C library's `tan`.
    """
    return external_call["tan", Float64](x)


def atan2(y: Float64, x: Float64) -> Float64:
    """Return the angle of (x, y), as the C library computes it.

    Args:
        y: The second coordinate.
        x: The first coordinate.

    Returns:
        The result of the C library's `atan2`.
    """
    return external_call["atan2", Float64](y, x)


def acos(x: Float64) -> Float64:
    """Return the arc cosine, as the C library computes it.

    Args:
        x: A value from -1 to 1.

    Returns:
        The result of the C library's `acos`.
    """
    return external_call["acos", Float64](x)


def power(x: Float64, y: Float64) -> Float64:
    """Return x to the power y, as the C library computes it, which is what
    Python's `x ** y` gives for two floats.

    Args:
        x: The base.
        y: The exponent.

    Returns:
        The result of the C library's `pow`.
    """
    return external_call["pow", Float64](x, y)


def log2(x: Float64) -> Float64:
    """Return the base-2 logarithm, as the C library computes it, which is
    what CPython's `math.log2` calls.

    Args:
        x: A positive number.

    Returns:
        The result of the C library's `log2`.
    """
    return external_call["log2", Float64](x)


@no_inline
def product(a: Float64, b: Float64) -> Float64:
    """Return `a * b` with one rounding that never fuses with an add.

    The function is not inlined, so the compiler cannot contract the
    product and a later sum into one fused multiply-add. The result is the
    same with and without `--fp-mode contract=off`.

    Args:
        a: The first factor.
        b: The second factor.

    Returns:
        The rounded product.
    """
    return a * b


def _power_of_two(exponent: Int) -> Float64:
    """Return 2 to an integer power from -1074 to 1023, exactly."""
    var result = 1.0
    var remaining = exponent
    while remaining > 500:
        result *= ldexp(Float64(1), 500)
        remaining -= 500
    while remaining < -500:
        result *= ldexp(Float64(1), -500)
        remaining += 500
    return result * ldexp(Float64(1), Int32(remaining))


def hypot(x: Float64, y: Float64) -> Float64:
    """Return the length of (x, y), as CPython 3.12 and 3.13 compute it.

    CPython's `math.hypot` does not call the C library. It scales by a
    power of two, sums the exact squares in double length, and corrects the
    square root once. This is CPython's `vector_norm` for two coordinates.

    Args:
        x: The first coordinate.
        y: The second coordinate.

    Returns:
        The length, with CPython's digits.
    """
    var coordinates: List[Float64] = [abs(x), abs(y)]
    var largest = 0.0
    for coordinate in coordinates:
        if coordinate > largest:
            largest = coordinate
    if isinf(largest):
        return largest
    if isnan(x) or isnan(y):
        return x + y
    if largest == 0.0:
        return largest
    var largest_exponent = _exponent(largest)
    if largest_exponent < -1023:
        var smallest_normal = _power_of_two(-1022)
        return product(
            smallest_normal,
            hypot(
                coordinates[0] / smallest_normal,
                coordinates[1] / smallest_normal,
            ),
        )
    var scale = _power_of_two(-largest_exponent)
    var csum = 1.0
    var frac1 = 0.0
    var frac2 = 0.0
    for coordinate in coordinates:
        var value = product(coordinate, scale)
        var high = product(value, value)
        var low = fma(value, value, -high)
        var total = csum + high
        var low_sum = high - (total - csum)
        csum = total
        frac1 += low
        frac2 += low_sum
    var h = sqrt(csum - 1.0 + (frac1 + frac2))
    var high = product(-h, h)
    var low = fma(-h, h, -high)
    var total = csum + high
    frac2 += high - (total - csum)
    csum = total
    frac1 += low
    var correction = csum - 1.0 + (frac1 + frac2)
    h += correction / product(2.0, h)
    return h / scale


def radians(degrees: Float64) -> Float64:
    """Return degrees in radians, as `math.radians` rounds it: the factor
    `pi / 180` is a rounded double before the product.

    Args:
        degrees: The angle in degrees.

    Returns:
        The angle in radians.
    """
    var factor = Float64(pi) / Float64(180)
    return degrees * factor


def py_sum(values: List[Float64], kinds: List[Bool]) -> Tuple[Float64, Bool]:
    """Sum as CPython 3.12's `sum` does from its start of int zero.

    Ints add exactly until the first float. Then each float item is added
    with Neumaier's compensation, an int item is added plainly, and the
    compensation is added once at the end when it is finite and not zero.

    Args:
        values: The items.
        kinds: True for each item that is an int.

    Returns:
        The sum, and whether it is an int.
    """
    var total = 0.0
    var index = 0
    while index < len(values) and kinds[index]:
        total += values[index]
        index += 1
    if index == len(values):
        return (total + 0.0, True)
    total = total + values[index]
    var compensation = 0.0
    index += 1
    while index < len(values):
        var x = values[index]
        if kinds[index]:
            total += x
        else:
            var t = total + x
            if abs(total) >= abs(x):
                compensation += (total - t) + x
            else:
                compensation += (x - t) + total
            total = t
        index += 1
    if (
        compensation != 0
        and not isinf(compensation)
        and not isnan(compensation)
    ):
        total += compensation
    return (total, False)


def float_sum(values: List[Float64]) -> Float64:
    """Sum floats as CPython 3.12's `sum` does.

    Args:
        values: The items, all floats.

    Returns:
        The sum.
    """
    var kinds = List[Bool](length=len(values), fill=False)
    return py_sum(values, kinds)[0]


def degrees(radians: Float64) -> Float64:
    """Return radians in degrees, as `math.degrees` rounds it: the factor
    `180 / pi` is a rounded double before the product.

    Args:
        radians: The angle in radians.

    Returns:
        The angle in degrees.
    """
    var factor = Float64(180) / Float64(pi)
    return product(radians, factor)


def _exponent(x: Float64) -> Int:
    """Return the exponent `frexp` gives a positive finite double."""
    var bits = bitcast[DType.uint64](x)
    var biased = Int((bits >> 52) & 0x7FF)
    if biased == 0:
        # A subnormal: scale it to a normal first; the scaling is exact.
        return _exponent(x * 18014398509481984.0) - 54
    return biased - 1022


def _norm(var parts: List[Float64], var largest: Float64) -> Float64:
    """Return the length of a vector of absolute values, as CPython 3.12's
    `vector_norm` computes it."""
    if isinf(largest):
        return largest
    for value in parts:
        if isnan(value):
            return value
    if largest == 0.0 or len(parts) <= 1:
        return largest
    var max_e = _exponent(largest)
    if max_e < -1023:
        for i in range(len(parts)):
            parts[i] /= _DBL_MIN
        return product(_DBL_MIN, _norm(parts^, largest / _DBL_MIN))
    var scale = external_call["ldexp", Float64](Float64(1), c_int(-max_e))
    var csum = 1.0
    var frac1 = 0.0
    var frac2 = 0.0
    for value in parts:
        var x = value * scale
        # The square and its exact error, then a sum and its exact error.
        var high = product(x, x)
        var low = fma(x, x, -high)
        var total = csum + high
        var error = high - (total - csum)
        csum = total
        frac1 += low
        frac2 += error
    var h = sqrt(csum - 1.0 + (frac1 + frac2))
    var high = product(-h, h)
    var low = fma(-h, h, -high)
    var total = csum + high
    var error = high - (total - csum)
    csum = total
    frac1 += low
    frac2 += error
    var x = csum - 1.0 + (frac1 + frac2)
    h += x / (2.0 * h)
    return h / scale


def dist(p: List[Float64], q: List[Float64]) raises -> Float64:
    """Return the distance between two points, as `math.dist` computes it
    in CPython 3.12: a scaled sum of squares with exact error terms and one
    correction step.

    Args:
        p: The first point.
        q: The second point.

    Returns:
        The Euclidean distance.

    Raises:
        Error: If the points have different numbers of coordinates.
    """
    if len(p) != len(q):
        raise Error("both points must have the same number of dimensions")
    var parts = List[Float64](capacity=len(p))
    var largest = 0.0
    for i in range(len(p)):
        var x = abs(p[i] - q[i])
        parts.append(x)
        if x > largest:
            largest = x
    return _norm(parts^, largest)


def floor_divide(a: Float64, b: Float64) raises -> Float64:
    """Return `a // b` for two floats, as CPython computes it from `fmod`.

    Args:
        a: The dividend.
        b: The divisor.

    Returns:
        The floored quotient.

    Raises:
        Error: If `b` is zero, as Python raises `ZeroDivisionError`.
    """
    if b == 0:
        raise Error("float floor division by zero")
    var mod = external_call["fmod", Float64](a, b)
    var div = (a - mod) / b
    if mod != 0 and (b < 0) != (mod < 0):
        div -= 1.0
    if div != 0:
        var floored = external_call["floor", Float64](div)
        if div - floored > 0.5:
            floored += 1.0
        return floored
    # A zero quotient takes the sign of the true quotient.
    return external_call["copysign", Float64](Float64(0), a / b)


def round_half_even(x: Float64) -> Float64:
    """Return `round(x)` for a float, as CPython rounds it: to the nearest
    whole number, and a half to the even one.

    Args:
        x: A finite number.

    Returns:
        The nearest whole number, as a float.
    """
    var rounded = external_call["round", Float64](x)
    if abs(x - rounded) == 0.5:
        rounded = 2.0 * external_call["round", Float64](x / 2.0)
    return rounded
