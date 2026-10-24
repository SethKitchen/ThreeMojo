# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the cut-out channel of a foliage mask.

    carla_mask_channel FILE

`FILE` is JSON with `width`, `height` and `pixels`. `pixels` is RGB,
one byte per channel. The chosen channel has the most samples below 16
or at least 240. An equal count keeps the earlier channel. The result
is that channel's bytes.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float
from tools._python_json import PY_DICT, PY_INT, PY_LIST, PyJson


def mask_text(text: String) raises -> String:
    """Return the cut-out channel as JSON.

    Args:
        text: A JSON object with `width`, `height` and RGB `pixels`.

    Returns:
        `channel` and `pixels`. `channel` is 0, 1 or 2.

    Raises:
        Error: If the JSON is not that image, or a pixel is out of range.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("mask request is not an object")
    var width = _whole(doc, doc.at(root, "width"))
    var height = _whole(doc, doc.at(root, "height"))
    if width < 1 or height < 1:
        raise Error("size is not positive")
    var count = width * height
    var pixels = doc.at(root, "pixels")
    if doc.kind(pixels) != PY_LIST or doc.length(pixels) != count * 3:
        raise Error("pixels do not match the image")
    var score = List[Int]()
    score.append(0)
    score.append(0)
    score.append(0)
    for index in range(count):
        for channel in range(3):
            var value = _byte(doc, doc.item(pixels, index * 3 + channel))
            if value < 16 or value >= 240:
                score[channel] += 1
    var best = 0
    if score[1] > score[0]:
        best = 1
    if score[2] > score[best]:
        best = 2
    var out = String('{"channel":')
    out += String(best)
    out += ',"pixels":['
    for index in range(count):
        if index > 0:
            out += ","
        out += String(_byte(doc, doc.item(pixels, index * 3 + best)))
    out += "]}"
    return out^


def _byte(doc: PyJson, node: Int) raises -> Int:
    """Return one pixel byte."""
    var value = _whole(doc, node)
    if value < 0 or value > 255:
        raise Error("pixel is out of range")
    return value


def _whole(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("value is not an integer")
    return Int(parse_float(doc.text(node)))


def main() raises:
    """Print the cut-out channel for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_mask_channel FILE", file=stderr)
        exit(2)
    try:
        print(mask_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_mask_channel:", error, file=stderr)
        exit(1)
