# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Stable atlas names for a town bake's resolved materials and textures.

    carla_bake_identity REQUEST.json

REQUEST.json holds `gltf`, `out_dir`, `mesh`, `kind`, `parts`, and
`settings`. The program prints `kind_` plus the SHA-256 of the canonical
JSON identity. It matches the reviewed Python bake identity.
"""

from std.collections import Dict
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import (
    PY_DICT,
    PY_INT,
    PY_LIST,
    MISSING,
    PyJson,
    dumps_canonical,
)
from tools._sha256 import sha256_hex


comptime _VERSION = 1
"""The identity encoding version. A new version changes every atlas name."""


def bake_key(request_text: String) raises -> String:
    """Return the atlas tag for one bake request.

    Args:
        request_text: JSON with `gltf`, `out_dir`, `mesh`, `kind`, `parts`,
            and `settings`.

    Returns:
        `kind`, an underscore, and 64 lowercase hex digits.

    Raises:
        Error: If the request, a glTF reference, a texture file, or a
            non-finite number is invalid.
    """
    var pair = bake_key_reads(request_text)
    return pair[0]


def bake_key_reads(request_text: String) raises -> Tuple[String, Int]:
    """Return the atlas tag and how many texture files were read.

    Args:
        request_text: The same JSON `bake_key` reads.

    Returns:
        The tag, and the number of file reads. A repeated image URI in one
        request is read once.

    Raises:
        Error: As `bake_key` does.
    """
    var doc = PyJson.parse(request_text)
    var reads = 0
    var version = _VERSION
    if doc.find(doc.root, "version") != MISSING:
        version = _int(doc, doc.at(doc.root, "version"))
    var tag = _key(doc, doc.root, version, reads)
    return (tag, reads)


def _key(
    mut doc: PyJson, root: Int, version: Int, mut reads: Int
) raises -> String:
    """Return the atlas tag for a parsed request."""
    var gltf = doc.at(root, "gltf")
    var out_dir = doc.text(doc.at(root, "out_dir"))
    var mesh = doc.text(doc.at(root, "mesh"))
    var kind = doc.text(doc.at(root, "kind"))
    var parts = doc.at(root, "parts")
    var settings = doc.at(root, "settings")
    var images = Dict[String, String]()
    var materials = Dict[String, String]()
    var ordered = doc.new_list()
    for index in range(doc.length(parts)):
        var part = doc.item(parts, index)
        var geometry = doc.text(doc.item(part, 0))
        var material = _int(doc, doc.item(part, 1))
        if not (String(material) in materials):
            var resolved = _resolve(
                doc,
                doc.item(doc.at(gltf, "materials"), material),
                gltf,
                out_dir,
                images,
                reads,
            )
            materials[String(material)] = _digest(doc, resolved)
        var pair = doc.new_list()
        doc.append(pair, doc.new_str(geometry))
        doc.append(pair, doc.new_str(materials[String(material)]))
        doc.append(ordered, pair)
    var payload = doc.new_list()
    doc.append(payload, doc.new_int(version))
    doc.append(payload, doc.new_str(mesh))
    doc.append(payload, doc.new_str(kind))
    doc.append(payload, ordered)
    doc.append(payload, settings)
    return kind + "_" + _digest(doc, payload)


def _digest(doc: PyJson, node: Int) raises -> String:
    """Return the SHA-256 of canonical JSON."""
    var text = dumps_canonical(doc, node)
    return sha256_hex(text.as_bytes())


def _int(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("glTF index is not an integer")
    return Int(doc.text(node))


def _resolve(
    mut doc: PyJson,
    node: Int,
    gltf: Int,
    out_dir: String,
    mut images: Dict[String, String],
    mut reads: Int,
) raises -> Int:
    """Return a copy with texture indexes replaced by file identities."""
    var kind = doc.kind(node)
    if kind == PY_LIST:
        var copy = doc.new_list()
        for index in range(doc.length(node)):
            doc.append(
                copy,
                _resolve(
                    doc, doc.item(node, index), gltf, out_dir, images, reads
                ),
            )
        return copy
    if kind != PY_DICT:
        return doc.copy_node(node)
    var copy = doc.new_dict()
    for index in range(doc.length(node)):
        var name = doc.key(node, index)
        var child = doc.value(node, index)
        if (
            name.endswith("Texture")
            and doc.kind(child) == PY_DICT
            and doc.find(child, "index") != MISSING
        ):
            doc.set(
                copy, name, _texture(doc, child, gltf, out_dir, images, reads)
            )
        else:
            doc.set(
                copy, name, _resolve(doc, child, gltf, out_dir, images, reads)
            )
    return copy


def _texture(
    mut doc: PyJson,
    reference: Int,
    gltf: Int,
    out_dir: String,
    mut images: Dict[String, String],
    mut reads: Int,
) raises -> Int:
    """Return one texture reference with its image and sampler inlined."""
    var index = _int(doc, doc.at(reference, "index"))
    var source = doc.item(doc.at(gltf, "textures"), index)
    var info = doc.new_dict()
    for cursor in range(doc.length(reference)):
        var name = doc.key(reference, cursor)
        if name != "index":
            doc.set(
                info,
                name,
                _resolve(
                    doc,
                    doc.value(reference, cursor),
                    gltf,
                    out_dir,
                    images,
                    reads,
                ),
            )
    var texture = doc.new_dict()
    for cursor in range(doc.length(source)):
        var name = doc.key(source, cursor)
        if name == "source":
            doc.set(
                texture,
                name,
                _image(
                    doc,
                    _int(doc, doc.value(source, cursor)),
                    gltf,
                    out_dir,
                    images,
                    reads,
                ),
            )
        elif name == "sampler":
            var sampler = doc.item(
                doc.at(gltf, "samplers"), _int(doc, doc.value(source, cursor))
            )
            doc.set(texture, name, doc.copy_node(sampler))
        else:
            doc.set(texture, name, doc.copy_node(doc.value(source, cursor)))
    doc.set(info, "texture", texture)
    return info


def _image(
    mut doc: PyJson,
    index: Int,
    gltf: Int,
    out_dir: String,
    mut images: Dict[String, String],
    mut reads: Int,
) raises -> Int:
    """Return one image record plus the SHA-256 of its file."""
    var source = doc.item(doc.at(gltf, "images"), index)
    var copy = doc.new_dict()
    var uri = String()
    for cursor in range(doc.length(source)):
        var name = doc.key(source, cursor)
        if name == "uri":
            uri = doc.text(doc.value(source, cursor))
        doc.set(copy, name, doc.copy_node(doc.value(source, cursor)))
    if uri.byte_length() == 0:
        raise Error("glTF image has no uri")
    if not (uri in images):
        var path = out_dir
        if not path.endswith("/"):
            path += "/"
        path += uri
        var data = Path(path).read_bytes()
        reads += 1
        images[uri] = sha256_hex(data)
    doc.set(copy, "sha256", doc.new_str(images[uri]))
    return copy


def main() raises:
    """Print the atlas tag for the request file named on the command line."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_bake_identity REQUEST.json", file=stderr)
        exit(2)
    try:
        print(bake_key(Path(arguments[1]).read_text()))
    except error:
        print("carla_bake_identity:", error, file=stderr)
        exit(1)
