# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Pack a town's loose glTF into one binary glTF.

    carla_town_glb OUT_DIR NAME

The program reads `OUT_DIR/NAME.gltf`, its buffer and its images. It
pads the buffer to a multiple of four, stores each image in that buffer,
and writes `OUT_DIR/NAME.glb`. It then removes the loose glTF, the loose
buffer and the `textures` directory.
"""

from std.os import listdir, remove, rmdir
from std.pathlib import Path
from std.sys import argv, exit, stderr

from loaders.json import ARRAY, BOOLEAN, NULL, NUMBER, OBJECT, STRING
from tools._json_tools import quote_ascii
from tools._json_tree import NOTHING, JsonTree
from tools._python_float import python_repr


def pack_glb(out_dir: String, name: String) raises:
    """Write `name`.glb and remove the loose files it replaces.

    Args:
        out_dir: The package directory.
        name: The package name, without an extension.

    Raises:
        Error: If the glTF, its buffer or an image is missing or not the
            shape this packer expects.
    """
    var gltf_path = out_dir + "/" + name + ".gltf"
    var bin_path = out_dir + "/" + name + ".bin"
    var tree = JsonTree()
    var root = tree.parse(Path(gltf_path).read_text())
    var blob = Path(bin_path).read_bytes()
    var images = tree.get(root, "images")
    if images != NOTHING:
        var count = len(tree.items(images))
        for index in range(count):
            var image = _at(tree, images, index)
            var uri = tree.text(tree.item(image, "uri"))
            _pad(blob)
            var offset = len(blob)
            var data = Path(out_dir + "/" + uri).read_bytes()
            for byte in range(len(data)):
                blob.append(data[byte])
            var views = tree.item(root, "bufferViews")
            var view = tree.object()
            tree.set(view, "buffer", tree.integer(0))
            tree.set(view, "byteOffset", tree.integer(offset))
            tree.set(view, "byteLength", tree.integer(len(data)))
            tree.append(views, view)
            var mime = "image/jpeg"
            if _ends(uri, ".png"):
                mime = "image/png"
            var fresh = tree.object()
            tree.set(
                fresh, "bufferView", tree.integer(len(tree.items(views)) - 1)
            )
            tree.set(fresh, "mimeType", tree.string(mime))
            tree.replace(images, index, fresh)
    _pad(blob)
    var buffers = tree.array()
    var one = tree.object()
    tree.set(one, "byteLength", tree.integer(len(blob)))
    tree.append(buffers, one)
    tree.set(root, "buffers", buffers)
    var text = _compact(tree, root).as_bytes()
    var json_bytes = List[UInt8]()
    for index in range(len(text)):
        json_bytes.append(text[index])
    while len(json_bytes) % 4 != 0:
        json_bytes.append(32)
    var total = 12 + 8 + len(json_bytes) + 8 + len(blob)
    var out = List[UInt8]()
    _u32(out, 0x46546C67)
    _u32(out, 2)
    _u32(out, total)
    _u32(out, len(json_bytes))
    _u32(out, 0x4E4F534A)
    for index in range(len(json_bytes)):
        out.append(json_bytes[index])
    _u32(out, len(blob))
    _u32(out, 0x004E4942)
    for index in range(len(blob)):
        out.append(blob[index])
    Path(out_dir + "/" + name + ".glb").write_bytes(Span(out))
    remove(gltf_path)
    remove(bin_path)
    _remove_tree(out_dir + "/textures")


def _compact(mut tree: JsonTree, node: Int) raises -> String:
    """Return JSON with no spaces, as `json.dumps(separators=(',', ':'))`."""
    var out = String()
    _write(out, tree, node)
    return out^


def _write(mut out: String, mut tree: JsonTree, node: Int) raises:
    """Append one value with no spaces around `:` or `,`."""
    var kind = tree.kind(node)
    if kind == NULL:
        out += "null"
    elif kind == BOOLEAN:
        out += "true" if tree.flag(node) else "false"
    elif kind == NUMBER:
        if tree.is_int(node):
            out += String(tree.int_value(node))
        else:
            out += python_repr(tree.value(node))
    elif kind == STRING:
        out += quote_ascii(tree.text(node))
    elif kind == ARRAY or kind == OBJECT:
        var count = len(tree.items(node))
        out += "[" if kind == ARRAY else "{"
        if count == 0:
            out += "]" if kind == ARRAY else "}"
            return
        var names = tree.names(node) if kind == OBJECT else List[String]()
        var items = tree.items(node)
        for index in range(count):
            if index > 0:
                out += ","
            if kind == OBJECT:
                out += quote_ascii(names[index]) + ":"
            _write(out, tree, items[index])
        out += "]" if kind == ARRAY else "}"
    else:
        raise Error("town glb cannot write this JSON value")


def _at(tree: JsonTree, node: Int, index: Int) raises -> Int:
    """Return one array item."""
    var items = tree.items(node)
    if index < 0 or index >= len(items):
        raise Error("list index out of range")
    return items[index]


def _pad(mut data: List[UInt8]):
    """Append zero bytes until the length is a multiple of four."""
    while len(data) % 4 != 0:
        data.append(0)


def _u32(mut out: List[UInt8], value: Int):
    """Append one little-endian unsigned 32-bit value."""
    var rest = value
    for _ in range(4):
        out.append(UInt8(rest & 255))
        rest >>= 8


def _ends(text: String, suffix: String) -> Bool:
    """Return whether `text` ends with `suffix`."""
    var raw = text.as_bytes()
    var tail = suffix.as_bytes()
    if len(raw) < len(tail):
        return False
    var start = len(raw) - len(tail)
    for index in range(len(tail)):
        if raw[start + index] != tail[index]:
            return False
    return True


def _remove_tree(path: String) raises:
    """Remove a directory and what it holds. A missing path is left out."""
    var directory = Path(path)
    if not directory.exists():
        return
    if directory.is_dir():
        for name in listdir(path):
            _remove_tree(String(directory / name))
        rmdir(path)
    else:
        remove(path)


def main() raises:
    """Pack the package named on the command line."""
    var arguments = argv()
    if len(arguments) != 3:
        print("usage: carla_town_glb OUT_DIR NAME", file=stderr)
        exit(2)
    try:
        pack_glb(arguments[1], arguments[2])
    except error:
        print("carla_town_glb:", error, file=stderr)
        exit(1)
