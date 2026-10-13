# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A ground surface behind a wall, as a broken line.

A `GradeProfile` gives the height of the ground at each distance behind a
vertical plane. The first point is on the plane, at distance zero. The
distances increase. The last segment is level, so the ground goes on
level past the last point, which lets a trial wedge reach as far as it
needs to.
"""

from std.math import isfinite
from units.si import Area64, Length64, Volume64

# Distances and heights closer than this, in meters, are the same.
comptime _TOLERANCE = 1e-9
# Where a tail profile stops short, it is extended level by this much, in
# meters (500 ft), so that a trial wedge always meets the ground.
comptime _EXTENSION = 152.4
# A tail profile shorter than this, in meters (100 ft), is extended.
comptime _SHORT = 30.48


@fieldwise_init
struct GradePoint(ImplicitlyCopyable):
    """One point of a ground surface."""

    # The distance behind the vertical plane.
    var distance: Length64
    # The height above the base of the plane.
    var height: Length64


struct GradeProfile(Copyable, Movable):
    """A broken-line ground surface that ends level."""

    var points: List[GradePoint]

    def __init__(out self, var points: List[GradePoint]) raises:
        """Make a profile from its points.

        Args:
            points: The points, from the plane outward.

        Raises:
            Error: If there are fewer than two points, a value is not
                finite, the first distance is not zero, the distances do
                not increase, or the last segment is not level.
        """
        if len(points) < 2:
            raise Error("A grade profile needs at least two points")
        # There are two points at least, so the loops always run.
        for p in points:  # pragma: no branch
            if not (isfinite(p.distance.value) and isfinite(p.height.value)):
                raise Error("A grade point must be finite")
        if abs(points[0].distance.value) > _TOLERANCE:
            raise Error("A grade profile must start at distance zero")
        for i in range(1, len(points)):  # pragma: no branch
            if points[i].distance.value <= points[i - 1].distance.value:
                raise Error("Grade-profile distances must increase")
        var n = len(points)
        if (
            abs(points[n - 1].height.value - points[n - 2].height.value)
            > _TOLERANCE
        ):
            raise Error("A grade profile must end with a level segment")
        self.points = points^

    def height_at(self, distance: Length64) -> Length64:
        """Return the ground height at a distance.

        Args:
            distance: The distance behind the plane.

        Returns:
            The height, level past the last point and before the first.
        """
        return Length64(self.height_si(distance.value))

    def height_si(self, x: Float64) -> Float64:
        """Return the ground height at a distance, both in meters.

        Args:
            x: The distance behind the plane, in meters.

        Returns:
            The height in meters.
        """
        if x <= self.points[0].distance.value:
            return self.points[0].height.value
        # A profile has two points at least, so the loop always runs.
        for i in range(1, len(self.points)):  # pragma: no branch
            var x1 = self.points[i].distance.value
            if x <= x1 + 1e-12:
                var x0 = self.points[i - 1].distance.value
                var y0 = self.points[i - 1].height.value
                var y1 = self.points[i].height.value
                return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
        return self.points[len(self.points) - 1].height.value

    def plane_height(self) -> Length64:
        """Return the ground height on the plane.

        Returns:
            The height at distance zero.
        """
        return self.points[0].height

    def area_and_moment(self, reach: Length64) -> Tuple[Area64, Volume64]:
        """Return the area under the ground from the plane to a distance.

        Args:
            reach: How far behind the plane to integrate.

        Returns:
            The area under the profile, and its first moment about the
            plane. Both are zero for a reach of zero or less.
        """
        var x_end = reach.value
        var xs = List[Float64]()
        xs.append(0)
        # A profile has two points at least, and `xs` holds both ends, so
        # both loops always run.
        for p in self.points:  # pragma: no branch
            if p.distance.value > 0 and p.distance.value < x_end:
                xs.append(p.distance.value)
        xs.append(x_end)
        var area = Float64(0)
        var first = Float64(0)
        for i in range(len(xs) - 1):  # pragma: no branch
            var xa = xs[i]
            var xb = xs[i + 1]
            if xb <= xa:
                continue
            var ya = self.height_si(xa)
            var yb = self.height_si(xb)
            var length = xb - xa
            area += 0.5 * (ya + yb) * length
            # The exact first moment of a linearly varying strip.
            first += length / 6.0 * (ya * (2 * xa + xb) + yb * (xa + 2 * xb))
        return (Area64(area), Volume64(first))

    def raised(self, rise: Length64) raises -> GradeProfile:
        """Return the profile with every height raised.

        Args:
            rise: How much to add to each height; negative lowers it.

        Returns:
            The raised profile.

        Raises:
            Error: If the rise is not finite.
        """
        if not isfinite(rise.value):
            raise Error("A rise must be finite")
        var out = List[GradePoint]()
        # A profile has two points at least, so the loop always runs.
        for p in self.points:  # pragma: no branch
            out.append(GradePoint(p.distance, p.height + rise))
        return GradeProfile(out^)

    def beyond(self, distance: Length64) raises -> GradeProfile:
        """Return the part of the profile past a distance, re-based there.

        The new plane is at `distance`. A tail that would end within 100 ft
        is extended level by 500 ft, so a wedge from the new plane always
        meets the ground.

        Args:
            distance: Where the new plane stands, zero or more.

        Returns:
            The tail profile.

        Raises:
            Error: If the distance is negative or not finite.
        """
        var x0 = distance.value
        if not (isfinite(x0) and x0 >= 0):
            raise Error(
                "A profile can only be cut at a distance of zero or more"
            )
        var out = List[GradePoint]()
        out.append(GradePoint(Length64(0), Length64(self.height_si(x0))))
        # A profile has two points at least, so the loop always runs.
        for p in self.points:  # pragma: no branch
            if p.distance.value > x0 + _TOLERANCE:
                out.append(
                    GradePoint(Length64(p.distance.value - x0), p.height)
                )
        var last = out[len(out) - 1]
        if len(out) == 1:
            out.append(GradePoint(Length64(_EXTENSION), last.height))
        elif last.distance.value < _SHORT:
            out.append(
                GradePoint(
                    Length64(last.distance.value + _EXTENSION), last.height
                )
            )
        return GradeProfile(out^)
