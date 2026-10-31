# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The metals mail and plate are made of, and how each one looks.

A metal reflects its own color, so mail and plate take the metal's color
as their dyes, and its finish as their material: how rough the surface
is, and how much of its look is metal.

| Metal | Color | Roughness | Metalness | What it is |
|---|---|---|---|---|
| `IRON` | dark gray | 0.5 | 0.9 | wrought iron, hammered and dull |
| `STEEL` | bright gray | 0.3 | 0.9 | polished steel |
| `BLACKENED` | near black | 0.55 | 0.7 | steel blackened in oil against rust |
| `BLUED` | deep blue | 0.28 | 0.9 | steel blued with heat |
| `BRONZE` | brown gold | 0.35 | 0.9 | tin bronze |
| `COPPER` | red brown | 0.35 | 0.9 | beaten copper |
| `BRASS` | pale gold | 0.3 | 0.9 | yellow brass |
| `SILVER` | white | 0.18 | 0.95 | polished silver |
| `GOLD` | deep yellow | 0.2 | 0.95 | gold, or gilt over steel |

`forged` makes a mail or plate garment of a metal: its dyes take the
metal's color, and its trim the color of a second metal, such as gilt
edges on blued steel. The colors are base reflectances in sRGB, set by
eye for each metal's look, not measured.

This is not a three.js port. See Extensions.

    var helm = forged(bascinet(), BLUED, GOLD)
"""

from core.ordinal import ordinal_label, ordinal_valid, require_valid
from render.framebuffer import Color


@fieldwise_init
struct Metal(Equatable, ImplicitlyCopyable, Writable):
    """What a mail or plate garment is made of."""

    var value: Int
    """Its index among the named values."""

    def is_valid(self) -> Bool:
        """Return whether this is a named metal.

        Returns:
            True for `IRON` through `GOLD`.
        """
        return ordinal_valid(self.value, METAL_COUNT - 1)


comptime IRON = Metal(0)
"""Wrought iron, hammered and dull."""
comptime STEEL = Metal(1)
"""Polished steel, the default."""
comptime BLACKENED = Metal(2)
"""Steel blackened in oil against rust."""
comptime BLUED = Metal(3)
"""Steel blued with heat."""
comptime BRONZE = Metal(4)
"""Tin bronze."""
comptime COPPER = Metal(5)
"""Beaten copper."""
comptime BRASS = Metal(6)
"""Yellow brass."""
comptime SILVER = Metal(7)
"""Polished silver."""
comptime GOLD = Metal(8)
"""Gold, or gilt over steel."""
comptime METAL_COUNT = 9
"""How many metals there are."""


def _metal_names() -> List[String]:
    """Return the metal names, in order."""
    return [
        "iron",
        "steel",
        "blackened",
        "blued",
        "bronze",
        "copper",
        "brass",
        "silver",
        "gold",
    ]


def metal_label(metal: Metal) -> String:
    """Return the name of a metal.

    Args:
        metal: A metal, named or not.

    Returns:
        Its name, as `"bronze"`, or `"metal"` when it is not named.
    """
    return ordinal_label(metal.is_valid(), metal.value, _metal_names(), "metal")


def metal_named(name: String) raises -> Metal:
    """Return the metal that `name` names.

    Args:
        name: A metal's name, as `metal_label` gives it.

    Returns:
        The named metal.

    Raises:
        Error: If `name` names no metal.
    """
    var names = _metal_names()
    for k in range(len(names)):  # pragma: no branch
        if names[k] == name:
            return Metal(k)
    raise Error("No metal is named " + name)


def require_metal(metal: Metal) raises:
    """Refuse a metal that is not named.

    Args:
        metal: The metal.

    Raises:
        Error: If the metal is not named.
    """
    require_valid(metal.is_valid(), "A metal must be a named one")


def metal_color(metal: Metal) raises -> Color:
    """Return the color a metal reflects.

    Args:
        metal: A named metal.

    Returns:
        Its base color, in sRGB.

    Raises:
        Error: If the metal is not named.
    """
    require_metal(metal)
    var colors: List[Color] = [
        Color(140, 138, 134),
        Color(198, 200, 206),
        Color(54, 54, 60),
        Color(58, 74, 118),
        Color(196, 138, 78),
        Color(206, 120, 84),
        Color(222, 184, 98),
        Color(232, 232, 236),
        Color(240, 194, 88),
    ]
    return colors[metal.value]


def metal_roughness(metal: Metal) raises -> Float32:
    """Return how rough a metal's polished surface is.

    Args:
        metal: A named metal.

    Returns:
        Zero for a mirror through one for a matte surface.

    Raises:
        Error: If the metal is not named.
    """
    require_metal(metal)
    var roughness: List[Float32] = [
        0.5,
        0.3,
        0.55,
        0.28,
        0.35,
        0.35,
        0.3,
        0.18,
        0.2,
    ]
    return roughness[metal.value]


def metal_metalness(metal: Metal) raises -> Float32:
    """Return how much of a metal's look is metal.

    Blackening leaves a film of oil and soot over the steel, so less of
    its look is the metal's own.

    Args:
        metal: A named metal.

    Returns:
        0.7 for blackened steel, 0.95 for silver and gold, 0.9 for the
        rest.

    Raises:
        Error: If the metal is not named.
    """
    require_metal(metal)
    if metal == BLACKENED:
        return 0.7
    if metal == SILVER or metal == GOLD:
        return 0.95
    return 0.9
