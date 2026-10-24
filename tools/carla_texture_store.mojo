# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Write one packaged CARLA texture file.

    carla_texture_store FILE

`FILE` is JSON. `op` is `color` or `masked`. `color` reads one image,
fits it, and writes the packaged file. `masked` uses a second image as
the cut-out.
"""

from std.os import makedirs
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float
from tools._python_json import (
    PY_BOOL,
    PY_DICT,
    PY_INT,
    PY_LIST,
    PY_STR,
    PyJson,
)
from tools._sha256 import sha256_hex
from tools.carla_image import image_file
from tools.carla_image_pack import pack_text
from tools.carla_jpeg import jpeg_text
from tools.carla_png import png_text
from tools.carla_texture_plan import plan_text


def store_text(text: String) raises -> String:
    """Return the URI of one packaged texture, and write that file.

    Args:
        text: JSON with `op`, `out_dir` and `max_size`. `color` also has
            `source` and `color`. `masked` also has `color` and `mask`
            paths.

    Returns:
        JSON `uri`, relative to `out_dir`. The file is under `textures/`.

    Raises:
        Error: If the JSON is not that request, or an image cannot be
            stored.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("store request is not an object")
    var op = _text(doc, doc.at(root, "op"), "op is not color or masked")
    var out_dir = _text(doc, doc.at(root, "out_dir"), "out_dir is not text")
    var limit = _whole(
        doc, doc.at(root, "max_size"), "max_size is not an integer"
    )
    if limit < 0:
        raise Error("max_size is negative")
    if op == "color":
        return _uri(_store_color(doc, root, out_dir, limit))
    if op == "masked":
        return _uri(_store_masked(doc, root, out_dir, limit))
    raise Error("op is not color or masked")


def _uri(path: String) -> String:
    """Return one relative path as JSON."""
    return '{"uri":"' + path + '"}'


def _store_color(
    doc: PyJson, root: Int, out_dir: String, limit: Int
) raises -> String:
    """Package one color or data texture."""
    var source = _text(doc, doc.at(root, "source"), "source is not text")
    var color = _flag(doc, doc.at(root, "color"), "color is not a bool")
    var opened = PyJson.parse(image_file(source))
    var width = _whole(
        opened, opened.at(opened.root, "width"), "size is not an integer"
    )
    var height = _whole(
        opened, opened.at(opened.root, "height"), "size is not an integer"
    )
    var mode = _text(
        opened, opened.at(opened.root, "mode"), "image mode is not text"
    )
    var count = width * height * 4
    var pixels = _ints(
        opened, opened.at(opened.root, "pixels"), count, "pixels"
    )
    var plan = PyJson.parse(
        plan_text(_plan(source, color, limit, width, height, False))
    )
    var packed = PyJson.parse(
        pack_text(
            _color_pack(
                mode,
                width,
                height,
                pixels,
                _flag(
                    plan, plan.at(plan.root, "neutral"), "neutral is not a bool"
                ),
                _flag(
                    plan, plan.at(plan.root, "resize"), "resize is not a bool"
                ),
                _whole(
                    plan, plan.at(plan.root, "width"), "size is not an integer"
                ),
                _whole(
                    plan,
                    plan.at(plan.root, "height"),
                    "size is not an integer",
                ),
            )
        )
    )
    return _commit(out_dir, plan, packed)


def _store_masked(
    doc: PyJson, root: Int, out_dir: String, limit: Int
) raises -> String:
    """Package one color image with a cut-out mask."""
    var color_path = _text(doc, doc.at(root, "color"), "color is not text")
    var mask_path = _text(doc, doc.at(root, "mask"), "mask is not text")
    var color = PyJson.parse(image_file(color_path))
    var mask = PyJson.parse(image_file(mask_path))
    var width = _whole(
        color, color.at(color.root, "width"), "size is not an integer"
    )
    var height = _whole(
        color, color.at(color.root, "height"), "size is not an integer"
    )
    var mask_w = _whole(
        mask, mask.at(mask.root, "width"), "size is not an integer"
    )
    var mask_h = _whole(
        mask, mask.at(mask.root, "height"), "size is not an integer"
    )
    var color_px = _ints(
        color, color.at(color.root, "pixels"), width * height * 4, "pixels"
    )
    var mask_px = _ints(
        mask, mask.at(mask.root, "pixels"), mask_w * mask_h * 4, "pixels"
    )
    var mask_mode = _text(
        mask, mask.at(mask.root, "mode"), "image mode is not text"
    )
    var plan = PyJson.parse(
        plan_text(_plan("", False, limit, width, height, True))
    )
    var packed = PyJson.parse(
        pack_text(
            _masked_pack(
                width,
                height,
                color_px,
                mask_mode,
                mask_w,
                mask_h,
                mask_px,
                _flag(
                    plan, plan.at(plan.root, "resize"), "resize is not a bool"
                ),
                _whole(
                    plan, plan.at(plan.root, "width"), "size is not an integer"
                ),
                _whole(
                    plan,
                    plan.at(plan.root, "height"),
                    "size is not an integer",
                ),
            )
        )
    )
    return _commit(out_dir, plan, packed)


def _commit(out_dir: String, plan: PyJson, packed: PyJson) raises -> String:
    """Encode the packed samples and write the named file."""
    var width = _whole(
        packed, packed.at(packed.root, "width"), "size is not an integer"
    )
    var height = _whole(
        packed, packed.at(packed.root, "height"), "size is not an integer"
    )
    var bands = _whole(
        packed, packed.at(packed.root, "bands"), "bands is not an integer"
    )
    var pixels = _ints(
        packed,
        packed.at(packed.root, "pixels"),
        width * height * bands,
        "pixels",
    )
    return _write(
        out_dir,
        _text(plan, plan.at(plan.root, "format"), "format is not text"),
        _whole(
            plan, plan.at(plan.root, "quality"), "quality is not an integer"
        ),
        _flag(plan, plan.at(plan.root, "optimize"), "optimize is not a bool"),
        width,
        height,
        bands,
        pixels,
    )


def _write(
    out_dir: String,
    format: String,
    quality: Int,
    optimize: Bool,
    width: Int,
    height: Int,
    bands: Int,
    pixels: List[Int],
) raises -> String:
    """Write one encoded image and return its relative URI."""
    var mode = String("RGB")
    if bands == 4:
        mode = "RGBA"
    elif bands != 3:
        raise Error("stored bands are not 3 or 4")
    var payload: List[UInt8]
    if format == "PNG":
        payload = png_text(
            _image_json(mode, width, height, quality, optimize, pixels, False)
        )
    elif format == "JPEG":
        payload = jpeg_text(
            _image_json(mode, width, height, quality, optimize, pixels, True)
        )
    else:
        raise Error("texture format is not JPEG or PNG")
    var suffix = String(".png")
    if format == "JPEG":
        suffix = ".jpg"
    var name = "texture_" + sha256_hex(Span(payload)) + suffix
    var folder = _join(out_dir, "textures")
    makedirs(folder, exist_ok=True)
    Path(_join(folder, name)).write_bytes(Span(payload))
    return "textures/" + name


def _plan(
    path: String,
    color: Bool,
    limit: Int,
    width: Int,
    height: Int,
    masked: Bool,
) raises -> String:
    """Return a texture-plan request."""
    var doc = PyJson()
    var root = doc.new_dict()
    doc.root = root
    var mode = String("texture")
    if masked:
        mode = "fit"
    doc.set(root, "mode", doc.new_str(mode))
    doc.set(root, "path", doc.new_str(path))
    doc.set(root, "color", doc.new_bool(color))
    doc.set(root, "max", doc.new_int(limit))
    doc.set(root, "width", doc.new_int(width))
    doc.set(root, "height", doc.new_int(height))
    return doc.dumps()


def _color_pack(
    mode: String,
    width: Int,
    height: Int,
    pixels: List[Int],
    neutral: Bool,
    resize: Bool,
    out_w: Int,
    out_h: Int,
) raises -> String:
    """Return a color pack request."""
    var doc = PyJson()
    var root = doc.new_dict()
    doc.root = root
    doc.set(root, "mode", doc.new_str("color"))
    doc.set(root, "image_mode", doc.new_str(mode))
    doc.set(root, "width", doc.new_int(width))
    doc.set(root, "height", doc.new_int(height))
    doc.set(root, "neutral", doc.new_bool(neutral))
    doc.set(root, "resize", doc.new_bool(resize))
    doc.set(root, "out_width", doc.new_int(out_w))
    doc.set(root, "out_height", doc.new_int(out_h))
    var listed = doc.new_list()
    for value in pixels:
        doc.append(listed, doc.new_int(value))
    doc.set(root, "pixels", listed)
    return doc.dumps()


def _masked_pack(
    width: Int,
    height: Int,
    color: List[Int],
    mask_mode: String,
    mask_w: Int,
    mask_h: Int,
    mask: List[Int],
    resize: Bool,
    out_w: Int,
    out_h: Int,
) raises -> String:
    """Return a masked pack request."""
    var doc = PyJson()
    var root = doc.new_dict()
    doc.root = root
    doc.set(root, "mode", doc.new_str("masked"))
    doc.set(root, "width", doc.new_int(width))
    doc.set(root, "height", doc.new_int(height))
    doc.set(root, "mask_mode", doc.new_str(mask_mode))
    doc.set(root, "mask_width", doc.new_int(mask_w))
    doc.set(root, "mask_height", doc.new_int(mask_h))
    doc.set(root, "resize", doc.new_bool(resize))
    doc.set(root, "out_width", doc.new_int(out_w))
    doc.set(root, "out_height", doc.new_int(out_h))
    var colors = doc.new_list()
    for value in color:
        doc.append(colors, doc.new_int(value))
    doc.set(root, "color", colors)
    var masks = doc.new_list()
    for value in mask:
        doc.append(masks, doc.new_int(value))
    doc.set(root, "mask", masks)
    return doc.dumps()


def _image_json(
    mode: String,
    width: Int,
    height: Int,
    quality: Int,
    optimize: Bool,
    pixels: List[Int],
    jpeg: Bool,
) raises -> String:
    """Return a PNG or JPEG encode request."""
    var doc = PyJson()
    var root = doc.new_dict()
    doc.root = root
    doc.set(root, "mode", doc.new_str(mode))
    doc.set(root, "width", doc.new_int(width))
    doc.set(root, "height", doc.new_int(height))
    doc.set(root, "optimize", doc.new_bool(optimize))
    if jpeg:
        doc.set(root, "quality", doc.new_int(quality))
    var listed = doc.new_list()
    for value in pixels:
        doc.append(listed, doc.new_int(value))
    doc.set(root, "pixels", listed)
    return doc.dumps()


def _ints(
    doc: PyJson, node: Int, count: Int, label: String
) raises -> List[Int]:
    """Return a list of integers of the expected length."""
    if doc.kind(node) != PY_LIST:
        raise Error(label + " are not a list")
    if doc.length(node) != count:
        raise Error(label + " do not match the image")
    var out = List[Int]()
    for index in range(count):
        out.append(
            _whole(doc, doc.item(node, index), "pixel is not an integer")
        )
    return out^


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


def _join(directory: String, name: String) -> String:
    """Join a directory and a file name with `/`."""
    if directory.byte_length() == 0:
        return name
    var raw = directory.as_bytes()
    if raw[len(raw) - 1] == 47:
        return directory + name
    return directory + "/" + name


def main() raises:
    """Write the texture described by the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_texture_store FILE", file=stderr)
        exit(2)
    try:
        print(store_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_texture_store:", error, file=stderr)
        exit(1)
