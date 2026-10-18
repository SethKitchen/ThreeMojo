# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Length along a polyline, and the unit direction of one step.

A 2D curve and a 3D curve sample different point types. Both points can
be subtracted and measured, so the walk lives here once. The same point
can hold its length between two bounds.
"""

from math.norm import _ordinary_squared
from std.math import max, min


trait PolylineVertex(Deinitable, ImplicitlyCopyable, Movable):
    """A point on a polyline."""

    def __sub__(self, other: Self) -> Self:
        """Return the step from `other` to this point.

        Args:
            other: The previous point.

        Returns:
            The step.
        """
        ...

    def length(self) -> Float32:
        """Return the length of this step.

        Returns:
            The length.
        """
        ...

    def normalize(mut self):
        """Scale this step to unit length. A zero step stays zero."""
        ...

    def length_sq(self) -> Float32:
        """Return the squared length of this step.

        Returns:
            The square of `length`.
        """
        ...

    def __mul__(self, factor: Float32) -> Self:
        """Return this step scaled by `factor`.

        Args:
            factor: The scale.

        Returns:
            The scaled step.
        """
        ...

    def __truediv__(self, divisor: Float32) -> Self:
        """Return this step divided by `divisor`.

        Args:
            divisor: The number to divide by.

        Returns:
            The divided step.
        """
        ...


def prefix_lengths[T: PolylineVertex](samples: List[T]) -> List[Float32]:
    """Return the distance along `samples`, starting at zero.

    Args:
        samples: The points in order. Callers pass at least two.

    Returns:
        One distance per point, in the same unit as `length`.
    """
    var out = List[Float32]()
    out.append(0)
    # At least two samples, so this loop runs.
    for index in range(1, len(samples)):  # pragma: no branch
        var step = samples[index] - samples[index - 1]
        out.append(out[index - 1] + step.length())
    return out^


def unit_direction[T: PolylineVertex](var slope: T) raises -> T:
    """Return `slope` scaled to unit length.

    Args:
        slope: The step. It is consumed.

    Returns:
        The same direction, of unit length.

    Raises:
        Error: If `slope` has no length.
    """
    if slope.length() == 0:
        raise Error("A curve has no direction where it turns back")
    slope.normalize()
    return slope^


def clamp_to_length[
    T: PolylineVertex
](mut value: T, low: Float32, high: Float32):
    """Hold `value`'s length between `low` and `high`.

    Args:
        value: The vector, changed in place.
        low: The shortest length.
        high: The longest.
    """
    var length = value.length()
    var limit = max(low, min(high, length))
    if _ordinary_squared(value.length_sq()):
        value = value / length * limit
        return
    value.normalize()
    value = value * limit
