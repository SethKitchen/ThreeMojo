# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose a vehicle's body and its glass.

    carla_vehicle_pick FILE

`FILE` is JSON with `refs` and `extras`. A pedestrian package is left
out. The body is the largest skeletal mesh. Glass and lights are the
static meshes. A name containing `_sc_` or `/sm_sc`, or ending in
`_prop`, is left out. The comparison ignores case. When the blueprint
names no body, `extras` supplies one from its folder. The file name
must end in `.uasset`. A skeleton or physics asset there is left out.
"""

from std.os.path import basename
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_float import parse_float
from tools._python_json import PY_DICT, PY_INT, PY_LIST, PyJson


def pick_text(text: String) raises -> String:
    """Return the body and the static meshes as JSON.

    Args:
        text: A JSON object with `refs` and `extras`.

    Returns:
        `body`, `static`, `skeletal`, and `error`. `body` is empty when none fit.

    Raises:
        Error: If the JSON is not an object, or a size is missing.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("pick request is not an object")
    var refs = _entries(doc, doc.at(root, "refs"), False)
    var extras = _entries(doc, doc.at(root, "extras"), True)
    var skeletal = List[Int]()
    var statics = List[Int]()
    var names = List[String]()
    for index in range(len(refs)):
        var path = refs[index].path
        if _has(path, "/Pedestrian/"):
            continue
        names.append(basename(path))
        if refs[index].kind == "SkeletalMesh":
            skeletal.append(index)
        elif refs[index].kind == "StaticMesh" and not _static_skip(path):
            statics.append(index)
    if len(skeletal) == 0:
        for index in range(len(extras)):
            var item = extras[index]
            if item.kind != "SkeletalMesh":
                continue
            if not _ends_exact(item.label, ".uasset"):
                continue
            if _contains(item.label, "skeleton") or _contains(
                item.label, "physics"
            ):
                continue
            # A negative mark is -(index + 1), so it cannot be a ref index.
            skeletal.append(-(index + 1))
    if len(skeletal) == 0:
        var message = String("no skeletal mesh among ")
        for index in range(len(names)):
            if index > 0:
                message += ", "
            message += names[index]
        return (
            '{"body":"","static":[],"skeletal":[],"error":'
            + _json(message)
            + "}"
        )
    _by_size(skeletal, refs, extras)
    var body = _path_at(skeletal[0], refs, extras)
    var out = String('{"body":')
    out += _json(body)
    out += ',"static":['
    for index in range(len(statics)):
        if index > 0:
            out += ","
        out += _json(refs[statics[index]].path)
    out += '],"skeletal":['
    for index in range(len(skeletal)):
        if index > 0:
            out += ","
        out += _json(_path_at(skeletal[index], refs, extras))
    out += '],"error":""}'
    return out^


@fieldwise_init
struct _Entry(ImplicitlyCopyable, Movable):
    var path: String
    var kind: String
    var size: Int
    var label: String


def _entries(doc: PyJson, node: Int, extras: Bool) raises -> List[_Entry]:
    """Read mesh records. Extras also carry the file name."""
    if doc.kind(node) != PY_LIST:
        raise Error("meshes are not a list")
    var out = List[_Entry]()
    for index in range(doc.length(node)):
        var item = doc.item(node, index)
        if doc.kind(item) != PY_DICT:
            raise Error("mesh is not an object")
        var path = doc.text(doc.at(item, "path"))
        var kind = doc.text(doc.at(item, "class"))
        var size = _whole(doc, doc.at(item, "size"))
        if size < 0:
            raise Error("size is negative")
        var label = String("")
        if extras:
            label = doc.text(doc.at(item, "name"))
        out.append(_Entry(path, kind, size, label))
    return out^


def _static_skip(path: String) -> Bool:
    """Return whether a static mesh is a collision piece or a prop."""
    return (
        _contains(path, "_sc_")
        or _contains(path, "/sm_sc")
        or _ends(path, "_prop")
    )


def _by_size(mut order: List[Int], refs: List[_Entry], extras: List[_Entry]):
    """Sort skeletal indexes so the largest file is first."""
    for index in range(1, len(order)):
        var key = order[index]
        var slot = index
        while slot > 0 and _size(order[slot - 1], refs, extras) < _size(
            key, refs, extras
        ):
            order[slot] = order[slot - 1]
            slot -= 1
        order[slot] = key


def _size(mark: Int, refs: List[_Entry], extras: List[_Entry]) -> Int:
    """Return the file size of one skeletal mark."""
    if mark < 0:
        return extras[-mark - 1].size
    return refs[mark].size


def _path_at(mark: Int, refs: List[_Entry], extras: List[_Entry]) -> String:
    """Return the package path of one skeletal mark."""
    if mark < 0:
        return extras[-mark - 1].path
    return refs[mark].path


def _has(text: String, needle: String) -> Bool:
    """Return whether `text` contains `needle`."""
    var raw = text.as_bytes()
    var pat = needle.as_bytes()
    if len(pat) == 0 or len(raw) < len(pat):
        return False
    for start in range(len(raw) - len(pat) + 1):
        var matched = True
        for index in range(len(pat)):
            if raw[start + index] != pat[index]:
                matched = False
                break
        if matched:
            return True
    return False


def _ends_exact(text: String, needle: String) -> Bool:
    """Return whether `text` ends with `needle`."""
    var raw = text.as_bytes()
    var pat = needle.as_bytes()
    if len(raw) < len(pat):
        return False
    var start = len(raw) - len(pat)
    for index in range(len(pat)):
        if raw[start + index] != pat[index]:
            return False
    return True


def _contains(text: String, needle: String) -> Bool:
    """Return whether `text` contains `needle`, ignoring ASCII case."""
    var raw = text.as_bytes()
    var pat = needle.as_bytes()
    if len(pat) == 0 or len(raw) < len(pat):
        return False
    for start in range(len(raw) - len(pat) + 1):
        var matched = True
        for index in range(len(pat)):
            if _fold(raw[start + index]) != _fold(pat[index]):
                matched = False
                break
        if matched:
            return True
    return False


def _ends(text: String, needle: String) -> Bool:
    """Return whether `text` ends with `needle`, ignoring ASCII case."""
    var raw = text.as_bytes()
    var pat = needle.as_bytes()
    if len(raw) < len(pat):
        return False
    var start = len(raw) - len(pat)
    for index in range(len(pat)):
        if _fold(raw[start + index]) != _fold(pat[index]):
            return False
    return True


def _fold(byte: UInt8) -> UInt8:
    """Return the ASCII lowercase of one byte."""
    if byte >= 65 and byte <= 90:
        return byte + 32
    return byte


def _json(text: String) -> String:
    """Return `text` as a JSON string."""
    var out = String('"')
    var raw = text.as_bytes()
    for index in range(len(raw)):
        var byte = raw[index]
        if byte == 34 or byte == 92:
            out += "\\"
        out += String(text[byte = index : index + 1])
    out += '"'
    return out^


def _whole(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("size is not an integer")
    return Int(parse_float(doc.text(node)))


def main() raises:
    """Print the body and the glass for the JSON file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_vehicle_pick FILE", file=stderr)
        exit(2)
    try:
        print(pick_text(Path(arguments[1]).read_text()))
    except error:
        print("carla_vehicle_pick:", error, file=stderr)
        exit(1)
