# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose how a CARLA texture is packaged.

    carla_texture_plan FILE

`FILE` is JSON. `texture` reads a file path, whether the texture is a
color, the size limit and the image size. A neutral name becomes an 8
pixel square of its average color, then the limit is applied. `fit`
applies only the limit. The fitted size uses Python's `round`, half to
even, and is at least one pixel. Color is JPEG at quality 88. A neutral
data texture is JPEG with optimization. Any other data texture is an
optimized PNG.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import PY_BOOL, PY_DICT, PY_INT, PyJson
from tools._python_math import round_half_even
from tools._sha256 import sha256_hex


@no_inline
def _fmul(a: Float64, b: Float64) -> Float64:
    """Return one product, kept separate from a fused operation."""
    return a * b


@no_inline
def _fdiv(a: Float64, b: Float64) -> Float64:
    """Return one quotient, kept separate from a fused operation."""
    return a / b


def plan_text(text: String) raises -> String:
    """Return the packaged size and encoding as JSON.

    Args:
        text: A JSON object. `mode` is `texture`, `fit` or `name`.

    Returns:
        For `texture` and `fit`: `neutral`, `width`, `height`, `resize`,
        `format`, `quality` and `optimize`. `quality` is -1 when the
        encoder keeps its default. For `name`: `name`, the SHA-256 of the
        file plus `texture_` and the suffix.

    Raises:
        Error: If the JSON is not that object, a size is not usable, or
            the format is not JPEG or PNG.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("texture plan is not an object")
    var mode = doc.text(doc.at(root, "mode"))
    if mode == "name":
        return _name(doc, root)
    if mode != "texture" and mode != "fit":
        raise Error("texture mode is not texture, fit or name")
    var width = _whole(doc, doc.at(root, "width"))
    var height = _whole(doc, doc.at(root, "height"))
    var limit = _whole(doc, doc.at(root, "max"))
    if width < 0 or height < 0 or limit < 0:
        raise Error("image size is negative")
    var neutral = False
    if mode == "texture":
        neutral = _neutral(_stem(doc.text(doc.at(root, "path"))))
        if neutral:
            width = 8
            height = 8
    var fitted = _fit(width, height, limit)
    var color = False
    if mode == "texture":
        color = _flag(doc, doc.at(root, "color"))
    var format = String("PNG")
    var quality = -1
    var optimize = True
    if mode == "texture" and color:
        format = "JPEG"
        quality = 88
        optimize = False
    elif neutral:
        format = "JPEG"
    var out = String('{"neutral":')
    out += _bool(neutral)
    out += ',"width":'
    out += String(fitted.width)
    out += ',"height":'
    out += String(fitted.height)
    out += ',"resize":'
    out += _bool(fitted.resize)
    out += ',"format":"'
    out += format
    out += '","quality":'
    out += String(quality)
    out += ',"optimize":'
    out += _bool(optimize)
    out += "}"
    return out^


@fieldwise_init
struct _Fit(ImplicitlyCopyable, Movable):
    var width: Int
    var height: Int
    var resize: Bool


def _name(doc: PyJson, root: Int) raises -> String:
    """Return the packaged file name of one encoded image."""
    var path = doc.text(doc.at(root, "path"))
    var format = doc.text(doc.at(root, "format"))
    var suffix = String(".png")
    if format == "JPEG":
        suffix = ".jpg"
    elif format != "PNG":
        raise Error("texture format is not JPEG or PNG")
    var digest = sha256_hex(Path(path).read_bytes())
    return '{"name":"texture_' + digest + suffix + '"}'


def _fit(width: Int, height: Int, limit: Int) raises -> _Fit:
    """Return the size after the limit, and whether it changed."""
    var big = width
    if height > big:
        big = height
    if big == 0:
        raise Error("image size is not positive")
    if big <= limit:
        return _Fit(width, height, False)
    var scale = _fdiv(Float64(limit), Float64(big))
    var out_w = _at_least_one(round_half_even(_fmul(Float64(width), scale)))
    var out_h = _at_least_one(round_half_even(_fmul(Float64(height), scale)))
    return _Fit(out_w, out_h, out_w != width or out_h != height)


def _at_least_one(value: Float64) -> Int:
    """Return `max(1, round(value))` for a whole-valued float."""
    var whole = Int(value)
    if whole < 1:
        return 1
    return whole


def _neutral(stem: String) -> Bool:
    """Return whether `stem` starts with a neutral texture name."""
    var names = List[String]()
    names.append("bmw_logo")
    names.append("vh_car_mercedesbenzcoupe_mercedestopmat_basecolor")
    names.append("vh_car_minicoopers_minimat")
    names.append("t_carlacola_d")
    names.append("vh_truck_carlacola_bodyworkmat_basecolor")
    names.append("t_billboard_d")
    names.append("sm_banner_")
    names.append("t_banner")
    for index in range(len(names)):
        if _starts(stem, names[index]):
            return True
    return False


def _stem(path: String) -> String:
    """Return the file stem, as `splitext(basename(path))` does."""
    var base = _basename(path)
    var raw = base.as_bytes()
    var dot = -1
    for index in range(len(raw)):
        if raw[index] == 46:
            dot = index
    if dot <= 0:
        return base
    return String(base[byte=:dot])


def _basename(path: String) -> String:
    """Return the last path segment. `/` and `\\` are separators."""
    var raw = path.as_bytes()
    var slash = -1
    for index in range(len(raw)):
        var byte = raw[index]
        if byte == 47 or byte == 92:
            slash = index
    if slash < 0:
        return path
    return String(path[byte = slash + 1 :])


def _starts(text: String, prefix: String) -> Bool:
    """Return whether `text` starts with `prefix`, ignoring ASCII case."""
    var raw = text.as_bytes()
    var pat = prefix.as_bytes()
    if len(pat) == 0 or len(raw) < len(pat):
        return False
    for index in range(len(pat)):
        if _fold(raw[index]) != _fold(pat[index]):
            return False
    return True


def _fold(byte: UInt8) -> UInt8:
    """Return the ASCII lowercase of one byte."""
    if byte >= 65 and byte <= 90:
        return byte + 32
    return byte


def _flag(doc: PyJson, node: Int) raises -> Bool:
    """Return a JSON bool."""
    if doc.kind(node) != PY_BOOL:
        raise Error("color is not a bool")
    return doc.flag(node)


def _whole(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("size is not an integer")
    return _digits(doc.text(node))


def _digits(text: String) raises -> Int:
    """Return the integer written in `text`."""
    var raw = text.as_bytes()
    if len(raw) == 0:
        raise Error("size is not an integer")
    var index = 0
    var negative = False
    if raw[0] == 45:
        negative = True
        index = 1
    if index >= len(raw):
        raise Error("size is not an integer")
    var value = 0
    for offset in range(index, len(raw)):
        var byte = raw[offset]
        if byte < 48 or byte > 57:
            raise Error("size is not an integer")
        value = value * 10 + Int(byte - 48)
    if negative:
        return -value
    return value


def _bool(value: Bool) -> String:
    """Return `true` or `false`."""
    if value:
        return "true"
    return "false"


def main() raises:
    """Print the texture plan for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_texture_plan FILE", file=stderr)
        exit(2)
    try:
        print(plan_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_texture_plan:", error, file=stderr)
        exit(1)
