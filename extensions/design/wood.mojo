# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Sawn lumber members and bolts by the NDS 2018, allowable stress design.

A `Lumber` holds the reference design values of a species and grade at
one size. `southern_pine_no2` gives Southern Pine No. 2 from NDS
Supplement Table 4B, as revised in 2013. The size factor is already in
those values.

- `simple_span_check`: a simply supported member under a uniform load,
  with the stresses, the deflections and the ratio of each to its limit.
  Shear is taken at a distance d from the support (NDS 3.4.3.1).
- `bearing_stress_ratio`: compression perpendicular to grain at a
  support (NDS 3.10).
- `dowel_bearing_strength`: Fe of wood parallel or perpendicular to
  grain, and Hankinson's formula between (NDS 12.3.3).
- `bolt_lateral_value`: the single-shear yield limit equations (NDS
  12.3.1), the reference lateral value Z and the governing mode's value
  of each of the six modes.
- `column_buckling_stress`, `column_stability_factor` and
  `beam_column_ratio`: a member in compression, and in compression and
  bending, by NDS 3.7.1 and equation 3.9-3.
"""

from std.math import cos, pi, sin, sqrt
from extensions.design.quantities import (
    POUND64,
    POUND_FOOT,
    POUND_PER_INCH,
    PSI,
)
from extensions.design.steel import require_positive
from units.si import (
    Angle64,
    Force64,
    INCH64,
    Length64,
    LineLoad64,
    Moment64,
    Pressure64,
    RADIAN,
)


@fieldwise_init
struct Lumber(Copyable, Movable):
    """The reference design values of sawn lumber at one size."""

    var name: String
    # Fb, with the size factor.
    var bending: Pressure64
    # Fv.
    var shear: Pressure64
    # Fc perpendicular to grain.
    var compression_perpendicular: Pressure64
    # Fc parallel to grain, with the size factor.
    var compression_parallel: Pressure64
    # E.
    var modulus: Pressure64
    # Emin.
    var minimum_modulus: Pressure64
    # G, the specific gravity, for dowel bearing.
    var specific_gravity: Float64

    def check(self) raises:
        """Refuse values that cannot be used.

        Raises:
            Error: If a value is not positive and finite, or the specific
                gravity is 1 or more.
        """
        var values: List[Float64] = [
            self.bending.value,
            self.shear.value,
            self.compression_perpendicular.value,
            self.compression_parallel.value,
            self.modulus.value,
            self.minimum_modulus.value,
            self.specific_gravity,
        ]
        # The list holds seven values, so the loop always runs.
        for v in values:  # pragma: no branch
            require_positive(v, "Lumber values must be positive and finite")
        if self.specific_gravity >= 1:
            raise Error("A specific gravity must be less than 1")


def dressed_depth(nominal_depth: Int) raises -> Length64:
    """Return the dressed depth of 2-inch dimension lumber.

    Args:
        nominal_depth: 4, 6, 8, 10 or 12, in inches.

    Returns:
        3-1/2, 5-1/2, 7-1/4, 9-1/4 or 11-1/4 in.

    Raises:
        Error: If the nominal depth is not one of those.
    """
    if nominal_depth == 4:
        return Length64(3.5, INCH64)
    if nominal_depth == 6:
        return Length64(5.5, INCH64)
    if nominal_depth == 8:
        return Length64(7.25, INCH64)
    if nominal_depth == 10:
        return Length64(9.25, INCH64)
    if nominal_depth == 12:
        return Length64(11.25, INCH64)
    raise Error("A nominal depth must be 4, 6, 8, 10 or 12 in")


def southern_pine_no2(nominal_depth: Int) raises -> Lumber:
    """Return Southern Pine No. 2 in a 2-inch thickness.

    The values are those of NDS Supplement Table 4B (2013 revision), in
    which the size factor is included.

    Args:
        nominal_depth: 4, 6, 8, 10 or 12, in inches.

    Returns:
        Fb 1100, 1000, 925, 800 or 750 psi; Fv 175 psi; Fc perp 565 psi;
        Fc 1450, 1250, 1200, 1050 or 975 psi; E 1,400,000 psi; Emin
        510,000 psi; G 0.55.

    Raises:
        Error: If the nominal depth is not one of those.
    """
    _ = dressed_depth(nominal_depth)
    var fb: Float64 = 750
    var fc: Float64 = 975
    if nominal_depth == 4:
        fb = 1100
        fc = 1450
    elif nominal_depth == 6:
        fb = 1000
        fc = 1250
    elif nominal_depth == 8:
        fb = 925
        fc = 1200
    elif nominal_depth == 10:
        fb = 800
        fc = 1050
    return Lumber(
        "Southern Pine No. 2 2x" + String(nominal_depth),
        Pressure64(fb, PSI),
        Pressure64(175, PSI),
        Pressure64(565, PSI),
        Pressure64(fc, PSI),
        Pressure64(1.4e6, PSI),
        Pressure64(510000, PSI),
        0.55,
    )


def joist_line_load(spacing: Length64, pressure: Pressure64) -> LineLoad64:
    """Return the line load on one joist of a floor.

    Args:
        spacing: The joist spacing, center to center.
        pressure: The floor load per area.

    Returns:
        The pressure times the spacing.
    """
    return LineLoad64(pressure.value * spacing.value)


@fieldwise_init
struct SimpleSpanCheck(ImplicitlyCopyable):
    """The stresses and deflections of a simply supported member."""

    var moment: Moment64
    # The shear at d from the support.
    var shear: Force64
    var bending_stress: Pressure64
    var allowable_bending: Pressure64
    var shear_stress: Pressure64
    var allowable_shear: Pressure64
    var live_deflection: Length64
    var total_deflection: Length64
    var bending_ratio: Float64
    var shear_ratio: Float64
    # The live deflection over span / live limit.
    var live_ratio: Float64
    # The total deflection over span / total limit.
    var total_ratio: Float64

    def governing_ratio(self) -> Float64:
        """Return the largest of the four ratios.

        Returns:
            The governing demand to capacity ratio.
        """
        return max(
            self.bending_ratio,
            self.shear_ratio,
            self.live_ratio,
            self.total_ratio,
        )


def simple_span_check(
    lumber: Lumber,
    width: Length64,
    depth: Length64,
    plies: Int,
    span: Length64,
    dead: LineLoad64,
    live: LineLoad64,
    load_duration: Float64,
    repetitive: Bool,
    live_limit: Float64,
    total_limit: Float64,
) raises -> SimpleSpanCheck:
    """Check a simply supported sawn member under a uniform load.

    The allowable bending stress is Fb CD Cr, with Cr = 1.15 for a
    repetitive member, and CL = 1 for a compression edge held by
    sheathing. The allowable shear stress is Fv CD. Deflection uses E.

    Args:
        lumber: The reference values.
        width: The dressed width of one ply.
        depth: The dressed depth.
        plies: The number of plies side by side, 1 or more.
        span: The design span.
        dead: The dead load per length on the member.
        live: The live load per length on the member.
        load_duration: CD, from 0.9 for permanent load to 1.6 for wind.
        repetitive: True for three or more members at 24 in. or less
            that share the load, such as floor joists.
        live_limit: The span over the allowed live deflection, such as
            360.
        total_limit: The span over the allowed total deflection, such as
            240.

    Returns:
        The stresses, the deflections and the ratios.

    Raises:
        Error: If the lumber is not valid, a size, the span, CD or a
            limit is not positive, a load is negative, or there are no
            plies.
    """
    lumber.check()
    var b = width.to(INCH64) * Float64(plies)
    var d = depth.to(INCH64)
    var l = span.to(INCH64)
    require_positive(b, "A member needs a width and plies")
    require_positive(d, "A member depth must be positive")
    require_positive(l, "A span must be positive")
    require_positive(load_duration, "CD must be positive")
    require_positive(live_limit, "A live deflection limit must be positive")
    require_positive(total_limit, "A total deflection limit must be positive")
    var wd = dead.to(POUND_PER_INCH)
    var wl = live.to(POUND_PER_INCH)
    if not (wd >= 0 and wl >= 0 and wd < Float64.MAX and wl < Float64.MAX):
        raise Error("A member's loads must be zero or more and finite")
    var w = wd + wl
    var section = b * d * d / 6
    var inertia = b * d * d * d / 12
    var m = w * l * l / 8
    var v = w * max(l / 2 - d, 0.0)
    var fb = m / section
    var fv = 1.5 * v / (b * d)
    var cr = 1.15 if repetitive else 1.0
    var fb_allow = lumber.bending.to(PSI) * load_duration * cr
    var fv_allow = lumber.shear.to(PSI) * load_duration
    var e = lumber.modulus.to(PSI)
    var defl_live = 5 * wl * l**4 / (384 * e * inertia)
    var defl_total = 5 * w * l**4 / (384 * e * inertia)
    return SimpleSpanCheck(
        Moment64(m / 12, POUND_FOOT),
        Force64(v, POUND64),
        Pressure64(fb, PSI),
        Pressure64(fb_allow, PSI),
        Pressure64(fv, PSI),
        Pressure64(fv_allow, PSI),
        Length64(defl_live, INCH64),
        Length64(defl_total, INCH64),
        fb / fb_allow,
        fv / fv_allow,
        defl_live / (l / live_limit),
        defl_total / (l / total_limit),
    )


def bearing_stress_ratio(
    lumber: Lumber,
    reaction: Force64,
    width: Length64,
    bearing_length: Length64,
) raises -> Float64:
    """Return the bearing stress at a support over Fc perpendicular.

    The bearing area factor Cb is 1, as at the end of a member.

    Args:
        lumber: The reference values.
        reaction: The support reaction.
        width: The width that bears.
        bearing_length: The length of bearing along the member.

    Returns:
        R / (b lb Fc perp).

    Raises:
        Error: If the lumber is not valid, a size is not positive, or the
            reaction is negative.
    """
    lumber.check()
    var b = width.to(INCH64)
    var lb = bearing_length.to(INCH64)
    require_positive(b, "A bearing width must be positive")
    require_positive(lb, "A bearing length must be positive")
    var r = reaction.to(POUND64)
    if not (r >= 0 and r < Float64.MAX):
        raise Error("A reaction must be zero or more and finite")
    return r / (b * lb * lumber.compression_perpendicular.to(PSI))


def dowel_bearing_strength(
    specific_gravity: Float64, diameter: Length64, grain_angle: Angle64
) raises -> Pressure64:
    """Return the dowel bearing strength of wood, NDS 12.3.3.

    Args:
        specific_gravity: G, from 0 to 1.
        diameter: The fastener diameter, 1/4 in. or more.
        grain_angle: The angle between the load and the grain, 0 to 90
            degrees.

    Returns:
        11200 G psi along the grain, 6100 G^1.45 / sqrt(D) psi across
        it, and Hankinson's formula between.

    Raises:
        Error: If G is not between 0 and 1, D is under 1/4 in., or the
            angle is outside 0 to 90 degrees.
    """
    if not (specific_gravity > 0 and specific_gravity < 1):
        raise Error("A specific gravity must be between 0 and 1")
    var d = diameter.to(INCH64)
    if not (d >= 0.25 and d < Float64.MAX):
        raise Error("A dowel bearing diameter must be 1/4 in. or more")
    var theta = grain_angle.to(RADIAN)
    if not (theta >= 0 and theta <= pi / 2 + 1e-12):
        raise Error("A grain angle must be from 0 to 90 degrees")
    var along = 11200 * specific_gravity
    var across = 6100 * specific_gravity**1.45 / sqrt(d)
    var s = sin(theta)
    var c = cos(theta)
    return Pressure64(along * across / (along * s * s + across * c * c), PSI)


@fieldwise_init
struct BoltValue(ImplicitlyCopyable):
    """The yield limit values of a single-shear bolt, NDS 12.3.1.

    `lateral` is Z, the least of the six modes.
    """

    var lateral: Force64
    var mode_im: Force64
    var mode_is: Force64
    var mode_ii: Force64
    var mode_iiim: Force64
    var mode_iiis: Force64
    var mode_iv: Force64


def bolt_lateral_value(
    diameter: Length64,
    main_length: Length64,
    side_thickness: Length64,
    main_bearing: Pressure64,
    side_bearing: Pressure64,
    bolt_yield: Pressure64,
    grain_angle: Angle64,
) raises -> BoltValue:
    """Return the reference lateral value of a bolt in single shear.

    The reduction term Rd is that of NDS Table 12.3.1B for a diameter of
    1/4 in. or more, with K theta = 1 + 0.25 (theta / 90).

    Args:
        diameter: D.
        main_length: `lm`, the bearing length in the main member. For a
            sill on concrete, the embedment.
        side_thickness: `ls`, the side member thickness.
        main_bearing: Fem. NDS Table 12E uses 7,500 psi for concrete.
        side_bearing: Fes, from `dowel_bearing_strength` for wood.
        bolt_yield: Fyb, 45,000 psi for an A307 bolt.
        grain_angle: The largest angle of the load to the grain of a
            member, 0 to 90 degrees.

    Returns:
        Z and the value of each mode.

    Raises:
        Error: If D is under 1/4 in., a length or strength is not
            positive, or the angle is outside 0 to 90 degrees.
    """
    var d = diameter.to(INCH64)
    var lm = main_length.to(INCH64)
    var ls = side_thickness.to(INCH64)
    var fem = main_bearing.to(PSI)
    var fes = side_bearing.to(PSI)
    var fyb = bolt_yield.to(PSI)
    if not (d >= 0.25 and d < Float64.MAX):
        raise Error("A bolt diameter must be 1/4 in. or more")
    require_positive(lm, "A main member length must be positive")
    require_positive(ls, "A side member thickness must be positive")
    require_positive(fem, "A main bearing strength must be positive")
    require_positive(fes, "A side bearing strength must be positive")
    require_positive(fyb, "A bolt yield strength must be positive")
    var theta = grain_angle.to(RADIAN)
    if not (theta >= 0 and theta <= pi / 2 + 1e-12):
        raise Error("A grain angle must be from 0 to 90 degrees")
    var k_theta = 1 + 0.25 * theta / (pi / 2)
    return _yield_limit(
        d, lm, ls, fem, fes, fyb, 4 * k_theta, 3.6 * k_theta, 3.2 * k_theta
    )


def nail_lateral_value(
    diameter: Length64,
    penetration: Length64,
    side_thickness: Length64,
    main_gravity: Float64,
    side_gravity: Float64,
    nail_yield: Pressure64,
) raises -> BoltValue:
    """Return the reference lateral value of a nail in single shear.

    NDS 12.3.1 with Rd = 2.2 in every mode (Table 12.3.1B, D of 0.17 in.
    or less), and Fe = 16,600 G^1.84 psi for each member (Table 12.3.3,
    D under 1/4 in.), so the value holds at any angle to the grain.

    Args:
        diameter: D, more than 0 and 0.17 in. or less.
        penetration: `lm`, the nail's length in the main member.
        side_thickness: `ls`, the side member thickness.
        main_gravity: G of the main member, from 0 to 1.
        side_gravity: G of the side member, from 0 to 1. NDS Table
            12.3.3B gives 0.50 for OSB.
        nail_yield: Fyb, 90,000 psi for a 10d common nail.

    Returns:
        Z and the value of each mode.

    Raises:
        Error: If D is outside the range, a G is not between 0 and 1, or
            a length or strength is not positive.
    """
    var d = diameter.to(INCH64)
    if not (d > 0 and d <= 0.17):
        raise Error("A nail diameter must be over 0 and 0.17 in. or less")
    for g in [main_gravity, side_gravity]:
        if not (g > 0 and g < 1):
            raise Error("A specific gravity must be between 0 and 1")
    var lm = penetration.to(INCH64)
    var ls = side_thickness.to(INCH64)
    var fyb = nail_yield.to(PSI)
    require_positive(lm, "A main member length must be positive")
    require_positive(ls, "A side member thickness must be positive")
    require_positive(fyb, "A nail yield strength must be positive")
    return _yield_limit(
        d,
        lm,
        ls,
        16600 * main_gravity**1.84,
        16600 * side_gravity**1.84,
        fyb,
        2.2,
        2.2,
        2.2,
    )


def _yield_limit(
    d: Float64,
    lm: Float64,
    ls: Float64,
    fem: Float64,
    fes: Float64,
    fyb: Float64,
    rd_one: Float64,
    rd_two: Float64,
    rd_three: Float64,
) -> BoltValue:
    # The six yield limit equations of NDS 12.3.1, in inches, psi and lb.
    var re = fem / fes
    var rt = lm / ls
    var z_im = d * lm * fem / rd_one
    var z_is = d * ls * fes / rd_one
    var k1 = (
        sqrt(re + 2 * re * re * (1 + rt + rt * rt) + rt * rt * re**3)
        - re * (1 + rt)
    ) / (1 + re)
    var z_ii = k1 * d * ls * fes / rd_two
    var k2 = -1 + sqrt(
        2 * (1 + re) + 2 * fyb * (1 + 2 * re) * d * d / (3 * fem * lm * lm)
    )
    var z_iiim = k2 * d * lm * fem / ((1 + 2 * re) * rd_three)
    var k3 = -1 + sqrt(
        2 * (1 + re) / re + 2 * fyb * (2 + re) * d * d / (3 * fem * ls * ls)
    )
    var z_iiis = k3 * d * ls * fem / ((2 + re) * rd_three)
    var z_iv = d * d / rd_three * sqrt(2 * fem * fyb / (3 * (1 + re)))
    var z = min(z_im, z_is, z_ii, z_iiim, z_iiis, z_iv)
    return BoltValue(
        Force64(z, POUND64),
        Force64(z_im, POUND64),
        Force64(z_is, POUND64),
        Force64(z_ii, POUND64),
        Force64(z_iiim, POUND64),
        Force64(z_iiis, POUND64),
        Force64(z_iv, POUND64),
    )


# The column factor c of NDS 3.7.1 for sawn lumber.
comptime SAWN_COLUMN_C = 0.8


def column_buckling_stress(
    minimum_modulus: Pressure64, slenderness: Float64
) raises -> Pressure64:
    """Return the critical buckling stress FcE of NDS 3.7.1.

    Args:
        minimum_modulus: E'min, the adjusted modulus for stability.
        slenderness: `le / d` about the axis of buckling, more than 0 and
            50 or less (NDS 3.7.1.4).

    Returns:
        0.822 E'min / (le / d)^2.

    Raises:
        Error: If the modulus is not positive or the slenderness is
            outside its range.
    """
    var e = minimum_modulus.to(PSI)
    require_positive(e, "A minimum modulus must be positive")
    if not (slenderness > 0 and slenderness <= 50):
        raise Error("A column slenderness le/d must be over 0 and 50 or less")
    return Pressure64(0.822 * e / (slenderness * slenderness), PSI)


def column_stability_factor(
    compression_star: Pressure64, buckling_stress: Pressure64, c: Float64
) raises -> Float64:
    """Return the column stability factor Cp of NDS equation 3.7-1.

    Args:
        compression_star: Fc*, the compression design value parallel to
            grain times all its factors except Cp.
        buckling_stress: FcE, from `column_buckling_stress`.
        c: 0.8 for sawn lumber (`SAWN_COLUMN_C`), between 0 and 1.

    Returns:
        Cp, more than 0 and 1 or less.

    Raises:
        Error: If a stress is not positive or c is not between 0 and 1.
    """
    var fc = compression_star.to(PSI)
    var fce = buckling_stress.to(PSI)
    require_positive(fc, "Fc* must be positive")
    require_positive(fce, "A buckling stress must be positive")
    if not (c > 0 and c < 1):
        raise Error("A column factor c must be between 0 and 1")
    var r = fce / fc
    var half = (1 + r) / (2 * c)
    return half - sqrt(half * half - r / c)


def beam_column_ratio(
    axial_stress: Pressure64,
    allowable_axial: Pressure64,
    bending_stress: Pressure64,
    allowable_bending: Pressure64,
    buckling_stress: Pressure64,
) raises -> Float64:
    """Return the interaction ratio of NDS equation 3.9-3, one bending axis.

    Args:
        axial_stress: `fc`, the compression stress.
        allowable_axial: F'c, with Cp.
        bending_stress: `fb1`, about the strong axis.
        allowable_bending: F'b1.
        buckling_stress: FcE1, buckling in the plane of bending.

    Returns:
        (fc / F'c)^2 + fb1 / (F'b1 (1 - fc / FcE1)). The member is
        adequate at 1 or less.

    Raises:
        Error: If a stress is negative, an allowable stress is not
            positive, or fc is not less than FcE1.
    """
    var fc = axial_stress.to(PSI)
    var fb = bending_stress.to(PSI)
    var fca = allowable_axial.to(PSI)
    var fba = allowable_bending.to(PSI)
    var fce = buckling_stress.to(PSI)
    if not (fc >= 0 and fb >= 0 and fc < Float64.MAX and fb < Float64.MAX):
        raise Error("A member stress must be zero or more and finite")
    require_positive(fca, "An allowable axial stress must be positive")
    require_positive(fba, "An allowable bending stress must be positive")
    if not (fc < fce and fce < Float64.MAX):
        raise Error("The axial stress must be less than FcE1 (NDS 3.9.2)")
    return (fc / fca) ** 2 + fb / (fba * (1 - fc / fce))
