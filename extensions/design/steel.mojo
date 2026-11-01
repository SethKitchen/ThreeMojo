# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Steel beams, columns and bearings by AISC 360-16, allowable strength
design.

A `WideFlange` holds the catalog properties of a rolled W shape that the
checks use. `w_shapes` gives the light W8, W10 and W12 shapes of the AISC
Shapes Database v15.0 that houses and small buildings use, lightest
first in each depth. A `Pipe` is a round column of standard weight.

- `flexural_strength`: chapter F2 (yielding and lateral-torsional
  buckling) and F3 (a noncompact or slender flange), strong axis.
- `shear_strength`: chapter G2.1, with the safety factor that the web
  slenderness picks.
- `web_local_yielding` and `web_crippling`: sections J10.2 and J10.3, at
  a support or under a load.
- `compression_strength`: chapter E3, for a member without slender
  elements.
- `concrete_bearing`: section J8, a plate on concrete.
- `combined_ratio`: section H1.1, axial force and flexure.
- `fillet_weld_strength`: section J2.4, a fillet weld.
- `bolt_shear_strength`: section J3.6, one bolt in shear.
- `base_plate_thickness`: the cantilever plate model of AISC Design
  Guide 1, for a column in compression.

Each function returns the nominal strength. Divide by the safety factor
that the module exports to get the allowable strength.
"""

from std.math import exp, log, pi, sqrt
from extensions.design.quantities import (
    CUBIC_INCH,
    INCH_TO_THE_FOURTH,
    KIP_INCH,
    SQUARE_INCH,
)
from extensions.geotech.quantities import KIP, KSI, PLF
from units.si import (
    Area64,
    Force64,
    INCH64,
    Length64,
    LineLoad64,
    Moment64,
    Pressure64,
    SecondMomentOfArea64,
    Volume64,
)

# The safety factors of ASD.
comptime FLEXURE_SAFETY = 1.67
comptime COMPRESSION_SAFETY = 1.67
# Shear of a stocky rolled web, G2.1(a). Other webs use 1.67.
comptime STOCKY_WEB_SHEAR_SAFETY = 1.50
comptime SHEAR_SAFETY = 1.67
comptime WEB_YIELDING_SAFETY = 1.50
comptime WEB_CRIPPLING_SAFETY = 2.00
comptime CONCRETE_BEARING_SAFETY = 2.31
comptime FILLET_WELD_SAFETY = 2.00
comptime BOLT_SAFETY = 2.00
comptime BASE_PLATE_SAFETY = 1.67
# The modulus of elasticity of steel, 29,000 ksi.
comptime STEEL_MODULUS_KSI = 29000.0


def require_positive(value: Float64, message: String) raises:
    """Raise unless a value is positive and finite.

    Args:
        value: The value.
        message: The error message.

    Raises:
        Error: If the value is not positive and finite.
    """
    if not (value > 0 and value < Float64.MAX):
        raise Error(message)


@fieldwise_init
struct WideFlange(Copyable, Movable):
    """The properties of a rolled W shape that the design checks use."""

    var name: String
    var depth: Length64
    var flange_width: Length64
    var flange_thickness: Length64
    var web_thickness: Length64
    # k_des: from the outer face of a flange to the toe of the fillet.
    var k_design: Length64
    var area: Area64
    var strong_inertia: SecondMomentOfArea64
    var elastic_modulus: Volume64
    var plastic_modulus: Volume64
    var weak_inertia: SecondMomentOfArea64
    var weak_radius: Length64
    # r_ts, the effective radius of gyration of F2-7.
    var effective_radius: Length64
    # h_o, the distance between the flange centroids.
    var flange_distance: Length64
    var torsion_constant: SecondMomentOfArea64
    var weight: LineLoad64

    def check(self) raises:
        """Refuse a shape that cannot be checked.

        Raises:
            Error: If a property is not positive and finite, or the
                fillets do not fit in the depth.
        """
        var values: List[Float64] = [
            self.depth.value,
            self.flange_width.value,
            self.flange_thickness.value,
            self.web_thickness.value,
            self.k_design.value,
            self.area.value,
            self.strong_inertia.value,
            self.elastic_modulus.value,
            self.plastic_modulus.value,
            self.weak_inertia.value,
            self.weak_radius.value,
            self.effective_radius.value,
            self.flange_distance.value,
            self.torsion_constant.value,
            self.weight.value,
        ]
        # The list holds fifteen values, so the loop always runs.
        for v in values:  # pragma: no branch
            require_positive(
                v, "A W shape's properties must be positive and finite"
            )
        if self.k_design.value * 2 >= self.depth.value:
            raise Error("A W shape's fillets must fit in its depth")

    def web_height(self) -> Length64:
        """Return h, the clear web height between the fillets.

        Returns:
            The depth less twice k_des.
        """
        return self.depth - self.k_design.scaled(2)

    def strong_radius(self) -> Length64:
        """Return r_x, the radius of gyration about the strong axis.

        Returns:
            `sqrt(I_x / A)`.
        """
        return Length64(sqrt(self.strong_inertia.value / self.area.value))


def _w(name: String, r: List[Float64]) -> WideFlange:
    """Return a W shape from a catalog row in inches."""
    return WideFlange(
        name,
        Length64(r[0], INCH64),
        Length64(r[1], INCH64),
        Length64(r[2], INCH64),
        Length64(r[3], INCH64),
        Length64(r[4], INCH64),
        Area64(r[5], SQUARE_INCH),
        SecondMomentOfArea64(r[6], INCH_TO_THE_FOURTH),
        Volume64(r[7], CUBIC_INCH),
        Volume64(r[8], CUBIC_INCH),
        SecondMomentOfArea64(r[9], INCH_TO_THE_FOURTH),
        Length64(r[10], INCH64),
        Length64(r[11], INCH64),
        Length64(r[12], INCH64),
        SecondMomentOfArea64(r[13], INCH_TO_THE_FOURTH),
        LineLoad64(r[14], PLF),
    )


def w_shapes() -> List[WideFlange]:
    """Return the light W8, W10 and W12 shapes, lightest first by depth.

    The values are those of the AISC Shapes Database v15.0.

    Returns:
        W8x10 to W8x24, W10x12 to W10x22 and W12x14 to W12x26.
    """
    var names: List[String] = [
        "W8x10",
        "W8x13",
        "W8x15",
        "W8x18",
        "W8x21",
        "W8x24",
        "W10x12",
        "W10x15",
        "W10x19",
        "W10x22",
        "W12x14",
        "W12x16",
        "W12x19",
        "W12x22",
        "W12x26",
    ]
    # d, bf, tf, tw, kdes, A, Ix, Sx, Zx, Iy, ry, rts, ho, J, plf
    var rows: List[List[Float64]] = [
        [
            7.89,
            3.94,
            0.205,
            0.17,
            0.505,
            2.96,
            30.8,
            7.81,
            8.87,
            2.09,
            0.841,
            1.06,
            7.69,
            0.0426,
            10.0,
        ],
        [
            7.99,
            4.0,
            0.255,
            0.23,
            0.555,
            3.84,
            39.6,
            9.91,
            11.4,
            2.73,
            0.843,
            1.06,
            7.74,
            0.0871,
            13.0,
        ],
        [
            8.11,
            4.02,
            0.315,
            0.245,
            0.615,
            4.44,
            48.0,
            11.8,
            13.6,
            3.41,
            0.876,
            1.07,
            7.8,
            0.137,
            15.0,
        ],
        [
            8.14,
            5.25,
            0.33,
            0.23,
            0.63,
            5.26,
            61.9,
            15.2,
            17.0,
            7.97,
            1.23,
            1.43,
            7.81,
            0.172,
            18.0,
        ],
        [
            8.28,
            5.27,
            0.4,
            0.25,
            0.7,
            6.16,
            75.3,
            18.2,
            20.4,
            9.77,
            1.26,
            1.45,
            7.88,
            0.282,
            21.0,
        ],
        [
            7.93,
            6.5,
            0.4,
            0.245,
            0.7,
            7.08,
            82.7,
            20.9,
            23.1,
            18.3,
            1.61,
            1.79,
            7.53,
            0.346,
            24.0,
        ],
        [
            9.87,
            3.96,
            0.21,
            0.19,
            0.51,
            3.54,
            53.8,
            10.9,
            12.6,
            2.18,
            0.785,
            1.01,
            9.66,
            0.0547,
            12.0,
        ],
        [
            9.99,
            4.0,
            0.27,
            0.23,
            0.57,
            4.41,
            68.9,
            13.8,
            16.0,
            2.89,
            0.81,
            1.04,
            9.72,
            0.104,
            15.0,
        ],
        [
            10.2,
            4.02,
            0.395,
            0.25,
            0.695,
            5.62,
            96.3,
            18.8,
            21.6,
            4.29,
            0.874,
            1.06,
            9.81,
            0.233,
            19.0,
        ],
        [
            10.2,
            5.75,
            0.36,
            0.24,
            0.66,
            6.49,
            118.0,
            23.2,
            26.0,
            11.4,
            1.33,
            1.55,
            9.84,
            0.239,
            22.0,
        ],
        [
            11.9,
            3.97,
            0.225,
            0.2,
            0.525,
            4.16,
            88.6,
            14.9,
            17.4,
            2.36,
            0.753,
            0.98,
            11.7,
            0.0704,
            14.0,
        ],
        [
            12.0,
            3.99,
            0.265,
            0.22,
            0.565,
            4.71,
            103.0,
            17.1,
            20.1,
            2.82,
            0.773,
            0.999,
            11.7,
            0.103,
            16.0,
        ],
        [
            12.2,
            4.01,
            0.35,
            0.235,
            0.65,
            5.57,
            130.0,
            21.3,
            24.7,
            3.76,
            0.822,
            1.03,
            11.9,
            0.18,
            19.0,
        ],
        [
            12.3,
            4.03,
            0.425,
            0.26,
            0.725,
            6.48,
            156.0,
            25.4,
            29.3,
            4.66,
            0.848,
            1.04,
            11.9,
            0.293,
            22.0,
        ],
        [
            12.2,
            6.49,
            0.38,
            0.23,
            0.68,
            7.65,
            204.0,
            33.4,
            37.2,
            17.3,
            1.51,
            1.75,
            11.8,
            0.3,
            26.0,
        ],
    ]
    var shapes = List[WideFlange]()
    # The catalog holds fifteen rows, so the loop always runs.
    for i in range(len(rows)):  # pragma: no branch
        shapes.append(_w(names[i], rows[i]))
    return shapes^


def w_shape(name: String) raises -> WideFlange:
    """Return the catalog W shape of a name.

    Args:
        name: A name such as "W8x18".

    Returns:
        The shape.

    Raises:
        Error: If the name is not in `w_shapes`.
    """
    # The catalog is never empty, so the loop always runs.
    for shape in w_shapes():  # pragma: no branch
        if shape.name == name:
            return shape.copy()
    raise Error("Unknown W shape: " + name)


@fieldwise_init
struct FlexuralStrength(ImplicitlyCopyable):
    """The nominal strong-axis flexural strengths of a W shape.

    `nominal` is the least of the limit states. Divide it by
    `FLEXURE_SAFETY` for the allowable moment.
    """

    var nominal: Moment64
    # Mp = Fy Zx, F2-1.
    var yielding: Moment64
    # F2-2 or F2-3, at most Mp.
    var lateral_torsional: Moment64
    # F3-1 or F3-2, or Mp for a compact flange.
    var flange_local: Moment64

    def allowable(self) -> Moment64:
        """Return the allowable moment.

        Returns:
            Mn divided by `FLEXURE_SAFETY`.
        """
        return self.nominal.scaled(1 / FLEXURE_SAFETY)


def flexural_strength(
    shape: WideFlange,
    yield_strength: Pressure64,
    unbraced: Length64,
    moment_gradient: Float64,
) raises -> FlexuralStrength:
    """Return the nominal flexural strength of a W shape, AISC F2 and F3.

    Args:
        shape: The shape. Its web must be compact, as the web of every
            catalog W shape is for a yield strength up to 65 ksi.
        yield_strength: Fy.
        unbraced: Lb, the length between braces of the compression
            flange. Zero for a continuously braced flange.
        moment_gradient: Cb, 1.0 or more.

    Returns:
        The limit states and the least of them.

    Raises:
        Error: If the shape is not valid, Fy is not positive, Lb is
            negative or Cb is less than 1.
    """
    shape.check()
    var fy = yield_strength.to(KSI)
    require_positive(fy, "A yield strength must be positive")
    var lb = unbraced.to(INCH64)
    if not (lb >= 0 and lb < Float64.MAX):
        raise Error("An unbraced length must be zero or more")
    if not (moment_gradient >= 1 and moment_gradient < Float64.MAX):
        raise Error("Cb must be 1.0 or more")
    var e = STEEL_MODULUS_KSI
    var zx = shape.plastic_modulus.to(CUBIC_INCH)
    var sx = shape.elastic_modulus.to(CUBIC_INCH)
    var mp = fy * zx
    var ry = shape.weak_radius.to(INCH64)
    var rts = shape.effective_radius.to(INCH64)
    var ho = shape.flange_distance.to(INCH64)
    var j = shape.torsion_constant.to(INCH_TO_THE_FOURTH)
    var lp = 1.76 * ry * sqrt(e / fy)
    var jc = j / (sx * ho)
    var lr = (
        1.95
        * rts
        * e
        / (0.7 * fy)
        * sqrt(jc + sqrt(jc * jc + 6.76 * (0.7 * fy / e) ** 2))
    )
    var ltb = mp
    if lb > lr:
        var slender = lb / rts
        var fcr = (
            moment_gradient
            * pi**2
            * e
            / slender**2
            * sqrt(1 + 0.078 * jc * slender**2)
        )
        ltb = min(fcr * sx, mp)
    elif lb > lp:
        ltb = min(
            moment_gradient
            * (mp - (mp - 0.7 * fy * sx) * (lb - lp) / (lr - lp)),
            mp,
        )
    var lam = shape.flange_width.value / (2 * shape.flange_thickness.value)
    var lam_p = 0.38 * sqrt(e / fy)
    var lam_r = 1.0 * sqrt(e / fy)
    var flb = mp
    if lam > lam_r:
        # A slender flange, F3-2, with kc = 4 / sqrt(h / tw) in its range.
        var kc = 4 / sqrt(shape.web_height().value / shape.web_thickness.value)
        kc = min(max(kc, 0.35), 0.76)
        flb = 0.9 * e * kc * sx / lam**2
    elif lam > lam_p:
        flb = mp - (mp - 0.7 * fy * sx) * (lam - lam_p) / (lam_r - lam_p)
    var least = min(mp, ltb, flb)
    return FlexuralStrength(
        Moment64(least, KIP_INCH),
        Moment64(mp, KIP_INCH),
        Moment64(ltb, KIP_INCH),
        Moment64(flb, KIP_INCH),
    )


@fieldwise_init
struct ShearStrength(ImplicitlyCopyable):
    """The nominal shear strength of a web and its safety factor."""

    var nominal: Force64
    var safety: Float64

    def allowable(self) -> Force64:
        """Return the allowable shear.

        Returns:
            Vn divided by the safety factor.
        """
        return self.nominal.scaled(1 / self.safety)


def shear_strength(
    shape: WideFlange, yield_strength: Pressure64
) raises -> ShearStrength:
    """Return the nominal shear strength of a W shape's web, AISC G2.1.

    Vn = 0.6 Fy Aw Cv1, with Aw = d tw. A web with h / tw at most
    2.24 sqrt(E / Fy) has Cv1 = 1 and a safety factor of 1.50. Any other
    web has 1.67, and Cv1 of G2-3 or G2-4 with kv = 5.34.

    Args:
        shape: The shape.
        yield_strength: Fy.

    Returns:
        The nominal strength and its safety factor.

    Raises:
        Error: If the shape is not valid or Fy is not positive.
    """
    shape.check()
    var fy = yield_strength.to(KSI)
    require_positive(fy, "A yield strength must be positive")
    var e = STEEL_MODULUS_KSI
    var aw = shape.depth.to(INCH64) * shape.web_thickness.to(INCH64)
    var slender = shape.web_height().value / shape.web_thickness.value
    var cv1 = 1.0
    var safety = STOCKY_WEB_SHEAR_SAFETY
    if slender > 2.24 * sqrt(e / fy):
        safety = SHEAR_SAFETY
        var limit = 1.10 * sqrt(5.34 * e / fy)
        if slender > limit:
            cv1 = limit / slender
    return ShearStrength(Force64(0.6 * fy * aw * cv1, KIP), safety)


def _bearing_inputs(
    shape: WideFlange, yield_strength: Pressure64, bearing_length: Length64
) raises -> Tuple[Float64, Float64]:
    """Return Fy in ksi and the bearing length in inches, checked."""
    shape.check()
    var fy = yield_strength.to(KSI)
    require_positive(fy, "A yield strength must be positive")
    var lb = bearing_length.to(INCH64)
    require_positive(lb, "A bearing length must be positive")
    return (fy, lb)


def web_local_yielding(
    shape: WideFlange,
    yield_strength: Pressure64,
    bearing_length: Length64,
    at_end: Bool,
) raises -> Force64:
    """Return the nominal web local yielding strength, AISC J10.2.

    Args:
        shape: The shape.
        yield_strength: Fy of the web.
        bearing_length: `lb`, the length of bearing along the beam.
        at_end: True if the load is within the depth of the member end,
            as at a support.

    Returns:
        Fy tw (2.5 k + lb) at an end, or Fy tw (5 k + lb) inside.

    Raises:
        Error: If the shape is not valid, or Fy or lb is not positive.
    """
    var inputs = _bearing_inputs(shape, yield_strength, bearing_length)
    var k = shape.k_design.to(INCH64)
    var spread = 2.5 * k if at_end else 5 * k
    return Force64(
        inputs[0] * shape.web_thickness.to(INCH64) * (spread + inputs[1]), KIP
    )


def web_crippling(
    shape: WideFlange,
    yield_strength: Pressure64,
    bearing_length: Length64,
    at_end: Bool,
) raises -> Force64:
    """Return the nominal web crippling strength, AISC J10.3.

    Args:
        shape: The shape.
        yield_strength: Fy of the web.
        bearing_length: `lb`, the length of bearing along the beam.
        at_end: True if the load is within half the depth of the member
            end, as at a support.

    Returns:
        J10-4 inside, or J10-5a or J10-5b at an end.

    Raises:
        Error: If the shape is not valid, or Fy or lb is not positive.
    """
    var inputs = _bearing_inputs(shape, yield_strength, bearing_length)
    var fy = inputs[0]
    var lb = inputs[1]
    var tw = shape.web_thickness.to(INCH64)
    var tf = shape.flange_thickness.to(INCH64)
    var d = shape.depth.to(INCH64)
    var root = sqrt(STEEL_MODULUS_KSI * fy * tf / tw)
    var ratio = (tw / tf) ** 1.5
    if not at_end:
        return Force64(0.80 * tw**2 * (1 + 3 * (lb / d) * ratio) * root, KIP)
    if lb / d <= 0.2:
        return Force64(0.40 * tw**2 * (1 + 3 * (lb / d) * ratio) * root, KIP)
    return Force64(
        0.40 * tw**2 * (1 + (4 * lb / d - 0.2) * ratio) * root, KIP
    )


@fieldwise_init
struct Pipe(Copyable, Movable):
    """A round steel pipe column by its design properties."""

    var name: String
    var outside_diameter: Length64
    # The design wall thickness, 0.93 times the nominal.
    var wall: Length64
    var area: Area64
    var radius_of_gyration: Length64


def standard_pipes() -> List[Pipe]:
    """Return standard-weight pipes, AISC Shapes Database v15.0.

    Returns:
        Pipe 3 Std, Pipe 3-1/2 Std and Pipe 4 Std.
    """
    var pipes = List[Pipe]()
    pipes.append(
        Pipe(
            "Pipe 3 Std",
            Length64(3.5, INCH64),
            Length64(0.201, INCH64),
            Area64(2.07, SQUARE_INCH),
            Length64(1.17, INCH64),
        )
    )
    pipes.append(
        Pipe(
            "Pipe 3-1/2 Std",
            Length64(4.0, INCH64),
            Length64(0.211, INCH64),
            Area64(2.5, SQUARE_INCH),
            Length64(1.34, INCH64),
        )
    )
    pipes.append(
        Pipe(
            "Pipe 4 Std",
            Length64(4.5, INCH64),
            Length64(0.221, INCH64),
            Area64(2.96, SQUARE_INCH),
            Length64(1.51, INCH64),
        )
    )
    return pipes^


def compression_strength(
    area: Area64,
    radius_of_gyration: Length64,
    yield_strength: Pressure64,
    effective_length: Length64,
) raises -> Force64:
    """Return the nominal compressive strength, AISC E3.

    The member must have no slender elements. A standard pipe meets that
    for D / t at most 0.11 E / Fy.

    Args:
        area: Ag.
        radius_of_gyration: `r` about the buckling axis.
        yield_strength: Fy.
        effective_length: Lc = K L.

    Returns:
        Fcr Ag, with Fcr of E3-2 or E3-3.

    Raises:
        Error: If a value is not positive and finite.
    """
    var a = area.to(SQUARE_INCH)
    var r = radius_of_gyration.to(INCH64)
    var fy = yield_strength.to(KSI)
    var lc = effective_length.to(INCH64)
    require_positive(a, "An area must be positive")
    require_positive(r, "A radius of gyration must be positive")
    require_positive(fy, "A yield strength must be positive")
    require_positive(lc, "An effective length must be positive")
    var slender = lc / r
    var fe = pi**2 * STEEL_MODULUS_KSI / slender**2
    var fcr: Float64
    if fy / fe <= 2.25:
        fcr = exp(log(0.658) * fy / fe) * fy
    else:
        fcr = 0.877 * fe
    return Force64(fcr * a, KIP)


def concrete_bearing(
    concrete_strength: Pressure64, plate_area: Area64, support_area: Area64
) raises -> Force64:
    """Return the nominal bearing strength of concrete under a plate,
    AISC J8.

    Args:
        concrete_strength: `f'c`.
        plate_area: A1, the area of the plate.
        support_area: A2, the largest area of the support that is
            geometrically similar to and concentric with A1. At least A1.

    Returns:
        0.85 f'c A1 sqrt(A2 / A1), at most 1.7 f'c A1.

    Raises:
        Error: If a value is not positive and finite, or A2 is less
            than A1.
    """
    var fc = concrete_strength.to(KSI)
    var a1 = plate_area.to(SQUARE_INCH)
    var a2 = support_area.to(SQUARE_INCH)
    require_positive(fc, "A concrete strength must be positive")
    require_positive(a1, "A plate area must be positive")
    require_positive(a2, "A support area must be positive")
    if a2 < a1:
        raise Error("The support area must be at least the plate area")
    return Force64(min(0.85 * fc * a1 * sqrt(a2 / a1), 1.7 * fc * a1), KIP)


def combined_ratio(
    axial_ratio: Float64, flexural_ratio: Float64
) raises -> Float64:
    """Return the interaction ratio of axial force and flexure, AISC H1.1.

    Args:
        axial_ratio: P_r / P_c, the required over the available axial
            strength.
        flexural_ratio: The sum of M_rx / M_cx and M_ry / M_cy.

    Returns:
        H1-1a, P_r / P_c + 8/9 M_r / M_c, for an axial ratio of 0.2 or
        more; otherwise H1-1b, P_r / (2 P_c) + M_r / M_c.

    Raises:
        Error: If a ratio is negative or not finite.
    """
    if not (axial_ratio >= 0 and axial_ratio < Float64.MAX):
        raise Error("An axial ratio must be zero or more and finite")
    if not (flexural_ratio >= 0 and flexural_ratio < Float64.MAX):
        raise Error("A flexural ratio must be zero or more and finite")
    if axial_ratio >= 0.2:
        return axial_ratio + 8.0 / 9.0 * flexural_ratio
    return axial_ratio / 2 + flexural_ratio


def fillet_weld_strength(
    size: Length64, length: Length64, electrode_strength: Pressure64
) raises -> Force64:
    """Return the nominal strength of a fillet weld, AISC J2.4.

    Args:
        size: `w`, the leg of an equal-leg fillet.
        length: The effective length of the weld.
        electrode_strength: F_EXX, such as 70 ksi.

    Returns:
        0.60 F_EXX (0.707 w) L, with the load taken as longitudinal.

    Raises:
        Error: If a value is not positive and finite.
    """
    var w = size.to(INCH64)
    var l = length.to(INCH64)
    var fexx = electrode_strength.to(KSI)
    require_positive(w, "A weld size must be positive")
    require_positive(l, "A weld length must be positive")
    require_positive(fexx, "An electrode strength must be positive")
    return Force64(0.60 * fexx * 0.707 * w * l, KIP)


def bolt_shear_strength(
    area: Area64, nominal_stress: Pressure64
) raises -> Force64:
    """Return the nominal shear strength of one bolt in one plane, AISC
    J3.6.

    Args:
        area: A_b, the nominal unthreaded body area.
        nominal_stress: F_nv of Table J3.2, such as 54 ksi for an A325
            bolt with threads in the shear plane.

    Returns:
        F_nv A_b.

    Raises:
        Error: If a value is not positive and finite.
    """
    var a = area.to(SQUARE_INCH)
    var f = nominal_stress.to(KSI)
    require_positive(a, "A bolt area must be positive")
    require_positive(f, "A bolt stress must be positive")
    return Force64(f * a, KIP)


def base_plate_thickness(
    load: Force64,
    width: Length64,
    length: Length64,
    cantilever: Length64,
    yield_strength: Pressure64,
) raises -> Length64:
    """Return the least thickness of a column base plate in compression.

    The plate bends as a cantilever under a uniform bearing pressure
    (AISC Design Guide 1, ASD): t = l sqrt(2 P_a Omega / (F_y B N)) with
    Omega = `BASE_PLATE_SAFETY`.

    Args:
        load: P_a, the ASD axial load.
        width: B, the plate width.
        length: N, the plate length.
        cantilever: `l`, the largest of m, n and lambda n'. For a round
            column of diameter D on a square plate, (N - 0.8 D) / 2.
        yield_strength: F_y of the plate.

    Returns:
        The least plate thickness.

    Raises:
        Error: If a value is not positive and finite.
    """
    var p = load.to(KIP)
    var b = width.to(INCH64)
    var n = length.to(INCH64)
    var l = cantilever.to(INCH64)
    var fy = yield_strength.to(KSI)
    require_positive(p, "A base plate load must be positive")
    require_positive(b, "A plate width must be positive")
    require_positive(n, "A plate length must be positive")
    require_positive(l, "A plate cantilever must be positive")
    require_positive(fy, "A yield strength must be positive")
    return Length64(l * sqrt(2 * p * BASE_PLATE_SAFETY / (fy * b * n)), INCH64)
