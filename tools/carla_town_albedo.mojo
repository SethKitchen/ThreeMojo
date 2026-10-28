# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read one town material's base color.

    carla_town_albedo FILE

`FILE` is JSON. It has `out_dir`, `material`, `textures` and `images`.
The program prints `factor`, four unit numbers. When the material has a
base-color texture, it also prints `image`: the width, the height and
the RGBA samples. Each byte is divided by 255.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float, python_repr
from tools._python_json import (
    MISSING,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
)
from tools.carla_image import image_file, unit_text
from tools._town_json import json_index, json_member


def albedo_text(text: String) raises -> String:
    """Return one material's base color as unit numbers.

    Args:
        text: JSON with `out_dir`, `material`, `textures` and `images`.
            `material` is one glTF material. A missing factor is
            `[1, 1, 1, 1]`.

    Returns:
        JSON with `factor`. `image` is present when the material has a
        base-color texture. Its `rgba` values match NumPy's division by
        255.

    Raises:
        Error: If the JSON is not that material, the factor is not four
            numbers, or the texture file cannot be read.
    """
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_DICT:
        raise Error("albedo request is not an object")
    var out_dir = _text(doc, json_member(doc, doc.root, "out_dir"))
    var material = json_member(doc, doc.root, "material")
    if doc.kind(material) != PY_DICT:
        raise Error("material is not an object")
    var factor = _factor(doc, material)
    var image = _image(doc, material, out_dir)
    var out = String('{"factor":')
    out += factor
    if image.byte_length() > 0:
        out += ',"image":'
        out += image
    out += "}"
    return out


def _factor(doc: PyJson, material: Int) raises -> String:
    """Return four unit factor numbers."""
    var pbr = doc.get(material, "pbrMetallicRoughness")
    if pbr == MISSING or doc.kind(pbr) != PY_DICT:
        return "[1.0,1.0,1.0,1.0]"
    var node = doc.get(pbr, "baseColorFactor")
    if node == MISSING:
        return "[1.0,1.0,1.0,1.0]"
    if doc.kind(node) != PY_LIST or doc.length(node) != 4:
        raise Error("factor is not 4 numbers")
    var out = String("[")
    for index in range(4):
        if index > 0:
            out += ","
        out += python_repr(_number(doc, doc.item(node, index)))
    out += "]"
    return out


def _image(doc: PyJson, material: Int, out_dir: String) raises -> String:
    """Return the base-color image, or an empty string when it is absent."""
    var pbr = doc.get(material, "pbrMetallicRoughness")
    if pbr == MISSING or doc.kind(pbr) != PY_DICT:
        return ""
    var texture = doc.get(pbr, "baseColorTexture")
    if texture == MISSING:
        return ""
    if doc.kind(texture) != PY_DICT:
        raise Error("texture is not an object")
    var index = json_index(doc, json_member(doc, texture, "index"))
    var textures = json_member(doc, doc.root, "textures")
    var images = json_member(doc, doc.root, "images")
    if doc.kind(textures) != PY_LIST or doc.kind(images) != PY_LIST:
        raise Error("textures are not a list")
    if index < 0 or index >= doc.length(textures):
        raise Error("texture index is out of range")
    var source = json_index(
        doc, json_member(doc, doc.item(textures, index), "source")
    )
    if source < 0 or source >= doc.length(images):
        raise Error("image index is out of range")
    var uri = _text(doc, json_member(doc, doc.item(images, source), "uri"))
    var opened = PyJson.parse(image_file(_join(out_dir, uri)))
    var unit = PyJson.parse(
        unit_text(
            '{"pixels":'
            + _compact(opened, opened.at(opened.root, "pixels"))
            + "}"
        )
    )
    var out = String('{"width":')
    out += _compact(opened, opened.at(opened.root, "width"))
    out += ',"height":'
    out += _compact(opened, opened.at(opened.root, "height"))
    out += ',"rgba":'
    out += _compact(unit, unit.at(unit.root, "rgba"))
    out += "}"
    return out


def _join(directory: String, uri: String) -> String:
    """Return `directory` joined with a relative `uri`."""
    var raw = uri.as_bytes()
    if len(raw) > 0 and raw[0] == 47:
        return uri
    var base = directory.as_bytes()
    if len(base) == 0:
        return uri
    if base[len(base) - 1] == 47:
        return directory + uri
    return directory + "/" + uri


def _number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number."""
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("factor is not 4 numbers")


def _text(doc: PyJson, node: Int) raises -> String:
    """Return a JSON string."""
    if doc.kind(node) != PY_STR:
        raise Error("text is not a string")
    return doc.text(node)


def _compact(doc: PyJson, node: Int) raises -> String:
    """Return JSON with no spaces."""
    var kind = doc.kind(node)
    if kind == PY_LIST:
        var out = String("[")
        var count = doc.length(node)
        for index in range(count):
            if index > 0:
                out += ","
            out += _compact(doc, doc.item(node, index))
        out += "]"
        return out
    if kind == PY_INT or kind == PY_FLOAT:
        return doc.text(node)
    raise Error("image value is not a number")


def main() raises:
    """Print the base color for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_albedo FILE", file=stderr)
        exit(2)
    try:
        print(albedo_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_albedo:", error, file=stderr)
        exit(1)
