# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Procedural textures for civil works: formed concrete, soil and riprap.

Each function returns a color map in sRGB, a roughness map and a normal
map that tile, as the CARLA textures do, from the same tileable value
noise. A texture spans one tile; `place` from the CARLA textures sets how
many meters a tile covers.

- **Formed concrete** is light gray cast against plywood forms: faint
  horizontal panel joints, a grid of form-tie holes, mottling and a
  little staining near the bottom of each panel.
- **Soil** is a tan-brown silty loess with darker clods and fine grit.
- **Riprap** is angular gray stones with dark gaps between them.
"""

from std.math import floor, sqrt
from extensions.carla.render_textures import (
    SurfaceMaps,
    hash2,
    normal_map,
    tile_fbm,
)
from math.smoothstep import smoothstep
from render.srgb import LINEAR, SRGB
from render.texture import BILINEAR, IGNORED, REPEAT, Texture


def _byte(value: Float32) -> UInt8:
    """Return a channel from zero to one as a byte."""
    return UInt8(Int(max(Float32(0), min(Float32(1), value)) * 255 + 0.5))


def _rgba(mut pixels: List[UInt8], r: Float32, g: Float32, b: Float32):
    """Append one opaque texel."""
    pixels.extend([_byte(r), _byte(g), _byte(b), 255])


def _check(size: Int) raises:
    """Refuse a texture of no texels."""
    if size < 1:
        raise Error("A texture needs at least one texel on a side")


def _maps(
    size: Int,
    var color: List[UInt8],
    var rough: List[UInt8],
    heights: List[Float32],
    strength: Float32,
) raises -> SurfaceMaps:
    """Return the three maps and a black emissive map."""
    var black = List[UInt8]()
    _rgba(black, 0, 0, 0)
    return SurfaceMaps(
        Texture(size, size, color^, REPEAT, BILINEAR, SRGB, True, IGNORED),
        Texture(size, size, rough^, REPEAT, BILINEAR, LINEAR, True, IGNORED),
        normal_map(heights, size, strength),
        Texture(1, 1, black^, REPEAT, BILINEAR, SRGB, True, IGNORED),
    )


def formed_concrete_maps(
    size: Int, panels: Int = 2, ties: Int = 4, seed: Int = 21
) raises -> SurfaceMaps:
    """Return concrete cast against plywood forms.

    Args:
        size: Texels on a side.
        panels: Form panels stacked down the tile; one or more.
        ties: Form ties across and down each panel; one or more.
        seed: Which concrete.

    Returns:
        The maps; the emissive map is black.

    Raises:
        Error: If `size`, `panels` or `ties` is less than one.
    """
    _check(size)
    if panels < 1 or ties < 1:
        raise Error("Formed concrete needs at least one panel and one tie")
    var color = List[UInt8](capacity=size * size * 4)
    var rough = List[UInt8](capacity=size * size * 4)
    var heights = List[Float32](capacity=size * size)
    var step = Float32(1) / Float32(size)
    # _check makes the size one or more, so these loops always run.
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var u = Float32(x) * step
            var v = Float32(y) * step
            var pv = v * Float32(panels)
            var within = pv - floor(pv)
            var joint = 1 - smoothstep(0.0, 0.008, min(within, 1 - within))
            var tu = u * Float32(ties)
            var tv = within * Float32(ties)
            var du = tu - floor(tu) - 0.5
            var dv = tv - floor(tv) - 0.5
            var tie = 1 - smoothstep(0.035, 0.06, sqrt(du * du + dv * dv))
            var mottle = tile_fbm(u, v, 3, 4, seed)
            var grain = hash2(x, y, seed + 3)
            var bleed = smoothstep(0.75, 1.0, within) * tile_fbm(
                u, v, 8, 2, seed + 9
            )
            var tone = (
                Float32(0.62)
                + (mottle - 0.5) * 0.16
                + (grain - 0.5) * 0.05
                - joint * 0.12
                - tie * 0.28
                - bleed * 0.08
            )
            _rgba(color, tone * 0.99, tone * 0.98, tone * 0.95)
            var r = Float32(0.86) + (grain - 0.5) * 0.08 - joint * 0.1
            _rgba(rough, r, r, r)
            heights.append(
                -joint * 0.5 - tie * 1.2 + grain * 0.08 + mottle * 0.1
            )
    return _maps(size, color^, rough^, heights, 1.4)


def soil_maps(size: Int, seed: Int = 31) raises -> SurfaceMaps:
    """Return silty loess soil.

    Args:
        size: Texels on a side.
        seed: Which soil.

    Returns:
        The maps; the emissive map is black.

    Raises:
        Error: If `size` is less than one.
    """
    _check(size)
    var color = List[UInt8](capacity=size * size * 4)
    var rough = List[UInt8](capacity=size * size * 4)
    var heights = List[Float32](capacity=size * size)
    var step = Float32(1) / Float32(size)
    # _check makes the size one or more, so these loops always run.
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var u = Float32(x) * step
            var v = Float32(y) * step
            var broad = tile_fbm(u, v, 3, 4, seed)
            var clod = smoothstep(0.55, 0.75, tile_fbm(u, v, 12, 3, seed + 5))
            var grit = hash2(x, y, seed + 7)
            var tone = (
                Float32(0.66)
                + (broad - 0.5) * 0.24
                + (grit - 0.5) * 0.1
                - clod * 0.1
            )
            _rgba(color, tone * 0.84, tone * 0.7, tone * 0.52)
            var r = Float32(0.95) - clod * 0.05
            _rgba(rough, r, r, r)
            heights.append(clod * 0.8 + grit * 0.3 + broad * 0.2)
    return _maps(size, color^, rough^, heights, 1.6)


def riprap_maps(
    size: Int, stones: Int = 6, seed: Int = 41
) raises -> SurfaceMaps:
    """Return angular riprap stones.

    Each texel takes the nearest of a jittered grid of stone centers that
    wraps, so the stones tile.

    Args:
        size: Texels on a side.
        stones: Stones across the tile; one or more.
        seed: Which riprap.

    Returns:
        The maps; the emissive map is black.

    Raises:
        Error: If `size` or `stones` is less than one.
    """
    _check(size)
    if stones < 1:
        raise Error("Riprap needs at least one stone across")
    var color = List[UInt8](capacity=size * size * 4)
    var rough = List[UInt8](capacity=size * size * 4)
    var heights = List[Float32](capacity=size * size)
    var step = Float32(1) / Float32(size)
    # _check makes the size one or more, so these loops always run.
    for y in range(size):  # pragma: no branch
        for x in range(size):  # pragma: no branch
            var u = Float32(x) * step * Float32(stones)
            var v = Float32(y) * step * Float32(stones)
            var cu = Int(floor(u))
            var cv = Int(floor(v))
            var best = Float32(1e9)
            var second = Float32(1e9)
            var owner = 0
            # Each range holds -1, 0 and 1, so these loops always run.
            for j in range(-1, 2):  # pragma: no branch
                for i in range(-1, 2):  # pragma: no branch
                    var gx = cu + i
                    var gy = cv + j
                    var wx = ((gx % stones) + stones) % stones
                    var wy = ((gy % stones) + stones) % stones
                    var px = Float32(gx) + 0.15 + 0.7 * hash2(wx, wy, seed)
                    var py = Float32(gy) + 0.15 + 0.7 * hash2(wx, wy, seed + 1)
                    # A Chebyshev-like metric gives angular faces.
                    var dx = abs(u - px)
                    var dy = abs(v - py)
                    var d = max(dx, dy) * 0.6 + (dx + dy) * 0.4
                    if d < best:
                        second = best
                        best = d
                        owner = wy * stones + wx
                    elif d < second:
                        second = d
            var gap = 1 - smoothstep(0.02, 0.07, second - best)
            var shade = hash2(owner, 0, seed + 2)
            var grain = hash2(x, y, seed + 3)
            var tone = (
                Float32(0.42)
                + (shade - 0.5) * 0.18
                + (grain - 0.5) * 0.06
                - gap * 0.3
            )
            _rgba(color, tone * 0.97, tone * 0.96, tone * 0.93)
            var r = Float32(0.8) + gap * 0.15
            _rgba(rough, r, r, r)
            heights.append((1 - gap) * (0.6 - best * 0.8) + grain * 0.05)
    return _maps(size, color^, rough^, heights, 2.5)
