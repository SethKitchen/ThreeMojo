# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""XYZ point clouds, from three.js `examples/jsm/loaders/XYZLoader.js`.

An XYZ file is text: one point a line, as `x y z`, or as `x y z r g b`
with each color channel from 0 to 255. A line that starts with `#` is a
comment. `parse_xyz` returns the points as a geometry with `position`,
and with `color` when the lines have colors.

**Colors.** three.js divides each channel by 255 and decodes it from
sRGB to linear light, and so does this port.

**What is read.** As in three.js, a line with other than three or six
values is stepped over. A value is read as `parseFloat` reads it, so
`1.5m` is 1.5.

**What is refused.** A value that is not a number, where three.js keeps
`NaN`. A file that mixes lines with colors and lines without them: three.js
makes a `color` attribute shorter than its `position` there.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, BufferGeometry
from loaders.js_number import js_parse_float
from render.srgb import srgb_to_linear
from std.math import isnan
from std.pathlib import Path


def _value(text: String, line: Int) raises -> Float64:
    """Return `parseFloat(text)`, refusing NaN."""
    var value = js_parse_float(text)
    if isnan(value):
        raise Error(
            "XYZ line " + String(line) + ": `" + text + "` is not a number"
        )
    return value


def parse_xyz(text: String) raises -> BufferGeometry:
    """Read an XYZ file's text, three.js's `XYZLoader.parse`.

    Args:
        text: The file.

    Returns:
        A geometry with `position`, and `color` when the points have
        colors. A file with no points gives a geometry with an empty
        `position`.

    Raises:
        Error: If a value is not a number, or some points have colors and
            others do not.
    """
    var vertices = List[Float32]()
    var colors = List[Float32]()
    var plain = 0
    var colored = 0
    var number = 0
    for raw in text.split("\n"):  # pragma: no branch
        number += 1
        var line = String(String(raw).strip())
        if line.startswith("#"):
            continue
        var values = List[String]()
        for piece in line.split():
            values.append(String(piece))
        var count = len(values)
        if count == 3:
            plain += 1
        elif count == 6:
            colored += 1
        else:
            continue
        for axis in range(3):  # pragma: no branch
            vertices.append(Float32(_value(values[axis], number)))
        if count == 6:
            for channel in range(3, 6):  # pragma: no branch
                var value = Float32(_value(values[channel], number) / 255)
                colors.append(srgb_to_linear(value))
    var mixed = plain > 0 and colored > 0
    if mixed:
        raise Error("XYZ: some points have colors and some do not")
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(vertices^, 3))
    if len(colors) > 0:
        geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    return geometry^


def read_xyz(path: String) raises -> BufferGeometry:
    """Read an XYZ file.

    Args:
        path: The file.

    Returns:
        What `parse_xyz` gives.

    Raises:
        Error: If the file cannot be read, or for anything `parse_xyz`
            refuses.
    """
    return parse_xyz(Path(path).read_text())
