# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the pixels a CARLA texture file stores.

    carla_image_pack FILE

`FILE` is JSON. `mode` is `color`, `masked`, `stitch` or `atlas`.
`color` builds the RGB samples of one texture, including a neutral 8
pixel square and a fitted resize. `masked` builds an RGBA cut-out.
`stitch` joins two RGBA pictures side by side, one row at a time.
`atlas` turns two float pictures into bytes, resizes each one, and
joins them the same way.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float, python_repr
from tools._python_json import (
    PY_BOOL,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
)
from tools.carla_image_resize import resize_text
from tools.carla_mask_channel import mask_text


def pack_text(text: String) raises -> String:
    """Return packaged texture pixels as JSON.

    Args:
        text: A JSON object. `mode` selects `color`, `masked`, `stitch`
            or `atlas`.

    Returns:
        `width`, `height`, `bands` and `pixels`. `color` has 3 bands.
        `masked` and `stitch` have 4.

    Raises:
        Error: If the JSON is not that picture, or a pixel is out of range.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("pack request is not an object")
    var mode_node = doc.at(root, "mode")
    if doc.kind(mode_node) != PY_STR:
        raise Error("mode is not color, masked, stitch or atlas")
    var mode = doc.text(mode_node)
    if mode == "color":
        return _color(doc, root)
    if mode == "masked":
        return _masked(doc, root)
    if mode == "stitch":
        return _stitch(doc, root)
    if mode == "atlas":
        return _atlas(doc, root)
    raise Error("mode is not color, masked, stitch or atlas")


def _color(doc: PyJson, root: Int) raises -> String:
    """Return the RGB samples of one color texture."""
    var width = _positive(doc, doc.at(root, "width"))
    var height = _positive(doc, doc.at(root, "height"))
    var rgba = _bytes(doc, doc.at(root, "pixels"), width * height * 4)
    var neutral = _flag(doc, doc.at(root, "neutral"))
    var resize = _flag(doc, doc.at(root, "resize"))
    var image_mode = _mode_name(doc, doc.at(root, "image_mode"))
    if neutral:
        var average = _resized(_rgb(rgba), width, height, 3, 1, 1, "box")
        rgba = _tile(average)
        width = 8
        height = 8
        image_mode = String("RGB")
    var out_w = width
    var out_h = height
    if resize:
        out_w = _positive(doc, doc.at(root, "out_width"))
        out_h = _positive(doc, doc.at(root, "out_height"))
        rgba = _resize_color(image_mode, rgba, width, height, out_w, out_h)
    else:
        rgba = _rgb(rgba)
    return _emit(out_w, out_h, 3, rgba)


def _masked(doc: PyJson, root: Int) raises -> String:
    """Return the RGBA samples of one cut-out texture."""
    var width = _positive(doc, doc.at(root, "width"))
    var height = _positive(doc, doc.at(root, "height"))
    var color = _bytes(doc, doc.at(root, "color"), width * height * 4)
    var mask_w = _positive(doc, doc.at(root, "mask_width"))
    var mask_h = _positive(doc, doc.at(root, "mask_height"))
    var mask = _bytes(doc, doc.at(root, "mask"), mask_w * mask_h * 4)
    var mask_mode = _mode_name(doc, doc.at(root, "mask_mode"))
    var resize = _flag(doc, doc.at(root, "resize"))
    var alpha: List[Int]
    if mask_mode == "RGBA" or mask_mode == "LA":
        alpha = _alpha(mask)
    else:
        alpha = _mask_alpha(_rgb(mask), mask_w, mask_h)
    if mask_w != width or mask_h != height:
        alpha = _resized(alpha, mask_w, mask_h, 1, width, height, "lanczos")
    var rgba = _compose(_rgb(color), alpha)
    var out_w = width
    var out_h = height
    if resize:
        out_w = _positive(doc, doc.at(root, "out_width"))
        out_h = _positive(doc, doc.at(root, "out_height"))
        rgba = _resized(rgba, width, height, 4, out_w, out_h, "lanczos")
    return _emit(out_w, out_h, 4, rgba)


def _stitch(doc: PyJson, root: Int) raises -> String:
    """Join two equal RGBA pictures side by side."""
    var width = _positive(doc, doc.at(root, "width"))
    var height = _positive(doc, doc.at(root, "height"))
    var count = width * height * 4
    var left = _bytes(doc, doc.at(root, "left"), count)
    var right = _bytes(doc, doc.at(root, "right"), count)
    var row = width * 4
    var out = List[Int]()
    for y in range(height):
        var start = y * row
        for offset in range(row):
            out.append(left[start + offset])
        for offset in range(row):
            out.append(right[start + offset])
    return _emit(width * 2, height, 4, out)


def _atlas(doc: PyJson, root: Int) raises -> String:
    """Quantize two float pictures, resize them, and join them."""
    var size = _positive(doc, doc.at(root, "size"))
    var views = doc.at(root, "views")
    if doc.kind(views) != PY_LIST or doc.length(views) != 2:
        raise Error("atlas needs two views")
    var left = _view_bytes(doc, doc.item(views, 0), size)
    var right = _view_bytes(doc, doc.item(views, 1), size)
    var row = size * 4
    var out = List[Int]()
    for y in range(size):
        var start = y * row
        for offset in range(row):
            out.append(left[start + offset])
        for offset in range(row):
            out.append(right[start + offset])
    return _emit(size * 2, size, 4, out)


def _view_bytes(doc: PyJson, node: Int, size: Int) raises -> List[Int]:
    """Return one float picture as resized RGBA bytes."""
    var samples = List[Float64]()
    var width = 0
    var height = 0
    _float_image(doc, node, width, height, samples)
    var request = String('{"mode":"bytes","pixels":[')
    for index in range(len(samples)):
        if index > 0:
            request += ","
        request += python_repr(samples[index])
    request += "]}"
    var quantized = PyJson.parse(resize_text(request))
    var pixels = _bytes(
        quantized,
        quantized.at(quantized.root, "pixels"),
        width * height * 4,
    )
    return _resized(pixels, width, height, 4, size, size, "lanczos")


def _float_image(
    doc: PyJson,
    node: Int,
    mut width: Int,
    mut height: Int,
    mut samples: List[Float64],
) raises:
    """Read one RGBA picture of unit floats."""
    if doc.kind(node) != PY_LIST or doc.length(node) == 0:
        raise Error("image is empty")
    height = doc.length(node)
    width = 0
    for row in range(height):
        var line = doc.item(node, row)
        if doc.kind(line) != PY_LIST:
            raise Error("image row is not a list")
        if row == 0:
            width = doc.length(line)
        elif doc.length(line) != width:
            raise Error("image rows differ")
        if width == 0:
            raise Error("image is empty")
        for column in range(width):
            var pixel = doc.item(line, column)
            if doc.kind(pixel) != PY_LIST or doc.length(pixel) != 4:
                raise Error("pixel is not 4 numbers")
            for channel in range(4):
                samples.append(_sample(doc, doc.item(pixel, channel)))


def _sample(doc: PyJson, node: Int) raises -> Float64:
    """Return one unit sample."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("sample is not a number")


def _resize_color(
    mode: String,
    rgba: List[Int],
    width: Int,
    height: Int,
    out_w: Int,
    out_h: Int,
) raises -> List[Int]:
    """Return RGB samples after the fitted resize for `mode`."""
    if mode == "P":
        return _rgb(_nearest(rgba, width, height, out_w, out_h))
    if mode == "LA" or mode == "RGBA":
        return _rgb(_resized(rgba, width, height, 4, out_w, out_h, "lanczos"))
    if mode == "L":
        var gray = _resized(
            _channel0(rgba), width, height, 1, out_w, out_h, "lanczos"
        )
        var out = List[Int]()
        for index in range(len(gray)):
            var value = gray[index]
            out.append(value)
            out.append(value)
            out.append(value)
        return out^
    return _resized(_rgb(rgba), width, height, 3, out_w, out_h, "lanczos")


def _nearest(
    pixels: List[Int], width: Int, height: Int, out_w: Int, out_h: Int
) -> List[Int]:
    """Return a nearest resize of RGBA samples."""
    var out = List[Int]()
    for y in range(out_h):
        var sy = _sample(y, height, out_h)
        for x in range(out_w):
            var sx = _sample(x, width, out_w)
            var start = (sy * width + sx) * 4
            out.append(pixels[start])
            out.append(pixels[start + 1])
            out.append(pixels[start + 2])
            out.append(pixels[start + 3])
    return out^


def _sample(pos: Int, source: Int, dest: Int) -> Int:
    """Return the source column Pillow uses for a palette sample."""
    var scaled = _fdiv(
        _fmul(_fadd(Float64(pos), 0.5), Float64(source)), Float64(dest)
    )
    var index = Int(scaled)
    var last = source - 1
    if index < last:
        return index
    return last


def _resized(
    pixels: List[Int],
    width: Int,
    height: Int,
    bands: Int,
    out_w: Int,
    out_h: Int,
    mode: String,
) raises -> List[Int]:
    """Return samples from `tools/carla_image_resize.mojo`."""
    var request = String('{"mode":"')
    request += mode
    request += '","width":'
    request += String(width)
    request += ',"height":'
    request += String(height)
    request += ',"bands":'
    request += String(bands)
    request += ',"out_width":'
    request += String(out_w)
    request += ',"out_height":'
    request += String(out_h)
    request += ',"pixels":['
    for index in range(len(pixels)):
        if index > 0:
            request += ","
        request += String(pixels[index])
    request += "]}"
    var parsed = PyJson.parse(resize_text(request))
    return _bytes(
        parsed, parsed.at(parsed.root, "pixels"), out_w * out_h * bands
    )


def _mask_alpha(rgb: List[Int], width: Int, height: Int) raises -> List[Int]:
    """Return the cut-out channel from `tools/carla_mask_channel.mojo`."""
    var request = String('{"width":')
    request += String(width)
    request += ',"height":'
    request += String(height)
    request += ',"pixels":['
    for index in range(len(rgb)):
        if index > 0:
            request += ","
        request += String(rgb[index])
    request += "]}"
    var parsed = PyJson.parse(mask_text(request))
    return _bytes(parsed, parsed.at(parsed.root, "pixels"), width * height)


def _tile(rgb: List[Int]) -> List[Int]:
    """Return an 8 by 8 RGBA square of one RGB color."""
    var out = List[Int]()
    for _ in range(64):
        out.append(rgb[0])
        out.append(rgb[1])
        out.append(rgb[2])
        out.append(255)
    return out^


def _rgb(pixels: List[Int]) -> List[Int]:
    """Drop the alpha sample of each RGBA pixel."""
    var out = List[Int]()
    var index = 0
    while index + 3 <= len(pixels):
        out.append(pixels[index])
        out.append(pixels[index + 1])
        out.append(pixels[index + 2])
        index += 4
    return out^


def _channel0(pixels: List[Int]) -> List[Int]:
    """Return the first sample of each RGBA pixel."""
    var out = List[Int]()
    var index = 0
    while index < len(pixels):
        out.append(pixels[index])
        index += 4
    return out^


def _alpha(pixels: List[Int]) -> List[Int]:
    """Return the alpha sample of each RGBA pixel."""
    var out = List[Int]()
    var index = 3
    while index < len(pixels):
        out.append(pixels[index])
        index += 4
    return out^


def _compose(rgb: List[Int], alpha: List[Int]) raises -> List[Int]:
    """Join RGB samples with one alpha sample per pixel."""
    if len(rgb) != len(alpha) * 3:
        raise Error("pixels do not match the image")
    var out = List[Int]()
    for index in range(len(alpha)):
        var base = index * 3
        out.append(rgb[base])
        out.append(rgb[base + 1])
        out.append(rgb[base + 2])
        out.append(alpha[index])
    return out^


def _emit(width: Int, height: Int, bands: Int, pixels: List[Int]) -> String:
    """Return one picture as JSON."""
    var out = String('{"width":')
    out += String(width)
    out += ',"height":'
    out += String(height)
    out += ',"bands":'
    out += String(bands)
    out += ',"pixels":['
    for index in range(len(pixels)):
        if index > 0:
            out += ","
        out += String(pixels[index])
    out += "]}"
    return out^


def _mode_name(doc: PyJson, node: Int) raises -> String:
    """Return an image mode name."""
    if doc.kind(node) != PY_STR:
        raise Error("image mode is not text")
    return doc.text(node)


def _flag(doc: PyJson, node: Int) raises -> Bool:
    """Return a JSON bool."""
    if doc.kind(node) != PY_BOOL:
        raise Error("flag is not a bool")
    return doc.flag(node)


def _positive(doc: PyJson, node: Int) raises -> Int:
    """Return a size that is at least one."""
    var value = _whole(doc, node, "size is not an integer")
    if value < 1:
        raise Error("size is not positive")
    return value


def _bytes(doc: PyJson, node: Int, expect: Int) raises -> List[Int]:
    """Read `expect` pixel bytes."""
    if doc.kind(node) != PY_LIST or doc.length(node) != expect:
        raise Error("pixels do not match the image")
    var out = List[Int]()
    for index in range(expect):
        var value = _whole(
            doc, doc.item(node, index), "pixel is not an integer"
        )
        if value < 0 or value > 255:
            raise Error("pixel is out of range")
        out.append(value)
    return out^


def _whole(doc: PyJson, node: Int, message: String) raises -> Int:
    """Return a JSON integer, or raise `message`."""
    if doc.kind(node) != PY_INT:
        raise Error(message)
    return Int(parse_float(doc.text(node)))


@no_inline
def _fmul(left: Float64, right: Float64) -> Float64:
    """Return one product, rounded before the next operation."""
    return left * right


@no_inline
def _fadd(left: Float64, right: Float64) -> Float64:
    """Return one sum, rounded before the next operation."""
    return left + right


@no_inline
def _fdiv(left: Float64, right: Float64) -> Float64:
    """Return one quotient, rounded before the next operation."""
    return left / right


def main() raises:
    """Print the packaged pixels for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_image_pack FILE", file=stderr)
        exit(2)
    try:
        print(pack_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_image_pack:", error, file=stderr)
        exit(1)
