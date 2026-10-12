# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Water against a wall.

When the water stands at one level on both sides, its lateral pressures
cancel, and the soil and concrete below it weigh their buoyant unit
weight. Counting buoyant weights and also a separate uplift force would
count the same pore water twice.

When the water is higher behind the wall than in front, as after a flood
falls quickly, the net lateral pressure is the difference of the two
hydrostatic diagrams. `net_hydrostatic` integrates it over the wall's
height: a triangle over the difference in head, and a rectangle below the
lower level. A level above the wall's top still pushes on the full height.
"""

from std.math import isfinite
from extensions.geotech.units import MomentPerLength64, UnitWeight64
from units.si import Length64, LineLoad64


@fieldwise_init
struct LateralResultant(ImplicitlyCopyable):
    """A lateral force on a wall and where it acts."""

    # The force per unit length of wall.
    var force: LineLoad64
    # Its moment about the wall's base.
    var moment: MomentPerLength64
    # Its height above the base.
    var arm: Length64


def _resultant(force: Float64, moment: Float64) -> LateralResultant:
    """Return a resultant from its force and moment, both in SI."""
    var arm = moment / force if force > 0 else 0.0
    return LateralResultant(
        LineLoad64(force), MomentPerLength64(moment), Length64(arm)
    )


def net_hydrostatic(
    back: Length64,
    front: Length64,
    height: Length64,
    unit_weight: UnitWeight64,
) raises -> LateralResultant:
    """Return the net water thrust of unequal levels on a wall.

    The levels are measured from the wall's base. A front level above the
    back level counts as equal to it.

    Args:
        back: The water level behind the wall.
        front: The water level in front of it.
        height: The height of the wall the water acts on.
        unit_weight: The unit weight of water.

    Returns:
        The net force, its moment about the base, and its arm.

    Raises:
        Error: If an input is not finite or the unit weight is negative.
    """
    if not (
        isfinite(back.value)
        and isfinite(front.value)
        and isfinite(height.value)
        and isfinite(unit_weight.value)
        and unit_weight.value >= 0
    ):
        raise Error("Water levels, height and unit weight must be finite")
    var gw = unit_weight.value
    var hb = max(back.value, 0.0)
    var hf = max(min(front.value, hb), 0.0)
    var h = max(height.value, 0.0)
    if h <= 1e-12 or hb <= 1e-12:
        return _resultant(0, 0)
    if h <= hf:
        # Both levels overtop the wall: a uniform net pressure.
        var p = gw * (hb - hf) * h
        return _resultant(p, p * h / 2)
    if h >= hb:
        return _resultant(
            0.5 * gw * (hb * hb - hf * hf), gw / 6 * (hb**3 - hf**3)
        )
    # The back level overtops the wall and the front level does not. From
    # 0 to hf the net pressure is the constant head difference; from hf to
    # h the front is dry and the back pressure is gw (hb - y).
    var p_rect = gw * (hb - hf) * hf
    var m_rect = p_rect * hf / 2
    var p_top = gw * ((hb - hf) * (h - hf) - 0.5 * (h - hf) ** 2)
    var m_top = gw * (hb * (h * h - hf * hf) / 2 - (h**3 - hf**3) / 3)
    return _resultant(p_rect + p_top, m_rect + m_top)


def effective_unit_weight(
    unit_weight: UnitWeight64,
    bottom: Length64,
    top: Length64,
    water: Optional[Length64],
    water_unit_weight: UnitWeight64,
) -> UnitWeight64:
    """Return the mean effective unit weight of a layer.

    The part of the layer below the water level weighs its buoyant unit
    weight.

    Args:
        unit_weight: The material's unit weight above water.
        bottom: The bottom of the layer.
        top: The top of the layer.
        water: The water level, or None for dry.
        water_unit_weight: The unit weight of water.

    Returns:
        The mean over the layer; the dry unit weight for a layer of no
        thickness or with no water.
    """
    if not water or top.value <= bottom.value:
        return unit_weight
    var y_bot = bottom.value
    var y_top = top.value
    var thick = y_top - y_bot
    var sub = min(max(0.0, min(y_top, water.value().value) - y_bot), thick)
    var dry = thick - sub
    return UnitWeight64(
        (
            unit_weight.value * dry
            + (unit_weight.value - water_unit_weight.value) * sub
        )
        / thick
    )
