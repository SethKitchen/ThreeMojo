# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared parameter and count boundaries for curve sampling."""

from math.polyline import PolylineVertex


def check_curve_parameter(value: Float64) raises:
    """Require a finite parameter in the closed unit interval.

    Args:
        value: The parameter, before any precision narrowing.

    Raises:
        Error: If the parameter is not finite or lies outside zero to one.
    """
    if not (value >= 0 and value <= 1):
        raise Error(
            "A curve parameter must be finite and lie from zero through one"
        )


def curve_sample_count(divisions: Int) raises -> Int:
    """Return the checked number of samples for a positive division count.

    Args:
        divisions: The number of runs between samples.

    Returns:
        One more than the number of divisions.

    Raises:
        Error: If divisions is not positive or the sample count overflows.
    """
    if divisions < 1:
        raise Error("A curve needs at least one division")
    return curve_count_sum(divisions, 1)


def curve_count_sum(first: Int, second: Int) raises -> Int:
    """Add two nonnegative curve counts without signed overflow.

    Args:
        first: The first count.
        second: The second count.

    Returns:
        Their sum.

    Raises:
        Error: If a count is negative or the sum cannot fit in Int.
    """
    if first < 0 or second < 0:
        raise Error("Curve counts cannot be negative")
    if first > Int.MAX - second:
        raise Error("A curve sample count cannot fit in Int")
    return first + second


def curve_count_product(first: Int, second: Int) raises -> Int:
    """Multiply two nonnegative curve counts without signed overflow.

    Args:
        first: The first count.
        second: The second count.

    Returns:
        Their product.

    Raises:
        Error: If a count is negative or the product cannot fit in Int.
    """
    if first < 0 or second < 0:
        raise Error("Curve counts cannot be negative")
    if second != 0:
        if first > Int.MAX // second:
            raise Error("A curve sample count cannot fit in Int")
    return first * second


def parameter_samples[
    C: AnyType,
    T: PolylineVertex,
    //,
    take: def(C, Float32) raises thin -> T,
](curve: C, divisions: Int) raises -> List[T]:
    """Return `divisions + 1` values at equal steps from zero through one.

    Parameters:
        C: The curve type.
        T: The value type.
        take: Reads `curve` at one parameter.

    Args:
        curve: The curve.
        divisions: How many runs to cut the parameter into. At least one.

    Returns:
        The values, first to last.

    Raises:
        Error: If `divisions` is less than one, the sample count cannot
            fit in Int, or `take` raises.
    """
    var sample_count = curve_sample_count(divisions)
    var out = List[T]()
    # At least one division, so this loop runs.
    for index in range(sample_count):  # pragma: no branch
        out.append(take(curve, Float32(index) / Float32(divisions)))
    return out^
