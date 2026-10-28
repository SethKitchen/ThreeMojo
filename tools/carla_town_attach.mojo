# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Add a town material to a package.

    carla_town_attach FILE

`FILE` is JSON. `mode` is `resolve` or `picture`. `resolve` reads a
material `name`. A basic shape, an empty name, or a dummy material
becomes the plain gray material. Any other name is rebuilt from its
files. `picture` adds one baked picture. `kind` is `impostor` or
`baked`. The image, the texture and the material use the counts already
in the package.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float
from tools._python_json import MISSING, PY_DICT, PY_INT, PY_STR, PyJson


comptime PLAIN = "BasicShapeMaterial"
"""The engine shape material, drawn as one flat gray."""
comptime DUMMY = "dummy_material"
"""The prefix of a material that has no exported file."""


def attach_text(text: String) raises -> String:
    """Return a plain material, a rebuild request, or one picture material.

    Args:
        text: JSON with `mode`. `resolve` has `name`. `picture` has
            `kind`, `name`, `uri`, and the current `images`, `textures`
            and `materials` counts.

    Returns:
        `resolve` returns `plain` and the material, or `rebuild`.
        `picture` returns the image, the texture, the material and the
        material index.

    Raises:
        Error: If the JSON is not that request, or a count is negative.
    """
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_DICT:
        raise Error("attach request is not an object")
    var mode = _text(doc, _member(doc, doc.root, "mode"), "mode is not text")
    if mode == "resolve":
        return _resolve(doc)
    if mode == "picture":
        return _picture(doc)
    raise Error("mode is not resolve or picture")


def _resolve(doc: PyJson) raises -> String:
    """Return the plain material, or ask for a rebuilt one."""
    var name = _text(doc, _member(doc, doc.root, "name"), "name is not text")
    if name == PLAIN or name.byte_length() == 0 or _starts(name, DUMMY):
        return (
            '{"action":"plain","material":{"name":"plain",'
            + '"pbrMetallicRoughness":{"baseColorFactor":[0.5,0.5,0.5,1],'
            + '"metallicFactor":0.0,"roughnessFactor":0.7}}}'
        )
    return '{"action":"rebuild"}'


def _picture(doc: PyJson) raises -> String:
    """Return one impostor or baked picture material."""
    var kind = _text(doc, _member(doc, doc.root, "kind"), "kind is not text")
    if kind != "impostor" and kind != "baked":
        raise Error("kind is not impostor or baked")
    var name = _text(doc, _member(doc, doc.root, "name"), "name is not text")
    var uri = _text(doc, _member(doc, doc.root, "uri"), "uri is not text")
    var images = _whole(doc, _member(doc, doc.root, "images"), "images")
    var textures = _whole(doc, _member(doc, doc.root, "textures"), "textures")
    var materials = _whole(
        doc, _member(doc, doc.root, "materials"), "materials"
    )
    if images < 0 or textures < 0 or materials < 0:
        raise Error("count is negative")
    var out = String('{"image":{"uri":')
    out += _quote(uri)
    out += '},"texture":{"sampler":0,"source":'
    out += String(images)
    out += '},"material":{"name":'
    out += _quote(name)
    out += ',"pbrMetallicRoughness":{"baseColorTexture":{"index":'
    out += String(textures)
    if kind == "impostor":
        out += '},"metallicFactor":0.0,"roughnessFactor":0.9},"alphaMode":"MASK","alphaCutoff":0.5,"doubleSided":true}'
    else:
        out += (
            '},"metallicFactor":0.0,"roughnessFactor":0.85},"doubleSided":true}'
        )
    out += ',"index":'
    out += String(materials)
    out += "}"
    return out


def _starts(text: String, prefix: String) -> Bool:
    """Return whether `text` begins with `prefix`."""
    var raw = text.as_bytes()
    var head = prefix.as_bytes()
    if len(raw) < len(head):
        return False
    for index in range(len(head)):
        if raw[index] != head[index]:
            return False
    return True


def _member(doc: PyJson, node: Int, key: String) raises -> Int:
    """Return a member, or raise `KeyError` text when it is absent."""
    var found = doc.get(node, key)
    if found == MISSING:
        raise Error("KeyError: '" + key + "'")
    return found


def _whole(doc: PyJson, node: Int, message: String) raises -> Int:
    """Return a JSON integer, or raise `message`."""
    if doc.kind(node) != PY_INT:
        raise Error(message + " is not an integer")
    return Int(parse_float(doc.text(node)))


def _text(doc: PyJson, node: Int, message: String) raises -> String:
    """Return a JSON string, or raise `message`."""
    if doc.kind(node) != PY_STR:
        raise Error(message)
    return doc.text(node)


def _quote(text: String) -> String:
    """Return one JSON string."""
    var out = String('"')
    var raw = text.as_bytes()
    for index in range(len(raw)):
        var byte = raw[index]
        if byte == 34 or byte == 92:
            out += "\\"
            out += chr(Int(byte))
        else:
            out += chr(Int(byte))
    out += '"'
    return out


def main() raises:
    """Print the material for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_attach FILE", file=stderr)
        exit(2)
    try:
        print(attach_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_town_attach:", error, file=stderr)
        exit(1)
