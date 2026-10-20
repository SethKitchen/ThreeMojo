# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The frame of a scan: which way is up, how long one unit is, and where
the scan stands in a building's coordinates.

A scan keeps the coordinates of the software that made it. A building
model uses meters, with z up and +y north. A `ScanFrame` maps one to the
other in four steps:

1. Take away `origin`, a point in scan units.
2. Read the coordinates along the building axes. `up` and `north` name
   the scan axes that become +z and +y. +x is north cross up, so the
   axes are always right-handed.
3. Multiply by `unit`, the length of one scan unit.
4. Turn the plan by `heading` about +z, counterclockwise.

SuperSplat shows a SOG or PLY scene turned half a turn about z, as the
PlayCanvas engine shows a PLY file. So a scene that looks upright there
has its up along the scan's -y. `supersplat_frame` is that frame, with
-z north and one unit taken as one meter.

**The scale.** A photo scan has no scale of its own. `scale` records
where the unit came from: a publisher's convention that nobody checked, a
length a person measured, or a storey height that was assumed. Every
result made from a scan carries it, so that a structural number made from
an assumed scale is not read as a measured one.

**The heading.** `estimate_heading` finds the plan angle of the walls
from the splats themselves. A wall splat is thin across the wall and
long along it and up it. The angle of each such splat's long plan axis,
modulo a quarter turn, is counted in one-degree bins, and the heading
turns the strongest angle onto the x axis.
"""

from core.gaussian_splat_utils import GaussianSplatGeometry
from core.ordinal import ordinal_label, ordinal_valid
from generators.utils import Vec3d
from math.finite import require_finite, require_positive_finite
from std.math import atan2, cos, floor, isfinite, pi, sin, sqrt
from units.si import Angle64, Length64, METER, RADIAN

comptime HEADING_BINS = 90
"""How many bins of the heading count cover a quarter turn."""
comptime WALL_RATIO = Float64(4)
"""A wall splat is at least this many times longer than it is thick, in plan and up the wall."""


@fieldwise_init
struct ScanAxis(Equatable, ImplicitlyCopyable, Writable):
    """One of the six signed axes of a scan's own coordinates."""

    var value: Int
    """The stored ordinal."""

    def is_valid(self) -> Bool:
        """Return True if this names one of the 6 axes.

        Returns:
            Whether the value is 0 to 5.
        """
        return ordinal_valid(self.value, 6 - 1)

    def name(self) -> String:
        """Return the axis's name: a sign and a letter.

        Returns:
            The name, such as "-y", or "unknown" for a value that is not
            valid.
        """
        var names: List[String] = ["+x", "-x", "+y", "-y", "+z", "-z"]
        return ordinal_label(self.is_valid(), self.value, names, "unknown")

    def index(self) -> Int:
        """Return which coordinate the axis reads.

        Returns:
            0 for x, 1 for y and 2 for z.
        """
        return self.value // 2

    def sign(self) -> Float64:
        """Return the axis's direction along its coordinate.

        Returns:
            1 for a + axis and -1 for a - axis.
        """
        if self.value % 2 == 0:
            return 1
        return -1


comptime SCAN_POSITIVE_X = ScanAxis(0)
"""The scan's +x axis."""
comptime SCAN_NEGATIVE_X = ScanAxis(1)
"""The scan's -x axis."""
comptime SCAN_POSITIVE_Y = ScanAxis(2)
"""The scan's +y axis."""
comptime SCAN_NEGATIVE_Y = ScanAxis(3)
"""The scan's -y axis: up in a SuperSplat scene."""
comptime SCAN_POSITIVE_Z = ScanAxis(4)
"""The scan's +z axis."""
comptime SCAN_NEGATIVE_Z = ScanAxis(5)
"""The scan's -z axis: north in `supersplat_frame`."""


def scan_axis(name: String) raises -> ScanAxis:
    """Return the axis that a name such as "-y" gives.

    Args:
        name: A sign, `+` or `-`, and a letter, `x`, `y` or `z`.

    Returns:
        The axis.

    Raises:
        Error: If the name is not one of the six.
    """
    for value in range(6):
        if ScanAxis(value).name() == name:
            return ScanAxis(value)
    raise Error("Scan frame: '" + name + "' is not an axis such as -y")


@fieldwise_init
struct ScaleSource(Equatable, ImplicitlyCopyable, Writable):
    """Where the length of a scan unit came from."""

    var value: Int
    """The stored ordinal."""

    def is_valid(self) -> Bool:
        """Return True if this names one of the 3 sources.

        Returns:
            Whether the value is 0 to 2.
        """
        return ordinal_valid(self.value, 3 - 1)

    def name(self) -> String:
        """Return the source's name, in lowercase.

        Returns:
            The name, or "unknown" for a value that is not valid.
        """
        var names: List[String] = ["declared", "measured", "assumed"]
        return ordinal_label(self.is_valid(), self.value, names, "unknown")


comptime SCALE_DECLARED = ScaleSource(0)
"""A publisher's convention, such as one unit to the meter, that nobody checked against the place."""
comptime SCALE_MEASURED = ScaleSource(1)
"""A person measured a length in the place and in the scan."""
comptime SCALE_ASSUMED = ScaleSource(2)
"""A storey height was assumed and matched to the scan."""


def scale_source(name: String) raises -> ScaleSource:
    """Return the scale source that a name gives.

    Args:
        name: `declared`, `measured` or `assumed`.

    Returns:
        The source.

    Raises:
        Error: If the name is not one of the three.
    """
    for value in range(3):
        if ScaleSource(value).name() == name:
            return ScaleSource(value)
    raise Error("Scan frame: '" + name + "' is not a scale source")


def axis_vector(axis: ScanAxis) raises -> Vec3d:
    """Return a scan axis as a unit vector in scan coordinates.

    Args:
        axis: The axis.

    Returns:
        The vector.

    Raises:
        Error: If the axis is not valid.
    """
    if not axis.is_valid():
        raise Error("Scan frame: an axis is 0 to 5")
    var out = List[Float64](length=3, fill=0)
    out[axis.index()] = axis.sign()
    return Vec3d(out[0], out[1], out[2])


@fieldwise_init
struct ScanFrame(ImplicitlyCopyable):
    """How a scan's coordinates map to a building's; see the module
    docstring."""

    var up: ScanAxis
    """The scan axis that becomes +z."""
    var north: ScanAxis
    """The scan axis that becomes +y before the heading turn."""
    var unit: Length64
    """The length of one scan unit."""
    var scale: ScaleSource
    """Where the unit came from."""
    var heading: Angle64
    """The turn of the plan about +z, counterclockwise."""
    var origin: Vec3d
    """The scan point that becomes the building's origin, in scan units."""

    def check(self) raises:
        """Refuse a frame that does not map a scan.

        Raises:
            Error: If an axis or the scale source is not valid, up and
                north are along one coordinate, the unit is not positive
                and finite, or the heading or the origin is not finite.
        """
        if not self.up.is_valid() or not self.north.is_valid():
            raise Error("Scan frame: an axis is 0 to 5")
        if self.up.index() == self.north.index():
            raise Error("Scan frame: up and north must be different axes")
        if not self.scale.is_valid():
            raise Error("Scan frame: a scale source is 0 to 2")
        require_positive_finite(
            self.unit.to(METER), "Scan frame: the unit must be positive"
        )
        require_finite(
            self.heading.value, "Scan frame: the heading must be finite"
        )
        if not (
            isfinite(self.origin.x)
            and isfinite(self.origin.y)
            and isfinite(self.origin.z)
        ):
            raise Error("Scan frame: the origin must be finite")

    def axes(self) raises -> List[Vec3d]:
        """Return the building's x, y and z axes in scan coordinates,
        before the heading turn.

        Returns:
            Three unit vectors.

        Raises:
            Error: If an axis is not valid.
        """
        var z = axis_vector(self.up)
        var y = axis_vector(self.north)
        return [y.cross(z), y, z]

    def map(self) raises -> AxisMap:
        """Return the frame as the scan axis each building axis reads.

        Returns:
            The map, which places many points without building the axes
            again.

        Raises:
            Error: If an axis is not valid.
        """
        var turn = self.heading.to(RADIAN)
        return AxisMap(
            _x_axis(self),
            self.north,
            self.up,
            self.origin,
            self.unit.to(METER),
            cos(turn),
            sin(turn),
        )

    def to_building(self, point: Vec3d) raises -> Vec3d:
        """Return a scan point in building coordinates, in meters.

        Args:
            point: The point, in scan units.

        Returns:
            The point; see the module docstring.

        Raises:
            Error: If an axis is not valid.
        """
        return self.map().place(point)


def _read(point: Vec3d, axis: ScanAxis) -> Float64:
    """Return a point's coordinate along a signed scan axis.

    Args:
        point: The point.
        axis: The axis.

    Returns:
        The coordinate, negated for a - axis.
    """
    var index = axis.index()
    var value = point.z
    if index == 0:
        value = point.x
    elif index == 1:
        value = point.y
    return axis.sign() * value


def _slot(first: Int, second: Int) -> Int:
    """Return where a covariance entry is in a splat's six numbers.

    Args:
        first: A row, 0 to 2.
        second: A column, 0 to 2.

    Returns:
        The place of xx, xy, xz, yy, yz or zz.
    """
    var low = min(first, second)
    var high = max(first, second)
    if low == 0:
        return high
    if low == 1:
        return high + 2
    return 5


@fieldwise_init
struct AxisMap(ImplicitlyCopyable):
    """A frame read once: the scan axis of each building axis, the origin,
    the unit and the heading turn."""

    var x: ScanAxis
    """The scan axis that becomes building x."""
    var y: ScanAxis
    """The scan axis that becomes building y."""
    var z: ScanAxis
    """The scan axis that becomes building z."""
    var origin: Vec3d
    """The scan point that becomes the building's origin."""
    var unit: Float64
    """The meters in one scan unit."""
    var cos: Float64
    """The cosine of the heading."""
    var sin: Float64
    """The sine of the heading."""

    def place(self, point: Vec3d) -> Vec3d:
        """Return a scan point in building coordinates, in meters.

        Args:
            point: The point, in scan units.

        Returns:
            The point; see the module docstring.
        """
        var d = point - self.origin
        var x = _read(d, self.x) * self.unit
        var y = _read(d, self.y) * self.unit
        return Vec3d(
            x * self.cos - y * self.sin,
            x * self.sin + y * self.cos,
            _read(d, self.z) * self.unit,
        )

    def covariance(
        self, values: List[Float32], at: Int
    ) -> SIMD[DType.float64, 8]:
        """Return a covariance on the building axes, before the heading
        turn, in square meters.

        Args:
            values: Six numbers a splat, xx, xy, xz, yy, yz and zz.
            at: The first of the splat's six.

        Returns:
            The building's xx, xy, xz, yy, yz and zz, then two zeros.
        """
        var axes: SIMD[DType.int64, 4] = [
            Int64(self.x.index()),
            Int64(self.y.index()),
            Int64(self.z.index()),
            0,
        ]
        var signs: SIMD[DType.float64, 4] = [
            self.x.sign(),
            self.y.sign(),
            self.z.sign(),
            0,
        ]
        var area = self.unit * self.unit
        var out = SIMD[DType.float64, 8](0)
        var place = 0
        for row in range(3):  # pragma: no branch
            for column in range(row, 3):  # pragma: no branch
                var stored = values[
                    at + _slot(Int(axes[row]), Int(axes[column]))
                ]
                out[place] = signs[row] * signs[column] * Float64(stored) * area
                place += 1
        return out


def supersplat_frame() -> ScanFrame:
    """Return the frame of a scene that looks upright in SuperSplat.

    Returns:
        Up along -y, north along -z, one unit declared as one meter, no
        heading and the scan origin.
    """
    return ScanFrame(
        SCAN_NEGATIVE_Y,
        SCAN_NEGATIVE_Z,
        Length64(1, METER),
        SCALE_DECLARED,
        Angle64(0, RADIAN),
        Vec3d(0, 0, 0),
    )


def building_covariance(
    geometry: GaussianSplatGeometry, splat: Int, frame: ScanFrame
) raises -> List[Float64]:
    """Return a splat's covariance on the building axes, before the
    heading turn, in square meters.

    Args:
        geometry: The splats.
        splat: Which splat.
        frame: The scan's frame.

    Returns:
        The six numbers xx, xy, xz, yy, yz and zz.

    Raises:
        Error: If an axis of the frame is not valid.
    """
    var c = frame.map().covariance(geometry.covariances, splat * 6)
    return [c[0], c[1], c[2], c[3], c[4], c[5]]


def _x_axis(frame: ScanFrame) raises -> ScanAxis:
    """Return the scan axis that becomes +x: north cross up.

    Args:
        frame: The frame.

    Returns:
        The axis.

    Raises:
        Error: If an axis of the frame is not valid.
    """
    var x = frame.axes()[0]
    var values: List[Float64] = [x.x, x.y, x.z]
    var axis = 0
    for index in range(3):
        if values[index] != 0:
            axis = index * 2
            if values[index] < 0:
                axis += 1
    return ScanAxis(axis)


def estimate_heading(
    geometry: GaussianSplatGeometry, frame: ScanFrame
) raises -> Angle64:
    """Return the heading that turns a scan's walls onto the plan axes.

    Each wall splat adds its weight, its opacity times how much longer
    than thick it is, to the bin of its angle. The five bins around the
    heaviest place, counted around the quarter turn, give the weighted
    mean angle.

    Args:
        geometry: The splats.
        frame: The scan's frame. Its heading is not used.

    Returns:
        A turn from minus to plus 45 degrees. Adding it to the frame's
        heading lines the strongest wall angle up with x.

    Raises:
        Error: If the frame is not valid, or no splat is a wall splat.
    """
    frame.check()
    var map = frame.map()
    var weights = List[Float64](length=HEADING_BINS, fill=0)
    var moments = List[Float64](length=HEADING_BINS, fill=0)
    var quarter = pi / 2
    for splat in range(geometry.count()):
        var c = map.covariance(geometry.covariances, splat * 6)
        var a = c[0]
        var b = c[1]
        var d = c[3]
        var mean = (a + d) / 2
        var spread = sqrt(((a - d) / 2) * ((a - d) / 2) + b * b)
        var long = mean + spread
        var thin = mean - spread
        if long <= 0 or thin * WALL_RATIO > long or thin * WALL_RATIO > c[5]:
            continue
        var weight = (
            Float64(geometry.colors[splat * 4 + 3]) / 255 * (1 - thin / long)
        )
        # The long plan axis, as an angle modulo a quarter turn.
        var angle = atan2(2 * b, a - d) / 2
        var folded = angle - quarter * floor(angle / quarter)
        var slot = Int(folded / quarter * HEADING_BINS) % HEADING_BINS
        weights[slot] += weight
        moments[slot] += weight * folded
    var best = 0
    var heaviest = Float64(0)
    for slot in range(HEADING_BINS):  # pragma: no branch
        var total = Float64(0)
        for offset in range(-2, 3):  # pragma: no branch
            total += weights[(slot + offset + HEADING_BINS) % HEADING_BINS]
        if total > heaviest:
            heaviest = total
            best = slot
    if heaviest == 0:
        raise Error("Scan frame: no splat is a wall splat")
    # The mean angle of the five bins. A bin past either end of the
    # quarter turn holds angles a quarter turn away.
    var moment = Float64(0)
    for offset in range(-2, 3):  # pragma: no branch
        var place = best + offset
        var slot = (place + HEADING_BINS) % HEADING_BINS
        var wrap = Float64(0)
        if place < 0:
            wrap = -quarter
        elif place >= HEADING_BINS:
            wrap = quarter
        moment += moments[slot] + weights[slot] * wrap
    var angle = moment / heaviest
    if angle > quarter / 2:
        angle -= quarter
    return Angle64(-angle, RADIAN)
