# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Draw in a working color space of sRGB, as the three.js splat example does.

The renderer's colors are linear light. It decodes an authored color from sRGB
when it makes a target, and it encodes the light to sRGB when it resolves the
target. The three.js example `webgpu_gaussian_splat` sets
`ColorManagement.workingColorSpace` to `SRGBColorSpace` instead. Its colors,
its background and its blending are all in sRGB values, and its output is the
same values. A splat scan stores colors that look right blended that way.

`srgb_working_target` makes a target whose background is the given color as it
is, and `resolve_srgb_working` writes the target out without a transfer
function. A frame drawn between the two blends the values that the scan stores,
and shows them unchanged.
"""

from render.color_spaces import LINEAR_SRGB_COLOR_SPACE, output_encoding
from render.framebuffer import Color, FloatColor, Framebuffer
from render.target import RenderTarget


def srgb_working_target(
    width: Int, height: Int, background: Color
) raises -> RenderTarget:
    """Make a target that holds sRGB values, cleared to a color as it is.

    Args:
        width: The image width, in pixels.
        height: The image height, in pixels.
        background: The color to clear to. Its bytes are used as they are,
            with no decoding. Its alpha is kept.

    Returns:
        The target.

    Raises:
        Error: If either dimension is not positive.
    """
    var target = RenderTarget(width, height, background)
    var clear = FloatColor(of=background).premultiplied()
    target.clear = clear
    target.colors = List[FloatColor](length=width * height, fill=clear)
    return target^


def resolve_srgb_working(target: RenderTarget) raises -> Framebuffer:
    """Write out a target that holds sRGB values, with no transfer function.

    Args:
        target: The target, made by `srgb_working_target` and drawn into.

    Returns:
        The image, in the values that the target holds.

    Raises:
        Error: If the target cannot be resolved.
    """
    return target.resolve(output=output_encoding(LINEAR_SRGB_COLOR_SPACE))
