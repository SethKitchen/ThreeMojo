# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Global stability on circular slip surfaces, by Bishop's method.

A `SlopeSection` is a vertical cut through the ground: a top surface, the
soil below it, and regions of other materials, such as a wall's concrete
or a layer of fill. x runs across the section and z up. The ground is
taken to fail toward -x, so a wall's front faces -x.

`bishop_factor` cuts the mass above a circle into vertical slices and
finds the factor of safety F that satisfies Bishop's simplified method:

    F = sum[(c b + (W - u b) tan phi) / m] / sum[W sin(alpha)],
    m = cos(alpha) + sin(alpha) tan(phi) / F,

where W is a slice's weight with any surcharge and ponded water on it, b
its width, alpha its base's inclination, and u the pore pressure at its
base under a water table. F is found by fixed-point iteration.

`critical_circle` searches a grid of centers and radii for the lowest
factor of safety, keeping only circles whose mass holds every given
point: the corners of a footing, so that the circle passes under it.
"""

from std.math import asin, cos, inf, isfinite, sin, sqrt, tan
from extensions.geotech.units import UnitWeight64
from extensions.geotech.wall import Soil
from units.si import Length64, Pressure64

comptime _SLICES = 60
comptime _COLUMN = 24
comptime _ITERATIONS = 100
# The smallest m_alpha used; smaller values make F run away at a steep
# exit, a known weakness of Bishop's method.
comptime _M_FLOOR = 0.2


@fieldwise_init
struct SectionPoint(ImplicitlyCopyable):
    """A point of a section."""

    var x: Length64
    var z: Length64


struct SlopeRegion(Copyable, Movable):
    """A polygon of one material."""

    var outline: List[SectionPoint]
    var soil: Soil

    def __init__(out self, var outline: List[SectionPoint], soil: Soil) raises:
        """Make a region.

        Args:
            outline: The polygon's corners, in either order.
            soil: Its material.

        Raises:
            Error: If the outline has fewer than three corners, or a
                corner or the soil is not valid.
        """
        if len(outline) < 3:
            raise Error("A region needs at least three corners")
        # There are three corners at least, so the loop always runs.
        for p in outline:  # pragma: no branch
            if not (isfinite(p.x.value) and isfinite(p.z.value)):
                raise Error("A region corner must be finite")
        soil.check()
        self.outline = outline^
        self.soil = soil

    def contains(self, x: Float64, z: Float64) -> Bool:
        """Return True if a point is inside the polygon.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            Whether it is inside, by the even-odd rule.
        """
        var inside = False
        var n = len(self.outline)
        var j = n - 1
        # A region has three corners at least, so the loop always runs.
        for i in range(n):  # pragma: no branch
            var xi = self.outline[i].x.value
            var zi = self.outline[i].z.value
            var xj = self.outline[j].x.value
            var zj = self.outline[j].z.value
            if (zi > z) != (zj > z):
                var cross = xi + (z - zi) * (xj - xi) / (zj - zi)
                if x < cross:
                    inside = not inside
            j = i
        return inside


@fieldwise_init
struct Surcharge(ImplicitlyCopyable):
    """A uniform vertical pressure on the surface between two x."""

    var start: Length64
    var end: Length64
    var pressure: Pressure64


def _line_at(line: List[SectionPoint], x: Float64) -> Float64:
    """Return a broken line's z at x, level past its ends."""
    var n = len(line)
    if x <= line[0].x.value:
        return line[0].z.value
    # A line has two points at least, so the loop always runs. x is past
    # every point before i, so x0 < x <= x1 and the run is not vertical.
    for i in range(1, n):  # pragma: no branch
        var x1 = line[i].x.value
        if x <= x1:
            var x0 = line[i - 1].x.value
            var z0 = line[i - 1].z.value
            var z1 = line[i].z.value
            return z0 + (z1 - z0) * (x - x0) / (x1 - x0)
    return line[n - 1].z.value


def _check_line(line: List[SectionPoint], what: String) raises:
    """Refuse a broken line that is short, not finite or goes back."""
    if len(line) < 2:
        raise Error(what + " needs at least two points")
    # There are two points at least, so the loop always runs.
    for i in range(len(line)):  # pragma: no branch
        if not (isfinite(line[i].x.value) and isfinite(line[i].z.value)):
            raise Error(what + " must be finite")
        if i > 0 and line[i].x.value < line[i - 1].x.value:
            raise Error(what + " must not turn back in x")


struct SlopeSection(Copyable, Movable):
    """A section through the ground, for slip-circle analysis."""

    # The top of the solid: ground, and the top of any wall.
    var surface: List[SectionPoint]
    # The material below the surface, outside every region.
    var ground: Soil
    var regions: List[SlopeRegion]
    # The water table, or an empty list for none. Above the surface it is
    # ponded water.
    var water_table: List[SectionPoint]
    var water_unit_weight: UnitWeight64
    var surcharges: List[Surcharge]

    def __init__(
        out self,
        var surface: List[SectionPoint],
        ground: Soil,
        water_unit_weight: UnitWeight64,
    ) raises:
        """Make a section of one soil under a surface, with no water.

        Args:
            surface: The top of the solid, with x not decreasing.
            ground: The soil.
            water_unit_weight: The unit weight of water.

        Raises:
            Error: If the surface or the soil is not valid.
        """
        _check_line(surface, "A surface")
        ground.check()
        self.surface = surface^
        self.ground = ground
        self.regions = List[SlopeRegion]()
        self.water_table = List[SectionPoint]()
        self.water_unit_weight = water_unit_weight
        self.surcharges = List[Surcharge]()

    def set_water_table(mut self, var line: List[SectionPoint]) raises:
        """Set the water table.

        Args:
            line: The table, with x not decreasing.

        Raises:
            Error: If the line is not valid.
        """
        _check_line(line, "A water table")
        self.water_table = line^

    def soil_at(self, x: Float64, z: Float64) -> Soil:
        """Return the material at a point below the surface.

        Args:
            x: The point's x, in meters.
            z: The point's z, in meters.

        Returns:
            The first region that holds it, else the ground.
        """
        for r in self.regions:
            if r.contains(x, z):
                return r.soil
        return self.ground

    def top_at(self, x: Float64) -> Float64:
        """Return the surface's z at x, in meters.

        Args:
            x: The x, in meters.

        Returns:
            The z.
        """
        return _line_at(self.surface, x)

    def water_at(self, x: Float64) -> Float64:
        """Return the water table's z at x, in meters.

        Args:
            x: The x, in meters.

        Returns:
            The z; minus infinity with no water table.
        """
        if len(self.water_table) == 0:
            return -inf[DType.float64]()
        return _line_at(self.water_table, x)


@fieldwise_init
struct SlipCircle(ImplicitlyCopyable):
    """A circular slip surface."""

    var center_x: Length64
    var center_z: Length64
    var radius: Length64


@fieldwise_init
struct SlipResult(ImplicitlyCopyable):
    """A slip circle and its factor of safety."""

    var circle: SlipCircle
    var factor: Float64
    # Where the slip surface leaves and enters the surface.
    var start: Length64
    var end: Length64
    # The mass above the circle, per unit length.
    var weight: Float64


def bishop_factor(
    section: SlopeSection, circle: SlipCircle
) raises -> SlipResult:
    """Return the factor of safety of one slip circle.

    Args:
        section: The ground.
        circle: The circle.

    Returns:
        The factor; infinite where the circle moves no driving mass.

    Raises:
        Error: If the radius is not positive or the center not finite.
    """
    var xc = circle.center_x.value
    var zc = circle.center_z.value
    var r = circle.radius.value
    if not (isfinite(xc) and isfinite(zc) and isfinite(r) and r > 0):
        raise Error("A slip circle needs a finite center and positive radius")
    var gw = section.water_unit_weight.value
    var b = 2 * r / Float64(_SLICES)
    var weights = List[Float64]()
    var alphas = List[Float64]()
    var cohesions = List[Float64]()
    var frictions = List[Float64]()
    var effective = List[Float64]()
    var first = inf[DType.float64]()
    var last = -inf[DType.float64]()
    var total = Float64(0)
    # _SLICES and _COLUMN are positive constants, so these loops always run.
    for k in range(_SLICES):  # pragma: no branch
        var x = xc - r + (Float64(k) + 0.5) * b
        var dx = x - xc
        var root = sqrt(max(r * r - dx * dx, 0.0))
        var z_base = zc - root
        var z_top = section.top_at(x)
        if z_top <= z_base:
            continue
        var dz = (z_top - z_base) / Float64(_COLUMN)
        var w = Float64(0)
        for j in range(_COLUMN):  # pragma: no branch
            var z = z_base + (Float64(j) + 0.5) * dz
            w += section.soil_at(x, z).unit_weight.value * dz
        w *= b
        var zw = section.water_at(x)
        if zw > z_top:
            w += gw * (zw - z_top) * b
        for s in section.surcharges:
            if x >= s.start.value and x <= s.end.value:
                w += s.pressure.value * b
        var u = gw * max(zw - z_base, 0.0)
        var base = section.soil_at(x, z_base + 1e-6)
        weights.append(w)
        alphas.append(asin(max(-1.0, min(1.0, dx / r))))
        cohesions.append(base.cohesion.value * b)
        frictions.append(tan(base.friction.value))
        effective.append(max(w - u * b, 0.0))
        first = min(first, x - b / 2)
        last = max(last, x + b / 2)
        total += w
    var driving = Float64(0)
    for i in range(len(weights)):
        driving += weights[i] * sin(alphas[i])
    if not (driving > 1e-9):
        return SlipResult(
            circle, inf[DType.float64](), Length64(0), Length64(0), total
        )
    var f = Float64(1)
    # _ITERATIONS is a positive constant, and a positive driving sum needs
    # a slice, so both loops always run.
    for _ in range(_ITERATIONS):  # pragma: no branch
        var resisting = Float64(0)
        for i in range(len(weights)):  # pragma: no branch
            var m = cos(alphas[i]) + sin(alphas[i]) * frictions[i] / f
            m = max(m, _M_FLOOR)
            resisting += (cohesions[i] + effective[i] * frictions[i]) / m
        var next = resisting / driving
        if abs(next - f) < 1e-7:
            f = next
            break
        f = next
    return SlipResult(circle, f, Length64(first), Length64(last), total)


@fieldwise_init
struct SlipSearch(ImplicitlyCopyable):
    """A grid of trial circles."""

    var left: Length64
    var right: Length64
    var bottom: Length64
    var top: Length64
    var columns: Int
    var rows: Int
    var smallest: Length64
    var largest: Length64
    var radii: Int


def _holds(circle: SlipCircle, points: List[SectionPoint]) -> Bool:
    """Return True if every point is inside the circle."""
    for p in points:
        var dx = p.x.value - circle.center_x.value
        var dz = p.z.value - circle.center_z.value
        if dx * dx + dz * dz >= circle.radius.value * circle.radius.value:
            return False
    return True


def critical_circle(
    section: SlopeSection,
    search: SlipSearch,
    inside: List[SectionPoint] = List[SectionPoint](),
) raises -> SlipResult:
    """Return the circle of lowest factor of safety on a grid.

    Args:
        section: The ground.
        search: The grid of centers and radii.
        inside: Points every trial circle's mass must hold.

    Returns:
        The critical circle; an infinite factor if no circle qualifies.

    Raises:
        Error: If the grid has no cells or its radii are not positive.
    """
    if search.columns < 1 or search.rows < 1 or search.radii < 1:
        raise Error("A slip search needs at least one center and radius")
    if not (
        search.smallest.value > 0
        and search.largest.value >= search.smallest.value
    ):
        raise Error("A slip search's radii must be positive and in order")
    var best = SlipResult(
        SlipCircle(Length64(0), Length64(0), Length64(1)),
        inf[DType.float64](),
        Length64(0),
        Length64(0),
        0,
    )
    # The grid has one column, row and radius at least, so these loops
    # always run.
    for i in range(search.columns):  # pragma: no branch
        var tx = 0.5 if search.columns == 1 else Float64(i) / Float64(
            search.columns - 1
        )
        var x = search.left.value + tx * (
            search.right.value - search.left.value
        )
        for j in range(search.rows):  # pragma: no branch
            var tz = 0.5 if search.rows == 1 else Float64(j) / Float64(
                search.rows - 1
            )
            var z = search.bottom.value + tz * (
                search.top.value - search.bottom.value
            )
            for k in range(search.radii):  # pragma: no branch
                var tr = 0.5 if search.radii == 1 else Float64(k) / Float64(
                    search.radii - 1
                )
                var radius = search.smallest.value + tr * (
                    search.largest.value - search.smallest.value
                )
                var circle = SlipCircle(
                    Length64(x), Length64(z), Length64(radius)
                )
                if not _holds(circle, inside):
                    continue
                var result = bishop_factor(section, circle)
                if result.factor < best.factor:
                    best = result
    return best
