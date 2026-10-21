# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Text, boxes, lines and arrows drawn on a rendered frame.

An `Overlay` draws in pixels, x right and y down, after the scene is
rendered. Every shape is a set of polygons filled by the even-odd rule.
Each pixel is sampled 4 by 4 times, so edges are smooth. The fill is
blended over the frame with an opacity.

Text is set in a TrueType font: the font's glyph contours become the
polygons. `text_width` measures a string so a caller can place it.

`project` with a camera puts a world point on the frame, so a label can
point at the part of the scene it names.
"""

from std.math import cos, floor, isfinite, pi, sin, sqrt
from math.vector2 import Vector2
from loaders.font import Font
from loaders.ttf import read_ttf
from render.framebuffer import Color, Framebuffer
from units.si import Length, METER

comptime _SUB = 4
comptime LEFT = 0
comptime CENTER = 1
comptime RIGHT = 2


def _blend(
    mut frame: Framebuffer, x: Int, y: Int, color: Color, cover: Float64
) raises:
    """Blend a color over one pixel by a coverage from zero to one."""
    if cover <= 0:
        return
    var a = min(cover, 1.0)
    var under = frame.get_pixel(x, y)
    var r = Float64(under.r) * (1 - a) + Float64(color.r) * a
    var g = Float64(under.g) * (1 - a) + Float64(color.g) * a
    var b = Float64(under.b) * (1 - a) + Float64(color.b) * a
    frame.set_pixel(
        x,
        y,
        Color(
            UInt8(Int(r + 0.5)),
            UInt8(Int(g + 0.5)),
            UInt8(Int(b + 0.5)),
            under.a,
        ),
    )


def _pixel_index(value: Float64) -> Int:
    """Return the floor of a pixel coordinate.

    A value that does not fit in an integer is past every pixel. `Int` of
    such a float is not that coordinate.

    Args:
        value: The coordinate, in pixels.

    Returns:
        The floor, or `Int.MAX` or `Int.MIN` when `value` does not fit.
    """
    if not (value < Float64(Int.MAX)):
        return Int.MAX
    if value <= -Float64(Int.MAX):
        return Int.MIN
    return Int(floor(value))


def fill_polygons(
    mut frame: Framebuffer,
    rings: List[List[Tuple[Float64, Float64]]],
    color: Color,
    opacity: Float64 = 1.0,
) raises:
    """Fill polygons by the even-odd rule, smoothed and blended.

    Args:
        frame: The frame to draw on.
        rings: The closed rings, in pixels; holes are rings too.
        color: The fill color.
        opacity: From zero, unseen, to one, opaque.

    Raises:
        Error: If a point is not finite.
    """
    var x_lo = Float64(1e30)
    var x_hi = Float64(-1e30)
    var y_lo = Float64(1e30)
    var y_hi = Float64(-1e30)
    for ring in rings:
        for p in ring:
            if not (isfinite(p[0]) and isfinite(p[1])):
                raise Error("An overlay point must be finite")
            x_lo = min(x_lo, p[0])
            x_hi = max(x_hi, p[0])
            y_lo = min(y_lo, p[1])
            y_hi = max(y_hi, p[1])
    if x_hi < x_lo:
        return
    var px0 = max(_pixel_index(x_lo), 0)
    var px1 = min(_pixel_index(x_hi), frame.width - 1)
    var py0 = max(_pixel_index(y_lo), 0)
    var py1 = min(_pixel_index(y_hi), frame.height - 1)
    if px1 < px0 or py1 < py0:
        return
    var span = px1 - px0 + 1
    var weight = opacity / Float64(_SUB * _SUB)
    # The box holds a pixel and a ring holds a point, after the checks
    # above, and _SUB is a positive constant, so these loops always run.
    for py in range(py0, py1 + 1):  # pragma: no branch
        var cover = List[Float64](length=span, fill=0)
        for s in range(_SUB):  # pragma: no branch
            var sy = Float64(py) + (Float64(s) + 0.5) / Float64(_SUB)
            var xs = List[Float64]()
            for ring in rings:  # pragma: no branch
                var n = len(ring)
                for i in range(n):
                    var a = ring[i]
                    var b = ring[(i + 1) % n]
                    if (a[1] > sy) != (b[1] > sy):
                        xs.append(
                            a[0] + (sy - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
                        )
            # Insertion sort: a row crosses few edges.
            for i in range(1, len(xs)):
                var v = xs[i]
                var j = i - 1
                while j >= 0 and xs[j] > v:
                    xs[j + 1] = xs[j]
                    j -= 1
                xs[j + 1] = v
            var k = 0
            while k + 1 < len(xs):
                var xa = xs[k]
                var xb = xs[k + 1]
                var first = max(_pixel_index(xa), px0)
                var last = min(_pixel_index(xb), px1)
                for px in range(first, last + 1):
                    for c in range(_SUB):  # pragma: no branch
                        var sx = Float64(px) + (Float64(c) + 0.5) / Float64(
                            _SUB
                        )
                        if sx >= xa and sx < xb:
                            cover[px - px0] += weight
                k += 2
        for i in range(span):  # pragma: no branch
            _blend(frame, px0 + i, py, color, cover[i])


def fill_rect(
    mut frame: Framebuffer,
    x0: Float64,
    y0: Float64,
    x1: Float64,
    y1: Float64,
    color: Color,
    opacity: Float64 = 1.0,
) raises:
    """Fill a rectangle.

    Args:
        frame: The frame.
        x0: The left edge, in pixels.
        y0: The top edge.
        x1: The right edge.
        y1: The bottom edge.
        color: The fill color.
        opacity: From zero to one.

    Raises:
        Error: If a coordinate is not finite.
    """
    var ring: List[Tuple[Float64, Float64]] = [
        (x0, y0),
        (x1, y0),
        (x1, y1),
        (x0, y1),
    ]
    fill_polygons(frame, [ring^], color, opacity)


def stroke_line(
    mut frame: Framebuffer,
    x0: Float64,
    y0: Float64,
    x1: Float64,
    y1: Float64,
    width: Float64,
    color: Color,
    opacity: Float64 = 1.0,
) raises:
    """Draw a straight line of a width, with square ends.

    Args:
        frame: The frame.
        x0: The start's x, in pixels.
        y0: The start's y.
        x1: The end's x.
        y1: The end's y.
        width: The line's width, in pixels.
        color: The color.
        opacity: From zero to one.

    Raises:
        Error: If a coordinate is not finite.
    """
    var dx = x1 - x0
    var dy = y1 - y0
    var length = sqrt(dx * dx + dy * dy)
    if not (length > 1e-9):
        return
    var nx = -dy / length * width / 2
    var ny = dx / length * width / 2
    var ring: List[Tuple[Float64, Float64]] = [
        (x0 + nx, y0 + ny),
        (x1 + nx, y1 + ny),
        (x1 - nx, y1 - ny),
        (x0 - nx, y0 - ny),
    ]
    fill_polygons(frame, [ring^], color, opacity)


def fill_disc(
    mut frame: Framebuffer,
    x: Float64,
    y: Float64,
    radius: Float64,
    color: Color,
    opacity: Float64 = 1.0,
) raises:
    """Fill a circle.

    Args:
        frame: The frame.
        x: The center's x, in pixels.
        y: The center's y.
        radius: The radius, in pixels.
        color: The color.
        opacity: From zero to one.

    Raises:
        Error: If a coordinate is not finite.
    """
    var ring = List[Tuple[Float64, Float64]]()
    for k in range(32):
        var t = 2 * pi * Float64(k) / 32
        ring.append((x + radius * cos(t), y + radius * sin(t)))
    fill_polygons(frame, [ring^], color, opacity)


def arrow(
    mut frame: Framebuffer,
    x0: Float64,
    y0: Float64,
    x1: Float64,
    y1: Float64,
    width: Float64,
    color: Color,
    opacity: Float64 = 1.0,
) raises:
    """Draw an arrow from one point to a head at another.

    Args:
        frame: The frame.
        x0: The tail's x, in pixels.
        y0: The tail's y.
        x1: The head's x.
        y1: The head's y.
        width: The shaft's width; the head is four times as wide.
        color: The color.
        opacity: From zero to one.

    Raises:
        Error: If a coordinate is not finite.
    """
    var dx = x1 - x0
    var dy = y1 - y0
    var length = sqrt(dx * dx + dy * dy)
    if not (length > 1e-9):
        return
    var ux = dx / length
    var uy = dy / length
    var head = min(width * 4, length * 0.6)
    var bx = x1 - ux * head
    var by = y1 - uy * head
    stroke_line(frame, x0, y0, bx, by, width, color, opacity)
    var ring: List[Tuple[Float64, Float64]] = [
        (x1, y1),
        (bx - uy * head * 0.5, by + ux * head * 0.5),
        (bx + uy * head * 0.5, by - ux * head * 0.5),
    ]
    fill_polygons(frame, [ring^], color, opacity)


struct Overlay(Movable):
    """A font, for drawing text on frames."""

    var font: Font

    def __init__(out self, var font: Font):
        """Use a font.

        Args:
            font: The font.
        """
        self.font = font^

    @staticmethod
    def from_ttf(path: String) raises -> Overlay:
        """Load a TrueType font.

        Args:
            path: The .ttf file.

        Returns:
            An overlay in that font.

        Raises:
            Error: If the font cannot be read.
        """
        return Overlay(read_ttf(path))

    def _rings(
        self, text: String, size: Float64
    ) raises -> List[List[Tuple[Float64, Float64]]]:
        """Return a string's glyph outlines, in em units scaled to size."""
        var out = List[List[Tuple[Float64, Float64]]]()
        if text.byte_length() == 0:
            return out^
        # Every contour of every glyph, filled by the even-odd rule, draws
        # the holes whatever order the font lists its contours in.
        # Sorting contours into shapes with holes, as `to_shapes` does,
        # drops a hole a font lists before its outline.
        var paths = self.font.generate_paths(text, Length(Float32(size), METER))
        for path in paths:
            for sub in path.sub_paths:
                # A glyph's outline starts only when it draws, so each one
                # has a curve, and sampling it gives two points at least.
                var pts = sub.sample(4)
                var ring = List[Tuple[Float64, Float64]]()
                for p in pts:  # pragma: no branch
                    ring.append((Float64(p.x), Float64(p.y)))
                if len(ring) >= 3:
                    out.append(ring^)
        return out^

    def text_width(self, text: String, size: Float64) raises -> Float64:
        """Return how wide a string is drawn.

        Args:
            text: The string.
            size: The em size, in pixels.

        Returns:
            The width of its ink, in pixels.
        """
        var rings = self._rings(text, size)
        var hi = Float64(0)
        # Each ring has three points at least.
        for r in rings:
            for p in r:  # pragma: no branch
                hi = max(hi, p[0])
        return hi

    def text(
        self,
        mut frame: Framebuffer,
        text: String,
        x: Float64,
        baseline: Float64,
        size: Float64,
        color: Color,
        anchor: Int = LEFT,
        opacity: Float64 = 1.0,
    ) raises:
        """Draw a string.

        Args:
            frame: The frame.
            text: The string; one line.
            x: Where the anchor goes, in pixels.
            baseline: The baseline's y, in pixels.
            size: The em size, in pixels.
            color: The color.
            anchor: LEFT, CENTER or RIGHT.
            opacity: From zero to one.

        Raises:
            Error: If the font has no glyph for a character.
        """
        var rings = self._rings(text, size)
        if len(rings) == 0:
            return
        var width = Float64(0)
        # There is a ring, and each has three points at least, so these
        # loops always run.
        for r in rings:  # pragma: no branch
            for p in r:  # pragma: no branch
                width = max(width, p[0])
        var left = x
        if anchor == CENTER:
            left = x - width / 2
        elif anchor == RIGHT:
            left = x - width
        var placed = List[List[Tuple[Float64, Float64]]]()
        for r in rings:  # pragma: no branch
            var ring = List[Tuple[Float64, Float64]]()
            for p in r:  # pragma: no branch
                ring.append((left + p[0], baseline - p[1]))
            placed.append(ring^)
        fill_polygons(frame, placed, color, opacity)

    def label(
        self,
        mut frame: Framebuffer,
        lines: List[String],
        x: Float64,
        y: Float64,
        size: Float64,
        color: Color,
        background: Color,
        opacity: Float64 = 0.82,
        accent: Optional[Color] = None,
    ) raises -> Tuple[Float64, Float64]:
        """Draw lines of text on a box whose top left is at (x, y).

        Args:
            frame: The frame.
            lines: The lines, top first.
            x: The box's left, in pixels.
            y: The box's top.
            size: The em size, in pixels.
            color: The text color.
            background: The box color.
            opacity: The box's opacity.
            accent: A color for a bar down the box's left side, if any.

        Returns:
            The box's width and height.

        Raises:
            Error: If the font has no glyph for a character.
        """
        var pad = size * 0.45
        var line_height = size * 1.25
        var width = Float64(0)
        for line in lines:
            width = max(width, self.text_width(line, size))
        var bar = size * 0.3 if accent else 0.0
        var w = width + 2 * pad + bar
        var h = Float64(len(lines)) * line_height + pad * 1.2
        fill_rect(frame, x, y, x + w, y + h, background, opacity)
        if accent:
            fill_rect(frame, x, y, x + bar, y + h, accent.value(), 1.0)
        for i in range(len(lines)):
            self.text(
                frame,
                lines[i],
                x + bar + pad,
                y + pad * 0.6 + Float64(i + 1) * line_height - size * 0.28,
                size,
                color,
            )
        return (w, h)
