# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wind on the donjon, by EN 1991-1-4, and what it does to the base of the
tower.

The donjon is a hollow round shaft of brick, so the rules for a circular
cylinder apply. Every rule here is from EN 1991-1-4:2005+A1:2010 (the clause
is named at each function), with the one number that the standard leaves to
the country, the fundamental basic wind velocity, taken from the National
Annex of Belgium as a bound.

- **Peak velocity pressure**, 4.3 to 4.5: the roughness factor
  `kr ln(z / z0)`, the turbulence intensity `kI / ln(z / z0)`, and
  `qp = (1 + 7 Iv) (rho / 2) vm^2`.
- **Force coefficient of a cylinder**, 7.9.2, Figure 7.28: `cf0` from the
  Reynolds number and the roughness of the surface, which is 3 mm for
  brickwork (Table 7.13). The effective slenderness is from Table 7.16 and
  the end-effect factor from Figure 7.36.
- **Structural factor**, 6.3.1 and Annex B, from the natural frequency, with
  the logarithmic decrement of damping from Annex F. Clause 6.2(1)d allows 1
  for a round chimney lower than 60 m and 6.5 diameters.
- **Vortex shedding**, Annex E: it need not be checked when the critical wind
  velocity `b n1 / St` is over 1.25 times the mean wind velocity, or when the
  shaft is shorter than 6 diameters.

The natural frequency has three sources, and the module computes them all.
F.3 gives an empirical formula for chimneys. A cantilever beam gives the
Euler-Bernoulli result. The finite element model of `extensions.structure`
gives the third, and it must agree with the beam.

The standard gives a force for the wind. The base of the tower resists it
with its weight. `base_check` finds the stresses in the annulus of the base
and compares them with the strength of the masonry of `masonry`.
"""

from std.math import exp, isfinite, log, log10, pi, sqrt
from extensions.building.kinds import CIRCLE
from extensions.building.material import brick
from extensions.building.model import Section
from extensions.castle.masonry import Masonry, historic_brick
from extensions.castle.plan import CastlePlan
from extensions.structure.ids import NodeId
from extensions.structure.modal import solve_modes
from extensions.structure.model import StructuralModel
from generators.utils import Vec3d
from units.si import (
    Area64,
    Density64,
    Force64,
    Frequency64,
    KILOGRAM_PER_CUBIC_METER,
    Length64,
    METER,
    METER_PER_SECOND,
    Moment64,
    PASCAL,
    PER_SECOND,
    Pressure64,
    SecondMomentOfArea64,
    Velocity64,
)

# Standard gravity, in meters per second squared.
comptime _GRAVITY = 9.80665
# The kinematic viscosity of air, in square meters per second: 15e-6, as in
# the worked examples of EN 1991-1-4 for the Reynolds number of 7.9.
comptime _VISCOSITY = 1.5e-5
# The strips that the height of a shaft is cut into to sum the wind.
comptime _STRIPS = 60
# The equivalent roughness of brickwork, in meters: Table 7.13.
comptime BRICKWORK_ROUGHNESS = 0.003
# The thickness of the wall of the donjon. No survey gives it, so it is an
# assumption of the same kind as the thickness of the quay wall.
comptime DONJON_WALL_THICKNESS = 1.2
# The fundamental basic wind velocity of the Belgian zones runs from 23 to
# 26 m/s. The zone of Torhout is not known from the text, so the highest value
# bounds it.
comptime BELGIAN_BASIC_VELOCITY = 26.0


@fieldwise_init
struct WindSite(ImplicitlyCopyable):
    """The wind climate and the roughness of the ground upwind of a site."""

    # The basic wind velocity vb: the 10 minute mean over open country at 10
    # m, with a 2 percent annual chance of exceedance (4.2).
    var basic_velocity: Velocity64
    # The roughness length z0 and the minimum height zmin of the terrain
    # category (Table 4.1).
    var roughness_length: Length64
    var minimum_height: Length64
    # The density of the air, 1.25 kg/m^3 (4.5, note 2).
    var air_density: Density64
    # The turbulence factor kI, 1.0 (4.4, note 2).
    var turbulence_factor: Float64

    def check(self) raises:
        """Refuse a site that no wind can blow on.

        Raises:
            Error: If the velocity, the lengths, the density or the factor
                is not positive and finite, or the minimum height is not
                over the roughness length.
        """
        var values = [
            self.basic_velocity.value,
            self.roughness_length.value,
            self.minimum_height.value,
            self.air_density.value,
            self.turbulence_factor,
        ]
        for at in range(len(values)):
            if not (isfinite(values[at]) and values[at] > 0.0):
                raise Error(
                    "A wind site needs a positive finite velocity, roughness"
                    " length, minimum height, air density and turbulence"
                    " factor"
                )
        if not (self.minimum_height.value > self.roughness_length.value):
            raise Error("The minimum height must be over the roughness length")

    def _height(self, z: Length64) raises -> Float64:
        """Return the height that the profile reads: the minimum height for
        anything lower."""
        if not (isfinite(z.value) and z.value >= 0.0):
            raise Error("A height must be zero or more and finite")
        return max(z.value, self.minimum_height.value)

    def roughness_factor(self, z: Length64) raises -> Float64:
        """Return the roughness factor cr(z), from 4.3.2 (4.4) and (4.5).

        Args:
            z: The height over the ground.

        Returns:
            The factor kr ln(z / z0), with z no lower than zmin and kr from the
            roughness length.

        Raises:
            Error: If the site is invalid or the height is not finite and
                zero or more.
        """
        self.check()
        var kr = 0.19 * (self.roughness_length.value / 0.05) ** 0.07
        return kr * log(self._height(z) / self.roughness_length.value)

    def mean_velocity(self, z: Length64) raises -> Velocity64:
        """Return the mean wind velocity vm(z), 4.3.1 (4.3), over flat ground.

        Args:
            z: The height over the ground.

        Returns:
            The velocity cr(z) vb.

        Raises:
            Error: If the site is invalid or the height is not valid.
        """
        return Velocity64(
            self.roughness_factor(z) * self.basic_velocity.value,
            METER_PER_SECOND,
        )

    def turbulence_intensity(self, z: Length64) raises -> Float64:
        """Return the turbulence intensity Iv(z), 4.4 (4.7).

        Args:
            z: The height over the ground.

        Returns:
            The intensity kI / ln(z / z0), with z no lower than zmin.

        Raises:
            Error: If the site is invalid or the height is not valid.
        """
        self.check()
        return self.turbulence_factor / log(
            self._height(z) / self.roughness_length.value
        )

    def peak_pressure(self, z: Length64) raises -> Pressure64:
        """Return the peak velocity pressure qp(z), 4.5 (4.8).

        Args:
            z: The height over the ground.

        Returns:
            (1 + 7 Iv(z)) (rho / 2) vm(z)^2.

        Raises:
            Error: If the site is invalid or the height is not valid.
        """
        var velocity = self.mean_velocity(z).value
        var intensity = self.turbulence_intensity(z)
        return Pressure64(
            (1.0 + 7.0 * intensity)
            * 0.5
            * self.air_density.value
            * velocity
            * velocity,
            PASCAL,
        )


def terrain_category_ii(basic_velocity: Velocity64) -> WindSite:
    """Return a site of terrain category II: low vegetation, grass and
    isolated obstacles at 20 obstacle heights or more (Table 4.1).

    Args:
        basic_velocity: The basic wind velocity.

    Returns:
        The site, with z0 of 0.05 m and zmin of 2 m.
    """
    return WindSite(
        basic_velocity,
        Length64(0.05, METER),
        Length64(2.0, METER),
        Density64(1.25, KILOGRAM_PER_CUBIC_METER),
        1.0,
    )


def terrain_category_iii(basic_velocity: Velocity64) -> WindSite:
    """Return a site of terrain category III: regular cover of vegetation,
    villages and permanent forest (Table 4.1).

    Args:
        basic_velocity: The basic wind velocity.

    Returns:
        The site, with z0 of 0.3 m and zmin of 5 m.
    """
    return WindSite(
        basic_velocity,
        Length64(0.3, METER),
        Length64(5.0, METER),
        Density64(1.25, KILOGRAM_PER_CUBIC_METER),
        1.0,
    )


def wijnendale_wind_site() -> WindSite:
    """Return the wind site of the castle: category II and the highest basic
    wind velocity of the Belgian National Annex.

    The domain is a forest and open fields, so its terrain lies between
    categories II and III. Category II gives the larger pressure at 30 m, so it
    is the safe choice.

    Returns:
        The site.
    """
    return terrain_category_ii(
        Velocity64(BELGIAN_BASIC_VELOCITY, METER_PER_SECOND)
    )


def reynolds_number(diameter: Length64, velocity: Velocity64) raises -> Float64:
    """Return the Reynolds number of a cylinder in the wind, 7.9.2 (7.15).

    Args:
        diameter: The diameter of the cylinder.
        velocity: The wind velocity at the top of the cylinder.

    Returns:
        The number b v / nu, with a kinematic viscosity of 15e-6 m^2/s.

    Raises:
        Error: If the diameter or the velocity is not positive and finite.
    """
    if not (
        isfinite(diameter.value)
        and diameter.value > 0.0
        and isfinite(velocity.value)
        and velocity.value > 0.0
    ):
        raise Error("A diameter and a velocity must be positive and finite")
    return diameter.value * velocity.value / _VISCOSITY


def cylinder_force_coefficient(
    reynolds: Float64, roughness: Length64, diameter: Length64
) raises -> Float64:
    """Return the force coefficient cf,0 of a cylinder with no free end flow,
    7.9.2, Figure 7.28.

    Below a Reynolds number of about 1.8e5 it is 1.2. It then falls along
    `0.11 / (Re / 1e6)^1.4` to a floor of 0.4, which a rough surface lifts at
    once to `1.2 + 0.18 log10(10 k / b) / (1 + 0.4 log10(Re / 1e6))`. The
    figure is drawn for k/b from 1e-5 to 1e-2, so the ratio is held inside
    that range.

    Args:
        reynolds: The Reynolds number.
        roughness: The equivalent roughness k of the surface (Table 7.13).
        diameter: The diameter b.

    Returns:
        The coefficient cf,0.

    Raises:
        Error: If an input is not positive and finite.
    """
    if not (
        isfinite(reynolds)
        and reynolds > 0.0
        and isfinite(roughness.value)
        and roughness.value > 0.0
        and isfinite(diameter.value)
        and diameter.value > 0.0
    ):
        raise Error(
            "A Reynolds number, a roughness and a diameter must be positive"
            " and finite"
        )
    var scaled = reynolds / 1.0e6
    var plateau_ends = (0.11 / 1.2) ** (1.0 / 1.4)
    if scaled <= plateau_ends:
        return 1.2
    var ratio = min(max(roughness.value / diameter.value, 1.0e-5), 1.0e-2)
    var falling = max(0.11 / scaled**1.4, 0.4)
    var rough = 1.2 + 0.18 * log10(10.0 * ratio) / (1.0 + 0.4 * log10(scaled))
    return max(falling, rough)


def effective_slenderness(
    length: Length64, diameter: Length64
) raises -> Float64:
    """Return the effective slenderness of a free-standing circular
    cylinder, Table 7.16.

    For a length of 50 m or more it is `0.7 l / b`, and for under 15 m it is
    `l / b`, each at most 70. Between them the two values at 15 m and 50 m
    are interpolated.

    Args:
        length: The length l of the cylinder.
        diameter: The diameter b.

    Returns:
        The slenderness lambda.

    Raises:
        Error: If the length or the diameter is not positive and finite.
    """
    if not (
        isfinite(length.value)
        and length.value > 0.0
        and isfinite(diameter.value)
        and diameter.value > 0.0
    ):
        raise Error("A length and a diameter must be positive and finite")
    var b = diameter.value
    var l = length.value
    if l >= 50.0:
        return min(0.7 * l / b, 70.0)
    var short = min(min(l, 15.0) / b, 70.0)
    if l < 15.0:
        return short
    var long = min(0.7 * 50.0 / b, 70.0)
    return short + (long - short) * (l - 15.0) / 35.0


def end_effect_factor(slenderness: Float64) raises -> Float64:
    """Return the end-effect factor of a solid body, 7.13, Figure 7.36 for a
    solidity ratio of 1.

    The curve is read from the figure: 0.6 at a slenderness of 1, 0.70 at 10,
    0.92 at 70 and 1.0 at 200, straight between them on a log scale. The
    reading is good to about 0.02. A worked example of the standard reads
    0.6 at a slenderness of 1 and 0.65 at 2.4, which agrees.

    Args:
        slenderness: The effective slenderness lambda.

    Returns:
        The factor psi_lambda.

    Raises:
        Error: If the slenderness is not positive and finite.
    """
    if not (isfinite(slenderness) and slenderness > 0.0):
        raise Error("A slenderness must be positive and finite")
    if slenderness <= 1.0:
        return 0.6
    if slenderness >= 200.0:
        return 1.0
    var x = log10(slenderness)
    if slenderness <= 10.0:
        return 0.6 + 0.1 * x
    if slenderness <= 70.0:
        return 0.7 + (0.92 - 0.7) * (x - 1.0) / (log10(70.0) - 1.0)
    return 0.92 + (1.0 - 0.92) * (x - log10(70.0)) / (
        log10(200.0) - log10(70.0)
    )


@fieldwise_init
struct Shaft(Copyable, Movable):
    """A hollow round tower of masonry, fixed at its foundation."""

    # The outer diameter b and the thickness of the wall.
    var outer_diameter: Length64
    var wall_thickness: Length64
    # The height from the foundation to the top of the parapet.
    var height: Length64
    # How far the foundation lies below the ground round the tower.
    var base_below_ground: Length64
    # The masonry.
    var masonry: Masonry
    # The equivalent roughness of the wall: 3 mm for brickwork.
    var roughness: Length64
    # A dead load on the top, such as a roof or a spire, in newtons.
    var top_load: Force64

    def check(self) raises:
        """Refuse a shaft that cannot stand.

        Raises:
            Error: If a length is not positive and finite, the wall is
                thicker than the radius, the foundation is deeper than the
                height, the roughness is not positive, or the load is
                negative or not finite.
        """
        var lengths = [
            self.outer_diameter.value,
            self.wall_thickness.value,
            self.height.value,
            self.roughness.value,
        ]
        for at in range(len(lengths)):
            if not (isfinite(lengths[at]) and lengths[at] > 0.0):
                raise Error("A shaft needs a positive finite size")
        if not (self.wall_thickness.value < self.outer_diameter.value / 2.0):
            raise Error("The wall of a shaft must be thinner than its radius")
        if not (
            isfinite(self.base_below_ground.value)
            and self.base_below_ground.value >= 0.0
            and self.base_below_ground.value < self.height.value
        ):
            raise Error(
                "The foundation must lie below the ground, but not by more"
                " than the height"
            )
        if not (isfinite(self.top_load.value) and self.top_load.value >= 0.0):
            raise Error("A top load must be zero or more and finite")
        self.masonry.check()

    def inner_diameter(self) -> Length64:
        """Return the diameter of the bore.

        Returns:
            The outer diameter less twice the wall.
        """
        return Length64(
            self.outer_diameter.value - 2.0 * self.wall_thickness.value
        )

    def area(self) -> Area64:
        """Return the area of the ring of masonry.

        Returns:
            The cross-sectional area.
        """
        var outer = self.outer_diameter.value
        var inner = self.inner_diameter().value
        return Area64(pi / 4.0 * (outer * outer - inner * inner))

    def inertia(self) -> SecondMomentOfArea64:
        """Return the second moment of area of the ring.

        Returns:
            The second moment of area about a diameter.
        """
        var outer = self.outer_diameter.value
        var inner = self.inner_diameter().value
        return SecondMomentOfArea64(pi / 64.0 * (outer**4 - inner**4))

    def mass_per_length(self) raises -> Float64:
        """Return the mass of the masonry along one meter of the shaft.

        Returns:
            The mass, in kilograms per meter.

        Raises:
            Error: If the masonry is not valid.
        """
        self.masonry.check()
        return self.masonry.density.value * self.area().value

    def weight(self) raises -> Force64:
        """Return the weight of the shaft and its top load.

        Returns:
            The dead load on the base.

        Raises:
            Error: If the masonry is not valid.
        """
        return Force64(
            self.mass_per_length() * self.height.value * _GRAVITY
            + self.top_load.value
        )

    def core_radius(self) -> Length64:
        """Return the radius of the core of the section: the distance from the
        axis inside which a thrust causes no tension.

        Returns:
            (Do^2 + Di^2) / (8 Do).
        """
        var outer = self.outer_diameter.value
        var inner = self.inner_diameter().value
        return Length64((outer * outer + inner * inner) / (8.0 * outer))


def donjon_shaft(plan: CastlePlan) raises -> Shaft:
    """Return the donjon of a plan as a shaft.

    The wall thickness is an assumption. The other sizes are those of the
    plan.

    Args:
        plan: The plan, whose first tower is the donjon.

    Returns:
        The shaft.

    Raises:
        Error: If the plan has no tower or the shaft is invalid.
    """
    if len(plan.towers) == 0:
        raise Error("A plan needs a tower for a donjon")
    ref donjon = plan.towers[0]
    var shaft = Shaft(
        Length64(2.0 * donjon.radius.value),
        Length64(DONJON_WALL_THICKNESS),
        Length64(donjon.top().value - donjon.base.value),
        Length64(max(plan.ground_level.value - donjon.base.value, 0.0)),
        historic_brick(),
        Length64(BRICKWORK_ROUGHNESS),
        Force64(0.0),
    )
    shaft.check()
    return shaft^


@fieldwise_init
struct StructuralFactor(Copyable, Movable):
    """The structural factor cscd and the numbers that it is made of."""

    # The reference height zs, the turbulence intensity there, and the
    # turbulent length scale L(zs).
    var reference_height: Length64
    var turbulence_intensity: Float64
    var length_scale: Length64
    # The background factor B^2 and the resonance response factor R^2.
    var background: Float64
    var resonance: Float64
    # The peak factor kp and the up-crossing frequency of B.5.
    var peak_factor: Float64
    var up_crossing: Frequency64
    # The logarithmic decrement of damping, structural and aerodynamic.
    var log_decrement: Float64
    # cscd, equation 6.1.
    var value: Float64


def structural_factor(
    site: WindSite,
    height: Length64,
    width: Length64,
    frequency: Frequency64,
    force_coefficient: Float64,
    mass_per_length: Float64,
    structural_decrement: Float64,
) raises -> StructuralFactor:
    """Return the structural factor cscd of a vertical structure by Annex B.

    It follows B.1 (turbulent length scale), B.2 (background factor, peak
    factor, resonance factor), F.5 (damping) and the equation 6.1.

    Args:
        site: The wind site.
        height: The height h of the structure over the ground.
        width: The width b of the structure across the wind.
        frequency: The natural frequency n1 of the fundamental bending mode.
        force_coefficient: The force coefficient cf, for the aerodynamic
            damping.
        mass_per_length: The equivalent mass me of the fundamental mode for
            each meter of height, in kilograms per meter.
        structural_decrement: The logarithmic decrement of structural damping
            (Table F.2).

    Returns:
        The factor and its parts.

    Raises:
        Error: If an input is not positive and finite, or the site is not
            valid.
    """
    site.check()
    var inputs = [
        height.value,
        width.value,
        frequency.value,
        force_coefficient,
        mass_per_length,
        structural_decrement,
    ]
    for at in range(len(inputs)):
        if not (isfinite(inputs[at]) and inputs[at] > 0.0):
            raise Error(
                "A structural factor needs a positive finite height, width,"
                " frequency, force coefficient, mass and damping"
            )
    var h = height.value
    var b = width.value
    var n1 = frequency.value
    # Figure 6.1: for a vertical structure the reference height is 0.6 h.
    var zs = max(0.6 * h, site.minimum_height.value)
    var intensity = site.turbulence_intensity(Length64(zs))
    var vm = site.mean_velocity(Length64(zs)).value
    # B.1: the length scale, with L(z) = L(zmin) below zmin.
    var alpha = 0.67 + 0.05 * log(site.roughness_length.value)
    var scale = 300.0 * (zs / 200.0) ** alpha
    # B.2 (B.3): the background factor.
    var background = 1.0 / (1.0 + 0.9 * ((b + h) / scale) ** 0.63)
    # B.1 (B.2): the spectrum at the natural frequency.
    var f_l = n1 * scale / vm
    var spectrum = 6.8 * f_l / (1.0 + 10.2 * f_l) ** (5.0 / 3.0)
    # B.2 (B.7) and (B.8): the aerodynamic admittance.
    var eta_h = 4.6 * h / scale * f_l
    var eta_b = 4.6 * b / scale * f_l
    var admittance_h = 1.0 - (1.0 - exp(-2.0 * eta_h)) / (2.0 * eta_h)
    admittance_h /= eta_h
    var admittance_b = 1.0 - (1.0 - exp(-2.0 * eta_b)) / (2.0 * eta_b)
    admittance_b /= eta_b
    # F.5 (F.18): the aerodynamic damping.
    var aerodynamic = (
        force_coefficient
        * site.air_density.value
        * b
        * vm
        / (2.0 * n1 * mass_per_length)
    )
    var delta = structural_decrement + aerodynamic
    # B.2 (B.6): the resonance response factor.
    var resonance = (
        pi * pi / (2.0 * delta) * spectrum * admittance_h * admittance_b
    )
    # B.2 (B.5) and (B.4): the up-crossing frequency and the peak factor.
    var up_crossing = max(n1 * sqrt(resonance / (background + resonance)), 0.08)
    var root = sqrt(2.0 * log(up_crossing * 600.0))
    var peak = max(root + 0.6 / root, 3.0)
    var value = (
        1.0 + 2.0 * peak * intensity * sqrt(background + resonance)
    ) / (1.0 + 7.0 * intensity)
    return StructuralFactor(
        Length64(zs),
        intensity,
        Length64(scale),
        background,
        resonance,
        peak,
        Frequency64(up_crossing, PER_SECOND),
        delta,
        value,
    )


def shaft_frequency_en(shaft: Shaft) raises -> Frequency64:
    """Return the fundamental frequency of a masonry chimney by F.2 (F.3).

    The formula is `700 b / h^2` for a shaft of one diameter from the
    ground to its top, where all of the weight carries the stiffness.

    Args:
        shaft: The shaft.

    Returns:
        The frequency.

    Raises:
        Error: If the shaft is not valid.
    """
    shaft.check()
    var h = shaft.height.value
    return Frequency64(700.0 * shaft.outer_diameter.value / (h * h), PER_SECOND)


def shaft_frequency_beam(shaft: Shaft) raises -> Frequency64:
    """Return the fundamental frequency of the shaft as an Euler-Bernoulli
    cantilever.

    The frequency is `1.8751^2 / (2 pi) sqrt(E I / (m L^4))`, with E of the
    masonry as `1000 f_k`.

    Args:
        shaft: The shaft.

    Returns:
        The frequency.

    Raises:
        Error: If the shaft is not valid.
    """
    shaft.check()
    var modulus = shaft.masonry.elastic_modulus().value
    var stiffness = modulus * shaft.inertia().value
    var length = shaft.height.value
    return Frequency64(
        1.8751**2
        / (2.0 * pi)
        * sqrt(stiffness / (shaft.mass_per_length() * length**4)),
        PER_SECOND,
    )


def shaft_frequency_fe(shaft: Shaft, elements: Int = 12) raises -> Frequency64:
    """Return the fundamental frequency of the shaft from the finite element
    model of `extensions.structure`.

    The model is a cantilever of frame members. The model's section is a solid
    circle, so the ring is stood in for by a solid circle of the same second
    moment of area, with a density that gives the same mass per meter.

    Args:
        shaft: The shaft.
        elements: The number of members, from 2 to 16. The frequency has
            converged to 5 digits by 8 members. With 20 or more members the
            solver of the model finds the stiffness matrix singular.

    Returns:
        The lowest natural frequency.

    Raises:
        Error: If the shaft is not valid or the number of members is not
            from 2 to 16.
    """
    shaft.check()
    if elements < 2 or elements > 16:
        raise Error("A cantilever model needs from 2 to 16 members")
    var equivalent = (64.0 * shaft.inertia().value / pi) ** 0.25
    var solid_area = pi * equivalent * equivalent / 4.0
    var material = brick()
    material.density = Density64(
        shaft.mass_per_length() / solid_area, KILOGRAM_PER_CUBIC_METER
    )
    material.elastic_modulus = shaft.masonry.elastic_modulus()
    var section = Section(
        CIRCLE,
        Length64(equivalent),
        Length64(equivalent),
        Length64(0.0),
        Length64(0.0),
    )
    var model = StructuralModel()
    for at in range(elements + 1):
        _ = model.add_node(
            Vec3d(
                0.0, 0.0, shaft.height.value * Float64(at) / Float64(elements)
            )
        )
    model.fix(NodeId(0))
    for at in range(elements):
        _ = model.add_member(
            NodeId(at), NodeId(at + 1), section, material, Vec3d(1.0, 0.0, 0.0)
        )
    var modes = solve_modes(model, 1)
    return modes.frequencies[0]


@fieldwise_init
struct TowerWind(Copyable, Movable):
    """The wind on a shaft: the coefficients and the force at its base."""

    # The peak velocity pressure at the top, and the Reynolds number there.
    var peak_pressure: Pressure64
    var reynolds: Float64
    # The force coefficient without end effects, the slenderness, the
    # end-effect factor and the force coefficient.
    var cf0: Float64
    var slenderness: Float64
    var end_effect: Float64
    var cf: Float64
    # The detailed structural factor, and the factor used: at least 1.
    var structural: StructuralFactor
    var cscd: Float64
    # The natural frequency that the dynamic factor used.
    var frequency: Frequency64
    # The critical velocity of vortex shedding, and whether Annex E asks for
    # the effect to be investigated.
    var critical_velocity: Velocity64
    var vortex_check_needed: Bool
    # The shear and the moment at the foundation, summed over the height with
    # the pressure of each height.
    var base_shear: Force64
    var base_moment: Moment64
    # The shear of the simple rule, cscd cf qp(ze) b h.
    var simple_force: Force64


def tower_wind(
    site: WindSite, shaft: Shaft, frequency: Frequency64
) raises -> TowerWind:
    """Return the wind action on a shaft by EN 1991-1-4.

    The force at each height is `cscd cf qp(z) b dz`. The coefficients are
    those of the top, where the Reynolds number is highest and `ze` of 7.9.2
    (6) lies.

    Args:
        site: The wind site.
        shaft: The shaft.
        frequency: The natural frequency of its fundamental mode.

    Returns:
        The coefficients and the shear and the moment at the foundation.

    Raises:
        Error: If the site, the shaft or the frequency is not valid.
    """
    site.check()
    shaft.check()
    if not (isfinite(frequency.value) and frequency.value > 0.0):
        raise Error("A natural frequency must be positive and finite")
    var b = shaft.outer_diameter.value
    var below = shaft.base_below_ground.value
    var ze = shaft.height.value - below
    var top = site.peak_pressure(Length64(ze))
    var speed = sqrt(2.0 * top.value / site.air_density.value)
    var reynolds = reynolds_number(
        shaft.outer_diameter, Velocity64(speed, METER_PER_SECOND)
    )
    var cf0 = cylinder_force_coefficient(
        reynolds, shaft.roughness, shaft.outer_diameter
    )
    var slenderness = effective_slenderness(Length64(ze), shaft.outer_diameter)
    var end_effect = end_effect_factor(slenderness)
    var cf = cf0 * end_effect
    var detailed = structural_factor(
        site,
        Length64(ze),
        shaft.outer_diameter,
        frequency,
        cf,
        shaft.mass_per_length(),
        0.03,
    )
    # Clause 6.2(1)d allows 1, which is safe when the detailed value is lower.
    var cscd = max(detailed.value, 1.0)
    var critical = b * frequency.value / 0.18
    var mean_top = site.mean_velocity(Length64(ze)).value
    var needed = ze / b > 6.0 and critical <= 1.25 * mean_top
    var height = shaft.height.value
    var strip = height / Float64(_STRIPS)
    var shear = Float64(0)
    var moment = Float64(0)
    for at in range(_STRIPS):
        var z = (Float64(at) + 0.5) * strip
        var pressure = site.peak_pressure(Length64(max(z - below, 0.0))).value
        var force = cscd * cf * pressure * b * strip
        shear += force
        moment += force * z
    return TowerWind(
        top,
        reynolds,
        cf0,
        slenderness,
        end_effect,
        cf,
        detailed^,
        cscd,
        frequency,
        Velocity64(critical, METER_PER_SECOND),
        needed,
        Force64(shear),
        Moment64(moment),
        Force64(cscd * cf * top.value * b * height),
    )


@fieldwise_init
struct BaseCheck(Copyable, Movable):
    """The stresses at the base of a shaft under its weight and the wind."""

    # The weight, and the shear and moment of the wind at the design level.
    var weight: Force64
    var shear: Force64
    var moment: Moment64
    # The eccentricity of the thrust of the stabilizing combination, and the
    # radius of the core.
    var eccentricity: Length64
    var core_radius: Length64
    # Whether the thrust stays inside the core: no tension.
    var tension_free: Bool
    # The extreme stresses, compression positive.
    var maximum_stress: Pressure64
    var minimum_stress: Pressure64
    var design_strength: Pressure64
    var compression_utilization: Float64
    # The shear stress, the resistance of the masonry and their ratio.
    var shear_stress: Pressure64
    var shear_resistance: Pressure64
    var shear_utilization: Float64
    # The overturning moment over the moment that the weight resists with
    # about the outer edge: below 1 the tower stands.
    var overturning_utilization: Float64


def base_check(shaft: Shaft, wind: TowerWind) raises -> BaseCheck:
    """Check the base of a shaft against the wind.

    Two combinations of EN 1990 are used, with the wind as the leading
    variable action at 1.5. The combination for compression has the weight at
    1.35. The combination for overturning and shear has it at 0.9, because the
    weight then helps.

    Args:
        shaft: The shaft.
        wind: The wind on it.

    Returns:
        The stresses and their ratios to the strengths.

    Raises:
        Error: If the shaft is not valid.
    """
    shaft.check()
    var weight = shaft.weight().value
    var area = shaft.area().value
    var modulus = shaft.inertia().value / (shaft.outer_diameter.value / 2.0)
    var shear = 1.5 * wind.base_shear.value
    var moment = 1.5 * wind.base_moment.value
    var compression_normal = 1.35 * weight
    var stabilizing_normal = 0.9 * weight
    var maximum = compression_normal / area + moment / modulus
    var minimum = stabilizing_normal / area - moment / modulus
    var eccentricity = moment / stabilizing_normal
    var core = shaft.core_radius().value
    var design = shaft.masonry.design_strength().value
    var shear_stress = 2.0 * shear / area
    var resistance = (
        shaft.masonry.shear_strength(
            Pressure64(stabilizing_normal / area)
        ).value
        / shaft.masonry.partial_factor
    )
    var radius = shaft.outer_diameter.value / 2.0
    return BaseCheck(
        Force64(weight),
        Force64(shear),
        Moment64(moment),
        Length64(eccentricity),
        Length64(core),
        eccentricity <= core,
        Pressure64(maximum),
        Pressure64(minimum),
        Pressure64(design),
        maximum / design,
        Pressure64(shear_stress),
        Pressure64(resistance),
        shear_stress / resistance,
        moment / (stabilizing_normal * radius),
    )
