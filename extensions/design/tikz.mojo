# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The body of a TikZ drawing, built from a model.

A drawing sheet sets the scale with the `x` and `y` keys of its
`tikzpicture` and then inputs a body. A `TikzBody` writes that body: the
commands in model units, such as inches of the building. The styles are
names that the sheet's preamble defines, such as `wl` for a wall line or
`steel` for a steel fill. So one model makes the plan, the sections and
the details in the house style of the sheet.

The dimension commands call the sheet's `\\dimline` and `\\dimlinev`
macros, which draw the arrows, the extension ticks and the label.
"""

from std.pathlib import Path
from loaders.js_number import js_to_fixed


def _n(value: Float64) raises -> String:
    """Return a coordinate with two decimals."""
    if not (value > -Float64.MAX and value < Float64.MAX):
        raise Error("A drawing coordinate must be finite")
    return js_to_fixed(value, 2)


def _point(x: Float64, y: Float64) raises -> String:
    """Return a TikZ point."""
    return "(" + _n(x) + "," + _n(y) + ")"


struct TikzBody(Movable):
    """The commands of a TikZ drawing, in model units."""

    var lines: List[String]
    var source: String

    def __init__(out self, var source: String):
        """Start an empty body.

        Args:
            source: What wrote the body, for its first comment line.
        """
        self.lines = List[String]()
        self.source = source^

    def raw(mut self, command: String):
        """Add a command as it is.

        Args:
            command: A full TikZ command, with its semicolon.
        """
        self.lines.append(command)

    def comment(mut self, text: String):
        """Add a comment line.

        Args:
            text: The comment, without the percent sign.
        """
        self.lines.append("% " + text)

    def fill_rect(
        mut self,
        style: String,
        x0: Float64,
        y0: Float64,
        x1: Float64,
        y1: Float64,
    ) raises:
        """Fill a rectangle.

        Args:
            style: The fill style.
            x0: One corner's x.
            y0: One corner's y.
            x1: The opposite corner's x.
            y1: The opposite corner's y.

        Raises:
            Error: If a coordinate is not finite.
        """
        self.lines.append(
            "\\fill["
            + style
            + "] "
            + _point(x0, y0)
            + " rectangle "
            + _point(x1, y1)
            + ";"
        )

    def draw_rect(
        mut self,
        style: String,
        x0: Float64,
        y0: Float64,
        x1: Float64,
        y1: Float64,
    ) raises:
        """Draw a rectangle's outline.

        Args:
            style: The line style.
            x0: One corner's x.
            y0: One corner's y.
            x1: The opposite corner's x.
            y1: The opposite corner's y.

        Raises:
            Error: If a coordinate is not finite.
        """
        self.lines.append(
            "\\draw["
            + style
            + "] "
            + _point(x0, y0)
            + " rectangle "
            + _point(x1, y1)
            + ";"
        )

    def box(
        mut self,
        fill: String,
        line: String,
        x0: Float64,
        y0: Float64,
        x1: Float64,
        y1: Float64,
    ) raises:
        """Fill a rectangle and draw its outline.

        Args:
            fill: The fill style.
            line: The line style.
            x0: One corner's x.
            y0: One corner's y.
            x1: The opposite corner's x.
            y1: The opposite corner's y.

        Raises:
            Error: If a coordinate is not finite.
        """
        self.fill_rect(fill, x0, y0, x1, y1)
        self.draw_rect(line, x0, y0, x1, y1)

    def polyline(
        mut self, style: String, xs: List[Float64], ys: List[Float64]
    ) raises:
        """Draw a line through points.

        Args:
            style: The line style.
            xs: The x of each point.
            ys: The y of each point.

        Raises:
            Error: If there are fewer than two points, the lists differ in
                length, or a coordinate is not finite.
        """
        if len(xs) != len(ys) or len(xs) < 2:
            raise Error("A polyline needs two points or more")
        var text = "\\draw[" + style + "] " + _point(xs[0], ys[0])
        # Two points or more were required above, so the loop always runs.
        for i in range(1, len(xs)):  # pragma: no branch
            text += " -- " + _point(xs[i], ys[i])
        self.lines.append(text + ";")

    def line(
        mut self,
        style: String,
        x0: Float64,
        y0: Float64,
        x1: Float64,
        y1: Float64,
    ) raises:
        """Draw a straight line.

        Args:
            style: The line style.
            x0: The start's x.
            y0: The start's y.
            x1: The end's x.
            y1: The end's y.

        Raises:
            Error: If a coordinate is not finite.
        """
        self.polyline(style, [x0, x1], [y0, y1])

    def circle(
        mut self, style: String, x: Float64, y: Float64, radius: Float64
    ) raises:
        """Fill a circle.

        Args:
            style: The fill style.
            x: The center's x.
            y: The center's y.
            radius: The radius, positive.

        Raises:
            Error: If the radius is not positive or a value is not finite.
        """
        if not (radius > 0):
            raise Error("A circle's radius must be positive")
        self.lines.append(
            "\\fill["
            + style
            + "] "
            + _point(x, y)
            + " circle ("
            + _n(radius)
            + ");"
        )

    def label(
        mut self,
        style: String,
        anchor: String,
        x: Float64,
        y: Float64,
        text: String,
    ) raises:
        """Place a text node.

        Args:
            style: The node style, with any extra keys after a comma.
            anchor: The TikZ anchor, such as "west" or "south".
            x: The x of the anchor.
            y: The y of the anchor.
            text: The LaTeX text.

        Raises:
            Error: If a coordinate is not finite.
        """
        self.lines.append(
            "\\node["
            + style
            + ",anchor="
            + anchor
            + "] at "
            + _point(x, y)
            + " {"
            + text
            + "};"
        )

    def leader(
        mut self,
        style: String,
        x0: Float64,
        y0: Float64,
        x1: Float64,
        y1: Float64,
    ) raises:
        """Draw a leader from a callout to the element it names.

        Args:
            style: The line style, such as a color.
            x0: The x at the callout.
            y0: The y at the callout.
            x1: The x at the element, where the arrowhead is.
            y1: The y at the element.

        Raises:
            Error: If a coordinate is not finite.
        """
        self.lines.append(
            "\\draw["
            + style
            + ",line width=0.4pt,-{Stealth[length=3pt]}] "
            + _point(x0, y0)
            + " -- "
            + _point(x1, y1)
            + ";"
        )

    def dimension(
        mut self, x0: Float64, x1: Float64, y: Float64, text: String
    ) raises:
        """Add a horizontal dimension with the sheet's `\\dimline`.

        Args:
            x0: The left end.
            x1: The right end.
            y: The height of the dimension line.
            text: The label.

        Raises:
            Error: If a coordinate is not finite.
        """
        self.lines.append(
            "\\dimline{"
            + _n(x0)
            + "}{"
            + _n(y)
            + "}{"
            + _n(x1)
            + "}{"
            + _n(y)
            + "}{"
            + text
            + "}"
        )

    def vertical_dimension(
        mut self, x: Float64, y0: Float64, y1: Float64, text: String
    ) raises:
        """Add a vertical dimension with the sheet's `\\dimlinev`.

        Args:
            x: The x of the dimension line.
            y0: The low end.
            y1: The high end.
            text: The label.

        Raises:
            Error: If a coordinate is not finite.
        """
        self.lines.append(
            "\\dimlinev{"
            + _n(x)
            + "}{"
            + _n(y0)
            + "}{"
            + _n(x)
            + "}{"
            + _n(y1)
            + "}{"
            + text
            + "}"
        )

    def render(self) -> String:
        """Return the body text.

        Returns:
            A comment line, then one command per line.
        """
        var out = "% Auto-generated by " + self.source + ". Do not edit.\n"
        for l in self.lines:
            out += l + "\n"
        return out

    def write(self, path: String) raises:
        """Write the body.

        Args:
            path: Where to write it.

        Raises:
            Error: If the file cannot be written.
        """
        Path(path).write_text(self.render())
