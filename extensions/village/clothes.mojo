# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The everyday clothes of the village's people.

`village_outfit` dresses a person in the garments of `extensions.attire`:
a linen shirt next to the skin, wool hose, a wool tunic over the shirt,
leather boots and, if asked, a wool hood. The tunic, its trim and the
hose take the dyes that you give, so each person of the village can wear
their own colors. `dress` then makes each garment from the person's own
skin: see `extensions.attire.outfit`.

The dyes of `NATURAL_DYES` are the colors that a village dyer gets from
plants and from undyed wool: madder red, woad blue, weld yellow, walnut
brown, nettle green, and gray and cream wool. `dyed_outfit` picks a tunic,
a trim and a hose from them by a seed.
"""

from extensions.attire.garment import boots, hood, hose, shirt, tunic
from extensions.attire.kinds import TRIM_DYE
from extensions.attire.outfit import Outfit
from render.framebuffer import Color

comptime MADDER = Color(150, 42, 34)
"""Madder red."""
comptime WOAD = Color(42, 72, 124)
"""Woad blue."""
comptime WELD = Color(196, 164, 64)
"""Weld yellow."""
comptime WALNUT = Color(92, 62, 40)
"""Walnut brown."""
comptime NETTLE = Color(70, 96, 52)
"""Nettle green."""
comptime GRAY_WOOL = Color(118, 114, 106)
"""Undyed gray wool."""
comptime CREAM_WOOL = Color(214, 202, 176)
"""Undyed cream wool."""

comptime NATURAL_DYES = 7
"""How many dyes `natural_dye` gives."""


def natural_dye(index: Int) -> Color:
    """Return one of the village's natural dyes.

    Args:
        index: Which dye. Any integer: it is taken modulo `NATURAL_DYES`.

    Returns:
        Madder, woad, weld, walnut, nettle, gray wool or cream wool.
    """
    # The remainder takes the divisor's sign, so it is never negative.
    var k = index % NATURAL_DYES
    if k == 0:
        return MADDER
    if k == 1:
        return WOAD
    if k == 2:
        return WELD
    if k == 3:
        return WALNUT
    if k == 4:
        return NETTLE
    if k == 5:
        return GRAY_WOOL
    return CREAM_WOOL


def village_outfit(
    tunic_dye: Color, trim_dye: Color, hose_dye: Color, hooded: Bool
) raises -> Outfit:
    """Return a villager's everyday clothes.

    Args:
        tunic_dye: The color of the tunic, and of the hood.
        trim_dye: The color of the tunic's hems.
        hose_dye: The color of the hose.
        hooded: Whether a hood covers the head and the neck.

    Returns:
        A shirt, hose, a tunic, boots and, if `hooded`, a hood.

    Raises:
        Error: Never: the wardrobe's garments check.
    """
    var outfit = Outfit()
    outfit.add(shirt())
    var legs = hose()
    for k in range(len(legs.dyes)):  # pragma: no branch
        legs.dyes[k] = hose_dye
    outfit.add(legs^)
    var coat = tunic()
    for k in range(len(coat.dyes)):  # pragma: no branch
        coat.dyes[k] = tunic_dye
    coat.dyes[TRIM_DYE.value] = trim_dye
    outfit.add(coat^)
    outfit.add(boots())
    if hooded:
        var cowl = hood()
        for k in range(len(cowl.dyes)):  # pragma: no branch
            cowl.dyes[k] = tunic_dye
        outfit.add(cowl^)
    return outfit^


def dyed_outfit(seed: Int, hooded: Bool) raises -> Outfit:
    """Return a villager's everyday clothes in dyes picked by a seed.

    The tunic takes one dye, its trim the next, and the hose the dye
    three after the tunic's, so no two of them share a color.

    Args:
        seed: Which dyes. Any integer.
        hooded: Whether a hood covers the head and the neck.

    Returns:
        The outfit of `village_outfit`.

    Raises:
        Error: Never: the wardrobe's garments check.
    """
    return village_outfit(
        natural_dye(seed), natural_dye(seed + 1), natural_dye(seed + 3), hooded
    )
