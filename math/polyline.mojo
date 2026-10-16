# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Length along a polyline, and the unit direction of one step.

A 2D curve and a 3D curve sample different point types. Both points can
be subtracted and measured, so the walk lives here once.
"""


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
