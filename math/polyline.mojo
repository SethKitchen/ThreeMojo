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
from math.utils import clamp, clamp_unit
from std.math import acos, pi, sqrt
from units.measure import angle_radians
from units.si import Angle


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

    def dot(self, other: Self) -> Float32:
        """Return the dot product of this step and `other`.

        Args:
            other: The other step.

        Returns:
            The dot product.
        """
        ...

    def __add__(self, other: Self) -> Self:
        """Return the sum of this step and `other`.

        Args:
            other: The step to add.

        Returns:
            The sum.
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
    var limit = clamp(length, low, high)
    if _ordinary_squared(value.length_sq()):
        value = value / length * limit
        return
    value.normalize()
    value = value * limit


def scale_to_length[T: PolylineVertex](mut value: T, length: Float32):
    """Scale `value` to `length`. A zero vector stays zero.

    Args:
        value: The vector, changed in place.
        length: The new length.
    """
    value.normalize()
    value = value * length


def add_scaled[T: PolylineVertex](mut value: T, other: T, factor: Float32):
    """Add `other` times `factor` into `value`.

    Args:
        value: The vector, changed in place.
        other: The vector to add.
        factor: What to scale `other` by first.
    """
    value = value + other * factor


def distance_between[T: PolylineVertex](start: T, end: T) -> Float32:
    """Return the distance from `start` to `end`.

    Args:
        start: The first point.
        end: The other point.

    Returns:
        The Euclidean distance.
    """
    var step = start - end
    return step.length()


def distance_between_squared[T: PolylineVertex](start: T, end: T) -> Float32:
    """Return the squared distance from `start` to `end`.

    Args:
        start: The first point.
        end: The other point.

    Returns:
        The squared Euclidean distance.
    """
    var step = start - end
    return step.length_sq()


def angle_between[T: PolylineVertex](start: T, end: T) -> Angle:
    """Return the angle between `start` and `end`.

    Args:
        start: The first vector.
        end: The other vector.

    Returns:
        From zero to a half turn. A right angle if either vector is zero.
    """
    var first_squared = start.length_sq()
    var second_squared = end.length_sq()
    var product = first_squared * second_squared
    var theta: Float32
    if (
        _ordinary_squared(first_squared)
        and _ordinary_squared(second_squared)
        and _ordinary_squared(product)
    ):
        theta = start.dot(end) / sqrt(product)
    else:
        var first = start
        var second = end
        first.normalize()
        second.normalize()
        # A zero vector stays zero, so this is every component being zero.
        if first.length_sq() == 0 or second.length_sq() == 0:
            return angle_radians(pi / 2)
        theta = first.dot(second)
    return Angle(acos(clamp_unit(theta)), RADIAN)


def lerp_in_place[T: PolylineVertex](mut value: T, other: T, alpha: Float32):
    """Move `value` toward `other` by `alpha`.

    Args:
        value: The vector, changed in place.
        other: The vector to move toward.
        alpha: Zero stays, one arrives. Values outside run on.
    """
    var step = other - value
    value = value + step * alpha


def lerp_between[
    T: PolylineVertex
](mut value: T, start: T, end: T, alpha: Float32):
    """Set `value` a fraction of the way from `start` to `end`.

    Args:
        value: The vector, changed in place.
        start: The vector at an `alpha` of zero.
        end: The vector at an `alpha` of one.
        alpha: How far along.
    """
    var step = end - start
    value = start + step * alpha
