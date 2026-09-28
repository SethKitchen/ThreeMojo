# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A color from a color temperature, ported from three.js
`examples/jsm/utils/ColorUtils.js`.

`set_kelvin` gives the color of a black body at a temperature, by Tanner
Helland's fit, as three.js's `setKelvin` does. A candle flame is near
1900 K, a tungsten bulb near 3200 K, daylight near 6500 K and a clear blue
sky near 10000 K. The fit gives sRGB channels from 0 to 255, and the color
holds them decoded into linear light, as three.js's `setRGB( r, g, b,
SRGBColorSpace )` stores them in its linear working space.

Reference: https://tannerhelland.com/2012/09/18/convert-temperature-rgb-algorithm-code.html
"""

from render.framebuffer import FloatColor
from render.srgb import srgb_to_linear
from std.math import isfinite, log, pow
from units.temperature import KELVIN, Temperature

# The range the fit holds for. A temperature outside it is clamped to it,
# as three.js clamps it.
comptime COLDEST_KELVIN = Float64(1000)
comptime HOTTEST_KELVIN = Float64(40000)


def _channel(value: Float64) -> Float32:
    """Return one fitted channel from 0 to 255 as linear light."""
    return srgb_to_linear(Float32(min(max(value, 0), 255) / 255))


def set_kelvin(mut color: FloatColor, temperature: Temperature) raises:
    """Set a color from a color temperature, three.js's
    `ColorUtils.setKelvin`.

    The alpha is kept, as three.js's `Color` has none to change.

    Args:
        color: The color to set.
        temperature: The color temperature. Clamped to 1000 K to 40000 K.

    Raises:
        Error: If the temperature is not a number.
    """
    var kelvin = Float64(temperature.to(KELVIN))
    if not isfinite(kelvin):
        raise Error("A color temperature must be a number")
    var temp = min(max(kelvin, COLDEST_KELVIN), HOTTEST_KELVIN) / 100
    var red = Float64(255)
    var green: Float64
    if temp <= 66:
        green = 99.4708025861 * log(temp) - 161.1195681661
    else:
        red = 329.698727446 * pow(temp - 60, -0.1332047592)
        green = 288.1221695283 * pow(temp - 60, -0.0755148492)
    var blue = Float64(255)
    if temp < 66:
        blue = 0
        if temp > 19:
            blue = 138.5177312231 * log(temp - 10) - 305.0447927307
    color.r = _channel(red)
    color.g = _channel(green)
    color.b = _channel(blue)


def kelvin_color(temperature: Temperature) raises -> FloatColor:
    """Return the opaque color of a color temperature.

    Args:
        temperature: The color temperature. Clamped to 1000 K to 40000 K.

    Returns:
        The color, in linear light; see `set_kelvin`.

    Raises:
        Error: If the temperature is not a number.
    """
    var color = FloatColor(0.0, 0.0, 0.0)
    set_kelvin(color, temperature)
    return color
