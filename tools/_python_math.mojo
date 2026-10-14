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
from std.math import isinf, isnan, pi


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
