# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Foundation walls, strips and footings by ACI 318-19.

A basement wall spans vertically between the slab at its base and the
floor at its top. `propped_wall_effects` gives the reactions, the largest
moment and its height for an equivalent-fluid soil pressure and a uniform
lateral surcharge. `cantilever_wall_effects` gives the same for a wall
that is free at its top.

The strength of a unit width uses `ConcreteStrip` and
`flexural_resistance` of `extensions.geotech.concrete`, which give the
rectangular stress block of ACI 22.2 with phi = 0.90. `tension_strain`
says whether the section is tension controlled (ACI 21.2.2).

- `one_way_shear_strength`: ACI Table 22.5.5.1(c), a member without
  shear reinforcement, with the size effect factor.
- `two_way_shear_stress`: ACI Table 22.6.5.2, the least of the three
  stresses, with the size effect factor.
- `plain_flexural_strength`: ACI 14.5.2.1, a plain concrete section.
- `minimum_wall_steel`: ACI 11.6.1, the vertical and horizontal ratios.
- `wall_in_plane_shear_strength`: ACI 11.5.4.3, a wall loaded along its
  length.
- `plain_bearing_strength` and `plain_two_way_shear_strength`: ACI
  14.5.6.1 and 14.5.5.1, plain concrete.
- `square_footing_side` and `strip_footing_width`: the plan size for an
  allowable soil pressure.

The equations are in pounds and inches, as the code states them; the
functions take and return SI quantities.
"""

from std.math import sqrt
from extensions.design.quantities import POUND64, PSI, SQUARE_INCH
from extensions.design.steel import require_positive
from extensions.geotech.concrete import ConcreteStrip
from extensions.geotech.quantities import MomentPerLength64, UnitWeight64
from units.si import (
    Area64,
    Force64,
    INCH64,
    Length64,
    LineLoad64,
    Pressure64,
)

# The strength reduction factor of shear, ACI 21.2.1.
comptime SHEAR_PHI = 0.75
# The strength reduction factor of plain concrete, ACI 21.2.1.
comptime PLAIN_PHI = 0.60
# The net tensile strain at and above which a section is tension
# controlled, for Grade 60 bars (ACI 21.2.2).
comptime TENSION_CONTROLLED_STRAIN = 0.005
# Points per span of the moment scan.
comptime _STEPS = 2000


@fieldwise_init
struct WallEffects(ImplicitlyCopyable):
    """The effects of lateral pressure on a unit width of wall.

    Heights are measured up from the bottom support. A reaction is the
    force per width that a support applies to the wall.
    """

    var bottom_reaction: LineLoad64
    var top_reaction: LineLoad64
    var max_moment: MomentPerLength64
    var max_moment_height: Length64
    var max_shear: LineLoad64
    # The total lateral force per width.
    var total_force: LineLoad64


def _pressure(
    y: Float64, soil_height: Float64, fluid: Float64, surcharge: Float64
) -> Float64:
    """Return the lateral pressure at height y, in pascals."""
    if y > soil_height:
        return 0
    return fluid * (soil_height - y) + surcharge


def _check_wall_inputs(
    span: Length64,
    soil_height: Length64,
    fluid_pressure: UnitWeight64,
    surcharge: Pressure64,
) raises:
    """Refuse wall loads that cannot be analyzed."""
    require_positive(span.value, "A wall span must be positive")
    if not (soil_height.value >= 0 and soil_height.value < Float64.MAX):
        raise Error("A soil height must be zero or more and finite")
    if not (fluid_pressure.value >= 0 and fluid_pressure.value < Float64.MAX):
        raise Error("An equivalent fluid pressure must be zero or more")
    if not (surcharge.value >= 0 and surcharge.value < Float64.MAX):
        raise Error("A lateral surcharge must be zero or more")


def propped_wall_effects(
    span: Length64,
    soil_height: Length64,
    fluid_pressure: UnitWeight64,
    surcharge: Pressure64,
) raises -> WallEffects:
    """Return the effects on a wall pinned at its bottom and its top.

    The pressure at height y below the soil surface is the equivalent
    fluid pressure times the depth, plus the uniform lateral surcharge.
    Soil higher than the top support loads the wall only up to the span.

    Args:
        span: The height between the supports.
        soil_height: The height of the soil surface above the bottom
            support.
        fluid_pressure: The equivalent fluid pressure, such as 60 pcf.
        surcharge: The uniform lateral pressure of a surcharge, such as K
            times a vertical surcharge.

    Returns:
        The reactions, the largest moment and its height, the largest
        shear and the total force.

    Raises:
        Error: If the span is not positive or a load is negative.
    """
    _check_wall_inputs(span, soil_height, fluid_pressure, surcharge)
    var l = span.value
    var hs = soil_height.value
    var g = fluid_pressure.value
    var q = surcharge.value
    var dy = l / Float64(_STEPS)
    # Simpson's rule over the span for the force and its moment about the
    # base. The pressure has a kink at the soil surface, so put a node
    # there when it falls inside the span.
    var force = 0.0
    var first = 0.0
    var top = min(hs, l)
    if top > 0:
        var n = _STEPS
        var h = top / Float64(n)
        # The rule has _STEPS + 1 points, so the loop always runs.
        for i in range(n + 1):  # pragma: no branch
            var y = h * Float64(i)
            var weight = 1.0 if (i == 0 or i == n) else (
                4.0 if i % 2 == 1 else 2.0
            )
            var p = _pressure(y, hs, g, q)
            force += weight * p
            first += weight * p * y
        force *= h / 3
        first *= h / 3
    var r_top = first / l
    var r_bottom = force - r_top
    # Scan the moment: M(y) = Rb y - integral of p (y - t) dt.
    var best = 0.0
    var best_y = 0.0
    var load = 0.0
    var load_moment = 0.0
    var previous = _pressure(0, hs, g, q)
    # The scan has _STEPS points, so the loop always runs.
    for i in range(1, _STEPS + 1):  # pragma: no branch
        var y = dy * Float64(i)
        var p = _pressure(y, hs, g, q)
        var piece = (previous + p) / 2 * dy
        load_moment += load * dy + piece * dy / 2
        load += piece
        var m = r_bottom * y - load_moment
        if m > best:
            best = m
            best_y = y
        previous = p
    return WallEffects(
        LineLoad64(r_bottom),
        LineLoad64(r_top),
        MomentPerLength64(best),
        Length64(best_y),
        LineLoad64(max(abs(r_bottom), abs(r_top))),
        LineLoad64(force),
    )


def cantilever_wall_effects(
    height: Length64,
    soil_height: Length64,
    fluid_pressure: UnitWeight64,
    surcharge: Pressure64,
) raises -> WallEffects:
    """Return the effects on a wall fixed at its base and free at its top.

    Args:
        height: The height of the wall above the fixed base.
        soil_height: The height of the soil surface above the base.
        fluid_pressure: The equivalent fluid pressure.
        surcharge: The uniform lateral pressure of a surcharge.

    Returns:
        The base reaction and moment. The top reaction is zero.

    Raises:
        Error: If the height is not positive or a load is negative.
    """
    _check_wall_inputs(height, soil_height, fluid_pressure, surcharge)
    var h = min(soil_height.value, height.value)
    var hs = soil_height.value
    var g = fluid_pressure.value
    var q = surcharge.value
    # Closed form over the loaded height h, with the pressure at the top
    # of the loaded height g (hs - h) + q.
    var p_top = g * (hs - h) + q
    var p_base = g * hs + q
    var force = (p_top + p_base) / 2 * h
    var moment = p_top * h * h / 2 + (p_base - p_top) * h * h / 6
    return WallEffects(
        LineLoad64(force),
        LineLoad64(0),
        MomentPerLength64(moment),
        Length64(0),
        LineLoad64(force),
        LineLoad64(force),
    )


def stress_block_factor(concrete_strength: Pressure64) raises -> Float64:
    """Return beta1 of ACI Table 22.2.2.4.3.

    Args:
        concrete_strength: `f'c`.

    Returns:
        0.85 up to 4,000 psi, less 0.05 per 1,000 psi above, at least
        0.65.

    Raises:
        Error: If f'c is not positive.
    """
    var fc = concrete_strength.to(PSI)
    require_positive(fc, "A concrete strength must be positive")
    if fc <= 4000:
        return 0.85
    return max(0.85 - 0.05 * (fc - 4000) / 1000, 0.65)


def tension_strain(strip: ConcreteStrip) raises -> Float64:
    """Return the net tensile strain in the bars at nominal strength.

    Args:
        strip: The strip.

    Returns:
        0.003 (d - c) / c, with c = a / beta1.

    Raises:
        Error: If the strip is not valid or holds no steel.
    """
    strip.check()
    if strip.steel.value <= 0:
        raise Error("A strip without steel has no tensile strain")
    var c = strip.block_depth().value / stress_block_factor(
        strip.concrete_strength
    )
    return 0.003 * (strip.depth().value - c) / c


def _size_effect(depth: Float64) -> Float64:
    """Return lambda_s = sqrt(2 / (1 + d / 10)), at most 1, d in inches."""
    return min(sqrt(2 / (1 + depth / 10)), 1.0)


def one_way_shear_strength(
    width: Length64,
    depth: Length64,
    steel_area: Area64,
    concrete_strength: Pressure64,
) raises -> Force64:
    """Return phi Vc of a member without shear reinforcement.

    ACI Table 22.5.5.1(c): Vc = 8 lambda_s rho_w^(1/3) sqrt(f'c) b d, at
    most 5 sqrt(f'c) b d, normal-weight concrete, no axial load.

    Args:
        width: `b`, the width of the section.
        depth: `d`, the effective depth.
        steel_area: As, the tension steel in the width.
        concrete_strength: `f'c`. Its root is taken at most 100 psi.

    Returns:
        `phi Vc` with phi = 0.75.

    Raises:
        Error: If a size or f'c is not positive, or As is negative.
    """
    var b = width.to(INCH64)
    var d = depth.to(INCH64)
    var area = steel_area.to(SQUARE_INCH)
    var fc = concrete_strength.to(PSI)
    require_positive(b, "A shear width must be positive")
    require_positive(d, "A shear depth must be positive")
    require_positive(fc, "A concrete strength must be positive")
    if not (area >= 0 and area < Float64.MAX):
        raise Error("A steel area must be zero or more and finite")
    var root = min(sqrt(fc), 100.0)
    var rho = area / (b * d)
    var vc = 8 * _size_effect(d) * rho ** (1.0 / 3.0) * root * b * d
    vc = min(vc, 5 * root * b * d)
    return Force64(SHEAR_PHI * vc, POUND64)


def two_way_shear_stress(
    depth: Length64,
    perimeter: Length64,
    aspect: Float64,
    location: Float64,
    concrete_strength: Pressure64,
) raises -> Pressure64:
    """Return phi vc of a slab or footing in two-way shear.

    ACI Table 22.6.5.2: the least of 4, 2 + 4 / beta and
    2 + alpha_s d / b_o, times lambda_s sqrt(f'c).

    Args:
        depth: `d`, the effective depth.
        perimeter: `b_o`, the critical perimeter at d / 2 from the column.
        aspect: `beta`, the long over the short side of the column, 1 or
            more.
        location: `alpha_s`, 40 inside, 30 at an edge, 20 at a corner.
        concrete_strength: `f'c`. Its root is taken at most 100 psi.

    Returns:
        `phi vc` with phi = 0.75.

    Raises:
        Error: If a value is not positive, or beta is under 1.
    """
    var d = depth.to(INCH64)
    var bo = perimeter.to(INCH64)
    var fc = concrete_strength.to(PSI)
    require_positive(d, "A shear depth must be positive")
    require_positive(bo, "A critical perimeter must be positive")
    require_positive(location, "alpha_s must be positive")
    require_positive(fc, "A concrete strength must be positive")
    if not (aspect >= 1 and aspect < Float64.MAX):
        raise Error("beta must be 1 or more")
    var root = min(sqrt(fc), 100.0)
    var factor = min(4.0, 2 + 4 / aspect, 2 + location * d / bo)
    return Pressure64(SHEAR_PHI * factor * _size_effect(d) * root, PSI)


def plain_flexural_strength(
    width: Length64, thickness: Length64, concrete_strength: Pressure64
) raises -> MomentPerLength64:
    """Return phi Mn of a plain concrete section per unit width.

    ACI 14.5.2.1(a): Mn = 5 sqrt(f'c) Sm. A footing cast against soil
    uses its thickness less 2 in. (ACI 14.5.1.7).

    Args:
        width: The width the moment acts on.
        thickness: The thickness used for the section modulus.
        concrete_strength: `f'c`.

    Returns:
        `phi 5 sqrt(f'c) b h^2 / 6 over b`, with phi = 0.60.

    Raises:
        Error: If a value is not positive.
    """
    var b = width.to(INCH64)
    var h = thickness.to(INCH64)
    var fc = concrete_strength.to(PSI)
    require_positive(b, "A width must be positive")
    require_positive(h, "A thickness must be positive")
    require_positive(fc, "A concrete strength must be positive")
    var stress = Pressure64(PLAIN_PHI * 5 * sqrt(fc), PSI)
    var t = thickness.value
    return MomentPerLength64(stress.value * t * t / 6)


def minimum_wall_steel(
    thickness: Length64, large_bars: Bool
) raises -> Tuple[Length64, Length64]:
    """Return the least vertical and horizontal steel of a cast wall.

    ACI Table 11.6.1, Grade 60 bars: vertical 0.0012 and horizontal
    0.0020 of the gross area for No. 5 bars and smaller; 0.0015 and
    0.0025 for larger bars.

    Args:
        thickness: The wall thickness.
        large_bars: True for bars larger than No. 5.

    Returns:
        The vertical and the horizontal steel areas per unit length,
        which have the dimension of a length.

    Raises:
        Error: If the thickness is not positive.
    """
    require_positive(thickness.value, "A wall thickness must be positive")
    var vertical = 0.0015 if large_bars else 0.0012
    var horizontal = 0.0025 if large_bars else 0.0020
    return (thickness.scaled(vertical), thickness.scaled(horizontal))


def square_footing_side(
    load: Force64, allowable: Pressure64, self_weight: Pressure64
) raises -> Length64:
    """Return the least side of a square footing.

    Args:
        load: The service load on the footing.
        allowable: The allowable soil pressure.
        self_weight: The pressure of the footing and the soil and slab
            over it.

    Returns:
        `sqrt(P / (q_a - w))`.

    Raises:
        Error: If the load is negative, the allowable pressure is not
            positive, or the self weight is negative or uses it all.
    """
    if not (load.value >= 0 and load.value < Float64.MAX):
        raise Error("A footing load must be zero or more and finite")
    require_positive(allowable.value, "An allowable pressure must be positive")
    if not (self_weight.value >= 0 and self_weight.value < allowable.value):
        raise Error("A footing's weight must be under the allowable pressure")
    return Length64(sqrt(load.value / (allowable.value - self_weight.value)))


def strip_footing_width(
    load: LineLoad64, allowable: Pressure64, self_weight: Pressure64
) raises -> Length64:
    """Return the least width of a strip footing.

    Args:
        load: The service load per length of the strip.
        allowable: The allowable soil pressure.
        self_weight: The pressure of the footing and the soil and slab
            over it.

    Returns:
        `w / (q_a - w_self)`.

    Raises:
        Error: If the load is negative, the allowable pressure is not
            positive, or the self weight is negative or uses it all.
    """
    if not (load.value >= 0 and load.value < Float64.MAX):
        raise Error("A footing load must be zero or more and finite")
    require_positive(allowable.value, "An allowable pressure must be positive")
    if not (self_weight.value >= 0 and self_weight.value < allowable.value):
        raise Error("A footing's weight must be under the allowable pressure")
    return Length64(load.value / (allowable.value - self_weight.value))


def wall_in_plane_shear_strength(
    thickness: Length64,
    aspect_ratio: Float64,
    horizontal_ratio: Float64,
    concrete_strength: Pressure64,
    yield_strength: Pressure64,
) raises -> LineLoad64:
    """Return the nominal in-plane shear strength of a wall per length.

    ACI 11.5.4.3: V_n = (alpha_c sqrt(f'c) + rho_t f_y) A_cv, with
    alpha_c = 3 for h_w / l_w up to 1.5, 2 from 2.0, and linear between;
    at most 8 sqrt(f'c) A_cv (11.5.4.2).

    Args:
        thickness: The wall thickness.
        aspect_ratio: `h_w / l_w`, the wall height over its length.
        horizontal_ratio: `rho_t`, the distributed horizontal steel ratio.
        concrete_strength: `f'c`.
        yield_strength: `f_y` of the horizontal bars.

    Returns:
        V_n per unit length of wall.

    Raises:
        Error: If a value is not positive, or the steel ratio is negative.
    """
    var h = thickness.to(INCH64)
    var fc = concrete_strength.to(PSI)
    var fy = yield_strength.to(PSI)
    require_positive(h, "A wall thickness must be positive")
    require_positive(aspect_ratio, "A wall aspect ratio must be positive")
    require_positive(fc, "A concrete strength must be positive")
    require_positive(fy, "A yield strength must be positive")
    if not (horizontal_ratio >= 0 and horizontal_ratio < 1):
        raise Error("A steel ratio must be zero or more and less than 1")
    var alpha = 3.0
    if aspect_ratio >= 2.0:
        alpha = 2.0
    elif aspect_ratio > 1.5:
        alpha = 3.0 - 2.0 * (aspect_ratio - 1.5)
    var stress = min(alpha * sqrt(fc) + horizontal_ratio * fy, 8 * sqrt(fc))
    return LineLoad64(Pressure64(stress, PSI).value * thickness.value)


def plain_bearing_strength(
    area: Area64, concrete_strength: Pressure64
) raises -> Force64:
    """Return the nominal bearing strength of plain concrete, ACI 14.5.6.1.

    Without the confinement factor sqrt(A2 / A1), which is conservative.

    Args:
        area: A1, the loaded area.
        concrete_strength: `f'c`.

    Returns:
        0.85 f'c A1. Multiply by `PLAIN_PHI`.

    Raises:
        Error: If a value is not positive and finite.
    """
    var a = area.to(SQUARE_INCH)
    var fc = concrete_strength.to(PSI)
    require_positive(a, "A bearing area must be positive")
    require_positive(fc, "A concrete strength must be positive")
    return Force64(0.85 * fc * a, POUND64)


def plain_two_way_shear_strength(
    perimeter: Length64,
    thickness: Length64,
    aspect_ratio: Float64,
    concrete_strength: Pressure64,
) raises -> Force64:
    """Return the nominal two-way shear strength of plain concrete, ACI
    14.5.5.1(b).

    Args:
        perimeter: `b_o`, the critical perimeter at h / 2 from the load.
        thickness: `h`.
        aspect_ratio: `beta`, the long side over the short side of the
            loaded area, 1 or more.
        concrete_strength: `f'c`.

    Returns:
        (4/3 + 8 / (3 beta)) sqrt(f'c) b_o h, at most 2.66 sqrt(f'c)
        b_o h. Multiply by `PLAIN_PHI`.

    Raises:
        Error: If a value is not positive, or beta is less than 1.
    """
    var bo = perimeter.to(INCH64)
    var h = thickness.to(INCH64)
    var fc = concrete_strength.to(PSI)
    require_positive(bo, "A perimeter must be positive")
    require_positive(h, "A thickness must be positive")
    require_positive(fc, "A concrete strength must be positive")
    if not (aspect_ratio >= 1 and aspect_ratio < Float64.MAX):
        raise Error("beta must be 1 or more")
    var factor = min(4.0 / 3.0 + 8.0 / (3.0 * aspect_ratio), 2.66)
    return Force64(factor * sqrt(fc) * bo * h, POUND64)
