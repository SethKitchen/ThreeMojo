# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A cantilever retaining wall and the loads on one unit length of it.

The section is a stem on a footing. The toe is the part of the footing in
front of the stem, the heel the part behind it. A key may hang below the
front edge. x runs from the toe edge toward the heel, and y up from the
bottom of the footing.

`wall_loads` builds the unfactored loads:

- **DC**: the stem, less any openings; the footing; the key; pipe walls
  over the heel.
- **EV**: the soil on the heel, less what pipes displace, and the soil of
  a rising grade over the heel.
- **LS_V**: the live-load surcharge on the heel, for bearing only.
- **EH**: the active thrust on the vertical plane through the heel's end.
  Under a broken grade it is a trial wedge; under level or uniformly
  sloping ground it is Rankine's, with buoyant soil below the water level.
- **ES**: a uniform earth surcharge for a rise given as a height.
- **LS**: the live-load surcharge as a uniform lateral pressure over the
  height it acts on, and a line load on top of the wall, such as a rail.
- **WA**: the net thrust of a water level that is higher behind the wall
  than in front.
- **PW**: water in full pipe barrels.

Same-level water is carried by buoyant unit weights, with no separate
uplift. `stem_effects` gives the moment and shear at the base of the stem
for a set of load factors.
"""

from std.math import isfinite
from extensions.geotech.earth_pressure import (
    WedgeResultant,
    rankine_active,
    trial_wedge_resultant,
)
from extensions.geotech.kinds import DC, EH, ES, EV, LS, LS_V, PW, WA
from extensions.geotech.loads import LateralLoad, LoadFactors, VerticalLoad
from extensions.geotech.pipes import BuriedPipe, pipe_weights
from extensions.geotech.profile import GradeProfile
from extensions.geotech.quantities import MomentPerLength64, UnitWeight64
from extensions.geotech.water import effective_unit_weight, net_hydrostatic
from units.si import Angle64, Length64, LineLoad64, Pressure64

# Strips across the heel that weigh a terrace below the water level.
comptime _TERRACE_STRIPS = 40


@fieldwise_init
struct Soil(ImplicitlyCopyable):
    """A soil's unit weight and strength."""

    var unit_weight: UnitWeight64
    var friction: Angle64
    var cohesion: Pressure64

    def check(self) raises:
        """Refuse a soil that cannot be analyzed.

        Raises:
            Error: If the unit weight or cohesion is negative or not
                finite, or the friction angle is outside 0 to 90 degrees.
        """
        if not (
            isfinite(self.unit_weight.value) and self.unit_weight.value >= 0
        ):
            raise Error("A soil unit weight must be zero or more and finite")
        if not (
            isfinite(self.friction.value)
            and self.friction.value >= 0
            and self.friction.value < 1.5707963267948966
        ):
            raise Error("A friction angle must be from 0 up to 90 degrees")
        if not (isfinite(self.cohesion.value) and self.cohesion.value >= 0):
            raise Error("A cohesion must be zero or more and finite")


@fieldwise_init
struct CantileverWall(ImplicitlyCopyable):
    """The cross-section of a cantilever retaining wall."""

    # From the bottom of the footing to the top of the stem.
    var height: Length64
    # The footing's thickness.
    var footing: Length64
    # The stem's thickness.
    var stem: Length64
    # The footing's width, B.
    var width: Length64
    # The footing in front of the stem.
    var toe: Length64
    # How deep a key hangs below the toe edge; zero for none.
    var key_depth: Length64
    # The key's thickness.
    var key_width: Length64
    # How far the stem stands above the retained ground at the wall.
    var exposed: Length64
    # The area of openings in the stem's face, per unit length of wall.
    var stem_void: Length64

    def heel(self) -> Length64:
        """Return the footing behind the stem.

        Returns:
            The width less the toe and the stem.
        """
        return self.width - self.toe - self.stem

    def stem_height(self) -> Length64:
        """Return the stem's height above the footing.

        Returns:
            The height less the footing.
        """
        return self.height - self.footing

    def retained_height(self) -> Length64:
        """Return the height of soil at the stem's back face.

        Returns:
            The height less the exposed stem.
        """
        return self.height - self.exposed

    def check(self) raises:
        """Refuse a section that cannot stand.

        Raises:
            Error: If a dimension is not finite, a size is not positive,
                the heel is negative, the footing is not below the top,
                or the retained soil is not above the footing.
        """
        var values: List[Float64] = [
            self.height.value,
            self.footing.value,
            self.stem.value,
            self.width.value,
            self.toe.value,
            self.key_depth.value,
            self.key_width.value,
            self.exposed.value,
            self.stem_void.value,
        ]
        # The list holds nine values, so the loop always runs.
        for v in values:  # pragma: no branch
            if not isfinite(v):
                raise Error("A wall dimension must be finite")
        if not (
            self.height.value > 0
            and self.footing.value > 0
            and self.stem.value > 0
            and self.width.value > 0
        ):
            raise Error(
                "A wall's height, footing, stem and width must be positive"
            )
        if (
            self.toe.value < 0
            or self.key_depth.value < 0
            or self.key_width.value < 0
            or self.exposed.value < 0
            or self.stem_void.value < 0
        ):
            raise Error(
                "A wall's toe, key, exposure and void cannot be negative"
            )
        if self.heel().value < 0:
            raise Error("The toe and stem are wider than the footing")
        if self.footing.value >= self.height.value:
            raise Error("The footing must be below the top of the wall")
        if self.retained_height().value <= self.footing.value:
            raise Error("The retained soil must stand above the footing")


struct RetainedSide(Copyable, Movable):
    """What stands behind a wall: soil, grade, traffic and water."""

    var soil: Soil
    # The ground's rise above the retained height, by distance behind the
    # stem's back face, or None for level ground.
    var grade: Optional[GradeProfile]
    # A rise given as a height of uniform earth surcharge, used with no
    # grade.
    var rise: Length64
    # How much of that rise to credit as weight on the heel; None credits
    # all of it.
    var rise_weight: Optional[Length64]
    # A uniform backslope for Rankine's coefficient, used with no grade.
    var backslope: Angle64
    # The live-load surcharge as an equivalent height of soil, h_eq.
    var live_height: Length64
    # A horizontal line load on top of the wall, such as a rail.
    var top_load: LineLoad64
    # Its height above the top of the wall.
    var top_load_height: Length64
    # The water level above the footing's base, or None for dry.
    var water: Optional[Length64]
    # How much lower the water stands in front of the wall.
    var water_drop: Length64
    # Pipes in the soil, measured from the footing's base.
    var pipes: List[BuriedPipe]

    def __init__(out self, soil: Soil):
        """Make level, dry ground with no traffic and no pipes.

        Args:
            soil: The retained soil.
        """
        self.soil = soil
        self.grade = None
        self.rise = Length64(0)
        self.rise_weight = None
        self.backslope = Angle64(0)
        self.live_height = Length64(0)
        self.top_load = LineLoad64(0)
        self.top_load_height = Length64(0)
        self.water = None
        self.water_drop = Length64(0)
        self.pipes = List[BuriedPipe]()

    def check(self) raises:
        """Refuse conditions that cannot be analyzed.

        Raises:
            Error: If the soil or a pipe is not valid, or a height, load or
                level is negative or not finite.
        """
        self.soil.check()
        for p in self.pipes:
            p.check()
        var values: List[Float64] = [
            self.rise.value,
            self.live_height.value,
            self.top_load.value,
            self.top_load_height.value,
            self.water_drop.value,
        ]
        # The list holds five values, so the loop always runs.
        for v in values:  # pragma: no branch
            if not (isfinite(v) and v >= 0):
                raise Error(
                    "Rises, surcharges, loads and water drops must be zero or"
                    " more"
                )
        if self.rise_weight and not (
            isfinite(self.rise_weight.value().value)
            and self.rise_weight.value().value >= 0
        ):
            raise Error("A credited rise must be zero or more")
        if self.water and not isfinite(self.water.value().value):
            raise Error("A water level must be finite")
        if not isfinite(self.backslope.value):
            raise Error("A backslope must be finite")


@fieldwise_init
struct WallMaterials(ImplicitlyCopyable):
    """The unit weights of the wall and of water."""

    var concrete: UnitWeight64
    var water: UnitWeight64


struct WallLoads(Copyable, Movable):
    """The unfactored loads on a unit length of wall."""

    var vertical: List[VerticalLoad]
    var lateral: List[LateralLoad]
    # The height of soil at the stem's back face.
    var retained_height: Length64
    # The height the lateral pressures act on, at the heel's end.
    var pressure_height: Length64
    # Rankine's coefficient for the retained soil.
    var active: Float64
    # The trial wedge, where the grade is a broken line.
    var wedge: Optional[WedgeResultant]
    # The ground at the heel's end, where the grade is a broken line.
    var heel_profile: Optional[GradeProfile]

    def __init__(out self):
        """Make an empty set of loads."""
        self.vertical = List[VerticalLoad]()
        self.lateral = List[LateralLoad]()
        self.retained_height = Length64(0)
        self.pressure_height = Length64(0)
        self.active = 0
        self.wedge = None
        self.heel_profile = None

    def vertical_force(self, label: String) -> LineLoad64:
        """Return the sum of the vertical loads with a label.

        Args:
            label: The label.

        Returns:
            The sum; zero if none has it.
        """
        var total = Float64(0)
        for load in self.vertical:
            if load.label == label:
                total += load.force.value
        return LineLoad64(total)


def wall_loads(
    wall: CantileverWall, retained: RetainedSide, materials: WallMaterials
) raises -> WallLoads:
    """Return the unfactored loads on a unit length of wall.

    Args:
        wall: The section.
        retained: The conditions behind it.
        materials: The unit weights of concrete and water.

    Returns:
        The vertical and lateral loads.

    Raises:
        Error: If the wall or the conditions are not valid.
    """
    wall.check()
    retained.check()
    var out = WallLoads()
    var gw = materials.water
    var gamma = retained.soil.unit_weight
    var h = wall.height.value
    var t_ftg = wall.footing.value
    var t_stem = wall.stem.value
    var b = wall.width.value
    var toe = wall.toe.value
    var heel = wall.heel().value
    var h_soil = wall.retained_height().value
    out.retained_height = Length64(h_soil)
    out.active = rankine_active(retained.soil.friction, retained.backslope)
    var ka = out.active

    # --- vertical loads, with x from the toe edge.
    var stem_area = (
        max(wall.stem_height().value - wall.stem_void.value, 0.0) * t_stem
    )
    var gc_stem = effective_unit_weight(
        materials.concrete, wall.footing, wall.height, retained.water, gw
    )
    out.vertical.append(
        VerticalLoad(
            DC,
            "stem",
            LineLoad64(gc_stem.value * stem_area),
            Length64(toe + t_stem / 2),
        )
    )
    var gc_ftg = effective_unit_weight(
        materials.concrete, Length64(0), wall.footing, retained.water, gw
    )
    out.vertical.append(
        VerticalLoad(
            DC, "footing", LineLoad64(gc_ftg.value * b * t_ftg), Length64(b / 2)
        )
    )
    if wall.key_depth.value > 0:
        var d = wall.key_depth.value
        var gc_key = effective_unit_weight(
            materials.concrete, Length64(-d), Length64(0), retained.water, gw
        )
        out.vertical.append(
            VerticalLoad(
                DC,
                "key",
                LineLoad64(gc_key.value * wall.key_width.value * d),
                Length64(wall.key_width.value / 2),
            )
        )
    var stem_back = toe + t_stem
    var heel_arm = stem_back + heel / 2
    var gs = effective_unit_weight(
        gamma, wall.footing, Length64(h_soil), retained.water, gw
    )
    var heel_soil = gs.value * heel * (h_soil - t_ftg)
    if len(retained.pipes) > 0:
        var pw = pipe_weights(
            retained.pipes,
            wall.footing,
            Length64(h_soil),
            retained.water,
            gamma,
            gw,
            Length64(heel),
        )
        heel_soil -= pw.soil_removed.value
        if pw.wall_added.value > 1e-9:
            out.vertical.append(
                VerticalLoad(
                    DC, "pipe wall in heel", pw.wall_added, Length64(heel_arm)
                )
            )
        if abs(pw.water_added.value) > 1e-9:
            out.vertical.append(
                VerticalLoad(
                    PW,
                    "water in pipe barrels",
                    pw.water_added,
                    Length64(heel_arm),
                )
            )
    out.vertical.append(
        VerticalLoad(
            EV,
            "soil on heel",
            LineLoad64(max(heel_soil, 0.0)),
            Length64(heel_arm),
        )
    )
    if retained.grade:
        var grade = retained.grade.value().copy()
        var am = grade.area_and_moment(Length64(heel))
        var rise_area = am[0].value
        if rise_area > 0:
            var below = Float64(0)
            if retained.water and retained.water.value().value > h_soil:
                var cap = retained.water.value().value - h_soil
                var dx = heel / Float64(_TERRACE_STRIPS)
                # _TERRACE_STRIPS is a positive constant, so the loop
                # always runs.
                for k in range(_TERRACE_STRIPS):  # pragma: no branch
                    below += (
                        min(grade.height_si((Float64(k) + 0.5) * dx), cap) * dx
                    )
                below = min(max(below, 0.0), rise_area)
            var dry = rise_area - below
            var weight = (
                gamma.value * dry + max(gamma.value - gw.value, 0.0) * below
            )
            out.vertical.append(
                VerticalLoad(
                    EV,
                    "rising grade on heel",
                    LineLoad64(weight),
                    Length64(stem_back + am[1].value / rise_area),
                )
            )
    elif retained.rise.value > 0:
        var credited = retained.rise.value
        if retained.rise_weight:
            credited = min(retained.rise_weight.value().value, credited)
        if credited > 0:
            out.vertical.append(
                VerticalLoad(
                    EV,
                    "rise on heel",
                    LineLoad64(gamma.value * credited * heel),
                    Length64(heel_arm),
                )
            )
    out.vertical.append(
        VerticalLoad(
            LS_V,
            "live load on heel",
            LineLoad64(gamma.value * retained.live_height.value * heel),
            Length64(heel_arm),
        )
    )

    # --- lateral loads on the plane through the heel's end.
    var pressure_height = h_soil
    if retained.grade:
        var tail = (
            retained.grade.value()
            .raised(Length64(h_soil))
            .beyond(Length64(heel))
        )
        var earth = trial_wedge_resultant(
            tail,
            retained.soil.friction,
            gamma,
            gw,
            retained.water,
            0.0,
            retained.pipes,
        )
        out.lateral.append(
            LateralLoad(
                EH, "active earth, trial wedge", earth.wedge.thrust, earth.arm
            )
        )
        pressure_height = tail.plane_height().value
        out.wedge = earth
        out.heel_profile = tail^
    else:
        var yw = Float64(0)
        if retained.water:
            yw = min(max(retained.water.value().value, 0.0), h_soil)
        var g_dry = gamma.value
        var g_sub = gamma.value - gw.value
        var a = h_soil - yw
        var p1 = 0.5 * ka * g_dry * a * a
        var p2a = ka * g_dry * a * yw
        var p2b = 0.5 * ka * g_sub * yw * yw
        var p = p1 + p2a + p2b
        var m = p1 * (yw + a / 3) + p2a * yw / 2 + p2b * yw / 3
        out.lateral.append(
            LateralLoad(
                EH,
                "active earth",
                LineLoad64(p),
                Length64(m / p if p > 0 else 0.0),
            )
        )
        if retained.rise.value > 0:
            out.lateral.append(
                LateralLoad(
                    ES,
                    "rise surcharge",
                    LineLoad64(ka * gamma.value * retained.rise.value * h_soil),
                    Length64(h_soil / 2),
                )
            )
    out.pressure_height = Length64(pressure_height)
    out.lateral.append(
        LateralLoad(
            LS,
            "live-load surcharge",
            LineLoad64(
                ka * gamma.value * retained.live_height.value * pressure_height
            ),
            Length64(pressure_height / 2),
        )
    )
    out.lateral.append(
        LateralLoad(
            LS,
            "top-of-wall load",
            retained.top_load,
            Length64(h + retained.top_load_height.value),
        )
    )
    if retained.water_drop.value > 0:
        var pool = Float64(0)
        if retained.water:
            pool = max(retained.water.value().value, 0.0)
        var net = net_hydrostatic(
            Length64(pool),
            Length64(pool - retained.water_drop.value),
            wall.height,
            gw,
        )
        if net.force.value > 0:
            out.lateral.append(
                LateralLoad(WA, "differential water", net.force, net.arm)
            )
    return out^


@fieldwise_init
struct StemEffects(ImplicitlyCopyable):
    """The moment and shear at the base of the stem."""

    var moment: MomentPerLength64
    var shear: LineLoad64


def stem_effects(
    wall: CantileverWall,
    retained: RetainedSide,
    materials: WallMaterials,
    factors: LoadFactors,
) raises -> StemEffects:
    """Return the factored moment and shear at the base of the stem.

    The stem carries the earth on its own back face, the live-load
    surcharge over its retained height, the net water thrust and the top
    load. Under a broken grade the earth is a trial wedge on the stem's
    back face.

    Args:
        wall: The section.
        retained: The conditions behind it.
        materials: The unit weights of concrete and water.
        factors: The load factors.

    Returns:
        The moment and shear per unit length of wall.

    Raises:
        Error: If the wall or the conditions are not valid.
    """
    wall.check()
    retained.check()
    var gamma = retained.soil.unit_weight
    var gw = materials.water
    var t_ftg = wall.footing.value
    var h_soil = wall.retained_height().value
    var hp = h_soil - t_ftg
    var ka = rankine_active(retained.soil.friction, retained.backslope)
    var yw_stem = Float64(0)
    if retained.water:
        yw_stem = min(max(retained.water.value().value - t_ftg, 0.0), hp)
    var earth_force: Float64
    var earth_moment: Float64
    var rise_force = Float64(0)
    var rise_moment = Float64(0)
    if retained.grade:
        var profile = retained.grade.value().raised(Length64(hp))
        var level = Optional[Length64](None)
        if retained.water:
            level = Length64(retained.water.value().value - t_ftg)
        var pipes = List[BuriedPipe]()
        for p in retained.pipes:
            pipes.append(p.shifted(wall.footing))
        var earth = trial_wedge_resultant(
            profile, retained.soil.friction, gamma, gw, level, 0.0, pipes
        )
        earth_force = earth.wedge.thrust.value
        earth_moment = earth.moment.value
    else:
        var g = gamma.value
        var dry = hp - yw_stem
        var p_dry = 0.5 * ka * g * dry * dry
        var p_rect = ka * g * dry * yw_stem
        var p_sub = 0.5 * ka * max(g - gw.value, 0.0) * yw_stem * yw_stem
        earth_force = p_dry + p_rect + p_sub
        earth_moment = (
            p_dry * (yw_stem + dry / 3)
            + p_rect * yw_stem / 2
            + p_sub * yw_stem / 3
        )
        rise_force = ka * g * retained.rise.value * hp
        rise_moment = rise_force * hp / 2
    var water_force = Float64(0)
    var water_moment = Float64(0)
    if retained.water_drop.value > 0:
        # Soil saturation stops at the retained height, but hydrostatic
        # head does not. Integrate actual levels over the whole stem.
        var back = -t_ftg
        if retained.water:
            back = retained.water.value().value - t_ftg
        var net = net_hydrostatic(
            Length64(back),
            Length64(back - retained.water_drop.value),
            wall.stem_height(),
            gw,
        )
        water_force = net.force.value
        water_moment = net.moment.value
    var live = ka * gamma.value * retained.live_height.value
    var top = retained.top_load.value
    var lever = wall.stem_height().value + retained.top_load_height.value
    var m = (
        factors.of(EH) * earth_moment
        + factors.of(ES) * rise_moment
        + factors.of(LS) * live * hp * hp / 2
        + factors.of(WA) * water_moment
        + factors.of(LS) * top * lever
    )
    var v = (
        factors.of(EH) * earth_force
        + factors.of(ES) * rise_force
        + factors.of(LS) * live * hp
        + factors.of(WA) * water_force
        + factors.of(LS) * top
    )
    return StemEffects(MomentPerLength64(m), LineLoad64(v))
