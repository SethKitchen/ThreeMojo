# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The external stability of a cantilever wall, by AASHTO LRFD.

`check_stability` takes a wall's loads and gives a demand-to-capacity
ratio for each external failure mode. A ratio above one fails.

- **Eccentricity** (Art. 11.6.3.3): under the minimum vertical factors
  the resultant must stay within a fraction of the width from the center,
  B / 4 on soil in the 2010 edition.
- **Sliding** (Art. 10.6.3.4): the factored lateral load against the
  friction on the base, phi_tau V tan(phi_f) for concrete cast on soil.
  The passive resistance of a key counts only where credited.
- **Bearing** (Art. 10.6.3.1.2 and 11.6.3.2): under the maximum vertical
  factors, the vertical load spread uniformly over the effective width
  B' = B - 2e, after Meyerhof. The nominal resistance is the
  bearing-capacity equation with depth and load-inclination factors and
  the groundwater factors Cwq and Cwg. Where a required factored
  resistance is given, the ratio is to it instead.
- **Service pressure**: the larger of the Service I effective-width
  pressure and the peak of the linear pressure, against an allowed
  service pressure where one is given.

A resultant outside the footing has no contact: its ratios are infinite.
"""

from std.math import exp, inf, isfinite, pi, sin, tan
from extensions.geotech.earth_pressure import rankine_passive
from extensions.geotech.kinds import (
    BEARING,
    ContactMode,
    FULL_CONTACT,
    FailureMode,
    HEEL_TRIANGLE,
    OVERTURNING,
    SERVICE_PRESSURE,
    SLIDING,
    TOE_TRIANGLE,
)
from extensions.geotech.loads import (
    Resultant,
    factored,
    service_i,
    strength_i_maximum,
    strength_i_minimum,
)
from extensions.geotech.wall import (
    CantileverWall,
    RetainedSide,
    Soil,
    WallLoads,
)
from extensions.geotech.quantities import UnitWeight64
from units.si import Length64, LineLoad64, Pressure64


@fieldwise_init
struct BasePressure(ImplicitlyCopyable):
    """A linear, tension-free soil pressure under a footing."""

    var mode: ContactMode
    # Where the contact starts and ends, from the toe edge.
    var start: Length64
    var end: Length64
    # The pressures at the start and the end.
    var start_pressure: Pressure64
    var end_pressure: Pressure64

    def at(self, x: Length64) -> Pressure64:
        """Return the pressure at a point of the base.

        Args:
            x: The distance from the toe edge.

        Returns:
            The pressure; zero outside the contact.
        """
        var x0 = self.start.value
        var x1 = self.end.value
        if x.value < x0 or x.value > x1 or x1 <= x0:
            return Pressure64(0)
        var t = (x.value - x0) / (x1 - x0)
        return Pressure64(
            self.start_pressure.value
            + t * (self.end_pressure.value - self.start_pressure.value)
        )

    def peak(self) -> Pressure64:
        """Return the largest pressure.

        Returns:
            The larger end pressure.
        """
        return Pressure64(
            max(self.start_pressure.value, self.end_pressure.value)
        )


def base_pressure(
    vertical: LineLoad64, eccentricity: Length64, width: Length64
) raises -> BasePressure:
    """Return the linear, tension-free pressure under a footing.

    A positive eccentricity moves the resultant toward the toe.

    Args:
        vertical: The vertical load per unit length.
        eccentricity: The resultant's offset from the base's center.
        width: The footing's width.

    Returns:
        A trapezoid if the resultant is in the middle third, else a
        triangle; no contact if it is outside the base.

    Raises:
        Error: If a value is not finite, or the load or width is not positive.
    """
    var v = vertical.value
    var e = eccentricity.value
    var b = width.value
    if not (isfinite(v) and isfinite(b) and isfinite(e) and v > 0 and b > 0):
        raise Error(
            "A base pressure needs finite values and a positive load and width"
        )
    if abs(e) >= b / 2:
        return BasePressure(
            TOE_TRIANGLE if e > 0 else HEEL_TRIANGLE,
            Length64(0),
            Length64(0),
            Pressure64(inf[DType.float64]()),
            Pressure64(0),
        )
    if abs(e) <= b / 6:
        return BasePressure(
            FULL_CONTACT,
            Length64(0),
            width,
            Pressure64(v / b * (1 + 6 * e / b)),
            Pressure64(v / b * (1 - 6 * e / b)),
        )
    var contact = 3 * (b / 2 - abs(e))
    var peak = 2 * v / contact
    if e > 0:
        return BasePressure(
            TOE_TRIANGLE,
            Length64(0),
            Length64(contact),
            Pressure64(peak),
            Pressure64(0),
        )
    return BasePressure(
        HEEL_TRIANGLE,
        Length64(b - contact),
        width,
        Pressure64(0),
        Pressure64(peak),
    )


def bearing_factors(friction: Float64) -> Tuple[Float64, Float64, Float64]:
    """Return the bearing-capacity factors Nc, Nq and N_gamma.

    AASHTO LRFD Eq. 10.6.3.1.2a: Nq = e^(pi tan phi) tan^2(45 + phi / 2),
    Nc = (Nq - 1) / tan phi (5.14 at phi = 0), N_gamma = 2 (Nq + 1) tan phi.

    Args:
        friction: The friction angle, in radians.

    Returns:
        (Nc, Nq, N_gamma).
    """
    var t = tan(pi / 4 + friction / 2)
    var nq = exp(pi * tan(friction)) * t * t
    var nc = (nq - 1) / tan(friction) if friction > 0 else 5.14
    var ng = 2 * (nq + 1) * tan(friction)
    return (nc, nq, ng)


struct StabilitySettings(ImplicitlyCopyable, Writable):
    """Resistance factors and limits for the stability checks."""

    # The eccentricity limit as a fraction of the width: 1/4 on soil.
    var eccentricity_fraction: Float64
    # phi_tau for sliding of cast-in-place concrete on sand: 0.80.
    var sliding_factor: Float64
    # phi_ep for passive resistance: 0.50.
    var passive_factor: Float64
    # phi_b for bearing by the theoretical method: 0.45.
    var bearing_factor: Float64
    # Whether the key's passive resistance counts.
    var credit_passive: Bool
    # The footing's embedment below the ground in front, D_f.
    var embedment: Length64
    # The groundwater factors of Table 10.6.3.1.2a-2.
    var water_factor_q: Float64
    var water_factor_gamma: Float64
    # A factored bearing resistance the site must certify, if any.
    var required_bearing: Optional[Pressure64]
    # An allowed service pressure, if any.
    var allowed_service: Optional[Pressure64]

    def __init__(out self, embedment: Length64):
        """Make the usual settings for a wall on soil.

        Args:
            embedment: The footing's embedment, D_f.
        """
        self.eccentricity_fraction = 0.25
        self.sliding_factor = 0.80
        self.passive_factor = 0.50
        self.bearing_factor = 0.45
        self.credit_passive = False
        self.embedment = embedment
        self.water_factor_q = 1.0
        self.water_factor_gamma = 1.0
        self.required_bearing = None
        self.allowed_service = None

    def check(self) raises:
        """Refuse settings that cannot give meaningful check ratios.

        Raises:
            Error: If a setting is not finite, a factor or embedment is
                negative, or an eccentricity or pressure limit is not positive.
        """
        if not (
            isfinite(self.eccentricity_fraction)
            and self.eccentricity_fraction > 0
        ):
            raise Error("The eccentricity fraction must be finite and positive")
        var nonnegative: List[Float64] = [
            self.sliding_factor,
            self.passive_factor,
            self.bearing_factor,
            self.embedment.value,
            self.water_factor_q,
            self.water_factor_gamma,
        ]
        # Six factors are always present.
        for value in nonnegative:  # pragma: no branch
            if not (isfinite(value) and value >= 0):
                raise Error(
                    "Stability factors and embedment must be finite and"
                    " nonnegative"
                )
        if self.required_bearing:
            var value = self.required_bearing.value().value
            if not (isfinite(value) and value > 0):
                raise Error(
                    "Required bearing pressure must be finite and positive"
                )
        if self.allowed_service:
            var value = self.allowed_service.value().value
            if not (isfinite(value) and value > 0):
                raise Error(
                    "Allowed service pressure must be finite and positive"
                )

    def write_to(self, mut writer: Some[Writer]):
        """Write the settings.

        Args:
            writer: Where to write.
        """
        writer.write(
            "StabilitySettings(e/B ",
            self.eccentricity_fraction,
            ", phi_tau ",
            self.sliding_factor,
            ", phi_b ",
            self.bearing_factor,
            ")",
        )


@fieldwise_init
struct StabilityResult(ImplicitlyCopyable):
    """The external stability checks of a wall section."""

    # Under the minimum vertical factors.
    var minimum: Resultant
    var eccentricity: Length64
    var eccentricity_limit: Length64
    var eccentricity_ratio: Float64
    # Sliding.
    var sliding_resistance: LineLoad64
    var passive: LineLoad64
    var sliding_ratio: Float64
    var sliding_ratio_with_passive: Float64
    # Under the maximum vertical factors.
    var maximum: Resultant
    var bearing_eccentricity: Length64
    var effective_width: Length64
    var bearing_pressure: Pressure64
    var nominal_bearing: Pressure64
    var factored_bearing: Pressure64
    var bearing_ratio: Float64
    var required_bearing_ratio: Float64
    # Service I.
    var service: Resultant
    var service_pressure: Pressure64
    var service_ratio: Float64
    # The pressure distributions.
    var strength_pressure: BasePressure
    var minimum_pressure: BasePressure
    var service_distribution: BasePressure

    def ratio(self, mode: FailureMode) raises -> Float64:
        """Return the demand-to-capacity ratio of an external mode.

        Bearing reads the required resistance where one was given.

        Args:
            mode: SLIDING, OVERTURNING, BEARING or SERVICE_PRESSURE.

        Returns:
            The ratio; above one fails, and zero where no limit was given.

        Raises:
            Error: If the mode is not an external stability mode.
        """
        if mode == SLIDING:
            return self.sliding_ratio
        if mode == OVERTURNING:
            return self.eccentricity_ratio
        if mode == BEARING:
            if self.required_bearing_ratio > 0:
                return self.required_bearing_ratio
            return self.bearing_ratio
        if mode == SERVICE_PRESSURE:
            return self.service_ratio
        raise Error("Not an external stability mode: " + mode.name())


def check_stability(
    wall: CantileverWall,
    retained: RetainedSide,
    loads: WallLoads,
    foundation: Soil,
    water_unit_weight: UnitWeight64,
    settings: StabilitySettings,
) raises -> StabilityResult:
    """Check a wall section's eccentricity, sliding and bearing.

    Args:
        wall: The section.
        retained: The conditions behind it, for the water level.
        loads: Its unfactored loads, from `wall_loads`.
        foundation: The soil under the footing.
        water_unit_weight: The unit weight of water.
        settings: The resistance factors and limits.

    Returns:
        The checks.

    Raises:
        Error: If an input is not valid or a vertical resultant is not
            positive.
    """
    wall.check()
    foundation.check()
    settings.check()
    var b = wall.width.value
    var inf64 = inf[DType.float64]()

    var low = factored(loads.vertical, loads.lateral, strength_i_minimum())
    var e = b / 2 - low.location().value
    var e_limit = settings.eccentricity_fraction * b
    var phi_f = foundation.friction.value
    var friction = settings.sliding_factor * low.vertical.value * tan(phi_f)
    var gamma_p = foundation.unit_weight.value
    if retained.water and retained.water.value().value >= 0:
        gamma_p = max(gamma_p - water_unit_weight.value, 0.0)
    var d = wall.key_depth.value
    var passive = 0.5 * rankine_passive(foundation.friction) * gamma_p * d * d
    var h = low.horizontal.value
    var with_passive = friction + settings.passive_factor * passive
    var resist = (
        with_passive if settings.credit_passive and passive > 0 else friction
    )
    var sliding_ratio = h / resist if resist > 0 else inf64

    var high = factored(loads.vertical, loads.lateral, strength_i_maximum())
    var eb = b / 2 - high.location().value
    var b_eff = b - 2 * abs(eb)
    var q_u = high.vertical.value / b_eff if b_eff > 0 else inf64
    var factors = bearing_factors(phi_f)
    var b_used = max(b_eff, 0.0)
    var depth = settings.embedment.value
    var dq = Float64(1)
    if b_used > 0:
        dq = 1 + 2 * tan(phi_f) * (1 - sin(phi_f)) ** 2 * min(
            depth / b_used, 1.0
        )
    var load_ratio = high.horizontal.value / high.vertical.value
    var iq = max(0.0, 1 - load_ratio) ** 2
    var ig = max(0.0, 1 - load_ratio) ** 3
    var gf = foundation.unit_weight.value
    var q_n = (
        foundation.cohesion.value * factors[0]
        + gf * depth * factors[1] * settings.water_factor_q * dq * iq
        + 0.5 * gf * b_used * factors[2] * settings.water_factor_gamma * ig
    )
    var q_r = settings.bearing_factor * q_n
    var bearing_ratio = q_u / q_r if q_r > 0 else inf64
    var required_ratio = Float64(0)
    if settings.required_bearing:
        required_ratio = q_u / settings.required_bearing.value().value

    var serv = factored(loads.vertical, loads.lateral, service_i())
    var ev = b / 2 - serv.location().value
    var b_serv = b - 2 * abs(ev)
    var serv_dist = base_pressure(serv.vertical, Length64(ev), wall.width)
    var q_serv = inf64
    if b_serv > 0:
        q_serv = max(serv.vertical.value / b_serv, serv_dist.peak().value)
    var service_ratio = Float64(0)
    if settings.allowed_service:
        service_ratio = q_serv / settings.allowed_service.value().value

    return StabilityResult(
        low,
        Length64(e),
        Length64(e_limit),
        abs(e) / e_limit,
        LineLoad64(resist),
        LineLoad64(passive),
        sliding_ratio,
        h / with_passive if with_passive > 0 else inf64,
        high,
        Length64(eb),
        Length64(b_eff),
        Pressure64(q_u),
        Pressure64(q_n),
        Pressure64(q_r),
        bearing_ratio,
        required_ratio,
        serv,
        Pressure64(q_serv),
        service_ratio,
        base_pressure(high.vertical, Length64(eb), wall.width),
        base_pressure(low.vertical, Length64(e), wall.width),
        serv_dist,
    )
