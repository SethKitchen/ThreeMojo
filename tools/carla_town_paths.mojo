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
the sorted `/Game/...` meshes and materials, once each. `pending` reads
a JSON file and prints the packages that are not exported yet, in
batches.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tree import JsonTree
from tools._python_json import PY_DICT, PY_INT, PY_LIST, PY_NONE, PY_STR, PyJson


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


def export_path(root: String, game_path: String, suffix: String) -> String:
    """Return the exported file for a `/Game/...` package.

    Args:
        root: The directory that holds the export.
        game_path: A package path. The first six characters are removed,
            as `path[len("/Game/"):]` does.
        suffix: The suffix added to the joined path, such as `.gltf`.

    Returns:
        `root` joined with the remaining segments, then `suffix`. An
        empty segment in the middle is skipped. A final empty segment
        keeps the trailing slash.
    """
    var rest = String("")
    if game_path.byte_length() > 6:
        rest = String(game_path[byte=6:])
    return _join(root, _split(rest)) + suffix


def pending_text(text: String) raises -> String:
    """Return the packages that are not exported yet.

    Args:
        text: A JSON object with `root`, `batch`, `meshes` and
            `materials`.

    Returns:
        `todo`, the pending `meshes` and `materials`, and
        `mesh_batches` and `material_batches` of at most `batch` paths.

    Raises:
        Error: If the JSON is not that object, or `batch` is not positive.
    """
    var doc = PyJson.parse(text)
    var root = doc.root
    if doc.kind(root) != PY_DICT:
        raise Error("pending request is not an object")
    var folder = doc.text(doc.at(root, "root"))
    var batch = _whole(doc, doc.at(root, "batch"))
    if batch < 1:
        raise Error("batch is not positive")
    var meshes = _paths(doc, doc.at(root, "meshes"))
    var materials = _paths(doc, doc.at(root, "materials"))
    var mesh_pending = _missing(folder, meshes, ".gltf")
    var material_pending = _missing(folder, materials, ".mat")
    var tree = JsonTree()
    var obj = tree.object()
    tree.set(
        obj, "todo", tree.integer(len(mesh_pending) + len(material_pending))
    )
    tree.set(obj, "meshes", _array(tree, mesh_pending))
    tree.set(obj, "materials", _array(tree, material_pending))
    tree.set(obj, "mesh_batches", _batches(tree, mesh_pending, batch))
    tree.set(obj, "material_batches", _batches(tree, material_pending, batch))
    return tree.dumps(obj, False)


def _paths(doc: PyJson, node: Int) raises -> List[String]:
    """Return the strings in a JSON list."""
    if doc.kind(node) != PY_LIST:
        raise Error("packages are not a list")
    var out = List[String]()
    for index in range(doc.length(node)):
        var item = doc.item(node, index)
        if doc.kind(item) != PY_STR:
            raise Error("package is not a string")
        out.append(doc.text(item))
    return out^


def _missing(root: String, paths: List[String], suffix: String) -> List[String]:
    """Return the packages whose export file is absent."""
    var out = List[String]()
    for index in range(len(paths)):
        if not Path(export_path(root, paths[index], suffix)).exists():
            out.append(paths[index])
    return out^


def _batches(mut tree: JsonTree, paths: List[String], batch: Int) raises -> Int:
    """Return batches of at most `batch` paths."""
    var groups = tree.array()
    var current = tree.array()
    var count = 0
    for index in range(len(paths)):
        if count == batch:
            tree.append(groups, current)
            current = tree.array()
            count = 0
        tree.append(current, tree.string(paths[index]))
        count += 1
    if count > 0:
        tree.append(groups, current)
    return groups


def _split(text: String) -> List[String]:
    """Split `text` on `/`, keeping empty segments."""
    var parts = List[String]()
    var raw = text.as_bytes()
    var start = 0
    for index in range(len(raw) + 1):
        if index == len(raw) or raw[index] == 47:
            parts.append(String(text[byte=start:index]))
            start = index + 1
    return parts^


def _join(root: String, parts: List[String]) -> String:
    """Join `parts` onto `root`, as `os.path.join` does for `/`."""
    var out = root
    var trailing = False
    var saw = False
    for index in range(len(parts)):
        if parts[index].byte_length() == 0:
            trailing = True
            continue
        trailing = False
        saw = True
        if not _slash(out):
            out += "/"
        out += parts[index]
    if trailing or not saw:
        if not _slash(out):
            out += "/"
    return out^


def _slash(text: String) -> Bool:
    """Return whether `text` ends with `/`."""
    var raw = text.as_bytes()
    return len(raw) > 0 and raw[len(raw) - 1] == 47


def _whole(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer."""
    if doc.kind(node) != PY_INT:
        raise Error("batch is not an integer")
    var raw = doc.text(node).as_bytes()
    if len(raw) == 0:
        raise Error("batch is not an integer")
    var index = 0
    var negative = False
    if raw[0] == 45:
        negative = True
        index = 1
    if index >= len(raw):
        raise Error("batch is not an integer")
    var value = 0
    for offset in range(index, len(raw)):
        var byte = raw[offset]
        if byte < 48 or byte > 57:
            raise Error("batch is not an integer")
        value = value * 10 + Int(byte - 48)
    if negative:
        return -value
    return value


def _usage() raises:
    """Print the usage line and stop."""
    print(
        (
            "usage: carla_town_paths object TEXT | relative TEXT | wanted [FILE"
            " ...] | pending FILE"
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
    if arguments[1] == "pending" and len(arguments) == 3:
        try:
            print(pending_text(Path(arguments[2]).read_text()))
        except error:
            print("carla_town_paths:", error, file=stderr)
            exit(1)
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
