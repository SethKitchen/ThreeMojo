# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Draw a far building and write its picture.

    carla_town_bake FILE

`FILE` is JSON. It has `out`, `density`, `most`, `whole`, `far`, `parts`
and `views`. `whole` is the joined near mesh. `far` is the mesh that
receives texture coordinates. Each view has `forward`, `right` and `up`.
The program draws each view, spreads color into the empty texels, joins
the views, and writes one JPEG at `out`. It prints the texture
coordinates.
"""

from std.os import makedirs
from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from tools._process import _remove_tree

from tools._python_float import append_ascii, ascii_text, parse_float
from tools._python_json import (
    MISSING,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PyJson,
)
from tools.carla_image_pack import pack_text
from tools.carla_jpeg import jpeg_text
from tools.carla_town_atlas import atlas_text
from tools.carla_town_dilate import dilate_text
from tools.carla_town_splat import splat_text
from tools._town_json import (
    json_compact,
    json_member,
    json_named_int,
    json_text,
)


def bake_text(text: String) raises -> String:
    """Draw one far building and write its JPEG.

    Args:
        text: JSON with the near mesh, the far mesh, the views and the
            JPEG path. `density` is texels per meter. `most` is the
            longest side of one view, in pixels.

    Returns:
        JSON with `uvs`, one pair for each far corner.

    Raises:
        Error: If the JSON is not that building, a view cannot be drawn,
            or the picture cannot be written.
    """
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_DICT:
        raise Error("bake request is not an object")
    var mode = doc.get(doc.root, "mode")
    if mode != MISSING and json_text(doc, mode, "mode is not text") == "flat":
        return _flat_mesh(doc)
    var path = json_text(
        doc, json_member(doc, doc.root, "out"), "out is not text"
    )
    var density = _number(
        doc, json_member(doc, doc.root, "density"), "density is not a number"
    )
    var most = _number(
        doc, json_member(doc, doc.root, "most"), "most is not a number"
    )
    if not (density > 0.0) or not (most > 0.0):
        raise Error("density is not positive")
    var whole = json_member(doc, doc.root, "whole")
    var far = json_member(doc, doc.root, "far")
    if doc.kind(whole) != PY_DICT or doc.kind(far) != PY_DICT:
        raise Error("mesh is not an object")
    var parts = json_member(doc, doc.root, "parts")
    var views = json_member(doc, doc.root, "views")
    if doc.kind(parts) != PY_LIST or doc.length(parts) == 0:
        raise Error("parts are not a list")
    if doc.kind(views) != PY_LIST or doc.length(views) == 0:
        raise Error("views are not a list")
    var spans_text = atlas_text(_spans_request(doc, whole, views))
    var spans = PyJson.parse(spans_text)
    if spans.kind(spans.root) != PY_LIST or spans.length(
        spans.root
    ) != doc.length(views):
        raise Error("span count does not match the views")
    var drawn = List[String]()
    var parts_json = json_compact(doc, parts)
    for index in range(doc.length(views)):
        var view = doc.item(views, index)
        var span = spans.item(spans.root, index)
        var rgba = splat_text(
            _splat_request(doc, view, spans, span, parts_json)
        )
        drawn.append(_spread(rgba))
    var packed = atlas_text(_pack_request(doc, far, views, spans, drawn))
    _write_jpeg(path, packed)
    var out = String('{"uvs":')
    out += _array_of(packed, "uvs")
    out += "}"
    return out


def _flat_mesh(doc: PyJson) raises -> String:
    """Return one unsimplified mesh as unindexed corners."""
    var flat = atlas_text(
        '{"mode":"flat","positions":'
        + json_compact(doc, json_member(doc, doc.root, "positions"))
        + ',"triangles":'
        + json_compact(doc, json_member(doc, doc.root, "triangles"))
        + "}"
    )
    var out = String('{"positions":')
    out += _array_of(flat, "positions")
    out += ',"normals":'
    out += _array_of(flat, "normals")
    out += ',"triangles":'
    out += _array_of(flat, "triangles")
    out += "}"
    return out


def _spans_request(doc: PyJson, whole: Int, views: Int) raises -> String:
    """Return the atlas span request."""
    var out = String('{"mode":"spans","positions":')
    out += json_compact(doc, json_member(doc, whole, "positions"))
    out += ',"density":'
    out += json_compact(doc, json_member(doc, doc.root, "density"))
    out += ',"most":'
    out += json_compact(doc, json_member(doc, doc.root, "most"))
    out += ',"views":['
    for index in range(doc.length(views)):
        if index > 0:
            out += ","
        var view = doc.item(views, index)
        out += '{"right":'
        out += json_compact(doc, json_member(doc, view, "right"))
        out += ',"up":'
        out += json_compact(doc, json_member(doc, view, "up"))
        out += "}"
    out += "]}"
    return out


def _splat_request(
    doc: PyJson,
    view: Int,
    spans: PyJson,
    span: Int,
    parts_json: String,
) raises -> String:
    """Return one orthographic splat request."""
    var request = String('{"mode":"ortho","columns":')
    request += json_compact(spans, json_member(spans, span, "columns"))
    request += ',"rows":'
    request += json_compact(spans, json_member(spans, span, "rows"))
    request += ',"samples":3,"cap":8192,"seed":11,"right":'
    request += json_compact(doc, json_member(doc, view, "right"))
    request += ',"up":'
    request += json_compact(doc, json_member(doc, view, "up"))
    request += ',"forward":'
    request += json_compact(doc, json_member(doc, view, "forward"))
    request += ',"low_r":'
    request += json_compact(spans, json_member(spans, span, "low_r"))
    request += ',"low_u":'
    request += json_compact(spans, json_member(spans, span, "low_u"))
    request += ',"height":'
    request += json_compact(spans, json_member(spans, span, "height"))
    request += ',"span_u":'
    request += json_compact(spans, json_member(spans, span, "width"))
    request += ',"span_v":'
    request += json_compact(spans, json_member(spans, span, "height"))
    request += ',"parts":'
    request += parts_json
    request += "}"
    return request


def _spread(rgba_text: String) raises -> String:
    """Return one view after empty texels take a neighbor's color."""
    var image = PyJson.parse(rgba_text)
    if image.kind(image.root) != PY_LIST or image.length(image.root) == 0:
        raise Error("view is empty")
    var colors = List[UInt8]()
    var covered = List[UInt8]()
    append_ascii(colors, "[")
    append_ascii(covered, "[")
    var height = image.length(image.root)
    for row in range(height):
        if row > 0:
            append_ascii(colors, ",")
            append_ascii(covered, ",")
        var line = image.item(image.root, row)
        if image.kind(line) != PY_LIST:
            raise Error("view row is not a list")
        append_ascii(colors, "[")
        append_ascii(covered, "[")
        var width = image.length(line)
        for column in range(width):
            if column > 0:
                append_ascii(colors, ",")
                append_ascii(covered, ",")
            var pixel = image.item(line, column)
            if image.kind(pixel) != PY_LIST or image.length(pixel) != 4:
                raise Error("pixel is not RGBA")
            append_ascii(colors, "[")
            append_ascii(colors, json_compact(image, image.item(pixel, 0)))
            append_ascii(colors, ",")
            append_ascii(colors, json_compact(image, image.item(pixel, 1)))
            append_ascii(colors, ",")
            append_ascii(colors, json_compact(image, image.item(pixel, 2)))
            append_ascii(colors, "]")
            if (
                _number(image, image.item(pixel, 3), "alpha is not a number")
                > 0.0
            ):
                append_ascii(covered, "true")
            else:
                append_ascii(covered, "false")
        append_ascii(colors, "]")
        append_ascii(covered, "]")
    append_ascii(colors, "]")
    append_ascii(covered, "]")
    var folder = mkdtemp(prefix="town bake ")
    var file = folder + "/view.json"
    Path(file).write_text(
        '{"image":'
        + ascii_text(colors)
        + ',"covered":'
        + ascii_text(covered)
        + ',"passes":6}'
    )
    var dilated = dilate_text(file)
    _remove_tree(folder)
    return dilated^


def _pack_request(
    doc: PyJson,
    far: Int,
    views: Int,
    spans: PyJson,
    drawn: List[String],
) raises -> String:
    """Return the atlas pack request."""
    var out = String('{"mode":"pack","positions":')
    out += json_compact(doc, json_member(doc, far, "positions"))
    out += ',"normals":'
    out += json_compact(doc, json_member(doc, far, "normals"))
    out += ',"views":['
    for index in range(doc.length(views)):
        if index > 0:
            out += ","
        var view = doc.item(views, index)
        var span = spans.item(spans.root, index)
        out += '{"forward":'
        out += json_compact(doc, json_member(doc, view, "forward"))
        out += ',"right":'
        out += json_compact(doc, json_member(doc, view, "right"))
        out += ',"up":'
        out += json_compact(doc, json_member(doc, view, "up"))
        out += ',"span_r":['
        out += json_compact(spans, json_member(spans, span, "low_r"))
        out += ","
        out += json_compact(spans, json_member(spans, span, "high_r"))
        out += '],"span_u":['
        out += json_compact(spans, json_member(spans, span, "low_u"))
        out += ","
        out += json_compact(spans, json_member(spans, span, "high_u"))
        out += '],"image":'
        out += drawn[index]
        out += "}"
    out += "]}"
    return out


def _write_jpeg(path: String, packed: String) raises:
    """Quantize the atlas and write the JPEG."""
    var atlas = _array_of(packed, "atlas")
    var stored = pack_text('{"mode":"quantize","image":' + atlas + "}")
    var doc = PyJson.parse(stored)
    var jpeg = jpeg_text(
        '{"mode":"RGB","width":'
        + String(json_named_int(doc, doc.at(doc.root, "width"), "width"))
        + ',"height":'
        + String(json_named_int(doc, doc.at(doc.root, "height"), "height"))
        + ',"quality":85,"optimize":false,"pixels":'
        + _array_of(stored, "pixels")
        + "}"
    )
    var folder = _directory(path)
    if folder.byte_length() > 0:
        makedirs(folder, exist_ok=True)
    Path(path).write_bytes(Span(jpeg))


def _array_of(text: String, key: String) raises -> String:
    """Return the JSON value stored at `key`."""
    var marker = String('"') + key + '":'
    var start = text.find(marker)
    if start < 0:
        raise Error("bake result has no " + key)
    var raw = text.as_bytes()
    var at = start + len(marker.as_bytes())
    while at < len(raw) and raw[at] == 32:
        at += 1
    if at >= len(raw):
        raise Error("bake result has no " + key)
    var open = raw[at]
    var close: UInt8
    if open == 91:
        close = 93
    elif open == 123:
        close = 125
    else:
        raise Error("bake result has no " + key)
    var depth = 0
    var end = at
    var found = False
    for index in range(at, len(raw)):
        var byte = raw[index]
        if byte == open:
            depth += 1
        elif byte == close:
            depth -= 1
            if depth == 0:
                end = index + 1
                found = True
                break
    if not found:
        raise Error("bake result has no " + key)
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


def _number(doc: PyJson, node: Int, message: String) raises -> Float64:
    """Return a JSON number, or raise `message`."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error(message)


def main() raises:
    """Draw the building in the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_bake FILE", file=stderr)
        exit(2)
    try:
        print(bake_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_bake:", error, file=stderr)
        exit(1)
