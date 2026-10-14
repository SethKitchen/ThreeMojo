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
Mojo fuses `a + b * c` into one rounding by default.
"""

from std.ffi import external_call
from std.memory import bitcast
from std.benchmark import black_box
from std.math import fma, inf, isinf, isnan, nan, pi, sqrt


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


def degrees(radians: Float64) -> Float64:
    """Return radians in degrees, as `math.degrees` rounds it: the factor
    `180 / pi` is a rounded double before the product.

    Args:
        radians: The angle in radians.

    Returns:
        The angle in degrees.
    """
    var factor = Float64(180) / Float64(pi)
    return black_box(radians * factor)


def _product(x: Float64, y: Float64) -> Tuple[Float64, Float64]:
    """Return the rounded product and its exact error, as CPython's
    `dl_mul` does."""
    var rounded = black_box(x * y)
    return (rounded, fma(x, y, -rounded))


def _frexp_exponent(value: Float64) -> Int:
    """Return the exponent e of `frexp`: value = m * 2**e, 0.5 <= m < 1."""
    var bits = bitcast[DType.uint64](value) & 0x7FFFFFFFFFFFFFFF
    var field = Int(bits >> 52)
    if field != 0:
        return field - 1022
    var length = 0
    while bits != 0:
        bits >>= 1
        length += 1
    return length - 1074


def _power_of_two(exponent: Int) -> Float64:
    """Return 2**exponent exactly, for an exponent from -1074 to 1023."""
    if exponent >= -1022:
        return bitcast[DType.float64](UInt64(exponent + 1023) << 52)
    return bitcast[DType.float64](UInt64(1) << UInt64(exponent + 1074))


def _vector_norm(first: Float64, second: Float64, largest: Float64) -> Float64:
    """Return the norm of two finite magnitudes, as CPython's
    `vector_norm` does."""
    if largest == 0:
        return largest
    var exponent = _frexp_exponent(largest)
    if exponent < -1023:
        # Subnormal magnitudes scale up to normal ones first.
        var smallest = bitcast[DType.float64](UInt64(0x0010000000000000))
        return black_box(
            smallest
            * _vector_norm(
                first / smallest, second / smallest, largest / smallest
            )
        )
    var scale = _power_of_two(-exponent)
    var total = 1.0
    var low_products = 0.0
    var low_sums = 0.0
    for value in [first, second]:
        var scaled = black_box(value * scale)
        var square = _product(scaled, scaled)
        var sum = total + square[0]
        low_sums += (total - sum) + square[0]
        total = sum
        low_products += square[1]
    var root = sqrt(total - 1.0 + (low_products + low_sums))
    var square = _product(-root, root)
    var sum = total + square[0]
    low_sums += (total - sum) + square[0]
    total = sum
    low_products += square[1]
    var correction = total - 1.0 + (low_products + low_sums)
    root += correction / (2.0 * root)
    return root / scale


def hypot(x: Float64, y: Float64) -> Float64:
    """Return sqrt(x*x + y*y) as CPython 3.13's `math.hypot` computes it.

    CPython does not call the C library here. It scales both magnitudes by
    a power of two, sums the exact squares in double-double arithmetic and
    corrects the root once.

    Args:
        x: The first coordinate.
        y: The second coordinate.

    Returns:
        The length. An infinity wins over a NaN.
    """
    var first = abs(x)
    var second = abs(y)
    if isinf(first) or isinf(second):
        return inf[DType.float64]()
    if isnan(first) or isnan(second):
        return nan[DType.float64]()
    return _vector_norm(first, second, max(first, second))


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
