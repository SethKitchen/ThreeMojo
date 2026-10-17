# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shared kind, count, length-table, and parameter boundaries for curves.

`require_at_least_one` refuses a count below one. Geometry builders call
it for a segment, a step, or a division.
"""

from core.ordinal import require_positive
from math.polyline import PolylineVertex


def require_curve_kind(valid: Bool) raises:
    """Refuse a curve kind that is not named.

    Args:
        valid: Whether the kind is one of the named kinds.

    Returns:
        Nothing. The call returns when the kind is named.

    Raises:
        Error: If the kind is not named.
    """
    if not valid:
        raise Error("A curve needs a kind that exists")


def require_distinct_points(moved: Bool) raises:
    """Refuse a curve whose points are all the same point.

    Args:
        moved: Whether some point differs from the first.

    Returns:
        Nothing. The call returns when two points differ.

    Raises:
        Error: If every point is the same point.
    """
    if not moved:
        raise Error("A curve needs two points that differ")


def require_length_table(count: Int) raises:
    """Refuse a curve length table with fewer than two entries.

    Args:
        count: How many entries the table has.

    Returns:
        Nothing. The call returns when the table has at least two entries.

    Raises:
        Error: If the table has fewer than two entries.
    """
    if count < 2:
        raise Error("A curve length table needs at least two entries")


def require_control_count(wanted: Int, count: Int) raises:
    """Refuse a control-point list that does not match a curve kind.

    A wanted count of zero means a spline, which needs at least two
    points. Any other wanted count must match exactly.

    Args:
        wanted: How many points the kind takes. Zero means a spline.
        count: How many points the curve has.

    Returns:
        Nothing. The call returns when the count matches.

    Raises:
        Error: If a spline has fewer than two points, or another kind has
            a different count.
    """
    if wanted == 0:
        if count < 2:
            raise Error("A spline needs at least two points")
    elif count != wanted:
        raise Error("A curve's points must match its kind")


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


def require_at_least_one(count: Int, message: String) raises:
    """Refuse a count below one.

    Args:
        count: How many pieces the caller was given.
        message: The error text for this caller.

    Returns:
        Nothing. The call returns when `count` is at least one.

    Raises:
        Error: If `count` is below one.
    """
    require_positive(count, message)


def curve_sample_count(divisions: Int) raises -> Int:
    """Return the checked number of samples for a positive division count.

    Args:
        divisions: The number of runs between samples.

    Returns:
        One more than the number of divisions.

    Raises:
        Error: If divisions is not positive or the sample count overflows.
    """
    require_at_least_one(divisions, "A curve needs at least one division")
    return curve_count_sum(divisions, 1)


def require_curve_counts(first: Int, second: Int) raises:
    """Refuse a negative curve count.

    Args:
        first: The first count.
        second: The second count.

    Returns:
        Nothing. The call returns when both counts are zero or more.

    Raises:
        Error: If either count is negative.
    """
    if first < 0 or second < 0:
        raise Error("Curve counts cannot be negative")


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
    require_curve_counts(first, second)
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
    require_curve_counts(first, second)
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
