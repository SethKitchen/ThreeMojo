# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Swept solids shared by the torso layers.

A rib, a costal cartilage, a sheet of muscle and a vessel are each a
sweep: a run of elliptical stations joined by tapered segments. A sweep
has its own axis hint, so a sheet can lie thin across the chest wall
whichever way its fibers run. A torso part is one or more sweeps, and
the diaphragm adds a domed shell.

Mass uses the analytic frustum volume of the stations. A display mesh
may widen a thin sweep. That widening is not this volume.
"""

from extensions.humanoid.side import LEFT, BodySide
from extensions.humanoid.skeleton.field import (
    Bounds,
    DistanceField,
    empty_bounds,
    field_gradient,
    flip_x,
    sd_ellipse_segment,
    sd_ellipsoid,
    smax,
    smin,
)
from math.vector3 import Vector3
from std.math import max, min, pi, sqrt

# A value larger than any distance a torso part can hold.
comptime FAR = Float32(1.0e9)


@fieldwise_init
struct Station(ImplicitlyCopyable):
    """One elliptical cross-section of a sweep, in meters.

    `ml` is the radius along the sweep's hint after the tangent is
    projected out. `ap` is the radius across both.
    """

    var p: Vector3
    var ml: Float32
    var ap: Float32


struct Sweep(Copyable, Movable):
    """A run of stations joined by tapered elliptical segments."""

    var stations: List[Station]
    var hint: Vector3
    var low: Vector3
    var high: Vector3

    def __init__(out self, hint: Vector3):
        """Start an empty sweep.

        Args:
            hint: The direction each station's `ml` radius runs along.
        """
        self.stations = List[Station]()
        self.hint = hint
        self.low = Vector3(FAR, FAR, FAR)
        self.high = Vector3(-FAR, -FAR, -FAR)

    def add(mut self, p: Vector3, ml: Float32, ap: Float32):
        """Append one station.

        Args:
            p: Its center, in meters.
            ml: Its radius along the hint, in meters.
            ap: Its radius across, in meters.
        """
        self.stations.append(Station(p, ml, ap))
        var r = max(ml, ap)
        self.low = Vector3(
            min(self.low.x, p.x - r),
            min(self.low.y, p.y - r),
            min(self.low.z, p.z - r),
        )
        self.high = Vector3(
            max(self.high.x, p.x + r),
            max(self.high.y, p.y + r),
            max(self.high.z, p.z + r),
        )

    def round(mut self, p: Vector3, r: Float32):
        """Append one round station.

        Args:
            p: Its center, in meters.
            r: Its radius, in meters.
        """
        self.add(p, r, r)

    def distance(self, point: Vector3, k: Float32) -> Float32:
        """Return how far `point` lies outside the sweep, in meters.

        Args:
            point: A point in the same frame, in meters.
            k: Smooth-union radius between segments, in meters.

        Returns:
            The signed distance. A sweep of one station is an ellipsoid.
        """
        var count = len(self.stations)
        var first = self.stations[0]
        if count < 2:
            return sd_ellipsoid(
                point, first.p, Vector3(first.ml, first.ap, first.ap)
            )
        var d = FAR
        for index in range(count - 1):  # pragma: no branch
            var a = self.stations[index]
            var b = self.stations[index + 1]
            d = smin(
                d,
                sd_ellipse_segment(
                    point, a.p, b.p, a.ml, a.ap, b.ml, b.ap, self.hint
                ),
                k,
            )
        return d

    def gap(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the sweep's box.

        Args:
            point: A point in the same frame, in meters.

        Returns:
            Zero inside the box, else the distance to it, in meters.
        """
        var dx = max(max(self.low.x - point.x, point.x - self.high.x), 0)
        var dy = max(max(self.low.y - point.y, point.y - self.high.y), 0)
        var dz = max(max(self.low.z - point.z, point.z - self.high.z), 0)
        return sqrt(dx * dx + dy * dy + dz * dz)

    def volume(self) -> Float32:
        """Return the sweep's analytic volume, in cubic meters.

        Each segment is an elliptical frustum. The two ends are capped
        by half ellipsoids.
        """
        var count = len(self.stations)
        var first = self.stations[0]
        var cap = first.ml * first.ap
        if count < 2:
            return Float32(4.0 / 3.0) * pi * cap * sqrt(cap)
        var volume = Float32(0)
        for index in range(count - 1):  # pragma: no branch
            var a = self.stations[index]
            var b = self.stations[index + 1]
            var area_a = a.ml * a.ap
            var area_b = b.ml * b.ap
            var length = (b.p - a.p).length()
            volume += (
                pi
                * length
                * (area_a + area_b + sqrt(area_a * area_b))
                / Float32(3)
            )
        var last = self.stations[count - 1]
        var end = last.ml * last.ap
        return volume + Float32(2.0 / 3.0) * pi * (
            cap * sqrt(cap) + end * sqrt(end)
        )


@fieldwise_init
struct Dome(ImplicitlyCopyable):
    """A thin shell of an ellipsoid, kept above a floor height."""

    var center: Vector3
    var radii: Vector3
    var half: Float32
    var floor: Float32


struct SweepField(Copyable, DistanceField, Movable):
    """The implicit solid of a torso part: sweeps, and perhaps a dome.

    A part may also carry cuts: sweeps taken away from the union, such
    as the orbits of a skull. See `cut`.
    """

    var sweeps: List[Sweep]
    var domes: List[Dome]
    var cuts: List[Sweep]
    var mirror: Bool
    var k: Float32
    var epsilon: Float32
    var low: Vector3
    var high: Vector3

    def __init__(
        out self,
        var sweeps: List[Sweep],
        var domes: List[Dome],
        side: BodySide,
        k: Float32,
        epsilon: Float32,
        pad: Float32,
    ):
        """Gather sweeps authored on the right and place them on `side`.

        Args:
            sweeps: The part's sweeps, in the torso frame.
            domes: The part's domed shells, if any.
            side: `LEFT` mirrors every sweep on x; `RIGHT` keeps them.
            k: Smooth-union radius, in meters.
            epsilon: Gradient step, in meters.
            pad: Margin around the box, in meters.
        """
        self.sweeps = sweeps^
        self.domes = domes^
        self.cuts = List[Sweep]()
        self.mirror = side == LEFT
        self.k = k
        self.epsilon = epsilon
        var box = empty_bounds()
        for index in range(len(self.sweeps)):  # pragma: no branch
            box.include_sphere(self.sweeps[index].low, 0)
            box.include_sphere(self.sweeps[index].high, 0)
        for index in range(len(self.domes)):
            box.include_ellipsoid(
                self.domes[index].center, self.domes[index].radii
            )
        box = box.padded(pad)
        if self.mirror:
            box = Bounds(
                Vector3(-box.high.x, box.low.y, box.low.z),
                Vector3(-box.low.x, box.high.y, box.high.z),
            )
        self.low = box.low
        self.high = box.high

    def cut(mut self, var hole: Sweep):
        """Take `hole` away from the part, with the part's smooth blend.

        The hole is authored on the right, as the sweeps are. It does
        not change the part's box, and `volume` does not subtract it.

        Args:
            hole: The sweep to take away.
        """
        self.cuts.append(hole^)

    def distance(self, point: Vector3) -> Float32:
        """Return how far `point` lies outside the part, in meters.

        Negative is inside. Zero is the surface.
        """
        return self.within(point, FAR)

    def within(self, point: Vector3, limit: Float32) -> Float32:
        """Return how far `point` lies outside the part, in meters, or
        `limit` if it lies at least that far.

        A caller that needs the distance only below some bound saves the
        sweeps farther than it.

        Args:
            point: A point in the part's frame, in meters.
            limit: The distance past which the answer may be `limit`.

        Returns:
            The signed distance, or `limit`.
        """
        var local = point
        if self.mirror:
            local = flip_x(point)
        var d = limit
        for index in range(len(self.sweeps)):  # pragma: no branch
            # A sweep farther than the blend cannot change the union.
            if self.sweeps[index].gap(local) > d + self.k:
                continue
            d = smin(d, self.sweeps[index].distance(local, self.k), self.k)
        for index in range(len(self.domes)):
            var dome = self.domes[index]
            var shell = abs(sd_ellipsoid(local, dome.center, dome.radii))
            d = smin(
                d, smax(shell - dome.half, dome.floor - local.y, self.k), self.k
            )
        # A cut only takes away: past the limit it cannot matter.
        if d >= limit:
            return limit
        for index in range(len(self.cuts)):
            d = smax(d, -self.cuts[index].distance(local, self.k), self.k)
        return d

    def gradient(self, point: Vector3) -> Vector3:
        """Return the unit outward normal of the field at `point`."""
        return field_gradient(self, point, self.epsilon)

    def volume(self) -> Float32:
        """Return the analytic volume of every sweep and dome, in m^3.

        Overlapping sweeps count twice. A dome counts its whole shell
        above the floor as half of the ellipsoid's shell. Cuts are not
        subtracted.
        """
        var volume = Float32(0)
        for index in range(len(self.sweeps)):  # pragma: no branch
            volume += self.sweeps[index].volume()
        for index in range(len(self.domes)):
            var r = self.domes[index].radii
            var area = Float32(4) * pi * pow_mean(r)
            volume += Float32(0.5) * area * 2 * self.domes[index].half
        return volume

    def widened(self, least: Float32) -> SweepField:
        """Return a copy whose every radius is at least `least`.

        Args:
            least: The smallest radius a display mesh shows, in meters.

        Returns:
            A wider copy with a larger blend and box.
        """
        var field = self.copy()
        for s in range(len(field.sweeps)):  # pragma: no branch
            for index in range(
                len(field.sweeps[s].stations)
            ):  # pragma: no branch
                field.sweeps[s].stations[index].ml = max(
                    field.sweeps[s].stations[index].ml, least
                )
                field.sweeps[s].stations[index].ap = max(
                    field.sweeps[s].stations[index].ap, least
                )
            field.sweeps[s].low = field.sweeps[s].low - Vector3(
                least, least, least
            )
            field.sweeps[s].high = field.sweeps[s].high + Vector3(
                least, least, least
            )
        field.k = max(field.k, Float32(0.4) * least)
        field.epsilon = max(field.epsilon, Float32(0.25) * least)
        field.low = field.low - Vector3(least, least, least)
        field.high = field.high + Vector3(least, least, least)
        return field^


def pow_mean(r: Vector3) -> Float32:
    """Return the mean of an ellipsoid's pairwise radius products.

    Four pi times this approximates the ellipsoid's surface area. It is
    exact for a sphere and within a few percent for a dome.

    Args:
        r: The three semi-axes, in meters.

    Returns:
        The mean product, in square meters.
    """
    return (r.x * r.y + r.y * r.z + r.z * r.x) / 3


def floats(*values: Float32) -> List[Float32]:
    """Return a list of the given values.

    Args:
        values: Numbers, in order.

    Returns:
        The list.
    """
    var out = List[Float32]()
    for value in values:  # pragma: no branch
        out.append(value)
    return out^


def spline_points(points: List[Vector3], steps: Int) -> List[Vector3]:
    """Return a Catmull-Rom curve through `points`.

    Args:
        points: Control points, in order.
        steps: Samples between two control points.

    Returns:
        The first point, then `steps` samples per span, ending on the
        last point.
    """
    var out = List[Vector3]()
    var last = len(points) - 1
    out.append(points[0])
    for span in range(last):  # pragma: no branch
        var p0 = points[max(span - 1, 0)]
        var p1 = points[span]
        var p2 = points[span + 1]
        var p3 = points[min(span + 2, last)]
        for step in range(1, steps + 1):  # pragma: no branch
            var t = Float32(step) / Float32(steps)
            var t2 = t * t
            var t3 = t2 * t
            var w0 = Float32(0.5) * (-t3 + 2 * t2 - t)
            var w1 = Float32(0.5) * (3 * t3 - 5 * t2 + 2)
            var w2 = Float32(0.5) * (-3 * t3 + 4 * t2 + t)
            var w3 = Float32(0.5) * (t3 - t2)
            out.append(p0 * w0 + p1 * w1 + p2 * w2 + p3 * w3)
    return out^


def tube(points: List[Vector3], first: Float32, last: Float32) -> Sweep:
    """Return a round sweep through `points`, tapering from end to end.

    Args:
        points: The centerline, in meters.
        first: Radius at the first point, in meters.
        last: Radius at the last point, in meters.

    Returns:
        The sweep.
    """
    var sweep = Sweep(Vector3(1, 0, 0))
    var count = len(points)
    for index in range(count):  # pragma: no branch
        var t = Float32(index) / Float32(max(count - 1, 1))
        sweep.round(points[index], first + (last - first) * t)
    return sweep^
