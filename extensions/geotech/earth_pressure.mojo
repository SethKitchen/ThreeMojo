# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The pressure of earth on a wall.

**Coefficients.** `rankine_active` and `rankine_passive` are Rankine's
coefficients for a smooth vertical wall, with a uniform backslope.
`at_rest` is Jaky's 1 - sin(phi). `coulomb_active` is Coulomb's
coefficient for a rough, battered wall, as in AASHTO LRFD Eq. 3.11.5.3-1.
`mononobe_okabe_active` adds a pseudo-static earthquake to it, as in
AASHTO LRFD Eq. A11.1.1.1-1.

**Trial wedge.** Where the ground behind the wall is a broken line, no
closed form fits. `trial_wedge` tries plane failure surfaces from the
base of a vertical plane, at angles from phi to 89 degrees. For each it
weighs the soil above the plane, with buoyant soil below a water level
and with buried pipes, and finds the thrust that holds it in balance with
no friction on the vertical plane (delta = 0). The largest thrust is the
active thrust. A scan of 720 angles finds the peak where the objective
has corners, and a golden-section search refines it.

`trial_wedge_resultant` finds where the thrust acts. It cuts the soil at
100 heights and finds the wedge thrust above each cut. The thrust above a
cut is the integral of the pressure above it, so integrating those
thrusts over height gives the moment about the base. For level ground
this gives the Rankine P H / 3.
"""

from std.math import atan, cos, isfinite, pi, sin, sqrt, tan
from extensions.geotech.kinds import ACROSS
from extensions.geotech.pipes import BuriedPipe, circle_band_area
from extensions.geotech.profile import GradePoint, GradeProfile
from extensions.geotech.quantities import MomentPerLength64, UnitWeight64
from units.si import Angle64, Length64, LineLoad64

comptime _SCAN = 720
comptime _GOLDEN_STEPS = 36
comptime _SLICES = 100
# The strips across a wedge that weigh the pipes in it.
comptime _PIPE_STRIPS = 16
# The steepest trial plane, in radians: 89 degrees.
comptime _STEEPEST = 1.5533430342749532


def _check_friction(phi: Float64) raises:
    """Refuse a friction angle outside 0 to 90 degrees."""
    if not (isfinite(phi) and phi >= 0 and phi < pi / 2):
        raise Error("A friction angle must be from 0 up to 90 degrees")


def rankine_active(
    friction: Angle64, backslope: Angle64 = Angle64(0)
) raises -> Float64:
    """Return Rankine's active earth-pressure coefficient.

    The coefficient applies on a vertical plane under ground that slopes up
    at the backslope angle. The thrust is parallel to the ground.

    Args:
        friction: The soil's friction angle.
        backslope: The slope of the ground behind the wall.

    Returns:
        Ka.

    Raises:
        Error: If the friction angle is outside 0 to 90 degrees, or the
            backslope is steeper than the friction angle.
    """
    var phi = friction.value
    var beta = backslope.value
    _check_friction(phi)
    if not isfinite(beta):
        raise Error("A backslope must be finite")
    if abs(beta) < 1e-12:
        var t = tan(pi / 4 - phi / 2)
        return t * t
    var radicand = cos(beta) ** 2 - cos(phi) ** 2
    if radicand < -1e-12:
        raise Error(
            "A Rankine backslope cannot be steeper than the friction angle"
        )
    var root = sqrt(max(radicand, 0.0))
    return cos(beta) * (cos(beta) - root) / (cos(beta) + root)


def rankine_passive(friction: Angle64) raises -> Float64:
    """Return Rankine's passive coefficient for level ground.

    Args:
        friction: The soil's friction angle.

    Returns:
        Kp = tan^2(45 + phi / 2).

    Raises:
        Error: If the friction angle is outside 0 to 90 degrees.
    """
    var phi = friction.value
    _check_friction(phi)
    var t = tan(pi / 4 + phi / 2)
    return t * t


def at_rest(friction: Angle64) raises -> Float64:
    """Return the at-rest coefficient of a normally consolidated soil.

    Args:
        friction: The soil's friction angle.

    Returns:
        K0 = 1 - sin(phi), after Jaky.

    Raises:
        Error: If the friction angle is outside 0 to 90 degrees.
    """
    var phi = friction.value
    _check_friction(phi)
    return 1 - sin(phi)


def coulomb_active(
    friction: Angle64,
    wall_friction: Angle64,
    backslope: Angle64 = Angle64(0),
    batter: Angle64 = Angle64(pi / 2),
) raises -> Float64:
    """Return Coulomb's active coefficient.

    AASHTO LRFD Eq. 3.11.5.3-1, with the wall face at `batter` from the
    horizontal (90 degrees is vertical).

    Args:
        friction: The soil's friction angle, phi.
        wall_friction: The friction angle between the soil and the wall,
            delta.
        backslope: The slope of the ground, beta.
        batter: The angle of the back face from the horizontal, theta.

    Returns:
        Ka.

    Raises:
        Error: If an angle is not finite or the friction angle is outside
            0 to 90 degrees, or the backslope is steeper than phi.
    """
    var phi = friction.value
    var delta = wall_friction.value
    var beta = backslope.value
    var theta = batter.value
    _check_friction(phi)
    if not (isfinite(delta) and isfinite(beta) and isfinite(theta)):
        raise Error("Coulomb angles must be finite")
    if beta > phi + 1e-12:
        raise Error(
            "A Coulomb backslope cannot be steeper than the friction angle"
        )
    var root = sqrt(
        max(sin(phi + delta) * sin(phi - beta), 0.0)
        / (sin(theta - delta) * sin(theta + beta))
    )
    var gamma = (1 + root) ** 2
    return sin(theta + phi) ** 2 / (
        gamma * sin(theta) ** 2 * sin(theta - delta)
    )


def mononobe_okabe_active(
    friction: Angle64,
    wall_friction: Angle64,
    horizontal: Float64,
    vertical: Float64 = 0.0,
    backslope: Angle64 = Angle64(0),
    batter: Angle64 = Angle64(0),
) raises -> Float64:
    """Return the Mononobe-Okabe seismic active coefficient.

    AASHTO LRFD Eq. A11.1.1.1-1. The batter `i` here is the back face's
    angle from the vertical, as the appendix measures it.

    Args:
        friction: The soil's friction angle, phi.
        wall_friction: The wall friction angle, delta.
        horizontal: The horizontal seismic coefficient, kh.
        vertical: The vertical seismic coefficient, kv.
        backslope: The slope of the ground, i.
        batter: The back face's angle from the vertical, beta.

    Returns:
        KAE.

    Raises:
        Error: If the seismic angle leaves no real solution, or an input
            is not finite.
    """
    var phi = friction.value
    var delta = wall_friction.value
    var i = backslope.value
    var beta = batter.value
    _check_friction(phi)
    if not (
        isfinite(delta)
        and isfinite(i)
        and isfinite(beta)
        and isfinite(horizontal)
        and isfinite(vertical)
    ):
        raise Error("Mononobe-Okabe inputs must be finite")
    if vertical >= 1:
        raise Error("The vertical seismic coefficient must be less than one")
    var psi = atan(horizontal / (1 - vertical))
    var s = sin(phi + delta) * sin(phi - psi - i)
    if s < 0:
        raise Error("The earthquake is too strong for a Mononobe-Okabe wedge")
    var root = sqrt(s / (cos(delta + beta + psi) * cos(i - beta)))
    return cos(phi - psi - beta) ** 2 / (
        cos(psi) * cos(beta) ** 2 * cos(delta + beta + psi) * (1 + root) ** 2
    )


@fieldwise_init
struct WedgeLoads(ImplicitlyCopyable):
    """What a trial wedge weighs and how wet it is."""

    var friction: Float64
    var unit_weight: Float64
    var water_unit_weight: Float64
    var horizontal: Float64


@fieldwise_init
struct Wedge(ImplicitlyCopyable):
    """The critical trial wedge behind a vertical plane."""

    # The active thrust, horizontal, per unit length of wall.
    var thrust: LineLoad64
    # The failure plane's angle from the horizontal.
    var angle: Angle64
    # Where the failure plane meets the ground, behind the plane.
    var reach: Length64
    # The weight of the wedge, per unit length of wall.
    var weight: LineLoad64


@fieldwise_init
struct WedgeResultant(ImplicitlyCopyable):
    """The active thrust and where it acts."""

    var wedge: Wedge
    # The moment of the thrust about the base of the plane.
    var moment: MomentPerLength64
    # The height of the thrust above the base of the plane.
    var arm: Length64


struct _Ground(Movable):
    """A trial wedge's ground, water and pipes as flat numbers in SI.

    Built once per search, so that each trial plane allocates nothing.
    `drop` lowers everything at once, for the cuts that find the arm.
    """

    var profile: GradeProfile
    var xs: List[Float64]
    var ys: List[Float64]
    var wet: Bool
    var level: Float64
    var drop: Float64
    var friction: Float64
    var gamma: Float64
    var gamma_w: Float64
    var kh: Float64
    # Pipes across the wall: count per panel length, outer and inner
    # radius, center, full, wall unit weight.
    var share: List[Float64]
    var outer: List[Float64]
    var inner: List[Float64]
    var center: List[Float64]
    var full: List[Bool]
    var wall: List[Float64]

    def __init__(
        out self,
        profile: GradeProfile,
        water: Optional[Length64],
        pipes: List[BuriedPipe],
        loads: WedgeLoads,
    ):
        """Flatten a profile, its water and the pipes across the wall.

        The profile is extended level by 500 ft past its last point.
        """
        self.profile = profile.copy()
        self.xs = List[Float64]()
        self.ys = List[Float64]()
        # A profile has two points at least, so the loop always runs.
        for p in profile.points:  # pragma: no branch
            self.xs.append(p.distance.value)
            self.ys.append(p.height.value)
        var n = len(self.xs)
        self.xs.append(max(self.xs[n - 1] + 152.4, 152.4))
        self.ys.append(self.ys[n - 1])
        self.wet = Bool(water)
        self.level = water.value().value if water else 0.0
        self.drop = 0
        self.friction = loads.friction
        self.gamma = loads.unit_weight
        self.gamma_w = loads.water_unit_weight
        self.kh = loads.horizontal
        self.share = List[Float64]()
        self.outer = List[Float64]()
        self.inner = List[Float64]()
        self.center = List[Float64]()
        self.full = List[Bool]()
        self.wall = List[Float64]()
        for p in pipes:
            # A pipe along the wall lies in the heel's section, not in the
            # wedge beyond the heel's plane.
            if p.run == ACROSS and p.count > 0 and p.outer_radius.value > 0:
                self.share.append(Float64(p.count) / p.panel.value)
                self.outer.append(p.outer_radius.value)
                self.inner.append(p.inner_radius.value)
                self.center.append(p.center.value)
                self.full.append(p.full)
                self.wall.append(p.wall_unit_weight.value)

    def height(self, x: Float64) -> Float64:
        """Return the ground's height at x, less the drop.

        The profile's own height is the same as the extended points':
        level past its last point, as the extension is.
        """
        return self.profile.height_si(x) - self.drop

    def areas(self, slope: Float64, x_end: Float64) -> Tuple[Float64, Float64]:
        """Return the wedge's area and its area below the water.

        Each piece of the ground between break points is straight, so
        trapezoids are exact. The break points are the profile's points,
        where the plane meets the water and where the ground does.
        """
        var total = Float64(0)
        var submerged = Float64(0)
        var yw = self.level - self.drop
        var x_line = yw / slope if slope > 0 else 1e300
        # The extended profile has three points at least, so the loop
        # always runs.
        for i in range(len(self.xs) - 1):  # pragma: no branch
            var a = max(self.xs[i], 0.0)
            var b = min(self.xs[i + 1], x_end)
            if b <= a:
                if self.xs[i] >= x_end:
                    break
                continue
            var y0 = self.ys[i] - self.drop
            var y1 = self.ys[i + 1] - self.drop
            var x0 = self.xs[i]
            var x1 = self.xs[i + 1]
            var ga = y0 + (y1 - y0) * (a - x0) / (x1 - x0)
            var gb = y0 + (y1 - y0) * (b - x0) / (x1 - x0)
            total += 0.5 * ((ga - slope * a) + (gb - slope * b)) * (b - a)
            if not self.wet:
                continue
            # Up to two more break points inside this piece.
            var p = 1e300
            var q = 1e300
            if x_line > a and x_line < b:
                p = x_line
            if (y0 - yw) * (y1 - yw) < 0:
                var xw = x0 + (yw - y0) * (x1 - x0) / (y1 - y0)
                if xw > a and xw < b:
                    q = xw
            if q < p:
                var t = p
                p = q
                q = t
            if p >= b:
                p = b
            if q >= b:
                q = b
            submerged += _under(y0, y1, x0, x1, yw, slope, a, p)
            submerged += _under(y0, y1, x0, x1, yw, slope, p, q)
            submerged += _under(y0, y1, x0, x1, yw, slope, q, b)
        return (max(total, 0.0), max(submerged, 0.0))

    def pipes_delta(self, slope: Float64, x_end: Float64) -> Float64:
        """Return the net weight the pipes add to a wedge.

        `force` calls it only for a wedge that reaches past the plane, so
        x_end is positive.
        """
        if len(self.share) == 0:
            return 0
        var dx = x_end / Float64(_PIPE_STRIPS)
        var gs = self.gamma
        var gw = self.gamma_w
        var yw = self.level - self.drop
        var total = Float64(0)
        # _PIPE_STRIPS is a positive constant and there is a pipe, so both
        # loops always run. Where the ground is not above the plane, every
        # band area below is zero and the strip adds nothing.
        for k in range(_PIPE_STRIPS):  # pragma: no branch
            var x = (Float64(k) + 0.5) * dx
            var y_lo = slope * x
            var y_hi = self.height(x)
            for j in range(len(self.share)):  # pragma: no branch
                var ro = self.outer[j]
                var ri = self.inner[j]
                var yc = self.center[j] - self.drop
                var scale = self.share[j] * dx
                var a_ext = circle_band_area(ro, yc, y_lo, y_hi)
                var a_int = circle_band_area(ri, yc, y_lo, y_hi)
                var a_wall = max(a_ext - a_int, 0.0)
                var a_ext_sub = Float64(0)
                var a_int_sub = Float64(0)
                if self.wet:
                    var top = min(y_hi, yw)
                    a_ext_sub = circle_band_area(ro, yc, y_lo, top)
                    a_int_sub = circle_band_area(ri, yc, y_lo, top)
                var a_dry = max(a_ext - a_ext_sub, 0.0)
                var a_wall_sub = max(a_ext_sub - a_int_sub, 0.0)
                var a_wall_dry = max(a_wall - a_wall_sub, 0.0)
                var gc = self.wall[j]
                total -= scale * (gs * a_dry + max(gs - gw, 0.0) * a_ext_sub)
                total += scale * (
                    gc * a_wall_dry + max(gc - gw, 0.0) * a_wall_sub
                )
                if self.full[j]:
                    total += scale * gw * max(a_int - a_int_sub, 0.0)
        return total

    def force(self, theta: Float64) -> Tuple[Float64, Float64, Float64]:
        """Return the thrust, reach and weight of one trial plane."""
        var slope = tan(theta)
        var x_end = Float64(-1)
        # The extended profile has three points at least, so the loop
        # always runs.
        for i in range(len(self.xs) - 1):  # pragma: no branch
            var xa = self.xs[i]
            var xb = self.xs[i + 1]
            var da = self.ys[i] - self.drop - slope * xa
            var db = self.ys[i + 1] - self.drop - slope * xb
            if da >= -1e-10 and db <= 1e-10:
                if abs(da - db) < 1e-12:
                    continue
                x_end = xa + da / (da - db) * (xb - xa)
                break
        if x_end <= 0:
            return (0.0, 0.0, 0.0)
        var areas = self.areas(slope, x_end)
        var weight = self.gamma * areas[0] - self.gamma_w * areas[1]
        weight += self.pipes_delta(slope, x_end)
        var thrust = weight * (self.kh + tan(theta - self.friction))
        return (max(thrust, 0.0), x_end, weight)

    def critical(self) -> Tuple[Float64, Float64, Float64, Float64]:
        """Return the thrust, angle, reach and weight of the critical
        plane: a scan of 720 angles, then a golden-section search."""
        var lo = self.friction + 1e-5
        var hi = _STEEPEST
        var step = (hi - lo) / Float64(_SCAN)
        var best = Float64(-1)
        var theta_best = lo
        # _SCAN and _GOLDEN_STEPS are positive constants, so these loops
        # always run.
        for k in range(_SCAN + 1):  # pragma: no branch
            var theta = lo + Float64(k) * step
            var f = self.force(theta)[0]
            if f >= best:
                best = f
                theta_best = theta
        var a = max(lo, theta_best - 2 * step)
        var b = min(hi, theta_best + 2 * step)
        var gr = (sqrt(5.0) - 1.0) / 2.0
        var c = b - gr * (b - a)
        var d = a + gr * (b - a)
        var fc = self.force(c)[0]
        var fd = self.force(d)[0]
        for _ in range(_GOLDEN_STEPS):  # pragma: no branch
            if fc < fd:
                a = c
                c = d
                fc = fd
                d = a + gr * (b - a)
                fd = self.force(d)[0]
            else:
                b = d
                d = c
                fd = fc
                c = b - gr * (b - a)
                fc = self.force(c)[0]
        var theta = 0.5 * (a + b)
        var r = self.force(theta)
        return (r[0], theta, r[1], r[2])


def _under(
    y0: Float64,
    y1: Float64,
    x0: Float64,
    x1: Float64,
    yw: Float64,
    slope: Float64,
    left: Float64,
    right: Float64,
) -> Float64:
    """Return the wedge's area below the water between two x, where the
    ground runs straight from (x0, y0) to (x1, y1)."""
    if right <= left:
        return 0
    var gl = y0 + (y1 - y0) * (left - x0) / (x1 - x0)
    var gr = y0 + (y1 - y0) * (right - x0) / (x1 - x0)
    var da = max(min(gl, yw) - slope * left, 0.0)
    var db = max(min(gr, yw) - slope * right, 0.0)
    return 0.5 * (da + db) * (right - left)


def _check_wedge_inputs(
    friction: Angle64,
    unit_weight: UnitWeight64,
    water_unit_weight: UnitWeight64,
    horizontal: Float64,
    pipes: List[BuriedPipe],
) raises:
    """Refuse inputs a trial wedge cannot use."""
    _check_friction(friction.value)
    if not (isfinite(unit_weight.value) and unit_weight.value >= 0):
        raise Error("A soil unit weight must be zero or more and finite")
    if not (isfinite(water_unit_weight.value) and water_unit_weight.value >= 0):
        raise Error("A water unit weight must be zero or more and finite")
    if not (isfinite(horizontal) and horizontal >= 0):
        raise Error("A seismic coefficient must be zero or more and finite")
    for p in pipes:
        p.check()


def trial_wedge(
    profile: GradeProfile,
    friction: Angle64,
    unit_weight: UnitWeight64,
    water_unit_weight: UnitWeight64,
    water: Optional[Length64] = None,
    horizontal: Float64 = 0.0,
    pipes: List[BuriedPipe] = List[BuriedPipe](),
) raises -> Wedge:
    """Return the critical Coulomb wedge behind a vertical plane.

    Args:
        profile: The ground, as heights above the base of the plane.
        friction: The soil's friction angle.
        unit_weight: The soil's moist unit weight.
        water_unit_weight: The unit weight of water.
        water: The water level above the base of the plane, or None.
        horizontal: A pseudo-static seismic coefficient, kh, zero or more.
        pipes: Pipes in the soil, measured from the same base.

    Returns:
        The wedge of largest thrust.

    Raises:
        Error: If an input is not valid.
    """
    _check_wedge_inputs(
        friction, unit_weight, water_unit_weight, horizontal, pipes
    )
    var ground = _Ground(
        profile,
        water,
        pipes,
        WedgeLoads(
            friction.value,
            unit_weight.value,
            water_unit_weight.value,
            horizontal,
        ),
    )
    var r = ground.critical()
    return Wedge(
        LineLoad64(r[0]), Angle64(r[1]), Length64(r[2]), LineLoad64(r[3])
    )


def trial_wedge_resultant(
    profile: GradeProfile,
    friction: Angle64,
    unit_weight: UnitWeight64,
    water_unit_weight: UnitWeight64,
    water: Optional[Length64] = None,
    horizontal: Float64 = 0.0,
    pipes: List[BuriedPipe] = List[BuriedPipe](),
) raises -> WedgeResultant:
    """Return the critical wedge's thrust, moment and arm.

    Args:
        profile: The ground, as heights above the base of the plane.
        friction: The soil's friction angle.
        unit_weight: The soil's moist unit weight.
        water_unit_weight: The unit weight of water.
        water: The water level above the base of the plane, or None.
        horizontal: A pseudo-static seismic coefficient, kh, zero or more.
        pipes: Pipes in the soil, measured from the same base.

    Returns:
        The thrust, its moment about the base of the plane and its height.

    Raises:
        Error: If an input is not valid, or the ground is not above the
            base of the plane.
    """
    _check_wedge_inputs(
        friction, unit_weight, water_unit_weight, horizontal, pipes
    )
    var height = profile.plane_height().value
    if not (height > 0):
        raise Error("The ground must stand above the base of the plane")
    var ground = _Ground(
        profile,
        water,
        pipes,
        WedgeLoads(
            friction.value,
            unit_weight.value,
            water_unit_weight.value,
            horizontal,
        ),
    )
    var r = ground.critical()
    var wedge = Wedge(
        LineLoad64(r[0]), Angle64(r[1]), Length64(r[2]), LineLoad64(r[3])
    )
    var dz = height / Float64(_SLICES)
    var moment = Float64(0)
    # _SLICES is a positive constant, so the loop always runs.
    for k in range(_SLICES):  # pragma: no branch
        ground.drop = (Float64(k) + 0.5) * dz
        moment += ground.critical()[0] * dz
    var thrust = wedge.thrust.value
    var arm = moment / thrust if thrust > 0 else 0.0
    return WedgeResultant(wedge, MomentPerLength64(moment), Length64(arm))
