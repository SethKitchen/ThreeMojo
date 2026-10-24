# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Spread covered texels into the empty texels beside them.

    carla_town_dilate FILE

`FILE` holds an image, a coverage mask and a pass count. Empty texels
take the colors of covered neighbors. The search wraps, as `numpy.roll`
does. Texels that stay empty take the mean of the covered colors.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tree import JsonTree
from tools._python_float import parse_float
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PyJson,
)


def dilate_text(path: String) raises -> String:
    """Return a dilated image as JSON.

    Args:
        path: A JSON object with `image`, `covered` and optional `passes`.
            `image` is a row of pixels, each pixel a list of channels.
            `covered` is a mask of the same height and width. `passes`
            defaults to 6.

    Returns:
        The image after the covered colors have spread. A pixel that is
        still empty takes the mean of the covered pixels.

    Raises:
        Error: If the file cannot be read, or the image and the mask have
            different shapes.
    """
    var doc = PyJson.parse(Path(path).read_text())
    if doc.kind(doc.root) != PY_DICT:
        raise Error("dilate is not an object")
    var height = 0
    var width = 0
    var channels = 0
    var pixels = _image(doc, doc.at(doc.root, "image"), height, width, channels)
    var mask = _mask(doc, doc.at(doc.root, "covered"), height, width)
    var passes = 6
    var named = doc.get(doc.root, "passes")
    if named != MISSING:
        passes = _int(doc, named)
        if passes < 0:
            raise Error("passes is negative")
    var result = _dilate(pixels^, mask^, height, width, channels, passes)
    return _emit(result, height, width, channels)


def _dilate(
    var pixels: List[Float64],
    var mask: List[UInt8],
    height: Int,
    width: Int,
    channels: Int,
    passes: Int,
) -> List[Float64]:
    """Return the image after `passes` spreads and a final mean fill."""
    var image = pixels^
    for _ in range(passes):
        if _all(mask):
            break
        var grown = _copy_mask(mask)
        var total = List[Float64]()
        var count = List[Float64]()
        for _ in range(len(image)):
            total.append(0.0)
        for _ in range(len(mask)):
            count.append(0.0)
        var shifts = List[Int]()
        shifts.append(1)
        shifts.append(0)
        shifts.append(-1)
        shifts.append(0)
        shifts.append(0)
        shifts.append(1)
        shifts.append(0)
        shifts.append(-1)
        for step in range(4):
            var dy = shifts[step * 2]
            var dx = shifts[step * 2 + 1]
            for row in range(height):
                for column in range(width):
                    var here = row * width + column
                    if mask[here] != 0:
                        continue
                    var source = _wrap(row - dy, height) * width + _wrap(
                        column - dx, width
                    )
                    if mask[source] == 0:
                        continue
                    for channel in range(channels):
                        var slot = here * channels + channel
                        total[slot] = (
                            total[slot] + image[source * channels + channel]
                        )
                    count[here] = count[here] + 1.0
                    grown[here] = 1
        for row in range(height):
            for column in range(width):
                var here = row * width + column
                if count[here] > 0.0 and mask[here] == 0:
                    for channel in range(channels):
                        var slot = here * channels + channel
                        image[slot] = total[slot] / count[here]
        mask = grown^
    if not _all(mask) and _any(mask):
        var sum = List[Float64]()
        for _ in range(channels):
            sum.append(0.0)
        var seen = 0.0
        for row in range(height):
            for column in range(width):
                var here = row * width + column
                if mask[here] == 0:
                    continue
                seen += 1.0
                for channel in range(channels):
                    sum[channel] = (
                        sum[channel] + image[here * channels + channel]
                    )
        for row in range(height):
            for column in range(width):
                var here = row * width + column
                if mask[here] != 0:
                    continue
                for channel in range(channels):
                    image[here * channels + channel] = sum[channel] / seen
    return image^


def _image(
    doc: PyJson,
    node: Int,
    mut height: Int,
    mut width: Int,
    mut channels: Int,
) raises -> List[Float64]:
    """Return the image as one list of channel values."""
    if doc.kind(node) != PY_LIST:
        raise Error("image is not a list")
    height = doc.length(node)
    width = 0
    channels = 0
    var out = List[Float64]()
    for row in range(height):
        var line = doc.item(node, row)
        if doc.kind(line) != PY_LIST:
            raise Error("image row is not a list")
        if row == 0:
            width = doc.length(line)
        elif doc.length(line) != width:
            raise Error("image rows differ")
        for column in range(width):
            var pixel = doc.item(line, column)
            if doc.kind(pixel) != PY_LIST:
                raise Error("pixel is not a list")
            if row == 0 and column == 0:
                channels = doc.length(pixel)
            elif doc.length(pixel) != channels:
                raise Error("pixels differ")
            for channel in range(channels):
                out.append(_number(doc, doc.item(pixel, channel)))
    return out^


def _mask(
    doc: PyJson, node: Int, height: Int, width: Int
) raises -> List[UInt8]:
    """Return the coverage mask, one byte per texel."""
    if doc.kind(node) != PY_LIST or doc.length(node) != height:
        raise Error("covered does not match the image")
    var out = List[UInt8]()
    for row in range(height):
        var line = doc.item(node, row)
        if doc.kind(line) != PY_LIST or doc.length(line) != width:
            raise Error("covered does not match the image")
        for column in range(width):
            out.append(
                UInt8(1) if _flag(doc, doc.item(line, column)) else UInt8(0)
            )
    return out^


def _copy_mask(mask: List[UInt8]) -> List[UInt8]:
    """Return a copy of a mask."""
    var out = List[UInt8]()
    for index in range(len(mask)):
        out.append(mask[index])
    return out^


def _all(mask: List[UInt8]) -> Bool:
    """Return whether every texel is covered."""
    for index in range(len(mask)):
        if mask[index] == 0:
            return False
    return True


def _any(mask: List[UInt8]) -> Bool:
    """Return whether any texel is covered."""
    for index in range(len(mask)):
        if mask[index] != 0:
            return True
    return False


def _wrap(index: Int, size: Int) -> Int:
    """Return `index` modulo `size`, with a negative index wrapping."""
    if size == 0:
        return 0
    var value = index % size
    if value < 0:
        value += size
    return value


def _emit(
    pixels: List[Float64], height: Int, width: Int, channels: Int
) raises -> String:
    """Return the image as nested JSON."""
    var tree = JsonTree()
    var rows = tree.array()
    for row in range(height):
        var line = tree.array()
        for column in range(width):
            var pixel = tree.array()
            for channel in range(channels):
                tree.append(
                    pixel,
                    tree.number(
                        pixels[(row * width + column) * channels + channel]
                    ),
                )
            tree.append(line, pixel)
        tree.append(rows, line)
    return tree.dumps(rows, False)


def _flag(doc: PyJson, node: Int) raises -> Bool:
    """Return a JSON bool, or a number that is not zero."""
    var kind = doc.kind(node)
    if kind == PY_BOOL:
        return doc.flag(node)
    if kind == PY_INT:
        return Int(doc.text(node)) != 0
    if kind == PY_FLOAT:
        return doc.number(node) != 0.0
    raise Error("covered value is not a bool")


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number as `float`."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("color is not a number")


def _int(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("passes is not an int")
    return Int(doc.text(node))


def main() raises:
    """Print one dilated image for the file on the command line."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_dilate FILE", file=stderr)
        exit(2)
    try:
        print(dilate_text(arguments[1]))
    except error:
        print("carla_town_dilate:", error, file=stderr)
        exit(1)
