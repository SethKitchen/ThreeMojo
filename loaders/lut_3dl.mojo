# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Color lookup tables in the `.3dl` format, from three.js
`examples/jsm/loaders/LUT3dlLoader.js`.

A `.3dl` file is text. Its first line of only digits and spaces is the
grid: the input values the table is sampled at, evenly spaced, one for
each entry along a side. Each line of exactly three numbers after it is
an entry: red, green and blue, with blue changing fastest, then green,
then red. `parse_lut_3dl` reads it into a `Data3DTexture` of `size`
texels a side, red across, green up and blue deep, as three.js builds
it.

**The scale.** three.js finds the largest number and scales every number
by the power of two at or above it, so a 10-bit table of values up to
1023 is divided by 1024. A table whose largest value is at most one half
is scaled up, as three.js scales it.

**The texels.** `UNSIGNED_BYTE_TYPE`, the default as in three.js, stores
each scaled number times 255, cut to a whole number and wrapped as a
JavaScript `Uint8Array` stores it; alpha is 255. `FLOAT_TYPE` stores the
scaled numbers, alpha one. The texture is clamped, bilinear and linear.

**What three.js does that this keeps.** A line of three numbers counts
as an entry wherever it is, the grid line included when the grid has
three values. Entries past `size` cubed wrap around and write over the
first ones, as three.js's indices wrap; missing ones are zero.

**Where this port differs.** three.js throws for a file with no grid and
for a grid that is not evenly spaced, and so does this. It also refuses
a number that is not one, where three.js reads `NaN`, and a table whose
largest number is not above zero, which three.js divides by zero.
"""

from render.srgb import LINEAR
from render.texture import (
    BILINEAR,
    CLAMP,
    FLOAT_TYPE,
    UNSIGNED_BYTE_TYPE,
    TexelType,
)
from render.volume_texture import Data3DTexture, VolumeImage
from std.math import ceil, isfinite, log2
from std.pathlib import Path


struct Lut3dl(Movable):
    """What a `.3dl` file holds: three.js's `{ size, texture3D }`, and the
    grid."""

    var size: Int
    # The grid's input values.
    var grid: List[Float64]
    # The power of two every number was divided by.
    var max_bit_value: Float64
    var texture: Data3DTexture

    def __init__(
        out self,
        size: Int,
        var grid: List[Float64],
        max_bit_value: Float64,
        var texture: Data3DTexture,
    ):
        """Hold what a file gave.

        Args:
            size: Entries a side.
            grid: The grid.
            max_bit_value: The scale.
            texture: The table.
        """
        self.size = size
        self.grid = grid^
        self.max_bit_value = max_bit_value
        self.texture = texture^


def _number(text: String) raises -> Float64:
    """Return JavaScript's `Number(text)` for a matched field.

    Raises:
        Error: If it is not a finite number.
    """
    var value: Float64
    try:
        value = Float64(text)
    except:
        raise Error("3DL: `" + text + "` is not a number")
    if not isfinite(value):
        raise Error("3DL: `" + text + "` is not a number")
    return value


def _lines(text: String) -> List[String]:
    """Return the lines of a text, split at each line break, as a
    multiline regular expression's `^` and `$` see them."""
    var out = List[String]()
    for line in text.replace("\r", "\n").split("\n"):  # pragma: no branch
        out.append(String(line))
    return out^


def _is_grid(line: String) -> Bool:
    """Return True for a line of only digits and spaces, `^[\\d ]+$`."""
    var bytes = line.as_bytes()
    if len(bytes) == 0:
        return False
    # Not empty, checked above: the loop always runs.
    for b in bytes:  # pragma: no branch
        var allowed = (b >= 48 and b <= 57) or b == 32
        if not allowed:
            return False
    return True


def _entry(line: String) -> List[String]:
    """Return the three fields of a data line,
    `^([\\d.e+-]+) +([\\d.e+-]+) +([\\d.e+-]+) *$`, or none."""
    var fields = List[String]()
    var bytes = line.as_bytes()
    var i = 0
    while i < len(bytes):
        var start = i
        while _number_at(bytes, i):
            i += 1
        if i == start:
            return List[String]()
        fields.append(String(line[byte=start:i]))
        var spaces = i
        while _space_at(bytes, i):
            i += 1
        var last = len(fields) == 3
        if last:
            return fields^ if i == len(bytes) else List[String]()
        if i == spaces:
            return List[String]()
    return List[String]()


def _number_at(bytes: Span[UInt8, _], i: Int) -> Bool:
    """Return True if there is a byte of `[\\d.e+-]` at `i`."""
    return i < len(bytes) and _in_number(bytes[i])


def _space_at(bytes: Span[UInt8, _], i: Int) -> Bool:
    """Return True if there is a space at `i`."""
    return i < len(bytes) and bytes[i] == 32


def _in_number(byte: UInt8) -> Bool:
    """Return True for a byte of `[\\d.e+-]`."""
    return (
        (byte >= 48 and byte <= 57)
        or byte == 46
        or byte == 101
        or (byte == 43 or byte == 45)
    )


def lut_3dl_byte(value: Float64) -> UInt8:
    """Return a number as a `Uint8Array` stores it: cut toward zero and
    wrapped modulo 256.

    Args:
        value: The number.

    Returns:
        The byte.
    """
    var whole = Int(value)
    return UInt8(((whole % 256) + 256) % 256)


def parse_lut_3dl(
    text: String, texel_type: TexelType = UNSIGNED_BYTE_TYPE
) raises -> Lut3dl:
    """Read a `.3dl` file's text, three.js's `LUT3dlLoader.parse`.

    Args:
        text: The whole file.
        texel_type: `UNSIGNED_BYTE_TYPE`, the default, or `FLOAT_TYPE`.

    Returns:
        The size, the grid, the scale and the texture.

    Raises:
        Error: If the texel type is not valid, the file has no grid, the
            grid is not evenly spaced, a number is not one, or the largest
            number is not above zero.
    """
    if not texel_type.is_valid():
        raise Error("3DL: a texel type that is not valid")
    var lines = _lines(text)
    var grid = List[Float64]()
    # A split gives at least one line: these loops always run.
    for line in lines:  # pragma: no branch
        if _is_grid(line):
            for field in line.split():
                grid.append(_number(String(field)))
            if len(grid) == 0:
                # A line of spaces: `"".split( /\s+/ )` is one empty
                # string, and `Number( "" )` is zero.
                grid.append(0)
            break
    if len(grid) == 0:
        raise Error("3DL: missing grid information")
    var size = len(grid)
    var step = grid[1] - grid[0] if size > 1 else Float64(0)
    for i in range(1, size):
        if grid[i] - grid[i - 1] != step:
            raise Error("3DL: inconsistent grid size")
    var cells = size * size * size
    var data = List[Float64](length=cells * 4, fill=0)
    var largest = Float64(0)
    var index = 0
    for line in lines:  # pragma: no branch
        var fields = _entry(line)
        if len(fields) == 0:
            continue
        var r = _number(fields[0])
        var g = _number(fields[1])
        var b = _number(fields[2])
        largest = max(max(largest, r), max(g, b))
        var b_layer = index % size
        var g_layer = (index // size) % size
        var r_layer = (index // (size * size)) % size
        var at = (b_layer * size * size + g_layer * size + r_layer) * 4
        data[at] = r
        data[at + 1] = g
        data[at + 2] = b
        index += 1
    if not largest > 0:
        raise Error("3DL: a table whose largest number is not above zero")
    var max_bit_value = 2.0 ** ceil(log2(largest))
    var image: VolumeImage
    if texel_type == FLOAT_TYPE:
        var floats = List[Float32]()
        for i in range(cells * 4):  # pragma: no branch
            var value = Float32(1) if i % 4 == 3 else Float32(
                data[i] / max_bit_value
            )
            floats.append(value)
        image = VolumeImage.of_floats(size, size, size, floats, 4)
    else:
        var bytes = List[UInt8]()
        for i in range(cells * 4):  # pragma: no branch
            var value = UInt8(255) if i % 4 == 3 else lut_3dl_byte(
                data[i] / max_bit_value * 255
            )
            bytes.append(value)
        image = VolumeImage.of_bytes(size, size, size, bytes, 4)
    var texture = Data3DTexture(image^, CLAMP, BILINEAR, LINEAR)
    return Lut3dl(size, grid^, max_bit_value, texture^)


def read_lut_3dl(
    path: String, texel_type: TexelType = UNSIGNED_BYTE_TYPE
) raises -> Lut3dl:
    """Read a `.3dl` file.

    Args:
        path: The file.
        texel_type: `UNSIGNED_BYTE_TYPE` or `FLOAT_TYPE`.

    Returns:
        What `parse_lut_3dl` gives.

    Raises:
        Error: If the file cannot be read, or for anything
            `parse_lut_3dl` refuses.
    """
    return parse_lut_3dl(Path(path).read_text(), texel_type)
