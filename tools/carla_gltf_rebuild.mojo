# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Apply one CARLA material plan and write its textures.

    carla_gltf_rebuild FILE

`FILE` is JSON. It holds the material, the `.mat` and `.props.txt` text,
the texture paths, and the textures already stored. The program prints
the material, the new image names, and the cache rows those images add.
`town` true drops vehicle tags. A blend material whose name contains
`glass` becomes the town's dark pane.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_INT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    PyJson,
)
from tools.carla_gltf_material import plan_material
from tools.carla_texture_store import store_text


@fieldwise_init
struct _Saved(Copyable, ImplicitlyCopyable, Movable):
    """One stored texture and its glTF index."""

    var op: String
    var source: String
    var flag: Bool
    var mask: String
    var index: Int


def rebuild_text(text: String) raises -> String:
    """Return one rebuilt material and the textures it added.

    Args:
        text: JSON with `material`, `mat`, `props`, `pngs`, `out_dir`,
            `max_size`, `texture_count`, and `cache`. `town` true applies
            the town glass rule.

    Returns:
        `material`, `images`, `cache_add`, and `report`. `images` are the
        new URIs, in the order their indexes were assigned.

    Raises:
        Error: If the JSON is not that request, a texture stem is missing,
            or an image cannot be stored.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("rebuild request is not an object")
    var material = doc.subtree(doc.at(root, "material"))
    if material.kind(material.root) != PY_DICT:
        raise Error("material is not an object")
    var name = String("")
    var named = material.get(material.root, "name")
    if named != MISSING and material.kind(named) == PY_STR:
        name = material.text(named)
    var plan = PyJson.parse(
        plan_material(
            _plan_request(
                name,
                _optional(doc, root, "mat"),
                _optional(doc, root, "props"),
                doc,
                doc.at(root, "pngs"),
            )
        )
    )
    var out_dir = _text(doc, doc.at(root, "out_dir"), "out_dir is not text")
    var limit = _whole(
        doc, doc.at(root, "max_size"), "max_size is not an integer"
    )
    if limit < 0:
        raise Error("max_size is negative")
    var next = _whole(
        doc, doc.at(root, "texture_count"), "texture_count is not an integer"
    )
    if next < 0:
        raise Error("texture_count is negative")
    var rows = _cache(doc, doc.at(root, "cache"))
    var added = List[_Saved]()
    var images = List[String]()
    var pbr = _factor_block(material, plan)
    _textures(
        material,
        pbr,
        plan,
        doc,
        doc.at(root, "pngs"),
        out_dir,
        limit,
        rows,
        added,
        images,
        next,
    )
    material.set(material.root, "pbrMetallicRoughness", pbr)
    _blend(material, plan)
    if _town(doc, root):
        _town_glass(material, name)
    return _result(material, plan, images, added)


def _factor_block(mut material: PyJson, plan: PyJson) raises -> Int:
    """Return a new roughness block with the plan's factors."""
    var pbr = material.new_dict()
    material.set(
        pbr,
        "baseColorFactor",
        material.adopt(plan, plan.at(plan.root, "baseColorFactor")),
    )
    material.set(
        pbr,
        "metallicFactor",
        material.adopt(plan, plan.at(plan.root, "metallicFactor")),
    )
    material.set(
        pbr,
        "roughnessFactor",
        material.adopt(plan, plan.at(plan.root, "roughnessFactor")),
    )
    return pbr


def _textures(
    mut material: PyJson,
    pbr: Int,
    plan: PyJson,
    paths: PyJson,
    pngs: Int,
    out_dir: String,
    limit: Int,
    mut rows: List[_Saved],
    mut added: List[_Saved],
    mut images: List[String],
    mut next: Int,
) raises:
    """Attach each texture step."""
    var steps = plan.at(plan.root, "textures")
    if plan.kind(steps) != PY_LIST:
        raise Error("textures are not a list")
    for index in range(plan.length(steps)):
        var step = plan.item(steps, index)
        var kind = _text(
            plan, plan.at(step, "kind"), "texture kind is not text"
        )
        if kind == "color" or kind == "normal" or kind == "orm":
            var stem = _text(plan, plan.at(step, "stem"), "stem is not text")
            var source = _path(paths, pngs, stem)
            var color = kind == "color"
            var slot = _color_index(
                rows, added, images, next, out_dir, limit, source, color
            )
            var node = _index(material, slot)
            if kind == "color":
                material.set(pbr, "baseColorTexture", node)
            elif kind == "normal":
                material.set(material.root, "normalTexture", node)
            else:
                material.set(pbr, "metallicRoughnessTexture", node)
                material.set(
                    material.root, "occlusionTexture", _index(material, slot)
                )
        elif kind == "masked":
            var color_stem = _text(
                plan, plan.at(step, "color"), "color is not text"
            )
            var mask_stem = _text(
                plan, plan.at(step, "mask"), "mask is not text"
            )
            var slot = _masked_index(
                rows,
                added,
                images,
                next,
                out_dir,
                limit,
                _path(paths, pngs, color_stem),
                _path(paths, pngs, mask_stem),
            )
            material.set(pbr, "baseColorTexture", _index(material, slot))
        else:
            raise Error("texture kind is not color, normal, masked or orm")


def _blend(mut material: PyJson, plan: PyJson) raises:
    """Copy the blend and extra decisions onto `material`."""
    _copy_key(material, plan, "alphaMode")
    _copy_key(material, plan, "alphaCutoff")
    var sided = plan.get(plan.root, "doubleSided")
    if sided != MISSING and plan.kind(sided) == PY_BOOL and plan.flag(sided):
        material.set(material.root, "doubleSided", material.new_bool(True))
    var extras = plan.get(plan.root, "extras")
    if extras != MISSING:
        material.set(material.root, "extras", material.adopt(plan, extras))
    if material.get(material.root, "extensions") != MISSING:
        material.remove(material.root, "extensions")


def _town_glass(mut material: PyJson, name: String) raises:
    """Drop vehicle tags. A named glass blend becomes the town pane."""
    if material.get(material.root, "extras") != MISSING:
        material.remove(material.root, "extras")
    var mode = material.get(material.root, "alphaMode")
    if mode == MISSING or material.kind(mode) != PY_STR:
        return
    if material.text(mode) != "BLEND" or _find(_lower(name), "glass") < 0:
        return
    material.remove(material.root, "alphaMode")
    var pbr = material.at(material.root, "pbrMetallicRoughness")
    if material.get(pbr, "baseColorTexture") != MISSING:
        material.remove(pbr, "baseColorTexture")
    var color = material.new_list()
    material.append(color, material.new_float(parse_float("0.05")))
    material.append(color, material.new_float(parse_float("0.065")))
    material.append(color, material.new_float(parse_float("0.08")))
    material.append(color, material.new_float(parse_float("1.0")))
    material.set(pbr, "baseColorFactor", color)
    material.set(pbr, "metallicFactor", material.new_float(parse_float("0.6")))
    material.set(
        pbr, "roughnessFactor", material.new_float(parse_float("0.06"))
    )


def _color_index(
    mut rows: List[_Saved],
    mut added: List[_Saved],
    mut images: List[String],
    mut next: Int,
    out_dir: String,
    limit: Int,
    source: String,
    color: Bool,
) raises -> Int:
    """Return the texture index of one color or data image."""
    var found = _cached(rows, "color", source, color, "")
    if found >= 0:
        return found
    var request = PyJson()
    var root = request.new_dict()
    request.root = root
    request.set(root, "op", request.new_str("color"))
    request.set(root, "out_dir", request.new_str(out_dir))
    request.set(root, "max_size", request.new_int(limit))
    request.set(root, "source", request.new_str(source))
    request.set(root, "color", request.new_bool(color))
    return _remember(
        rows,
        added,
        images,
        next,
        "color",
        source,
        color,
        "",
        _stored(store_text(request.dumps())),
    )


def _masked_index(
    mut rows: List[_Saved],
    mut added: List[_Saved],
    mut images: List[String],
    mut next: Int,
    out_dir: String,
    limit: Int,
    color: String,
    mask: String,
) raises -> Int:
    """Return the texture index of one cut-out image."""
    var found = _cached(rows, "masked", color, False, mask)
    if found >= 0:
        return found
    var request = PyJson()
    var root = request.new_dict()
    request.root = root
    request.set(root, "op", request.new_str("masked"))
    request.set(root, "out_dir", request.new_str(out_dir))
    request.set(root, "max_size", request.new_int(limit))
    request.set(root, "color", request.new_str(color))
    request.set(root, "mask", request.new_str(mask))
    return _remember(
        rows,
        added,
        images,
        next,
        "masked",
        color,
        False,
        mask,
        _stored(store_text(request.dumps())),
    )


def _remember(
    mut rows: List[_Saved],
    mut added: List[_Saved],
    mut images: List[String],
    mut next: Int,
    op: String,
    source: String,
    flag: Bool,
    mask: String,
    uri: String,
) -> Int:
    """Record one new texture and return its index."""
    var index = next
    next += 1
    images.append(uri)
    var row = _Saved(op, source, flag, mask, index)
    rows.append(row)
    added.append(row)
    return index


def _cached(
    rows: List[_Saved], op: String, source: String, flag: Bool, mask: String
) -> Int:
    """Return a stored index, or -1."""
    for index in range(len(rows)):
        var row = rows[index]
        if (
            row.op == op
            and row.source == source
            and row.flag == flag
            and row.mask == mask
        ):
            return row.index
    return -1


def _stored(text: String) raises -> String:
    """Return the URI from a texture-store result."""
    var doc = PyJson.parse(text)
    return _text(doc, doc.at(doc.root, "uri"), "uri is not text")


def _index(mut material: PyJson, slot: Int) -> Int:
    """Return `{"index": slot}`."""
    var node = material.new_dict()
    material.set(node, "index", material.new_int(slot))
    return node


def _path(doc: PyJson, pngs: Int, stem: String) raises -> String:
    """Return the file path of one texture stem."""
    if doc.kind(pngs) != PY_DICT:
        raise Error("pngs is not an object")
    var node = doc.get(pngs, stem)
    if node == MISSING:
        raise Error("texture stem is missing")
    return _text(doc, node, "texture path is not text")


def _plan_request(
    name: String, mat: String, props: String, doc: PyJson, pngs: Int
) raises -> String:
    """Return the material-plan request."""
    var request = PyJson()
    var root = request.new_dict()
    request.root = root
    request.set(root, "name", request.new_str(name))
    if mat.byte_length() == 0:
        request.set(root, "mat", request.new_none())
    else:
        request.set(root, "mat", request.new_str(mat))
    if props.byte_length() == 0:
        request.set(root, "props", request.new_none())
    else:
        request.set(root, "props", request.new_str(props))
    if doc.kind(pngs) != PY_DICT:
        raise Error("pngs is not an object")
    var listed = request.new_list()
    for index in range(doc.length(pngs)):
        request.append(listed, request.new_str(doc.key(pngs, index)))
    request.set(root, "pngs", listed)
    return request.dumps()


def _optional(doc: PyJson, root: Int, key: String) raises -> String:
    """Return a text field, or empty when it is null or absent."""
    var node = doc.get(root, key)
    if node == MISSING or doc.kind(node) == PY_NONE:
        return ""
    return _text(doc, node, key + " is not text")


def _copy_key(mut material: PyJson, plan: PyJson, key: String) raises:
    """Copy one optional plan field onto the material."""
    var node = plan.get(plan.root, key)
    if node != MISSING:
        material.set(material.root, key, material.adopt(plan, node))


def _town(doc: PyJson, root: Int) raises -> Bool:
    """Return whether this rebuild is for a town."""
    var node = doc.get(root, "town")
    if node == MISSING:
        return False
    if doc.kind(node) != PY_BOOL:
        raise Error("town is not a bool")
    return doc.flag(node)


def _result(
    material: PyJson, plan: PyJson, images: List[String], added: List[_Saved]
) raises -> String:
    """Return the rebuild JSON in insertion order."""
    var out = PyJson()
    var root = out.new_dict()
    out.root = root
    out.set(root, "material", out.adopt(material, material.root))
    var listed = out.new_list()
    for index in range(len(images)):
        out.append(listed, out.new_str(images[index]))
    out.set(root, "images", listed)
    var cache = out.new_list()
    for index in range(len(added)):
        var row = added[index]
        var item = out.new_dict()
        out.set(item, "op", out.new_str(row.op))
        out.set(item, "source", out.new_str(row.source))
        out.set(item, "color", out.new_bool(row.flag))
        out.set(item, "mask", out.new_str(row.mask))
        out.set(item, "index", out.new_int(row.index))
        out.append(cache, item)
    out.set(root, "cache_add", cache)
    out.set(root, "report", out.adopt(plan, plan.at(plan.root, "report")))
    return _compact(out, out.root)


def _cache(doc: PyJson, node: Int) raises -> List[_Saved]:
    """Read the textures already stored."""
    if doc.kind(node) != PY_LIST:
        raise Error("cache is not a list")
    var rows = List[_Saved]()
    for index in range(doc.length(node)):
        var item = doc.item(node, index)
        if doc.kind(item) != PY_DICT:
            raise Error("cache row is not an object")
        rows.append(
            _Saved(
                _text(doc, doc.at(item, "op"), "cache op is not text"),
                _text(doc, doc.at(item, "source"), "cache source is not text"),
                _flag(doc, doc.at(item, "color"), "cache color is not a bool"),
                _text(doc, doc.at(item, "mask"), "cache mask is not text"),
                _whole(
                    doc, doc.at(item, "index"), "cache index is not an integer"
                ),
            )
        )
    return rows^


def _compact(doc: PyJson, node: Int) raises -> String:
    """Return JSON with insertion order and no spaces."""
    var kind = doc.kind(node)
    if kind == PY_DICT:
        var out = String("{")
        for index in range(doc.length(node)):
            if index > 0:
                out += ","
            out += _quote(doc.key(node, index))
            out += ":"
            out += _compact(doc, doc.value(node, index))
        out += "}"
        return out
    if kind == PY_LIST:
        var out = String("[")
        for index in range(doc.length(node)):
            if index > 0:
                out += ","
            out += _compact(doc, doc.item(node, index))
        out += "]"
        return out
    if kind == PY_STR:
        return _quote(doc.text(node))
    if kind == PY_BOOL:
        if doc.flag(node):
            return "true"
        return "false"
    if kind == PY_NONE:
        return "null"
    return doc.text(node)


def _quote(text: String) -> String:
    """Return one JSON string."""
    var out = String('"')
    var raw = text.as_bytes()
    var hex = String("0123456789abcdef")
    for index in range(len(raw)):
        var byte = raw[index]
        if byte == 34 or byte == 92:
            out += "\\"
            out += chr(Int(byte))
        elif byte < 32:
            out += "\\u00"
            out += chr(Int(hex.as_bytes()[Int(byte >> 4)]))
            out += chr(Int(hex.as_bytes()[Int(byte & 15)]))
        else:
            out += chr(Int(byte))
    out += '"'
    return out


def _text(doc: PyJson, node: Int, message: String) raises -> String:
    """Return a JSON string, or raise `message`."""
    if doc.kind(node) != PY_STR:
        raise Error(message)
    return doc.text(node)


def _flag(doc: PyJson, node: Int, message: String) raises -> Bool:
    """Return a JSON bool, or raise `message`."""
    if doc.kind(node) != PY_BOOL:
        raise Error(message)
    return doc.flag(node)


def _whole(doc: PyJson, node: Int, message: String) raises -> Int:
    """Return a JSON integer, or raise `message`."""
    if doc.kind(node) != PY_INT:
        raise Error(message)
    return Int(parse_float(doc.text(node)))


def _lower(text: String) -> String:
    """Return `text` in ASCII lowercase."""
    var out = String()
    var raw = text.as_bytes()
    for index in range(len(raw)):
        var byte = raw[index]
        if byte >= 65 and byte <= 90:
            byte += 32
        out += chr(Int(byte))
    return out


def _find(text: String, needle: String) -> Int:
    """Return the byte index of `needle`, or -1."""
    var raw = text.as_bytes()
    var want = needle.as_bytes()
    if len(want) == 0 or len(want) > len(raw):
        return -1
    for start in range(len(raw) - len(want) + 1):
        var same = True
        for offset in range(len(want)):
            if raw[start + offset] != want[offset]:
                same = False
                break
        if same:
            return start
    return -1


def main() raises:
    """Print the rebuilt material for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_gltf_rebuild FILE", file=stderr)
        exit(2)
    try:
        print(rebuild_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_gltf_rebuild:", error, file=stderr)
        exit(1)
