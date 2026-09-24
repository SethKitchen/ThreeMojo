# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The scene as text: three.js's `AsciiEffect` from `examples/jsm/effects/`.

`AsciiEffect` draws the scene with a renderer and shrinks the image by its
resolution, as three.js draws its canvas into a smaller one. Each pixel of
every other row of the small image becomes one character. The character
is picked from a character set by the pixel's brightness: a dark pixel
takes a character near the end of the set, and a bright one a character
near the start.

three.js writes the result into an HTML table. `AsciiImage.text` returns
the characters as lines of plain text. `AsciiImage.html` returns the
markup three.js writes into the table cell, with a `span` for each
character when the color option is on.

**The shrink.** A browser's `drawImage` shrinks a canvas by a filter that
the browser picks. This port averages the pixels whose centers fall in a
small pixel's area, weighted by their alpha, so the result does not depend
on a browser.
"""

from cameras.camera import Camera
from core.assets import Assets
from core.scene import Scene
from render.framebuffer import Color, Framebuffer
from renderers.renderer import Renderer
from std.math import floor, isfinite

# The character set three.js's constructor takes by default.
comptime ASCII_CHARACTERS = " .:-+*=%@#"
# The set three.js falls back to when it is given an empty one.
comptime ASCII_FALLBACK = " .,:;i1tfLCG08@"
# The fallback when the color option is on.
comptime ASCII_COLOR_FALLBACK = " CGO08@"


def ascii_brightness(color: Color) -> Float32:
    """Return the brightness three.js's `AsciiEffect` reads from a pixel.

    Args:
        color: The pixel, in sRGB bytes.

    Returns:
        `0.3` red, `0.59` green and `0.11` blue over 255: zero for black
        and one for white. A pixel with an alpha of zero is one, as
        three.js's `asciifyImage` sets it.
    """
    if color.a == 0:
        return 1
    return (
        0.3 * Float32(color.r)
        + 0.59 * Float32(color.g)
        + 0.11 * Float32(color.b)
    ) / 255


def ascii_index(brightness: Float32, count: Int, invert: Bool) -> Int:
    """Return which character of a set a brightness picks:
    `Math.floor((1 - brightness) * (count - 1))`, the other way round
    when `invert` is on.

    Args:
        brightness: The pixel's brightness, zero to one.
        count: How many characters the set has, at least one.
        invert: Whether a bright pixel picks from the end of the set.

    Returns:
        The index, zero through `count - 1`.
    """
    var index = Int(floor((1 - brightness) * Float32(count - 1)))
    if invert:
        return count - index - 1
    return index


def ascii_characters(characters: String, color: Bool) -> List[String]:
    """Return a character set as one string per character, as three.js's
    `charSet.split('')` returns it.

    Args:
        characters: The set. An empty set is three.js's fallback.
        color: Whether the color option is on, which picks the fallback.

    Returns:
        The characters.
    """
    var chosen = characters
    if chosen.byte_length() == 0:
        chosen = ASCII_FALLBACK
        if color:
            chosen = ASCII_COLOR_FALLBACK
    var split = List[String]()
    for character in chosen.codepoint_slices():  # pragma: no branch
        split.append(String(character))
    return split^


def ascii_size(size: Int, resolution: Float32) -> Int:
    """Return the small image's width or height: three.js's
    `Math.floor(size * resolution)`.

    Args:
        size: The renderer's width or height.
        resolution: The effect's resolution.

    Returns:
        The size in pixels, which can be zero.
    """
    return Int(floor(Float32(size) * resolution))


def _first_center(edge: Int, size: Int, small: Int) -> Int:
    """Return the first pixel whose center is at or past a small pixel's
    edge: `ceil(edge * size / small - 0.5)`."""
    return (2 * edge * size + small - 1) // (2 * small)


def shrink(image: Framebuffer, width: Int, height: Int) raises -> List[Color]:
    """Return an image shrunk to `width` by `height`: each small pixel the
    average of the pixels whose centers fall in its area, weighted by
    their alpha.

    Args:
        image: The image, at least as large each way.
        width: The small width, at least one.
        height: The small height, at least one.

    Returns:
        The small pixels, row by row from the top. A small pixel that
        covers only transparent pixels is transparent black.

    Raises:
        Error: If the small size is not positive or is larger than the
            image.
    """
    if width < 1 or height < 1 or width > image.width or height > image.height:
        raise Error("A shrunk image must be from one pixel to the image's size")
    var small = List[Color](capacity=width * height)
    for y in range(height):  # pragma: no branch
        var top = _first_center(y, image.height, height)
        var bottom = _first_center(y + 1, image.height, height)
        for x in range(width):  # pragma: no branch
            var left = _first_center(x, image.width, width)
            var right = _first_center(x + 1, image.width, width)
            var r = Float32(0)
            var g = Float32(0)
            var b = Float32(0)
            var a = Float32(0)
            var count = 0
            for sy in range(top, bottom):  # pragma: no branch
                for sx in range(left, right):  # pragma: no branch
                    var pixel = image.get_pixel(sx, sy)
                    var alpha = Float32(pixel.a)
                    r += Float32(pixel.r) * alpha
                    g += Float32(pixel.g) * alpha
                    b += Float32(pixel.b) * alpha
                    a += alpha
                    count += 1
            if a == 0:
                small.append(Color(0, 0, 0, 0))
            else:
                small.append(
                    Color(
                        UInt8(Int(r / a + 0.5)),
                        UInt8(Int(g / a + 0.5)),
                        UInt8(Int(b / a + 0.5)),
                        UInt8(Int(a / Float32(count) + 0.5)),
                    )
                )
    return small^


struct AsciiImage(Movable):
    """What `AsciiEffect` produces: one character, and the color it was
    read from, for each cell."""

    # How many characters each line holds.
    var columns: Int
    # How many lines there are.
    var rows: Int
    # The characters, line by line from the top.
    var characters: List[String]
    # The small image's pixel under each character, in sRGB bytes.
    var colors: List[Color]
    # The options `html` reads.
    var color: Bool
    var alpha: Bool
    var block: Bool

    def __init__(
        out self,
        columns: Int,
        rows: Int,
        var characters: List[String],
        var colors: List[Color],
        color: Bool = False,
        alpha: Bool = False,
        block: Bool = False,
    ):
        """Hold the cells of an image.

        Args:
            columns: How many characters each line holds.
            rows: How many lines there are.
            characters: The characters, `columns` times `rows`.
            colors: The color under each character.
            color: Whether `html` colors each character.
            alpha: Whether `html` gives each character its opacity.
            block: Whether `html` fills each character's background.
        """
        self.columns = columns
        self.rows = rows
        self.characters = characters^
        self.colors = colors^
        self.color = color
        self.alpha = alpha
        self.block = block

    def text(self) -> String:
        """Return the characters as lines of plain text, each line ended
        by a newline.

        Returns:
            The text.
        """
        var out = String()
        for row in range(self.rows):  # pragma: no branch
            for column in range(self.columns):  # pragma: no branch
                out += self.characters[row * self.columns + column]
            out += "\n"
        return out^

    def html(self) -> String:
        """Return the markup three.js's `asciifyImage` writes into the
        table cell.

        A space is `&nbsp;` and a line ends with `<br/>`. With the color
        option on, each character is a `span` in its cell's color, with
        that color as its background when the block option is on and
        with its opacity when the alpha option is on.

        Returns:
            The markup.
        """
        var out = String()
        for row in range(self.rows):  # pragma: no branch
            for column in range(self.columns):  # pragma: no branch
                var slot = row * self.columns + column
                var character = self.characters[slot]
                if character == " ":
                    character = "&nbsp;"
                if not self.color:
                    out += character
                    continue
                var c = self.colors[slot]
                var rgb = String(
                    "rgb(", Int(c.r), ",", Int(c.g), ",", Int(c.b), ")"
                )
                out += "<span style='color:" + rgb + ";"
                if self.block:
                    out += "background-color:" + rgb + ";"
                if self.alpha:
                    out += "opacity:" + String(Float32(c.a) / 255) + ";"
                out += "'>" + character + "</span>"
            out += "<br/>"
        return out^


struct AsciiEffect(Movable):
    """The scene drawn as characters: three.js's `AsciiEffect`."""

    # The character set, darkest last: three.js's `charSet`.
    var characters: List[String]
    # The small image's size as a fraction of the renderer's:
    # `resolution`, 0.15 by default.
    var resolution: Float32
    # `color`: whether `AsciiImage.html` colors each character.
    var color: Bool
    # `alpha`: whether it gives each character its opacity.
    var alpha: Bool
    # `block`: whether it fills each character's background.
    var block: Bool
    # `invert`: whether a bright pixel picks from the end of the set.
    var invert: Bool

    def __init__(
        out self,
        characters: String = ASCII_CHARACTERS,
        resolution: Float32 = 0.15,
        color: Bool = False,
        alpha: Bool = False,
        block: Bool = False,
        invert: Bool = False,
    ) raises:
        """Take three.js's constructor arguments: the character set and
        the options.

        Args:
            characters: The character set, darkest last. An empty set is
                three.js's fallback.
            resolution: The small image's size as a fraction of the
                renderer's, above zero and at most one.
            color: Whether `AsciiImage.html` colors each character.
            alpha: Whether it gives each character its opacity.
            block: Whether it fills each character's background.
            invert: Whether a bright pixel picks from the end of the set.

        Raises:
            Error: If the resolution is not finite or not above zero and
                at most one.
        """
        if not isfinite(resolution) or resolution <= 0 or resolution > 1:
            raise Error("An ASCII resolution runs above zero to one")
        self.characters = ascii_characters(characters, color)
        self.resolution = resolution
        self.color = color
        self.alpha = alpha
        self.block = block
        self.invert = invert

    def asciify(self, image: Framebuffer) raises -> AsciiImage:
        """Turn a drawn image into characters: three.js's `asciifyImage`.

        The image is shrunk by the resolution. Every other row of the
        small image, from the top, becomes a line, and each of its pixels
        a character.

        Args:
            image: The drawn image.

        Returns:
            The characters.

        Raises:
            Error: If the image shrinks to nothing either way.
        """
        var width = ascii_size(image.width, self.resolution)
        var height = ascii_size(image.height, self.resolution)
        if width < 1 or height < 1:
            raise Error("The image is too small for that ASCII resolution")
        var small = shrink(image, width, height)
        var rows = (height + 1) // 2
        var characters = List[String](capacity=width * rows)
        var colors = List[Color](capacity=width * rows)
        for row in range(rows):  # pragma: no branch
            for x in range(width):  # pragma: no branch
                var pixel = small[row * 2 * width + x]
                var index = ascii_index(
                    ascii_brightness(pixel), len(self.characters), self.invert
                )
                characters.append(self.characters[index])
                colors.append(pixel)
        return AsciiImage(
            width,
            rows,
            characters^,
            colors^,
            self.color,
            self.alpha,
            self.block,
        )

    def render[
        C: Camera
    ](
        self, renderer: Renderer, scene: Scene, assets: Assets, camera: C
    ) raises -> AsciiImage:
        """Draw the scene and turn it into characters: three.js's
        `render`.

        Args:
            renderer: What the scene is drawn with.
            scene: The scene.
            assets: The geometry, materials and textures it names.
            camera: The camera.

        Returns:
            The characters.

        Raises:
            Error: Everything `Renderer.render` and `asciify` raise.
        """
        return self.asciify(renderer.render(scene, assets, camera))
