# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Resize one 8-bit image the way Pillow does.

    carla_image_resize FILE

`FILE` is JSON with `mode`, `width`, `height`, `bands`, `out_width`,
`out_height` and `pixels`. `mode` is `lanczos` or `box`. `bands` is 1,
3 or 4. A 4-band image is premultiplied, resized, then restored. The
horizontal pass runs before the vertical pass. The pixels match Pillow
12.3.
"""

from std.ffi import external_call
from std.math import ceil
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float
from tools._python_json import PY_DICT, PY_FLOAT, PY_INT, PY_LIST, PyJson


comptime PRECISION = 22
comptime BIAS = 1 << (PRECISION - 1)
comptime PI = 3.141592653589793


def resize_text(text: String) raises -> String:
    """Return the resized pixels as JSON.

    Args:
        text: A JSON object with the source image and the output size.

    Returns:
        `pixels`, one integer per channel, row by row.

    Raises:
        Error: If the JSON is not that image, or a pixel is out of range.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("resize request is not an object")
    var mode = doc.text(doc.at(root, "mode"))
    var lanczos = False
    if mode == "lanczos":
        lanczos = True
    elif mode != "box":
        raise Error("mode is not lanczos or box")
    var width = _whole(doc, doc.at(root, "width"), "size is not an integer")
    var height = _whole(doc, doc.at(root, "height"), "size is not an integer")
    var bands = _whole(doc, doc.at(root, "bands"), "size is not an integer")
    var out_w = _whole(doc, doc.at(root, "out_width"), "size is not an integer")
    var out_h = _whole(
        doc, doc.at(root, "out_height"), "size is not an integer"
    )
    if width < 1 or height < 1 or out_w < 1 or out_h < 1:
        raise Error("size is not positive")
    if bands != 1 and bands != 3 and bands != 4:
        raise Error("bands is not 1, 3, or 4")
    var pixels = _pixels(doc, doc.at(root, "pixels"), width * height * bands)
    if out_w != width or out_h != height:
        if bands == 4:
            _premultiply(pixels)
        if out_w != width:
            pixels = _horizontal(pixels, width, height, bands, out_w, lanczos)
            width = out_w
        if out_h != height:
            pixels = _vertical(pixels, width, height, bands, out_h, lanczos)
        if bands == 4:
            _unpremultiply(pixels)
    var out = String('{"pixels":[')
    for index in range(len(pixels)):
        if index > 0:
            out += ","
        out += String(pixels[index])
    out += "]}"
    return out^


def _horizontal(
    pixels: List[Int],
    width: Int,
    height: Int,
    bands: Int,
    out_w: Int,
    lanczos: Bool,
) -> List[Int]:
    """Resize every row."""
    var xmin = List[Int]()
    var xmax = List[Int]()
    var coeffs = List[Int]()
    var ksize = _coeffs(width, out_w, lanczos, xmin, xmax, coeffs)
    var out = List[Int]()
    for _ in range(out_w * height * bands):
        out.append(0)
    for yy in range(height):
        for xx in range(out_w):
            var acc0 = BIAS
            var acc1 = BIAS
            var acc2 = BIAS
            var acc3 = BIAS
            var start = xmin[xx]
            var count = xmax[xx]
            var base = xx * ksize
            for x in range(count):
                var src = ((yy * width) + (x + start)) * bands
                var weight = coeffs[base + x]
                acc0 = _i32(acc0 + pixels[src] * weight)
                if bands > 1:
                    acc1 = _i32(acc1 + pixels[src + 1] * weight)
                if bands > 2:
                    acc2 = _i32(acc2 + pixels[src + 2] * weight)
                if bands > 3:
                    acc3 = _i32(acc3 + pixels[src + 3] * weight)
            var dst = (yy * out_w + xx) * bands
            out[dst] = _clip8(acc0)
            if bands > 1:
                out[dst + 1] = _clip8(acc1)
            if bands > 2:
                out[dst + 2] = _clip8(acc2)
            if bands > 3:
                out[dst + 3] = _clip8(acc3)
    return out^


def _vertical(
    pixels: List[Int],
    width: Int,
    height: Int,
    bands: Int,
    out_h: Int,
    lanczos: Bool,
) -> List[Int]:
    """Resize every column."""
    var ymin = List[Int]()
    var ymax = List[Int]()
    var coeffs = List[Int]()
    var ksize = _coeffs(height, out_h, lanczos, ymin, ymax, coeffs)
    var out = List[Int]()
    for _ in range(width * out_h * bands):
        out.append(0)
    for yy in range(out_h):
        var start = ymin[yy]
        var count = ymax[yy]
        var base = yy * ksize
        for xx in range(width):
            var acc0 = BIAS
            var acc1 = BIAS
            var acc2 = BIAS
            var acc3 = BIAS
            for y in range(count):
                var src = (((y + start) * width) + xx) * bands
                var weight = coeffs[base + y]
                acc0 = _i32(acc0 + pixels[src] * weight)
                if bands > 1:
                    acc1 = _i32(acc1 + pixels[src + 1] * weight)
                if bands > 2:
                    acc2 = _i32(acc2 + pixels[src + 2] * weight)
                if bands > 3:
                    acc3 = _i32(acc3 + pixels[src + 3] * weight)
            var dst = (yy * width + xx) * bands
            out[dst] = _clip8(acc0)
            if bands > 1:
                out[dst + 1] = _clip8(acc1)
            if bands > 2:
                out[dst + 2] = _clip8(acc2)
            if bands > 3:
                out[dst + 3] = _clip8(acc3)
    return out^


def _coeffs(
    in_size: Int,
    out_size: Int,
    lanczos: Bool,
    mut origin: List[Int],
    mut count: List[Int],
    mut coeffs: List[Int],
) -> Int:
    """Return the fixed-point weights for one axis."""
    var scale = _fdiv(Float64(in_size), Float64(out_size))
    var filterscale = scale
    if filterscale < 1.0:
        filterscale = 1.0
    var support = 0.5
    if lanczos:
        support = 3.0
    support = _fmul(support, filterscale)
    var ksize = Int(ceil(support)) * 2 + 1
    var inv = _fdiv(1.0, filterscale)
    for xx in range(out_size):
        var center = _fadd(0.0, _fmul(Float64(xx) + 0.5, scale))
        var xmin = _trunc(_fadd(_fsub(center, support), 0.5))
        if xmin < 0:
            xmin = 0
        var xmax = _trunc(_fadd(_fadd(center, support), 0.5))
        if xmax > in_size:
            xmax = in_size
        xmax -= xmin
        var weights = List[Float64]()
        var total = 0.0
        for x in range(xmax):
            var pos = _fadd(_fsub(Float64(x + xmin), center), 0.5)
            pos = _fmul(pos, inv)
            var weight = _kernel(pos, lanczos)
            weights.append(weight)
            total = _fadd(total, weight)
        if total != 0.0:
            for x in range(len(weights)):
                weights[x] = _fdiv(weights[x], total)
        origin.append(xmin)
        count.append(xmax)
        for x in range(ksize):
            var weight = 0.0
            if x < len(weights):
                weight = weights[x]
            var scaled = _fmul(weight, Float64(1 << PRECISION))
            if weight < 0.0:
                coeffs.append(_trunc(_fadd(-0.5, scaled)))
            else:
                coeffs.append(_trunc(_fadd(0.5, scaled)))
    return ksize


def _kernel(x: Float64, lanczos: Bool) -> Float64:
    """Return one Pillow filter weight."""
    if lanczos:
        if -3.0 <= x and x < 3.0:
            return _fmul(_sinc(x), _sinc(_fdiv(x, 3.0)))
        return 0.0
    if -0.5 < x and x <= 0.5:
        return 1.0
    return 0.0


def _sinc(x: Float64) -> Float64:
    """Return sin(pi x) / (pi x), or 1 at zero."""
    if x == 0.0:
        return 1.0
    var angle = _fmul(x, PI)
    return _fdiv(_sin(angle), angle)


def _premultiply(mut pixels: List[Int]):
    """Store straight RGBA as Pillow's premultiplied RGBa."""
    var index = 0
    while index < len(pixels):
        var alpha = pixels[index + 3]
        for channel in range(3):
            pixels[index + channel] = (
                pixels[index + channel] * alpha + 127
            ) // 255
        index += 4


def _unpremultiply(mut pixels: List[Int]):
    """Restore straight RGBA from Pillow's premultiplied RGBa."""
    var index = 0
    while index < len(pixels):
        var alpha = pixels[index + 3]
        for channel in range(3):
            if alpha != 0:
                var straight = (pixels[index + channel] * 255) // alpha
                if straight > 255:
                    straight = 255
                pixels[index + channel] = straight
        index += 4


def _pixels(doc: PyJson, node: Int, expect: Int) raises -> List[Int]:
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


def _clip8(value: Int) -> Int:
    """Return an 8-bit sample from a fixed-point sum."""
    var shifted = value >> PRECISION
    if shifted < 0:
        return 0
    if shifted > 255:
        return 255
    return shifted


def _i32(value: Int) -> Int:
    """Return `value` wrapped to a signed 32-bit integer."""
    var bits = value & 0xFFFFFFFF
    if bits >= 0x80000000:
        return bits - 0x100000000
    return bits


def _trunc(value: Float64) -> Int:
    """Return `value` truncated toward zero."""
    if value < 0.0:
        return -Int(-value)
    return Int(value)


def _whole(doc: PyJson, node: Int, message: String) raises -> Int:
    """Return a JSON integer, or raise `message`."""
    if doc.kind(node) != PY_INT:
        raise Error(message)
    return Int(parse_float(doc.text(node)))


def _sin(value: Float64) -> Float64:
    """Return libm's sine."""
    return external_call["sin", Float64](value)


@no_inline
def _fmul(left: Float64, right: Float64) -> Float64:
    """Return one product, rounded before the next operation."""
    return left * right


@no_inline
def _fadd(left: Float64, right: Float64) -> Float64:
    """Return one sum, rounded before the next operation."""
    return left + right


@no_inline
def _fsub(left: Float64, right: Float64) -> Float64:
    """Return one difference, rounded before the next operation."""
    return left - right


@no_inline
def _fdiv(left: Float64, right: Float64) -> Float64:
    """Return one quotient, rounded before the next operation."""
    return left / right


def main() raises:
    """Print the resized pixels for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_image_resize FILE", file=stderr)
        exit(2)
    try:
        print(resize_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_image_resize:", error, file=stderr)
        exit(1)
