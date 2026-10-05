# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Operations on `List[Float64]` vectors that every solver shares.

A vector is a plain `List[Float64]`. The functions check that two vectors
have the same length and raise when they do not. A vector norm scales by
the largest entry first, so a vector of very large or very small finite
entries keeps a finite, accurate length.
"""

from std.math import isfinite, sqrt


def zeros(size: Int) raises -> List[Float64]:
    """Return a vector of zeros.

    Args:
        size: The number of entries. Zero or more.

    Returns:
        The vector.

    Raises:
        Error: If the size is negative.
    """
    if size < 0:
        raise Error("A vector size must be zero or more")
    var out = List[Float64](capacity=size)
    for _ in range(size):
        out.append(0.0)
    return out^


def check_same_size(a: List[Float64], b: List[Float64]) raises:
    """Refuse two vectors of different lengths.

    Args:
        a: The first vector.
        b: The second vector.

    Raises:
        Error: If the lengths differ.
    """
    if len(a) != len(b):
        raise Error("Two vectors must have the same length")


def check_finite(v: List[Float64]) raises:
    """Refuse a vector with an entry that is not a finite number.

    Args:
        v: The vector.

    Raises:
        Error: If an entry is infinite or not a number.
    """
    for i in range(len(v)):
        if not isfinite(v[i]):
            raise Error("A vector entry must be a finite number")


def dot(a: List[Float64], b: List[Float64]) raises -> Float64:
    """Return the dot product of two vectors.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The sum of the products of the entries.

    Raises:
        Error: If the lengths differ.
    """
    check_same_size(a, b)
    var total = Float64(0)
    for i in range(len(a)):
        total += a[i] * b[i]
    return total


def norm(v: List[Float64]) -> Float64:
    """Return the Euclidean length of a vector, scaled to avoid overflow.

    Args:
        v: The vector.

    Returns:
        The length. Zero for an empty or zero vector.
    """
    var largest = Float64(0)
    for i in range(len(v)):
        largest = max(largest, abs(v[i]))
    if largest == 0:
        return 0
    var total = Float64(0)
    var i = 0
    while i < len(v):
        var scaled = v[i] / largest
        total += scaled * scaled
        i += 1
    return largest * sqrt(total)


def axpy(alpha: Float64, x: List[Float64], mut y: List[Float64]) raises:
    """Add a multiple of one vector to another, in place: y = y + alpha x.

    Args:
        alpha: The multiple.
        x: The vector to add.
        y: The vector to change.

    Raises:
        Error: If the lengths differ.
    """
    check_same_size(x, y)
    for i in range(len(x)):
        y[i] += alpha * x[i]
