# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Size a tree impostor and fill its empty texels.

    carla_town_impostor FILE

`FILE` is JSON. `mode` is `frame`, `fill` or `light`. `frame` reads the
tree's points and the picture's width. `parts` is one position list per
mesh, in order. `positions` is that same list already joined. It prints
the two views and the two quads that cross on the trunk. `fill` reads
one RGBA picture. A
texel the tree does not cover takes the mean color of those it does.
`light` prints the unit vector `[0.35, 0.85, 0.4]`.
"""

from std.ffi import external_call
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import (
    append_ascii,
    ascii_text,
    cached_repr,
    python_repr,
)
from tools._python_json import MISSING, PY_DICT, PY_LIST, PyJson
from tools._python_math import round_half_even
from tools._town_json import json_index, json_number, json_vec3


def impostor_text(text: String) raises -> String:
    """Return one impostor step as JSON.

    Args:
        text: A JSON object. `mode` selects the step.

    Returns:
        The view sizes and the crossing quads, or the filled picture.

    Raises:
        Error: If the JSON is not that step.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("impostor request is not an object")
    var mode = doc.text(doc.at(root, "mode"))
    if mode == "frame":
        return _frame(doc, root)
    if mode == "fill":
        return _fill(doc, root)
    if mode == "light":
        return _light()
    raise Error("mode is not frame, fill or light")


def _frame(doc: PyJson, root: Int) raises -> String:
    """Return the two views and the two crossing quads."""
    var px = List[Float64]()
    var py = List[Float64]()
    var pz = List[Float64]()
    var parts = doc.find(root, "parts")
    if parts != MISSING:
        if doc.kind(parts) != PY_LIST:
            raise Error("parts are not a list")
        for index in range(doc.length(parts)):
            json_vec3(doc, doc.item(parts, index), px, py, pz)
    else:
        json_vec3(doc, doc.at(root, "positions"), px, py, pz)
    if len(px) == 0:
        raise Error("positions are empty")
    var size = json_index(doc, doc.at(root, "size"))
    var low_x = px[0]
    var low_y = py[0]
    var low_z = pz[0]
    var high_x = px[0]
    var high_y = py[0]
    var high_z = pz[0]
    for index in range(len(px)):
        if px[index] < low_x:
            low_x = px[index]
        if py[index] < low_y:
            low_y = py[index]
        if pz[index] < low_z:
            low_z = pz[index]
        if px[index] > high_x:
            high_x = px[index]
        if py[index] > high_y:
            high_y = py[index]
        if pz[index] > high_z:
            high_z = pz[index]
    var height = _fsub(high_y, low_y)
    var mid_x = _fdiv(_fadd(low_x, high_x), 2.0)
    var mid_z = _fdiv(_fadd(low_z, high_z), 2.0)
    var out = String('{"low":[')
    out += python_repr(low_x)
    out += ","
    out += python_repr(low_y)
    out += ","
    out += python_repr(low_z)
    out += '],"high":['
    out += python_repr(high_x)
    out += ","
    out += python_repr(high_y)
    out += ","
    out += python_repr(high_z)
    out += '],"views":['
    out += _view(0, low_x, high_x, high_y, height, size)
    out += ","
    out += _view(2, low_z, high_z, high_y, height, size)
    out += '],"positions":['
    _quad(out, low_x, mid_z, low_y, high_y, high_x, mid_z, True)
    _quad(out, mid_x, low_z, low_y, high_y, mid_x, high_z, False)
    out += '],"normals":['
    for index in range(8):
        if index > 0:
            out += ","
        out += "[0.0,1.0,0.0]"
    out += '],"uvs":[[0.0,1.0],[0.5,1.0],[0.5,0.0],[0.0,0.0],'
    out += "[0.5,1.0],[1.0,1.0],[1.0,0.0],[0.5,0.0]],"
    out += '"triangles":[[0,1,2],[0,2,3],[4,5,6],[4,6,7]]}'
    return out^


def _view(
    across: Int,
    low: Float64,
    high: Float64,
    top: Float64,
    height: Float64,
    size: Int,
) raises -> String:
    """Return one view's extent and its row count."""
    var width = _fsub(high, low)
    var denom = width
    if denom < 1e-6:
        denom = 1e-6
    var scaled = _fdiv(_fmul(Float64(size), height), denom)
    var rows = Int(round_half_even(scaled))
    if rows < 8:
        rows = 8
    var out = String('{"across":')
    out += String(across)
    out += ',"left":'
    out += python_repr(low)
    out += ',"top":'
    out += python_repr(top)
    out += ',"width":'
    out += python_repr(width)
    out += ',"height":'
    out += python_repr(height)
    out += ',"rows":'
    out += String(rows)
    out += "}"
    return out^


def _quad(
    mut out: String,
    x0: Float64,
    z0: Float64,
    low_y: Float64,
    high_y: Float64,
    x1: Float64,
    z1: Float64,
    first: Bool,
) raises:
    """Append four corners of one quad."""
    if not first:
        out += ","
    out += "["
    out += python_repr(x0)
    out += ","
    out += python_repr(low_y)
    out += ","
    out += python_repr(z0)
    out += "],["
    out += python_repr(x1)
    out += ","
    out += python_repr(low_y)
    out += ","
    out += python_repr(z1)
    out += "],["
    out += python_repr(x1)
    out += ","
    out += python_repr(high_y)
    out += ","
    out += python_repr(z1)
    out += "],["
    out += python_repr(x0)
    out += ","
    out += python_repr(high_y)
    out += ","
    out += python_repr(z0)
    out += "]"


def _fill(doc: PyJson, root: Int) raises -> String:
    """Give empty texels the mean color of the covered texels."""
    var red = List[Float64]()
    var green = List[Float64]()
    var blue = List[Float64]()
    var alpha = List[Float64]()
    var width = 0
    var height = 0
    _rgba(doc, doc.at(root, "image"), width, height, red, green, blue, alpha)
    var count = 0.0
    var sum_r = 0.0
    var sum_g = 0.0
    var sum_b = 0.0
    for index in range(len(alpha)):
        if alpha[index] > 0.0:
            sum_r = _fadd(sum_r, red[index])
            sum_g = _fadd(sum_g, green[index])
            sum_b = _fadd(sum_b, blue[index])
            count += 1.0
    if count > 0.0:
        sum_r = _fdiv(sum_r, count)
        sum_g = _fdiv(sum_g, count)
        sum_b = _fdiv(sum_b, count)
        for index in range(len(alpha)):
            if alpha[index] <= 0.0:
                red[index] = sum_r
                green[index] = sum_g
                blue[index] = sum_b
    var out = List[UInt8]()
    var cache = Dict[UInt64, String]()
    append_ascii(out, "[")
    for row in range(height):
        if row > 0:
            append_ascii(out, ",")
        append_ascii(out, "[")
        for col in range(width):
            if col > 0:
                append_ascii(out, ",")
            var cell = row * width + col
            append_ascii(out, "[")
            append_ascii(out, cached_repr(red[cell], cache))
            append_ascii(out, ",")
            append_ascii(out, cached_repr(green[cell], cache))
            append_ascii(out, ",")
            append_ascii(out, cached_repr(blue[cell], cache))
            append_ascii(out, ",")
            append_ascii(out, cached_repr(alpha[cell], cache))
            append_ascii(out, "]")
        append_ascii(out, "]")
    append_ascii(out, "]")
    return ascii_text(out)


def _rgba(
    doc: PyJson,
    node: Int,
    mut width: Int,
    mut height: Int,
    mut red: List[Float64],
    mut green: List[Float64],
    mut blue: List[Float64],
    mut alpha: List[Float64],
) raises:
    """Read an RGBA picture."""
    if doc.kind(node) != PY_LIST:
        raise Error("image is not a list")
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
        for column in range(width):
            var pixel = doc.item(line, column)
            if doc.kind(pixel) != PY_LIST or doc.length(pixel) != 4:
                raise Error("pixel is not 4 numbers")
            red.append(json_number(doc, doc.item(pixel, 0)))
            green.append(json_number(doc, doc.item(pixel, 1)))
            blue.append(json_number(doc, doc.item(pixel, 2)))
            alpha.append(json_number(doc, doc.item(pixel, 3)))


def _light() raises -> String:
    """Return the unit impostor light, as NumPy's norm writes it."""
    var xx = _fmul(0.35, 0.35)
    var yy = _fmul(0.85, 0.85)
    var zz = _fmul(0.4, 0.4)
    var norm = external_call["sqrt", Float64](_fadd(_fadd(xx, yy), zz))
    var out = String("[")
    out += python_repr(_fdiv(0.35, norm))
    out += ","
    out += python_repr(_fdiv(0.85, norm))
    out += ","
    out += python_repr(_fdiv(0.4, norm))
    out += "]"
    return out^


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
    """Print one impostor step for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_impostor FILE", file=stderr)
        exit(2)
    try:
        print(impostor_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_impostor:", error, file=stderr)
        exit(1)
