# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Hue, saturation and value, from three.js
`examples/jsm/math/ColorConverter.js`.

HSV is the color model of most color pickers. Value one is the pure hue at
full saturation, and white at none. three.js converts it through HSL:
`set_hsv` turns the three numbers into a hue, a saturation and a lightness
and sets the color from those, and `get_hsv` takes the color's HSL apart
the other way. Both work in the linear working space, as three.js's
`setHSL` and `getHSL` do by default.

One difference from three.js. Black and white have no saturation, and
three.js's arithmetic divides zero by zero for both. `setHSV` then gives a
color that is not a number, and `getHSV` a saturation that is not a
number. Here both give a saturation of zero, which is the answer the
arithmetic approaches. Every other input gives three.js's numbers.
"""

from render.framebuffer import FloatColor
from std.math import floor


@fieldwise_init
struct HSV(ImplicitlyCopyable):
    """A color as hue, saturation and value, each nominally zero to one.

    Hue runs once around the wheel from red through green and blue back to
    red. A value of zero is black; a value of one with no saturation is
    white.
    """

    var hue: Float32
    var saturation: Float32
    var value: Float32


def set_hsv(
    mut color: FloatColor, hue: Float32, saturation: Float32, value: Float32
) raises:
    """Set a color from hue, saturation and value, three.js's
    `ColorConverter.setHSV`.

    The hue wraps around the wheel, so 1.25 is 0.25; the saturation and the
    value are clamped to zero to one. The color's alpha is kept.

    Args:
        color: The color to set.
        hue: Where on the wheel.
        saturation: Zero for gray, one for the pure hue.
        value: Zero for black, one for the brightest.

    Raises:
        Error: Never; `FloatColor`'s HSL constructor raises only for a
            color space other than the two it takes.
    """
    var h = hue - floor(hue)
    var s = min(max(saturation, Float32(0)), Float32(1))
    var v = min(max(value, Float32(0)), Float32(1))
    var twice = (2 - s) * v
    var spread = twice if twice < 1 else 2 - twice
    # three.js divides zero by zero here for black and for white.
    var hsl_saturation = s * v / spread if spread != 0 else Float32(0)
    var alpha = color.a
    color = FloatColor(hue=h, saturation=hsl_saturation, lightness=twice / 2)
    color.a = alpha


def get_hsv(color: FloatColor) raises -> HSV:
    """Return a color as hue, saturation and value, three.js's
    `ColorConverter.getHSV`.

    Args:
        color: The color, in the linear working space.

    Returns:
        The three numbers. Black has a saturation of zero, where three.js
        gives a number that is not a number.

    Raises:
        Error: Never; `FloatColor.hsl` raises only for a color space other
            than the two it takes.
    """
    var hsl = color.hsl()
    var lightness = hsl.lightness
    var scaled = hsl.saturation * (
        lightness if lightness < 0.5 else 1 - lightness
    )
    var total = lightness + scaled
    # three.js divides zero by zero here for black.
    var saturation = 2 * scaled / total if total != 0 else Float32(0)
    return HSV(hsl.hue, saturation, total)
