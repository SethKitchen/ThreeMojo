# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Which of a frame's draws a renderer draws, and the corners of a retro
frame snapped to its pixels: what three.js's `OITPassNode` and
`RetroPassNode` do with `setRenderObjectFunction` and a vertex node.

**The draw filter.** three.js's `OITPassNode` draws its scene twice. The
first draw leaves out every object whose material is order-independent,
`isOITCapable`: transparent, with normal blending, and no transmission.
The second draws those objects alone, over no background, into its
accumulation targets. A renderer's `draw_filter` says which of the two
it draws. `ONE_OIT_DRAW` draws one capable draw, the renderer's
`oit_draw`-th, so the composer can weigh each on its own.

**The snap.** three.js's `RetroPassNode` rounds each corner's place on the
screen to a whole pixel from the center, in its vertex node. A renderer
with `snap_vertices` on does the same to each corner of a frame before it
is drawn.
"""

from materials.material import BLEND, Material
from render.rasterizer import RasterVertex
from std.math import floor


@fieldwise_init
struct DrawFilter(Equatable, ImplicitlyCopyable, Writable):
    """Which of a frame's draws a renderer draws, as a type rather than a
    bare int. It does not stop `DrawFilter(9)`, which `check_draw_filter`
    refuses."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the three filters.

        Returns:
            Whether the value names a filter.
        """
        return self.value >= 0 and self.value <= 2


# Every draw: what a renderer draws by default.
comptime ALL_DRAWS = DrawFilter(0)
# Every draw but the order-independent ones: `OITPassNode`'s first draw.
comptime NO_OIT_DRAWS = DrawFilter(1)
# One order-independent draw alone, the renderer's `oit_draw`-th, over no
# background and cleared to transparent black.
comptime ONE_OIT_DRAW = DrawFilter(2)


def check_draw_filter(filter: DrawFilter, index: Int) raises:
    """Refuse a filter no renderer could draw with.

    Args:
        filter: The filter.
        index: The order-independent draw it names, for `ONE_OIT_DRAW`.

    Raises:
        Error: If the filter is none of the three, or the index is negative.
    """
    if not filter.is_valid():
        raise Error("A draw filter must be one of the three")
    if index < 0:
        raise Error("An order-independent draw's index must not be negative")


def oit_capable(material: Material) -> Bool:
    """Return True if a material is drawn order-independently: three.js's
    `isOITCapable`, transparent, with normal blending, and without
    transmission.

    Args:
        material: The material.

    Returns:
        Whether the OIT pass weighs it rather than blends it.
    """
    return (
        material.transparent
        and material.blending == BLEND
        and not (material.transmission > 0)
    )


def kept_draws(
    capable: List[Bool], filter: DrawFilter, index: Int
) -> List[Bool]:
    """Return which draws a filter keeps.

    Args:
        capable: Whether each draw's material is order-independent.
        filter: The filter.
        index: Which order-independent draw `ONE_OIT_DRAW` keeps, counted
            over the capable draws alone.

    Returns:
        One flag a draw.
    """
    var kept = List[Bool](capacity=len(capable))
    var seen = 0
    for at in range(len(capable)):
        var keep = True
        if filter == NO_OIT_DRAWS:
            keep = not capable[at]
        elif filter == ONE_OIT_DRAW:
            keep = capable[at] and seen == index
        if capable[at]:
            seen += 1
        kept.append(keep)
    return kept^


def snap_to_pixels(mut corners: List[RasterVertex], width: Int, height: Int):
    """Round each corner's place on the screen to a whole pixel from the
    screen's center: three.js's `RetroPassNode` vertex node, which rounds
    `xy / (2 w) * size` and scales it back.

    Args:
        corners: The frame's corners, in pixels, changed in place.
        width: The target's width in pixels.
        height: The target's height in pixels.
    """
    var half_w = Float32(width) * 0.5
    var half_h = Float32(height) * 0.5
    for at in range(len(corners)):
        corners[at].x = floor(corners[at].x - half_w + 0.5) + half_w
        corners[at].y = floor(corners[at].y - half_h + 0.5) + half_h
