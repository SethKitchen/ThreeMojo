# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Single anchors in concrete by ACI 318-19 chapter 17.

The functions give the nominal strengths of one anchor away from other
anchors. Multiply each by its strength reduction factor. The concrete is
taken as cracked (psi_c = 1.0 and psi_cp = 1.0), and normalweight
(lambda_a = 1.0). That is conservative for a foundation wall.

- `steel_tension_strength` and `steel_shear_strength`: 17.6.1 and
  17.7.1, with f_uta at most 1.9 f_ya and 125 ksi.
- `breakout_tension_strength`: 17.6.2, with the reduced embedment of
  17.6.2.1.2 for an anchor near three or four edges.
- `pullout_strength`: 17.6.3, a headed stud or headed bolt.
- `bond_tension_strength`: 17.6.5, an adhesive anchor.
- `pryout_shear_strength`: 17.7.3.

Give an edge distance of 1.5 h_ef or more for a side without an edge.
The equations are in pounds and inches, as the code states them.
"""

from std.math import pi, sqrt
from extensions.design.kinds import AnchorKind, CAST_IN
from extensions.design.quantities import POUND64, PSI, SQUARE_INCH
from extensions.design.steel import require_positive
from extensions.geotech.quantities import KSI
from units.si import Area64, Force64, INCH64, Length64, Pressure64

# The strength reduction factors of Table 17.5.3, ductile steel.
comptime STEEL_TENSION_PHI = 0.75
comptime STEEL_SHEAR_PHI = 0.65
# Pryout, condition B (no supplementary reinforcement).
comptime PRYOUT_PHI = 0.70


def concrete_tension_phi(kind: AnchorKind) raises -> Float64:
    """Return phi of concrete breakout, pullout and bond in tension.

    Condition B (no supplementary reinforcement), Table 17.5.3. A
    post-installed anchor is taken as category 1.

    Args:
        kind: `CAST_IN` or `POST_INSTALLED`.

    Returns:
        0.70 for a cast-in anchor, 0.65 for a post-installed anchor.

    Raises:
        Error: If the kind is not valid.
    """
    if not kind.is_valid():
        raise Error("An anchor kind must be CAST_IN or POST_INSTALLED")
    return 0.70 if kind == CAST_IN else 0.65


def _tensile(
    tensile_strength: Pressure64, yield_strength: Pressure64
) raises -> Float64:
    """Return f_uta in psi, at most 1.9 f_ya and 125 ksi."""
    var futa = tensile_strength.to(PSI)
    var fya = yield_strength.to(PSI)
    require_positive(futa, "A tensile strength must be positive")
    require_positive(fya, "A yield strength must be positive")
    return min(futa, 1.9 * fya, Pressure64(125, KSI).to(PSI))


def steel_tension_strength(
    area: Area64, tensile_strength: Pressure64, yield_strength: Pressure64
) raises -> Force64:
    """Return N_sa, the steel strength of an anchor in tension, 17.6.1.2.

    Args:
        area: A_se,N, the effective area of the threaded rod.
        tensile_strength: f_uta of the steel.
        yield_strength: f_ya of the steel.

    Returns:
        A_se,N f_uta.

    Raises:
        Error: If a value is not positive and finite.
    """
    var a = area.to(SQUARE_INCH)
    require_positive(a, "An anchor area must be positive")
    return Force64(a * _tensile(tensile_strength, yield_strength), POUND64)


def steel_shear_strength(
    area: Area64, tensile_strength: Pressure64, yield_strength: Pressure64
) raises -> Force64:
    """Return V_sa, the steel strength of an anchor in shear, 17.7.1.2(b).

    For a headed bolt or a post-installed anchor without a sleeve
    through the shear plane.

    Args:
        area: A_se,V, the effective area of the threaded rod.
        tensile_strength: f_uta of the steel.
        yield_strength: f_ya of the steel.

    Returns:
        0.6 A_se,V f_uta.

    Raises:
        Error: If a value is not positive and finite.
    """
    var a = area.to(SQUARE_INCH)
    require_positive(a, "An anchor area must be positive")
    return Force64(
        0.6 * a * _tensile(tensile_strength, yield_strength), POUND64
    )


def _edges(
    x_minus: Length64, x_plus: Length64, y_minus: Length64, y_plus: Length64
) raises -> List[Float64]:
    """Return the four edge distances in inches, refusing bad ones."""
    var c: List[Float64] = [
        x_minus.to(INCH64),
        x_plus.to(INCH64),
        y_minus.to(INCH64),
        y_plus.to(INCH64),
    ]
    # The list holds four distances, so the loop always runs.
    for v in c:  # pragma: no branch
        require_positive(v, "An edge distance must be positive")
    return c^


def _projected(c: List[Float64], reach: Float64) -> Float64:
    """Return the projected area of a failure surface that reaches out
    `reach` from the anchor, cut off by the edges."""
    var wide = min(c[0], reach) + min(c[1], reach)
    var high = min(c[2], reach) + min(c[3], reach)
    return wide * high


def breakout_tension_strength(
    kind: AnchorKind,
    embedment: Length64,
    x_minus: Length64,
    x_plus: Length64,
    y_minus: Length64,
    y_plus: Length64,
    concrete_strength: Pressure64,
) raises -> Force64:
    """Return N_cb, the concrete breakout strength of one anchor, 17.6.2.

    N_b is k_c sqrt(f'c) h_ef^1.5 (17.6.2.2.1), with k_c = 24 for a
    cast-in anchor and 17 for a post-installed anchor. The optional
    h_ef^(5/3) form of 17.6.2.2.3 is not used. Where three or four edges
    are nearer than 1.5 h_ef, h_ef becomes the larger edge distance of
    those over 1.5 (17.6.2.1.2).

    Args:
        kind: `CAST_IN` or `POST_INSTALLED`.
        embedment: h_ef.
        x_minus: The distance to the edge on one side along x.
        x_plus: The distance to the edge on the other side along x.
        y_minus: The distance to the edge on one side along y.
        y_plus: The distance to the edge on the other side along y.
        concrete_strength: f'c.

    Returns:
        (A_Nc / A_Nco) psi_ed,N N_b.

    Raises:
        Error: If the kind is not valid or a value is not positive.
    """
    if not kind.is_valid():
        raise Error("An anchor kind must be CAST_IN or POST_INSTALLED")
    var hef = embedment.to(INCH64)
    require_positive(hef, "An embedment must be positive")
    var fc = concrete_strength.to(PSI)
    require_positive(fc, "A concrete strength must be positive")
    var c = _edges(x_minus, x_plus, y_minus, y_plus)
    var near = 0
    var largest = 0.0
    # The list holds four distances, so the loop always runs.
    for v in c:  # pragma: no branch
        if v < 1.5 * hef:
            near += 1
            largest = max(largest, v)
    if near >= 3:
        hef = largest / 1.5
    var reach = 1.5 * hef
    var least = min(c[0], c[1], c[2], c[3])
    var psi_ed = 1.0 if least >= reach else 0.7 + 0.3 * least / reach
    var kc = 24.0 if kind == CAST_IN else 17.0
    var nb = kc * sqrt(fc) * hef**1.5
    var ratio = _projected(c, reach) / (9 * hef * hef)
    return Force64(ratio * psi_ed * nb, POUND64)


def pullout_strength(
    bearing_area: Area64, concrete_strength: Pressure64
) raises -> Force64:
    """Return N_pn, the pullout strength of a headed anchor, 17.6.3.

    Args:
        bearing_area: A_brg, the net bearing area of the head or nut.
        concrete_strength: f'c.

    Returns:
        8 A_brg f'c, cracked concrete.

    Raises:
        Error: If a value is not positive and finite.
    """
    var a = bearing_area.to(SQUARE_INCH)
    var fc = concrete_strength.to(PSI)
    require_positive(a, "A bearing area must be positive")
    require_positive(fc, "A concrete strength must be positive")
    return Force64(8 * a * fc, POUND64)


def bond_tension_strength(
    diameter: Length64,
    embedment: Length64,
    cracked_bond: Pressure64,
    uncracked_bond: Pressure64,
    x_minus: Length64,
    x_plus: Length64,
    y_minus: Length64,
    y_plus: Length64,
) raises -> Force64:
    """Return N_a, the bond strength of one adhesive anchor, 17.6.5.

    The bond stresses are the characteristic values of the product's
    evaluation report (ACI 355.4).

    Args:
        diameter: d_a, the anchor diameter.
        embedment: h_ef.
        cracked_bond: tau_cr.
        uncracked_bond: tau_uncr, which sets c_Na (17.6.5.1.2).
        x_minus: The distance to the edge on one side along x.
        x_plus: The distance to the edge on the other side along x.
        y_minus: The distance to the edge on one side along y.
        y_plus: The distance to the edge on the other side along y.

    Returns:
        (A_Na / A_Nao) psi_ed,Na tau_cr pi d_a h_ef.

    Raises:
        Error: If a value is not positive, or tau_cr is more than
            tau_uncr.
    """
    var da = diameter.to(INCH64)
    var hef = embedment.to(INCH64)
    var tcr = cracked_bond.to(PSI)
    var tun = uncracked_bond.to(PSI)
    require_positive(da, "An anchor diameter must be positive")
    require_positive(hef, "An embedment must be positive")
    require_positive(tcr, "A bond stress must be positive")
    require_positive(tun, "A bond stress must be positive")
    if tcr > tun:
        raise Error("The cracked bond stress must not exceed the uncracked")
    var c = _edges(x_minus, x_plus, y_minus, y_plus)
    var cna = 10 * da * sqrt(tun / 1100)
    var least = min(c[0], c[1], c[2], c[3])
    var psi_ed = 1.0 if least >= cna else 0.7 + 0.3 * least / cna
    var nba = tcr * pi * da * hef
    var ratio = _projected(c, cna) / (4 * cna * cna)
    return Force64(ratio * psi_ed * nba, POUND64)


def pryout_shear_strength(
    embedment: Length64, tension_strength: Force64
) raises -> Force64:
    """Return V_cp, the pryout strength of one anchor, 17.7.3.

    Args:
        embedment: h_ef.
        tension_strength: N_cp: N_cb for a cast-in, expansion or undercut
            anchor, the lesser of N_a and N_cb for an adhesive anchor.

    Returns:
        k_cp N_cp, with k_cp = 1.0 below 2.5 in. of embedment and 2.0
        otherwise.

    Raises:
        Error: If a value is not positive and finite.
    """
    var hef = embedment.to(INCH64)
    require_positive(hef, "An embedment must be positive")
    require_positive(
        tension_strength.value, "A tension strength must be positive"
    )
    var kcp = 1.0 if hef < 2.5 else 2.0
    return tension_strength.scaled(kcp)
