# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Color lookup tables in the `.cube` format, from three.js
`examples/jsm/loaders/LUTCubeLoader.js`.

A `.cube` file is text. It gives the table's size on a `LUT_3D_SIZE` line,
then one line of three numbers per entry: red, green and blue. Red changes
fastest, then green, then blue. `parse_lut_cube` reads the text into a
`LutCube` whose `texture` is a `Data3DTexture` of `size` texels a side,
red across, green up and blue deep, as three.js builds it. A `lut_pass`
reads that texture.

**What is read.**

- `TITLE "name"`: the title, or none.
- `LUT_3D_SIZE n`: the size, two through 256, as Adobe's specification
  allows.
- `DOMAIN_MIN r g b` and `DOMAIN_MAX r g b`: the input range, zero to one
  by default. Each minimum must not be above its maximum, as three.js
  requires. The numbers are kept and not applied, as three.js's `LUTPass`
  does not apply them.
- A line of three numbers: one entry. There must be `size` cubed of them.
- A line that starts with `#` is a comment. Any other keyword is skipped,
  as three.js skips it.

**The texels.** `UNSIGNED_BYTE_TYPE`, the default as in three.js, stores
each number times 255, cut to a whole number as a JavaScript `Uint8Array`
cuts it. `FLOAT_TYPE` stores the numbers as they are. Alpha is one. The
texture is clamped on every axis, `BILINEAR`, and `LINEAR`, as three.js
sets `LinearFilter`, `ClampToEdgeWrapping` and no color space.

**Where this port is stricter.** three.js reads any line that matches its
pattern and ignores the rest. This refuses a size outside two through 256,
a data line that does not hold three finite numbers, a count of entries
other than `size` cubed, and for bytes a number outside zero to one, which
a `Uint8Array` would wrap. A `LUT_1D_SIZE` line is refused: three.js reads
no one-dimensional table either.

**Not ported.** three.js's `LUT3dlLoader` and `LUTImageLoader`, which
read `.3dl` files and image strips.
"""

from math.vector3 import Vector3
from render.texture import (
    BILINEAR,
    CLAMP,
    FLOAT_TYPE,
    UNSIGNED_BYTE_TYPE,
    TexelType,
)
from render.srgb import LINEAR
from render.volume_texture import Data3DTexture, VolumeImage
from std.math import isfinite
from std.pathlib import Path

# The largest table Adobe's `.cube` specification allows.
comptime LUT_MAX_SIZE = 256


struct LutCube(Movable):
    """What a `.cube` file holds: three.js's `LUTCubeLoader` result,
    `{ title, size, domainMin, domainMax, texture3D }`."""

    # The `TITLE`, or none.
    var title: Optional[String]
    # How many entries a side the table has.
    var size: Int
    # The input range the file declares; not applied.
    var domain_min: Vector3
    var domain_max: Vector3
    # The table, `size` texels a side.
    var texture: Data3DTexture

    def __init__(
        out self,
        var title: Optional[String],
        size: Int,
        domain_min: Vector3,
        domain_max: Vector3,
        var texture: Data3DTexture,
    ):
        """Hold what a file gave.

        Args:
            title: The title, or none.
            size: Entries a side.
            domain_min: The input range's low end.
            domain_max: The input range's high end.
            texture: The table.
        """
        self.title = title^
        self.size = size
        self.domain_min = domain_min
        self.domain_max = domain_max
        self.texture = texture^


def _where(line: Int) -> String:
    """Return the prefix an error names its line with."""
    return "LUT line " + String(line) + ": "


def _number(field: String, line: Int) raises -> Float32:
    """Return one number read from a field.

    Args:
        field: The text.
        line: Which line it is on, for the error.

    Returns:
        The number.

    Raises:
        Error: If the field is not a number, or is not finite once it is
            a `Float32`.
    """
    var wide: Float64
    try:
        wide = Float64(field)
    except:
        raise Error(_where(line) + "not a number: " + field)
    var value = Float32(wide)
    if not isfinite(value):
        raise Error(_where(line) + "a number must be finite: " + field)
    return value


def _triple(fields: List[String], first: Int, line: Int) raises -> Vector3:
    """Return the three numbers from `fields[first]` on.

    Args:
        fields: The line, split on white space.
        first: Where the numbers start.
        line: Which line it is, for the error.

    Returns:
        The numbers.

    Raises:
        Error: If the line does not hold exactly three numbers from
            `first`, or one is not a finite number.
    """
    if len(fields) != first + 3:
        raise Error(_where(line) + "three numbers are expected")
    return Vector3(
        _number(fields[first], line),
        _number(fields[first + 1], line),
        _number(fields[first + 2], line),
    )


def _size(fields: List[String], line: Int) raises -> Int:
    """Return the size a `LUT_3D_SIZE` line gives.

    Args:
        fields: The line, split on white space.
        line: Which line it is, for the error.

    Returns:
        The size.

    Raises:
        Error: If the line does not hold one whole number from two through
            256.
    """
    if len(fields) != 2:
        raise Error(_where(line) + "LUT_3D_SIZE takes one number")
    var size: Int
    try:
        size = Int(fields[1])
    except:
        raise Error(_where(line) + "not a whole number: " + fields[1])
    if size < 2 or size > LUT_MAX_SIZE:
        raise Error(_where(line) + "LUT_3D_SIZE runs from 2 through 256")
    return size


def _title(text: String, line: Int) raises -> String:
    """Return the quoted title of a `TITLE` line.

    Args:
        text: The line, stripped.
        line: Which line it is, for the error.

    Returns:
        The text between the quotes.

    Raises:
        Error: If the title is not in double quotes.
    """
    var open = text.find('"')
    var close = text.rfind('"')
    if open < 0 or close <= open:
        raise Error(_where(line) + "a TITLE is in double quotes")
    return String(text[byte = open + 1 : close])


def _is_keyword(key: String) -> Bool:
    """Return True if a field starts with a letter or an underscore, as a
    keyword does and a number does not."""
    var first = key.as_bytes()[0]
    return (
        (first >= 65 and first <= 90)
        or (first >= 97 and first <= 122)
        or first == 95
    )


def parse_lut_cube(
    text: String, texel_type: TexelType = UNSIGNED_BYTE_TYPE
) raises -> LutCube:
    """Read a `.cube` file's text into a table: three.js's
    `LUTCubeLoader.parse`.

    Args:
        text: The whole file.
        texel_type: `UNSIGNED_BYTE_TYPE`, the default as three.js's
            `setType` default is, or `FLOAT_TYPE`.

    Returns:
        The title, the size, the domain and the texture.

    Raises:
        Error: If the texel type is none of the named values; the file has
            no `LUT_3D_SIZE`, or a `LUT_1D_SIZE`; a line is malformed; the
            domain's minimum is above its maximum; the count of entries is
            not `size` cubed; or, for bytes, a number is outside zero to
            one.
    """
    if not texel_type.is_valid():
        raise Error(
            "A LUT's texel type must be UNSIGNED_BYTE_TYPE or FLOAT_TYPE"
        )
    var title = Optional[String]()
    var size = 0
    var domain_min = Vector3(0, 0, 0)
    var domain_max = Vector3(1, 1, 1)
    var entries = List[Float32]()
    var line = 0
    # A split yields at least one piece, even of an empty file.
    for raw in text.split("\n"):  # pragma: no branch
        line += 1
        var stripped = String(String(raw).strip())
        if stripped.byte_length() == 0 or stripped.startswith("#"):
            continue
        var fields = List[String]()
        for piece in stripped.split():  # pragma: no branch
            fields.append(String(piece))
        var key = fields[0]
        if key == "TITLE":
            title = _title(stripped, line)
        elif key == "LUT_3D_SIZE":
            size = _size(fields, line)
        elif key == "LUT_1D_SIZE":
            raise Error(_where(line) + "a 1D table is not read")
        elif key == "DOMAIN_MIN":
            domain_min = _triple(fields, 1, line)
        elif key == "DOMAIN_MAX":
            domain_max = _triple(fields, 1, line)
        elif _is_keyword(key):
            # Another keyword, such as `LUT_3D_INPUT_RANGE`: skipped, as
            # three.js skips any line its pattern does not match.
            continue
        else:
            var entry = _triple(fields, 0, line)
            var scale = Float32(1)
            if texel_type == UNSIGNED_BYTE_TYPE:
                scale = 255
            entries.append(entry.x * scale)
            entries.append(entry.y * scale)
            entries.append(entry.z * scale)
    if size == 0:
        raise Error("A .cube file needs a LUT_3D_SIZE line")
    if (
        domain_min.x > domain_max.x
        or domain_min.y > domain_max.y
        or domain_min.z > domain_max.z
    ):
        raise Error("A LUT's DOMAIN_MIN must not be above its DOMAIN_MAX")
    if len(entries) != size * size * size * 3:
        raise Error(
            "A .cube file of size "
            + String(size)
            + " holds "
            + String(size * size * size)
            + " entries"
        )
    var image: VolumeImage
    if texel_type == FLOAT_TYPE:
        image = VolumeImage.of_floats(size, size, size, entries, 3)
    else:
        var bytes = List[UInt8]()
        bytes.reserve(len(entries))
        # The size is at least two, so the loop runs.
        for index in range(len(entries)):  # pragma: no branch
            var value = entries[index]
            if value < 0 or value > 255:
                raise Error(
                    "A byte LUT holds numbers from zero to one; read it as"
                    " FLOAT_TYPE"
                )
            # Cut, as a `Uint8Array` cuts a number stored in it.
            bytes.append(UInt8(Int(value)))
        image = VolumeImage.of_bytes(size, size, size, bytes, 3)
    var texture = Data3DTexture(image^, CLAMP, BILINEAR, LINEAR)
    return LutCube(title^, size, domain_min, domain_max, texture^)


def read_lut_cube(
    path: String, texel_type: TexelType = UNSIGNED_BYTE_TYPE
) raises -> LutCube:
    """Read a `.cube` file into a table: three.js's `LUTCubeLoader.load`.

    Args:
        path: The file to read.
        texel_type: `UNSIGNED_BYTE_TYPE` or `FLOAT_TYPE`.

    Returns:
        The table; see `parse_lut_cube`.

    Raises:
        Error: If the file cannot be read, or for anything
            `parse_lut_cube` refuses.
    """
    return parse_lut_cube(Path(path).read_text(), texel_type)
