# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Write one CARLA vehicle package from a UModel export.

    carla_gltf_package EXPORT_ROOT MESH.gltf OUT_DIR NAME [--max-size N] [--budget N]

The program indexes the material files, rebuilds each material, removes
the skin, splits the lamps, and simplifies the mesh to `budget`
triangles. `budget` 0 keeps every triangle. The glTF text matches
`json.dump` with indent 1.
"""

from std.os import makedirs
from std.pathlib import Path
from std.sys import argv, exit, stderr
from std.tempfile import mkdtemp

from tools._process import run_program
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
from tools.carla_file_index import index_text
from tools.carla_gltf_compact import compact_gltf, gltf_text
from tools.carla_gltf_decimate import decimate_files
from tools.carla_gltf_dedupe import dedupe_text
from tools.carla_gltf_lamps import split_lamps
from tools.carla_gltf_rebuild import rebuild_text
from tools.carla_gltf_skin import strip_text


comptime KEEP = 400


@fieldwise_init
struct _Report(Copyable, ImplicitlyCopyable, Movable):
    """One printed material line."""

    var name: String
    var parent: String
    var textures: String


def package_vehicle(
    export_root: String,
    mesh: String,
    out_dir: String,
    name: String,
    max_size: Int,
    budget: Int,
) raises -> String:
    """Write one vehicle package and return its material report.

    Args:
        export_root: The directory of `.mat`, `.props.txt`, `.png`, and
            `.tga` files.
        mesh: The UModel glTF file.
        out_dir: The package directory. An existing directory is replaced.
        name: The output file stem.
        max_size: The longest side of a stored texture, in pixels.
        budget: The triangle count the free parts share. 0 keeps them all.

    Returns:
        The report text. Each material is one line, and the text ends
        with a newline when it is not empty.

    Raises:
        Error: If a file cannot be read, the glTF is not a vehicle mesh,
            or a material cannot be stored.
    """
    if max_size < 0:
        raise Error("max_size is negative")
    var pngs = _merged_textures(export_root)
    var mats = PyJson.parse(index_text(export_root, ".mat"))
    var props = PyJson.parse(index_text(export_root, ".props.txt"))
    var doc = PyJson.parse(Path(mesh).read_text())
    if doc.kind(doc.root) != PY_DICT:
        raise Error("glTF is not an object")
    _reset_textures(doc)
    doc = _reload(dedupe_text(_write_gltf(doc)))
    var rows = List[_Report]()
    var cache = String("[]")
    var materials = doc.get(doc.root, "materials")
    if materials != MISSING and doc.kind(materials) == PY_LIST:
        var count = doc.length(doc.at(doc.root, "textures"))
        _prepare_output(out_dir)
        for index in range(doc.length(materials)):
            var material = doc.item(materials, index)
            var material_name = _material_name(doc, material)
            var result = PyJson.parse(
                rebuild_text(
                    _rebuild_request(
                        doc,
                        material,
                        material_name,
                        mats,
                        props,
                        pngs,
                        out_dir,
                        max_size,
                        count,
                        cache,
                    )
                )
            )
            doc.set_item(
                materials,
                index,
                doc.adopt(result, result.at(result.root, "material")),
            )
            count = _append_images(doc, result, count)
            cache = _extend_cache(cache, result)
            rows.append(_report_of(result, material_name))
    else:
        _prepare_output(out_dir)
    var bin_path = _join(_dirname(mesh), _buffer_uri(doc))
    var data = Path(bin_path).read_bytes()
    doc = _reload(strip_text(_write_gltf(doc)))
    var packed = compact_gltf(doc, "compact", data)
    var lamps = split_lamps(doc, Span(packed))
    if budget > 0:
        lamps = _decimate(doc, lamps, budget)
    _finish(doc, name)
    Path(_join(out_dir, name + ".bin")).write_bytes(Span(lamps))
    Path(_join(out_dir, name + ".gltf")).write_text(_indented(doc))
    return _report_text(rows)


def _prepare_output(out_dir: String) raises:
    """Replace `out_dir` with an empty directory."""
    var removed = run_program(["rm", "-rf", out_dir], 30)
    if removed.status != 0:
        raise Error(removed.errors)
    makedirs(out_dir, exist_ok=True)


def _reset_textures(mut doc: PyJson) raises:
    """Start the packaged image tables."""
    doc.set(doc.root, "images", doc.new_list())
    doc.set(doc.root, "textures", doc.new_list())
    var samplers = doc.new_list()
    var sampler = doc.new_dict()
    doc.set(sampler, "magFilter", doc.new_int(9729))
    doc.set(sampler, "minFilter", doc.new_int(9987))
    doc.set(sampler, "wrapS", doc.new_int(10497))
    doc.set(sampler, "wrapT", doc.new_int(10497))
    doc.append(samplers, sampler)
    doc.set(doc.root, "samplers", samplers)


def _merged_textures(root: String) raises -> PyJson:
    """Return PNG paths, then TGA paths whose stem is still free."""
    var pngs = PyJson.parse(index_text(root, ".png"))
    var tgas = PyJson.parse(index_text(root, ".tga"))
    if pngs.kind(pngs.root) != PY_DICT or tgas.kind(tgas.root) != PY_DICT:
        raise Error("texture index is not an object")
    for index in range(tgas.length(tgas.root)):
        var stem = tgas.key(tgas.root, index)
        if pngs.get(pngs.root, stem) == MISSING:
            pngs.set(
                pngs.root,
                stem,
                pngs.new_str(tgas.text(tgas.value(tgas.root, index))),
            )
    return pngs^


def _rebuild_request(
    doc: PyJson,
    material: Int,
    name: String,
    mats: PyJson,
    props: PyJson,
    pngs: PyJson,
    out_dir: String,
    max_size: Int,
    count: Int,
    cache: String,
) raises -> String:
    """Return one rebuild request."""
    var request = PyJson()
    var root = request.new_dict()
    request.root = root
    request.set(root, "material", request.adopt(doc, material))
    request.set(root, "mat", _text_or_null(request, mats, name))
    request.set(root, "props", _text_or_null(request, props, name))
    request.set(root, "pngs", request.adopt(pngs, pngs.root))
    request.set(root, "out_dir", request.new_str(out_dir))
    request.set(root, "max_size", request.new_int(max_size))
    request.set(root, "texture_count", request.new_int(count))
    var cached = PyJson.parse(cache)
    request.set(root, "cache", request.adopt(cached, cached.root))
    request.set(root, "town", request.new_bool(False))
    return gltf_text(request)


def _text_or_null(
    mut request: PyJson, index: PyJson, name: String
) raises -> Int:
    """Return file text for `name`, or null."""
    var node = index.get(index.root, name)
    if node == MISSING:
        return request.new_none()
    return request.new_str(_file_text(index.text(node)))


def _append_images(mut doc: PyJson, result: PyJson, count: Int) raises -> Int:
    """Append new images and return the next texture index."""
    var images = doc.at(doc.root, "images")
    var textures = doc.at(doc.root, "textures")
    var listed = result.at(result.root, "images")
    var next = count
    for index in range(result.length(listed)):
        var image = doc.new_dict()
        doc.set(
            image, "uri", doc.new_str(result.text(result.item(listed, index)))
        )
        doc.append(images, image)
        var texture = doc.new_dict()
        doc.set(texture, "sampler", doc.new_int(0))
        doc.set(texture, "source", doc.new_int(doc.length(images) - 1))
        doc.append(textures, texture)
        next += 1
    return next


def _extend_cache(cache: String, result: PyJson) raises -> String:
    """Return the cache plus the rows this material stored."""
    var doc = PyJson.parse(cache)
    var added = result.at(result.root, "cache_add")
    for index in range(result.length(added)):
        doc.append(doc.root, doc.adopt(result, result.item(added, index)))
    return gltf_text(doc)


def _report_of(result: PyJson, name: String) raises -> _Report:
    """Return the printed line fields for one material."""
    var report = result.at(result.root, "report")
    var parent = result.text(result.item(report, 0))
    var names = result.item(report, 1)
    var textures = String("")
    for index in range(result.length(names)):
        if index > 0:
            textures += " "
        textures += result.text(result.item(names, index))
    return _Report(name, parent, textures)


def _decimate(
    mut doc: PyJson, data: List[UInt8], budget: Int
) raises -> List[UInt8]:
    """Simplify the mesh and return the buffer."""
    var folder = mkdtemp(prefix="gltf package ")
    var source_gltf = _join(folder, "in.gltf")
    var source_bin = _join(folder, "in.bin")
    var out_gltf = _join(folder, "out.gltf")
    var out_bin = _join(folder, "out.bin")
    Path(source_gltf).write_text(gltf_text(doc))
    Path(source_bin).write_bytes(Span(data))
    decimate_files(budget, KEEP, source_gltf, source_bin, out_gltf, out_bin)
    var updated = PyJson.parse(Path(out_gltf).read_text())
    doc = updated^
    return Path(out_bin).read_bytes()


def _finish(mut doc: PyJson, name: String) raises:
    """Set the package name, generator, and copyright."""
    var buffers = doc.at(doc.root, "buffers")
    var buffer = doc.item(buffers, 0)
    doc.set(buffer, "uri", doc.new_str(name + ".bin"))
    var asset = doc.at(doc.root, "asset")
    doc.set(asset, "generator", doc.new_str("ThreeMojo carla_gltf_fix.py"))
    doc.set(asset, "copyright", doc.new_str("CARLA Team, CC-BY 4.0"))
    var images = doc.get(doc.root, "images")
    if (
        images != MISSING
        and doc.kind(images) == PY_LIST
        and doc.length(images) == 0
    ):
        doc.remove(doc.root, "images")
        doc.remove(doc.root, "textures")
        doc.remove(doc.root, "samplers")


def _buffer_uri(doc: PyJson) raises -> String:
    """Return the current buffer file name."""
    var buffers = doc.at(doc.root, "buffers")
    var buffer = doc.item(buffers, 0)
    return doc.text(doc.at(buffer, "uri"))


def _material_name(doc: PyJson, material: Int) raises -> String:
    """Return a material name, or empty text."""
    var named = doc.get(material, "name")
    if named == MISSING or doc.kind(named) != PY_STR:
        return ""
    return doc.text(named)


def _file_text(path: String) raises -> String:
    """Return file text with universal newlines."""
    var data = Path(path).read_bytes()
    var cleaned = List[UInt8]()
    var index = 0
    while index < len(data):
        var byte = data[index]
        if byte == 13:
            cleaned.append(10)
            index += 1
            if index < len(data) and data[index] == 10:
                index += 1
            continue
        cleaned.append(byte)
        index += 1
    return String(unsafe_from_utf8=Span(cleaned))


def _write_gltf(doc: PyJson) raises -> String:
    """Write `doc` to a temporary file and return that path."""
    var folder = mkdtemp(prefix="gltf package ")
    var path = _join(folder, "mesh.gltf")
    Path(path).write_text(gltf_text(doc))
    return path


def _reload(text: String) raises -> PyJson:
    """Parse one glTF document."""
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_DICT:
        raise Error("glTF is not an object")
    return doc^


def _report_text(rows: List[_Report]) -> String:
    """Return the report, one material on each line."""
    var out = String("")
    for index in range(len(rows)):
        var row = rows[index]
        out += "  "
        out += _pad(row.name, 45)
        out += " "
        out += _pad(row.parent, 28)
        out += " "
        out += row.textures
        out += "\n"
    return out


def _pad(text: String, width: Int) -> String:
    """Return `text` padded with spaces to `width`."""
    var out = text
    while out.byte_length() < width:
        out += " "
    return out


def _indented(doc: PyJson) raises -> String:
    """Return JSON with indent 1, as `json.dump` writes it."""
    return _indent(doc, doc.root, 0)


def _indent(doc: PyJson, node: Int, level: Int) raises -> String:
    """Return one indented JSON value."""
    var kind = doc.kind(node)
    if kind == PY_DICT:
        if doc.length(node) == 0:
            return "{}"
        var out = String("{\n")
        for index in range(doc.length(node)):
            if index > 0:
                out += ",\n"
            out += _spaces(level + 1)
            out += _quote(doc.key(node, index))
            out += ": "
            out += _indent(doc, doc.value(node, index), level + 1)
        out += "\n"
        out += _spaces(level)
        out += "}"
        return out
    if kind == PY_LIST:
        if doc.length(node) == 0:
            return "[]"
        var out = String("[\n")
        for index in range(doc.length(node)):
            if index > 0:
                out += ",\n"
            out += _spaces(level + 1)
            out += _indent(doc, doc.item(node, index), level + 1)
        out += "\n"
        out += _spaces(level)
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


def _spaces(count: Int) -> String:
    """Return `count` spaces."""
    var out = String("")
    for _ in range(count):
        out += " "
    return out


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
        elif byte == 10:
            out += "\\n"
        elif byte == 13:
            out += "\\r"
        elif byte == 9:
            out += "\\t"
        elif byte < 32:
            out += "\\u00"
            out += chr(Int(hex.as_bytes()[Int(byte >> 4)]))
            out += chr(Int(hex.as_bytes()[Int(byte & 15)]))
        else:
            out += chr(Int(byte))
    out += '"'
    return out


def _dirname(path: String) -> String:
    """Return the directory of `path`."""
    var raw = path.as_bytes()
    var slash = -1
    for index in range(len(raw)):
        if raw[index] == 47:
            slash = index
    if slash < 0:
        return "."
    if slash == 0:
        return "/"
    return String(path[byte=0:slash])


def _join(directory: String, name: String) -> String:
    """Join a directory and a file name with `/`."""
    if directory.byte_length() == 0 or directory == ".":
        return name
    var raw = directory.as_bytes()
    if raw[len(raw) - 1] == 47:
        return directory + name
    return directory + "/" + name


def _whole(text: String) raises -> Int:
    """Return an integer argument."""
    return Int(parse_float(text))


def main() raises:
    """Write the vehicle package named on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    var positionals = List[String]()
    var max_size = 1024
    var budget = 35000
    var index = 1
    while index < len(arguments):
        var argument = arguments[index]
        if argument == "--max-size" or argument == "--budget":
            if index + 1 >= len(arguments):
                _usage()
            var value = _whole(arguments[index + 1])
            if argument == "--max-size":
                max_size = value
            else:
                budget = value
            index += 2
            continue
        positionals.append(argument)
        index += 1
    if len(positionals) != 4:
        _usage()
    try:
        var report = package_vehicle(
            positionals[0],
            positionals[1],
            positionals[2],
            positionals[3],
            max_size,
            budget,
        )
        var lines = report.splitlines()
        for line in lines:
            if line.byte_length() > 0:
                print(line)
    except error:
        print("carla_gltf_package:", error, file=stderr)
        exit(1)


def _usage() raises:
    """Print the usage line and stop."""
    print(
        (
            "usage: carla_gltf_package EXPORT_ROOT MESH.gltf OUT_DIR NAME"
            " [--max-size N] [--budget N]"
        ),
        file=stderr,
    )
    exit(2)
