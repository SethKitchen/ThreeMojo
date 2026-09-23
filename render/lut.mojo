# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Color maps, from three.js `examples/jsm/math/Lut.js`.

A color map turns a number into a color: a temperature into blue through
red, a stress into a heat color. A `Lut` samples a map at `n + 1` evenly
spaced points once, and `get_color` then finds the nearest sample for a
value between `min_v` and `max_v`. This is not the `.cube` table of
`loaders.lut_cube`, which grades the colors of a whole frame.

A map is a list of stops: a position from zero to one and a color as a hex
number. The four presets are three.js's: `RAINBOW`, `COOL_TO_WARM`,
`BLACKBODY` and `GRAYSCALE`. A custom map takes the place of three.js's
`addColorMap`.

**three.js's colors, kept.** three.js reads the first and the last stop with
`new Color(hex)`, which decodes sRGB into linear light, and every sample
between with `setHex(hex, LinearSRGBColorSpace)`, which does not. The two
ends of `COOL_TO_WARM` are therefore darker than the stops next to them. The
port keeps this, so a color here is the color three.js gives. `canvas_pixels`
reads every stop without decoding, as three.js's `updateCanvas` does.

**Refusals.** A preset that is not one of the four is refused: three.js
falls back to the rainbow for a name it does not know. A count below one, a
range of no width, a value that is not a number, and a custom map that does
not run from zero to one in order are refused. three.js gives no color for
them.
"""

from render.color_spaces import srgb_to_linear_three
from render.framebuffer import FloatColor
from std.benchmark import black_box
from std.math import floor, isfinite, max, min


@fieldwise_init
struct ColorMapName(Equatable, ImplicitlyCopyable, Writable):
    """Which preset color map, as a type rather than a bare int. three.js
    names a map with a string.

    See `core.object3d.NodeId` for why these are wrapped.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the presets below.

        Returns:
            Whether the value names a preset.
        """
        return self.value >= 0 and self.value <= 3


# Blue, cyan, green, yellow, red. three.js: `'rainbow'`.
comptime RAINBOW = ColorMapName(0)
# Blue through gray to red. three.js: `'cooltowarm'`.
comptime COOL_TO_WARM = ColorMapName(1)
# Black, red, yellow, white. three.js: `'blackbody'`.
comptime BLACKBODY = ColorMapName(2)
# Black to white. three.js: `'grayscale'`.
comptime GRAYSCALE = ColorMapName(3)


@fieldwise_init
struct ColorStop(ImplicitlyCopyable):
    """One stop of a color map: where, and which color."""

    # From zero to one.
    var position: Float64
    # The color as `0xRRGGBB`.
    var hex: Int


def color_map(name: ColorMapName) raises -> List[ColorStop]:
    """Return a preset's stops. three.js: `ColorMapKeywords`.

    Args:
        name: The preset.

    Returns:
        Its stops, in order.

    Raises:
        Error: If the value names no preset.
    """
    if not name.is_valid():
        raise Error("Not a color map: " + String(name.value))
    var hexes: List[Int]
    if name == RAINBOW:
        hexes = [0x0000FF, 0x00FFFF, 0x00FF00, 0xFFFF00, 0xFF0000]
    elif name == COOL_TO_WARM:
        hexes = [0x3C4EC2, 0x9BBCFF, 0xDCDCDC, 0xF6A385, 0xB40426]
    elif name == BLACKBODY:
        hexes = [0x000000, 0x780000, 0xE63200, 0xFFFF00, 0xFFFFFF]
    else:
        hexes = [0x000000, 0x404040, 0x7F7F80, 0xBFBFBF, 0xFFFFFF]
    var positions: List[Float64] = [0.0, 0.2, 0.5, 0.8, 1.0]
    var stops = List[ColorStop]()
    for index in range(5):  # pragma: no branch
        stops.append(ColorStop(positions[index], hexes[index]))
    return stops^


def check_color_map(stops: List[ColorStop]) raises:
    """Refuse a map that does not run from zero to one in order.

    Args:
        stops: The map.

    Raises:
        Error: If it has fewer than two stops, does not start at zero or
            end at one, goes back, or has a color that is not `0xRRGGBB`.
    """
    if len(stops) < 2:
        raise Error("A color map needs two stops or more")
    var ends = stops[0].position == 0 and stops[len(stops) - 1].position == 1
    if not ends:
        raise Error("A color map must start at zero and end at one")
    for index in range(len(stops)):  # pragma: no branch
        var hex = stops[index].hex
        if hex < 0 or hex > 0xFFFFFF:
            raise Error("A color stop's color must be 0xRRGGBB")
        if index > 0 and not (
            stops[index].position >= stops[index - 1].position
        ):
            raise Error("A color map's stops must go from zero to one")


def _channels(hex: Int) -> Tuple[Float64, Float64, Float64]:
    """Return a hex color's channels from zero to one, undecoded. three.js:
    `setHex(hex, LinearSRGBColorSpace)`.

    Args:
        hex: The color as `0xRRGGBB`.

    Returns:
        Red, green and blue.
    """
    return (
        Float64((hex >> 16) & 255) / 255,
        Float64((hex >> 8) & 255) / 255,
        Float64(hex & 255) / 255,
    )


def _decoded(hex: Int) -> FloatColor:
    """Return a hex color decoded from sRGB. three.js: `new Color(hex)`.

    Args:
        hex: The color as `0xRRGGBB`.

    Returns:
        The color in linear light.
    """
    var c = _channels(hex)
    return FloatColor(
        Float32(srgb_to_linear_three(c[0])),
        Float32(srgb_to_linear_three(c[1])),
        Float32(srgb_to_linear_three(c[2])),
    )


def _mix(
    low: ColorStop, high: ColorStop, at: Float64
) -> Tuple[Float64, Float64, Float64]:
    """Return the color between two stops, undecoded. three.js:
    `lerpColors`.

    Args:
        low: The stop below.
        high: The stop above.
        at: The position between them.

    Returns:
        Red, green and blue.
    """
    var t = (at - low.position) / (high.position - low.position)
    var a = _channels(low.hex)
    var b = _channels(high.hex)
    # The barrier keeps each product rounded on its own, as JavaScript
    # rounds it. A fused multiply-add rounds once, and a channel on a
    # midpoint of `canvas_pixels` then rounds the other way.
    return (
        a[0] + black_box((b[0] - a[0]) * t),
        a[1] + black_box((b[1] - a[1]) * t),
        a[2] + black_box((b[2] - a[2]) * t),
    )


def _round(x: Float64) -> Int:
    """Return JavaScript's `Math.round`: to the nearest whole number, a half
    up.

    Args:
        x: The number.

    Returns:
        The whole number.
    """
    var whole = floor(x)
    return Int(whole) + (1 if x - whole >= 0.5 else 0)


struct Lut(Copyable, Movable):
    """A color map sampled at evenly spaced points. three.js: `Lut`."""

    # The samples, `n + 1` of them, from zero to one.
    var lut: List[FloatColor]
    # The map's stops.
    var map: List[ColorStop]
    # How many steps between the samples.
    var n: Int
    # The value that maps to the first sample.
    var min_v: Float64
    # The value that maps to the last sample.
    var max_v: Float64

    def __init__(
        out self, name: ColorMapName = RAINBOW, count: Int = 32
    ) raises:
        """Create a table of a preset. three.js: the constructor.

        Args:
            name: The preset.
            count: How many steps; the table holds one more sample.

        Raises:
            Error: If the value names no preset or the count is below one.
        """
        self.lut = List[FloatColor]()
        self.map = List[ColorStop]()
        self.n = 0
        self.min_v = 0
        self.max_v = 1
        self.set_color_map(name, count)

    def __init__(out self, var stops: List[ColorStop], count: Int = 32) raises:
        """Create a table of a custom map. three.js: `addColorMap`, then
        `setColorMap` with its name.

        Args:
            stops: The map.
            count: How many steps.

        Raises:
            Error: If the map is refused by `check_color_map`, or the count
                is below one.
        """
        self.lut = List[FloatColor]()
        self.map = List[ColorStop]()
        self.n = 0
        self.min_v = 0
        self.max_v = 1
        self.set_custom_map(stops^, count)

    def set_color_map(mut self, name: ColorMapName, count: Int = 32) raises:
        """Sample a preset. three.js: `setColorMap`.

        Args:
            name: The preset.
            count: How many steps.

        Raises:
            Error: If the value names no preset or the count is below one.
        """
        self.set_custom_map(color_map(name), count)

    def set_custom_map(
        mut self, var stops: List[ColorStop], count: Int = 32
    ) raises:
        """Sample a custom map. three.js: `setColorMap` of a map that
        `addColorMap` added.

        Args:
            stops: The map.
            count: How many steps.

        Raises:
            Error: If the map is refused by `check_color_map`, or the count
                is below one.
        """
        check_color_map(stops)
        if count < 1:
            raise Error("A color table needs one step or more")
        var step = 1.0 / Float64(count)
        var lut = List[FloatColor]()
        lut.append(_decoded(stops[0].hex))
        for i in range(1, count):
            var alpha = Float64(i) * step
            for j in range(len(stops) - 1):  # pragma: no branch
                var inside = (
                    alpha > stops[j].position and alpha <= stops[j + 1].position
                )
                if inside:
                    var c = _mix(stops[j], stops[j + 1], alpha)
                    lut.append(
                        FloatColor(Float32(c[0]), Float32(c[1]), Float32(c[2]))
                    )
        lut.append(_decoded(stops[len(stops) - 1].hex))
        self.lut = lut^
        self.map = stops^
        self.n = count

    def set_min(mut self, value: Float64) raises:
        """Set the value that maps to the first color. three.js: `setMin`.

        Args:
            value: The value.

        Raises:
            Error: If it is not finite.
        """
        if not isfinite(value):
            raise Error("A color table's range must be finite")
        self.min_v = value

    def set_max(mut self, value: Float64) raises:
        """Set the value that maps to the last color. three.js: `setMax`.

        Args:
            value: The value.

        Raises:
            Error: If it is not finite.
        """
        if not isfinite(value):
            raise Error("A color table's range must be finite")
        self.max_v = value

    def get_color(self, alpha: Float64) raises -> FloatColor:
        """Return the color of a value. three.js: `getColor`.

        The value is clamped to the range, and the nearest sample is given.

        Args:
            alpha: The value.

        Returns:
            The color.

        Raises:
            Error: If the value is not a number, or the range has no width.
        """
        if alpha != alpha:
            raise Error(
                "A color table cannot look up a value that is not a number"
            )
        if self.max_v == self.min_v:
            raise Error("A color table's range needs some width")
        var clamped = max(self.min_v, min(self.max_v, alpha))
        var at = (clamped - self.min_v) / (self.max_v - self.min_v)
        return self.lut[_round(at * Float64(self.n))]

    def canvas_pixels(self) -> List[UInt8]:
        """Return the table as an image one pixel wide and `n` high, RGBA,
        top row first. three.js: `createCanvas` and `updateCanvas`.

        The top row is the top of the map. Each row is the map at a value
        stepped down from one, undecoded, as three.js draws it. A row the
        steps do not reach stays opaque black.

        Returns:
            `4 * n` bytes.
        """
        var data = List[UInt8](length=self.n * 4, fill=0)
        # `n` is one or more.
        for row in range(self.n):  # pragma: no branch
            data[row * 4 + 3] = 255
        var k = 0
        var step = 1.0 / Float64(self.n)
        # The value steps from one down to zero, three.js's loop. One, the
        # top, is inside no stop, so at most `n` rows are drawn.
        var i = 1.0
        while i >= 0:
            var j = len(self.map) - 1
            while j >= 1:
                var inside = (
                    i < self.map[j].position and i >= self.map[j - 1].position
                )
                if inside:
                    var c = _mix(self.map[j - 1], self.map[j], i)
                    data[k * 4] = UInt8(_round(c[0] * 255))
                    data[k * 4 + 1] = UInt8(_round(c[1] * 255))
                    data[k * 4 + 2] = UInt8(_round(c[2] * 255))
                    k += 1
                j -= 1
            i -= step
        return data^
