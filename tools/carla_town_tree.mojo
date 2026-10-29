# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Draw a far tree and write its picture.

    carla_town_tree FILE

`FILE` is JSON. It has `size`, `samples`, `out` and `parts`. Each part
has positions, normals, texture coordinates, triangles, a color
`factor`, `cut` and `masked`. A part can also have an `image`. The
program draws the front view and the side view, joins them, and writes
one PNG at `out`. It prints the two quads that cross on the trunk.
"""

from std.os import makedirs
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import PY_DICT, PY_LIST, PyJson
from tools.carla_image_pack import joined_rgba
from tools.carla_png import png_bytes
from tools.carla_town_impostor import impostor_text
from tools.carla_town_splat import SplatView, splat_view
from tools._town_json import (
    json_compact,
    json_member,
    json_named_int,
    json_text,
)


def tree_text(text: String) raises -> String:
    """Draw one far tree and write its PNG.

    Args:
        text: JSON with `size`, `samples`, `out` and `parts`. `size` is
            the picture width of one view, in pixels. `samples` is the
            sample count per covered texel. `out` is the PNG path.

    Returns:
        JSON with the two quads: `positions`, `normals`, `uvs` and
        `triangles`.

    Raises:
        Error: If the JSON is not that tree, a view cannot be drawn, or
            the picture cannot be written.
    """
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_DICT:
        raise Error("tree request is not an object")
    var size = json_named_int(doc, json_member(doc, doc.root, "size"), "size")
    var samples = json_named_int(
        doc, json_member(doc, doc.root, "samples"), "samples"
    )
    if size < 1:
        raise Error("size is not positive")
    if samples < 1:
        raise Error("samples is not positive")
    var out = json_text(
        doc, json_member(doc, doc.root, "out"), "out is not text"
    )
    var parts = json_member(doc, doc.root, "parts")
    if doc.kind(parts) != PY_LIST or doc.length(parts) == 0:
        raise Error("parts are not a list")
    var frame_text = impostor_text(_frame_request(doc, parts, size))
    var frame = PyJson.parse(frame_text)
    var views = frame.at(frame.root, "views")
    if frame.kind(views) != PY_LIST or frame.length(views) != 2:
        raise Error("a tree has two views")
    var light = impostor_text('{"mode":"light"}')
    var parts_json = json_compact(doc, parts)
    var left = _draw(
        frame, frame.item(views, 0), size, samples, light, parts_json
    )
    var right = _draw(
        frame, frame.item(views, 1), size, samples, light, parts_json
    )
    _write_png(out, size, left, right)
    return _quads(frame_text)


def _frame_request(doc: PyJson, parts: Int, size: Int) raises -> String:
    """Return the impostor frame request for these parts."""
    var out = String('{"mode":"frame","size":')
    out += String(size)
    out += ',"parts":['
    for index in range(doc.length(parts)):
        if index > 0:
            out += ","
        var part = doc.item(parts, index)
        if doc.kind(part) != PY_DICT:
            raise Error("part is not an object")
        out += json_compact(doc, json_member(doc, part, "positions"))
    out += "]}"
    return out


def _draw(
    frame: PyJson,
    view: Int,
    size: Int,
    samples: Int,
    light: String,
    parts_json: String,
) raises -> SplatView:
    """Return one drawn view."""
    var request = String('{"mode":"axis","columns":')
    request += String(size)
    request += ',"rows":'
    request += json_compact(frame, json_member(frame, view, "rows"))
    request += ',"samples":'
    request += String(samples)
    request += ',"cap":4096,"seed":7,"across":'
    request += json_compact(frame, json_member(frame, view, "across"))
    request += ',"left":'
    request += json_compact(frame, json_member(frame, view, "left"))
    request += ',"top":'
    request += json_compact(frame, json_member(frame, view, "top"))
    request += ',"span_u":'
    request += json_compact(frame, json_member(frame, view, "width"))
    request += ',"span_v":'
    request += json_compact(frame, json_member(frame, view, "height"))
    request += ',"fill":true,"light":'
    request += light
    request += ',"parts":'
    request += parts_json
    request += "}"
    return splat_view(request)


def _write_png(
    path: String, size: Int, left: SplatView, right: SplatView
) raises:
    """Join two views and write the PNG."""
    var left_width = left.columns
    var left_height = left.rows
    var right_width = right.columns
    var right_height = right.rows
    var values = joined_rgba(
        _rgba(left),
        left_width,
        left_height,
        _rgba(right),
        right_width,
        right_height,
        size,
    )
    var pixels = List[UInt8]()
    for index in range(len(values)):
        var value = values[index]
        if value < 0 or value > 255:
            raise Error("pixel is out of range")
        pixels.append(UInt8(value))
    var png = png_bytes("RGBA", size * 2, size, pixels, True, 4, 6)
    var folder = _directory(path)
    if folder.byte_length() > 0:
        makedirs(folder, exist_ok=True)
    Path(path).write_bytes(Span(png))


def _rgba(view: SplatView) -> List[Float64]:
    """Return one view as interleaved RGBA samples."""
    var count = view.columns * view.rows
    var out = List[Float64]()
    for index in range(count):
        out.append(view.red[index])
        out.append(view.green[index])
        out.append(view.blue[index])
        out.append(view.alpha[index])
    return out^


def _quads(frame_text: String) raises -> String:
    """Return the crossing quads from one frame."""
    var out = String('{"positions":')
    out += _array_of(frame_text, "positions")
    out += ',"normals":'
    out += _array_of(frame_text, "normals")
    out += ',"uvs":'
    out += _array_of(frame_text, "uvs")
    out += ',"triangles":'
    out += _array_of(frame_text, "triangles")
    out += "}"
    return out


def _array_of(text: String, key: String) raises -> String:
    """Return the JSON array stored at `key`."""
    var marker = String('"') + key + '":'
    var start = text.find(marker)
    if start < 0:
        raise Error("tree frame has no " + key)
    var raw = text.as_bytes()
    var at = start + len(marker.as_bytes())
    while at < len(raw) and raw[at] == 32:
        at += 1
    if at >= len(raw) or raw[at] != 91:
        raise Error("tree frame has no " + key)
    var depth = 0
    var end = at
    var found = False
    for index in range(at, len(raw)):
        var byte = raw[index]
        if byte == 91:
            depth += 1
        elif byte == 93:
            depth -= 1
            if depth == 0:
                end = index + 1
                found = True
                break
    if not found:
        raise Error("tree frame has no " + key)
    return String(text[byte=at:end])


def _directory(path: String) -> String:
    """Return the directory that holds `path`."""
    var raw = path.as_bytes()
    var slash = -1
    for index in range(len(raw)):
        if raw[index] == 47:
            slash = index
    if slash <= 0:
        return String(".")
    return String(path[byte=:slash])


def main() raises:
    """Draw the tree in the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_tree FILE", file=stderr)
        exit(2)
    try:
        print(tree_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_tree:", error, file=stderr)
        exit(1)
