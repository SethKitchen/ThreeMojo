# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Write a PNG file with Pillow's row filters.

    carla_png REQUEST OUT

`REQUEST` is JSON with `mode`, `width`, `height`, `optimize` and
`pixels`. `mode` is `L`, `RGB` or `RGBA`. `optimize` true adds Pillow's
average filter and uses zlib level 9. The file matches Pillow 12.3
`Image.save` for that mode.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import PY_BOOL, PY_DICT, PY_INT, PY_LIST, PY_STR, PyJson
from tools._zlib import crc32, deflate_filtered


def png_text(text: String) raises -> List[UInt8]:
    """Return PNG bytes for one JSON image.

    Args:
        text: A JSON object with `mode`, `width`, `height`, `optimize`
            and `pixels`.

    Returns:
        The PNG file. It matches Pillow's `Image.save` for `L`, `RGB`
        and `RGBA`.

    Raises:
        Error: If the JSON is not that image, or the pixel count does
            not match the size.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("png request is not an object")
    var mode_node = doc.at(root, "mode")
    if doc.kind(mode_node) != PY_STR:
        raise Error("png mode is not L, RGB or RGBA")
    var mode = doc.text(mode_node)
    var bands: Int
    var color: Int
    if mode == "L":
        bands = 1
        color = 0
    elif mode == "RGB":
        bands = 3
        color = 2
    elif mode == "RGBA":
        bands = 4
        color = 6
    else:
        raise Error("png mode is not L, RGB or RGBA")
    var width = _whole(doc, doc.at(root, "width"))
    var height = _whole(doc, doc.at(root, "height"))
    if width < 1 or height < 1:
        raise Error("png size is not positive")
    if width > 4096 or height > 4096:
        raise Error("png size is too large")
    var optimize = _flag(doc, doc.at(root, "optimize"))
    var pixels = _pixels(doc, doc.at(root, "pixels"), width * height * bands)
    return png_bytes(mode, width, height, pixels, optimize, bands, color)


def png_bytes(
    mode: String,
    width: Int,
    height: Int,
    pixels: List[UInt8],
    optimize: Bool,
    bands: Int,
    color: Int,
) raises -> List[UInt8]:
    """Return PNG bytes for raw 8-bit pixels.

    Args:
        mode: `L`, `RGB` or `RGBA`. Kept for the request text.
        width: The width in pixels.
        height: The height in pixels.
        pixels: Row-major samples, `bands` per pixel.
        optimize: True to use Pillow's optimize path.
        bands: 1, 3 or 4.
        color: The PNG color type, 0, 2 or 6.

    Returns:
        The PNG file.

    Raises:
        Error: If zlib cannot compress the scanlines.
    """
    _ = mode
    var filtered = _filter(pixels, width, height, bands, optimize)
    var level = -1
    if optimize:
        level = 9
    var compressed = deflate_filtered(filtered, level)
    var out = List[UInt8]()
    out.append(0x89)
    out.append(0x50)
    out.append(0x4E)
    out.append(0x47)
    out.append(0x0D)
    out.append(0x0A)
    out.append(0x1A)
    out.append(0x0A)
    var header = List[UInt8]()
    _be32(header, width)
    _be32(header, height)
    header.append(8)
    header.append(UInt8(color))
    header.append(0)
    header.append(0)
    header.append(0)
    _chunk(out, "IHDR", header)
    var chunk_size = 65536
    var room = width * 4
    if room > chunk_size:
        chunk_size = room
    var offset = 0
    while offset < len(compressed):
        var end = offset + chunk_size
        if end > len(compressed):
            end = len(compressed)
        var piece = List[UInt8]()
        for index in range(offset, end):
            piece.append(compressed[index])
        _chunk(out, "IDAT", piece)
        offset = end
    var empty = List[UInt8]()
    _chunk(out, "IEND", empty)
    return out^


def _filter(
    pixels: List[UInt8], width: Int, height: Int, bands: Int, optimize: Bool
) -> List[UInt8]:
    """Return scanlines filtered as Pillow's ZIP PNG encoder filters them."""
    var row_bytes = width * bands
    var previous = List[UInt8]()
    for _ in range(row_bytes + 1):
        previous.append(0)
    var out = List[UInt8]()
    for y in range(height):
        var raw = List[UInt8]()
        raw.append(0)
        var origin = y * row_bytes
        for index in range(row_bytes):
            raw.append(pixels[origin + index])
        var best = 0
        var best_sum = _none_sum(raw, row_bytes)
        var up = List[UInt8]()
        var prior = List[UInt8]()
        var average = List[UInt8]()
        var paeth = List[UInt8]()
        if best_sum > 0:
            up = _up(raw, previous, row_bytes)
            var score = _none_sum(up, row_bytes)
            if score < best_sum:
                best = 2
                best_sum = score
        if best_sum > 0:
            prior = _prior(raw, row_bytes, bands)
            var score = _none_sum(prior, row_bytes)
            if score < best_sum:
                best = 1
                best_sum = score
        if optimize and best_sum > 0:
            average = _average(raw, previous, row_bytes, bands)
            var score = _none_sum(average, row_bytes)
            if score < best_sum:
                best = 3
                best_sum = score
        if best_sum > 0:
            paeth = _paeth(raw, previous, row_bytes, bands)
            var score = _none_sum(paeth, row_bytes)
            if score < best_sum:
                best = 4
        if best == 0:
            _extend(out, raw)
        elif best == 1:
            _extend(out, prior)
        elif best == 2:
            _extend(out, up)
        elif best == 3:
            _extend(out, average)
        else:
            _extend(out, paeth)
        for index in range(row_bytes + 1):
            previous[index] = raw[index]
    return out^


def _none_sum(row: List[UInt8], row_bytes: Int) -> Int:
    """Return Pillow's distance of one filtered row, ignoring its type."""
    var total = 0
    for index in range(1, row_bytes + 1):
        total += _distance(Int(row[index]))
    return total


def _distance(value: Int) -> Int:
    """Return the distance of one byte from zero, as a signed byte."""
    if value < 128:
        return value
    return 256 - value


def _up(raw: List[UInt8], previous: List[UInt8], row_bytes: Int) -> List[UInt8]:
    """Return the Up filter of one row."""
    var out = List[UInt8]()
    out.append(2)
    for index in range(1, row_bytes + 1):
        out.append(UInt8((Int(raw[index]) - Int(previous[index])) & 255))
    return out^


def _prior(raw: List[UInt8], row_bytes: Int, bands: Int) -> List[UInt8]:
    """Return the Sub filter of one row."""
    var out = List[UInt8]()
    out.append(1)
    for index in range(1, bands + 1):
        out.append(raw[index])
    for index in range(bands + 1, row_bytes + 1):
        out.append(UInt8((Int(raw[index]) - Int(raw[index - bands])) & 255))
    return out^


def _average(
    raw: List[UInt8], previous: List[UInt8], row_bytes: Int, bands: Int
) -> List[UInt8]:
    """Return the Average filter of one row."""
    var out = List[UInt8]()
    out.append(3)
    for index in range(1, bands + 1):
        var value = Int(raw[index]) - Int(previous[index]) // 2
        out.append(UInt8(value & 255))
    for index in range(bands + 1, row_bytes + 1):
        var mixed = (Int(raw[index - bands]) + Int(previous[index])) // 2
        out.append(UInt8((Int(raw[index]) - mixed) & 255))
    return out^


def _paeth(
    raw: List[UInt8], previous: List[UInt8], row_bytes: Int, bands: Int
) -> List[UInt8]:
    """Return the Paeth filter of one row."""
    var out = List[UInt8]()
    out.append(4)
    for index in range(1, bands + 1):
        out.append(UInt8((Int(raw[index]) - Int(previous[index])) & 255))
    for index in range(bands + 1, row_bytes + 1):
        var left = Int(raw[index - bands])
        var above = Int(previous[index])
        var upper = Int(previous[index - bands])
        var left_distance = _abs(above - upper)
        var above_distance = _abs(left - upper)
        var diagonal = _abs(left + above - 2 * upper)
        var predicted = upper
        if left_distance <= above_distance and left_distance <= diagonal:
            predicted = left
        elif above_distance <= diagonal:
            predicted = above
        out.append(UInt8((Int(raw[index]) - predicted) & 255))
    return out^


def _abs(value: Int) -> Int:
    """Return the absolute value of a small integer."""
    if value < 0:
        return -value
    return value


def _extend(mut out: List[UInt8], row: List[UInt8]):
    """Append one filtered row."""
    for index in range(len(row)):
        out.append(row[index])


def _chunk(mut out: List[UInt8], tag: String, data: List[UInt8]) raises:
    """Append one PNG chunk."""
    _be32(out, len(data))
    var covered = List[UInt8]()
    var raw = tag.as_bytes()
    for index in range(len(raw)):
        out.append(raw[index])
        covered.append(raw[index])
    for index in range(len(data)):
        out.append(data[index])
        covered.append(data[index])
    var crc = crc32(covered)
    _be32(out, Int(crc))


def _be32(mut out: List[UInt8], value: Int):
    """Append one big-endian 32-bit value."""
    var rest = value
    if rest < 0:
        rest = 0
    out.append(UInt8((rest >> 24) & 255))
    out.append(UInt8((rest >> 16) & 255))
    out.append(UInt8((rest >> 8) & 255))
    out.append(UInt8(rest & 255))


def _pixels(doc: PyJson, node: Int, count: Int) raises -> List[UInt8]:
    """Read the sample bytes."""
    if doc.kind(node) != PY_LIST:
        raise Error("png pixels are not a list")
    if doc.length(node) != count:
        raise Error("png pixels do not match the image")
    var out = List[UInt8]()
    for index in range(count):
        var value = _whole(doc, doc.item(node, index))
        if value < 0 or value > 255:
            raise Error("png sample is out of range")
        out.append(UInt8(value))
    return out^


def _whole(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("png field is not an integer")
    var raw = doc.text(node).as_bytes()
    var index = 0
    var negative = False
    if len(raw) > 0 and raw[0] == 45:
        negative = True
        index = 1
    var value = 0
    for offset in range(index, len(raw)):
        var byte = raw[offset]
        if byte < 48 or byte > 57:
            raise Error("png field is not an integer")
        value = value * 10 + Int(byte - 48)
    if negative:
        return -value
    return value


def _flag(doc: PyJson, node: Int) raises -> Bool:
    """Return a JSON bool."""
    if doc.kind(node) != PY_BOOL:
        raise Error("optimize is not a bool")
    return doc.flag(node)


def main() raises:
    """Write the PNG file named on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 3:
        print("usage: carla_png REQUEST OUT", file=stderr)
        exit(2)
    try:
        var payload = png_text(Path(arguments[1]).read_text())
        Path(arguments[2]).write_bytes(Span(payload))
    except error:
        print("carla_png:", error, file=stderr)
        exit(1)
