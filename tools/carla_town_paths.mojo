# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the packages a CARLA town layout asks to export.

    carla_town_paths object TEXT
    carla_town_paths relative TEXT
    carla_town_paths wanted [FILE ...]

`object` prints the package in UE4SS's `Class /Game/A/B.B`. `relative`
prints the cooked `.uasset` path. `wanted` reads layout files and prints
the sorted `/Game/...` meshes and materials, once each.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tree import JsonTree
from tools._python_json import PY_DICT, PY_LIST, PY_NONE, PY_STR, PyJson


def package_of(full_name: String) raises -> String:
    """Return the package in a `Class /Game/A/B.B` name.

    Args:
        full_name: The UE4SS object name.

    Returns:
        The text before the last dot of the path. A path with no dot is
        returned whole. The class and the first space are removed.

    Raises:
        Error: If `full_name` has no space.
    """
    var space = full_name.find(" ")
    if space < 0:
        raise Error("object path has no class")
    var rest = String(full_name[byte = space + 1 :])
    var dot = rest.rfind(".")
    if dot < 0:
        return rest^
    return String(rest[byte=:dot])


def cooked_name(game_path: String) -> String:
    """Return the cooked package name of a `/Game/...` path.

    Args:
        game_path: A package path. The first six characters are removed,
            as `path[len("/Game/"):]` does, whether or not they are that
            prefix.

    Returns:
        The remaining text plus `.uasset`. A path of six characters or
        fewer returns `.uasset`.
    """
    var raw = game_path.as_bytes()
    if len(raw) <= 6:
        return String(".uasset")
    return String(game_path[byte=6:]) + ".uasset"


def wanted_text(var paths: List[String]) raises -> String:
    """Return the meshes and materials named in layout files.

    Args:
        paths: JSONL layout files. Each line is one component.

    Returns:
        An object with sorted `meshes` and `materials` arrays. Only paths
        that start with `/Game/` are kept, once each.

    Raises:
        Error: If a file cannot be read, a line is not a layout object, or
            an object name has no class.
    """
    var meshes = List[String]()
    var materials = List[String]()
    for index in range(len(paths)):
        _read(meshes, materials, paths[index])
    var tree = JsonTree()
    var obj = tree.object()
    tree.set(obj, "meshes", _array(tree, meshes))
    tree.set(obj, "materials", _array(tree, materials))
    return tree.dumps(obj, False)


def _read(
    mut meshes: List[String], mut materials: List[String], path: String
) raises:
    """Add the packages named in one layout file."""
    var lines = _lines(_newlines(Path(path).read_text()))
    for index in range(len(lines)):
        var doc = PyJson.parse(lines[index])
        if doc.kind(doc.root) != PY_DICT:
            raise Error("layout row is not an object")
        var mesh = doc.at(doc.root, "mesh")
        if doc.kind(mesh) != PY_STR:
            raise Error("mesh is not a string")
        _keep(meshes, doc.text(mesh))
        var listed = doc.at(doc.root, "materials")
        if doc.kind(listed) != PY_LIST:
            raise Error("materials is not a list")
        for item_index in range(doc.length(listed)):
            var item = doc.item(listed, item_index)
            if doc.kind(item) == PY_NONE:
                continue
            if doc.kind(item) != PY_STR:
                raise Error("material is not a string")
            if doc.text(item).byte_length() == 0:
                continue
            _keep(materials, doc.text(item))


def _keep(mut found: List[String], text: String) raises:
    """Keep a `/Game/` package, once, in sorted order."""
    var package = package_of(text)
    if not _starts(package, "/Game/"):
        return
    _add(found, package^)


def _array(mut tree: JsonTree, found: List[String]) raises -> Int:
    """Return a JSON array of `found`."""
    var array = tree.array()
    for index in range(len(found)):
        tree.append(array, tree.string(found[index]))
    return array


def _add(mut found: List[String], var text: String):
    """Insert `text` once, in code-point order."""
    var index = 0
    while index < len(found):
        if found[index] == text:
            return
        if _before(text, found[index]):
            break
        index += 1
    found.insert(index, text^)


def _before(left: String, right: String) -> Bool:
    """Return whether `left` sorts before `right`."""
    var a = left.as_bytes()
    var b = right.as_bytes()
    var count = len(a)
    if len(b) < count:
        count = len(b)
    for index in range(count):
        if a[index] < b[index]:
            return True
        if a[index] > b[index]:
            return False
    return len(a) < len(b)


def _lines(text: String) -> List[String]:
    """Return lines without their newline, as a text file yields them."""
    var out = List[String]()
    var raw = text.as_bytes()
    var start = 0
    for index in range(len(raw)):
        if raw[index] == 10:
            out.append(String(text[byte=start:index]))
            start = index + 1
    if start < len(raw):
        out.append(String(text[byte=start:]))
    return out^


def _newlines(text: String) -> String:
    """Return `text` with CR, LF and CRLF written as LF."""
    var out = String()
    var skip_lf = False
    for codepoint in text.codepoints():
        var code = Int(codepoint.to_u32())
        if skip_lf:
            skip_lf = False
            if code == 10:
                continue
        if code == 13:
            out += "\n"
            skip_lf = True
        elif code == 10:
            out += "\n"
        else:
            out += chr(code)
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


def _usage() raises:
    """Print the usage line and stop."""
    print(
        (
            "usage: carla_town_paths object TEXT | relative TEXT | wanted [FILE"
            " ...]"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print one package name, or the packages named in layout files."""
    var arguments = argv()
    if len(arguments) < 2:
        _usage()
    if arguments[1] == "object" and len(arguments) == 3:
        try:
            print(package_of(arguments[2]))
        except error:
            print("carla_town_paths:", error, file=stderr)
            exit(1)
        return
    if arguments[1] == "relative" and len(arguments) == 3:
        print(cooked_name(arguments[2]))
        return
    if arguments[1] == "wanted":
        var files = List[String]()
        for index in range(2, len(arguments)):
            files.append(arguments[index])
        try:
            print(wanted_text(files^))
        except error:
            print("carla_town_paths:", error, file=stderr)
            exit(1)
        return
    _usage()
