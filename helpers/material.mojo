# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The material every colored helper is drawn with.

three.js builds one for each helper: a `LineBasicMaterial` that is white,
takes its colors from the geometry, and is not tone mapped. Here the
geometry carries the colors and the material is the same for all of them,
so it is built once and named by every helper's `Line`.

Tone mapping is applied once to every pixel of a frame here rather than
per material, so a helper under a tone curve is curved with the scene.
This material leaves `tone_mapped` on, where three.js's helpers turn it
off: under a curve, a frame that holds an untoned primitive beside a
blended one is refused; see `render.rasterizer.check_output_kinds`. Set
`tone_mapped` to False on the material to keep the curve off an opaque
helper.
"""

from materials.material import BASIC, Blending, Material
from render.framebuffer import Color


def helper_material(
    opacity: Float32 = 1.0,
    blending: Optional[Blending] = None,
    transparent: Bool = False,
) raises -> Material:
    """Return the material a colored helper is drawn with: white, unlit,
    and tinted by the geometry's `color` attribute at every vertex.

    Args:
        opacity: One for an opaque helper, less to see through it.
        blending: `OPAQUE` or `BLEND`, or unset to follow `transparent`.
        transparent: Whether the helper blends over what is behind it.

    Returns:
        The material, of kind `BASIC` with `vertex_colors` set.

    Raises:
        Error: If `opacity` is outside zero to one, or `blending` holds a
            value that is neither named constant.
    """
    return Material(
        Color(255, 255, 255),
        kind=BASIC,
        vertex_colors=True,
        opacity=opacity,
        blending=blending,
        transparent=transparent,
    )
