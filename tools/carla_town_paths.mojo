# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Name the packages a CARLA town layout asks to export.

    carla_town_paths object TEXT
    carla_town_paths relative TEXT
    carla_town_paths wanted [FILE ...]
    carla_town_paths export ROOT GAME_PATH SUFFIX
    carla_town_paths split FILE
    carla_town_paths command FILE
    carla_town_paths drive [--root DIR] [--batch N] [--limit SECONDS] [TOWN ...]

`object` prints the package in UE4SS's `Class /Game/A/B.B`. `relative`
prints the cooked `.uasset` path. `wanted` reads layout files and prints
the sorted `/Game/...` meshes and materials, once each. `pending` reads
a JSON file and prints the packages that are not exported yet, in
batches. `export` joins `ROOT` with the package path and adds
`SUFFIX`. `split` reads a JSON list of packages. One package is given
up. A longer list is cut in half, with the extra package on the right.
`command` prints the UModel arguments for one batch. `drive` runs
UModel on each batch. A batch that takes too long is cut in half.
"""

from std.os import getenv
from std.os.path import join
from std.pathlib import Path, cwd
from std.sys import argv, exit, stderr

from tools._process import run_program
from tools._python_float import parse_float

from tools._json_tools import quote_ascii
from tools._json_tree import JsonTree
from tools._python_json import (
    PY_BOOL,
    PY_DICT,
    PY_INT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    PyJson,
)
from tools._town_json import json_text


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
    var text = Path(path).read_text()
    var lines = _lines(text.replace("\r\n", "\n").replace("\r", "\n"))
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
    if not package.startswith("/Game/"):
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
        if text < found[index]:
            break
        index += 1
    found.insert(index, text^)


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
    return _join(root, rest) + suffix


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


def _join(root: String, path: String) -> String:
    """Join the `/` parts of `path` onto `root`, as `os.path.join` does."""
    var out = root
    var trailing = False
    var saw = False
    for part in path.split("/"):
        if part.byte_length() == 0:
            trailing = True
            continue
        trailing = False
        saw = True
        if not out.endswith("/"):
            out += "/"
        out += part
    if trailing or not saw:
        if not out.endswith("/"):
            out += "/"
    return out^


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


def split_text(text: String) raises -> String:
    """Return how to divide one timed-out export batch.

    Args:
        text: A JSON list of package paths.

    Returns:
        `gave_up` and `path` when the list has one package. Otherwise
        `split`, `left` and `right`. `left` is the first half. `right`
        holds the rest, including the extra package of an odd count.

    Raises:
        Error: If `text` is not a list of strings, or the list is empty.
    """
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_LIST or doc.length(doc.root) == 0:
        raise Error("batch is empty")
    var names = List[String]()
    for index in range(doc.length(doc.root)):
        var item = doc.item(doc.root, index)
        if doc.kind(item) != PY_STR:
            raise Error("package is not text")
        names.append(doc.text(item))
    var tree = JsonTree()
    var obj = tree.object()
    if len(names) == 1:
        tree.set_text(obj, "action", "gave_up")
        tree.set_text(obj, "path", names[0])
        return tree.dumps(obj, False)
    var half = len(names) // 2
    var left = List[String]()
    var right = List[String]()
    for index in range(half):
        left.append(names[index])
    for index in range(half, len(names)):
        right.append(names[index])
    tree.set_text(obj, "action", "split")
    tree.set(obj, "left", tree.strings(left))
    tree.set(obj, "right", tree.strings(right))
    return tree.dumps(obj, False)


def command_text(text: String) raises -> String:
    """Return the UModel arguments for one export batch.

    Args:
        text: JSON with `umodel`, `content`, `out`, `mesh`, and
            `packages`. `packages` is a list of `/Game/...` paths.
            `mesh` true adds `-gltf`.

    Returns:
        A JSON list. The first package is the main file. Each later
        package is a `-pkg=` argument. Paths are cooked `.uasset` names.

    Raises:
        Error: If the JSON is not that batch, or the list is empty.
    """
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_DICT:
        raise Error("command request is not an object")
    var umodel = json_text(
        doc, doc.at(doc.root, "umodel"), "umodel is not text"
    )
    var content = json_text(
        doc, doc.at(doc.root, "content"), "content is not text"
    )
    var out = json_text(doc, doc.at(doc.root, "out"), "out is not text")
    var mesh_node = doc.at(doc.root, "mesh")
    if doc.kind(mesh_node) != PY_BOOL:
        raise Error("mesh is not a bool")
    var packages = doc.at(doc.root, "packages")
    if doc.kind(packages) != PY_LIST or doc.length(packages) == 0:
        raise Error("batch is empty")
    var args = List[String]()
    args.append(umodel)
    args.append("-game=ue4.26")
    args.append("-path=" + content)
    args.append("-export")
    args.append("-png")
    args.append("-out=" + out)
    if doc.flag(mesh_node):
        args.append("-gltf")
    for index in range(doc.length(packages)):
        var item = doc.item(packages, index)
        if doc.kind(item) != PY_STR:
            raise Error("package is not text")
        var cooked = cooked_name(doc.text(item))
        if index == 0:
            args.append(cooked)
        else:
            args.append("-pkg=" + cooked)
    var encoded = String("[")
    for index in range(len(args)):
        if index > 0:
            encoded += ","
        encoded += quote_ascii(args[index])
    encoded += "]"
    return encoded^


def drive(root: String, towns: List[String], batch: Int, limit: Float64) raises:
    """Export the packages named by each town layout.

    Args:
        root: The export directory. Layouts are in `layout`, cooked
            content is in `release/CarlaUE4/Content`, and UModel is
            `umodel/umodel_64.exe`. Exports land in `raw_town`.
        towns: The town names. Each layout is `layout/<town>.jsonl`.
        batch: The most packages in one UModel run.
        limit: The most seconds one UModel run may take.

    Raises:
        Error: If a layout cannot be read, `batch` or `limit` is not
            positive, or UModel cannot be started.
    """
    if batch < 1:
        raise Error("batch is not positive")
    if not limit > 0:
        raise Error("limit is not positive")
    var files = List[String]()
    for index in range(len(towns)):
        files.append(join(root, "layout/" + towns[index] + ".jsonl"))
    var wanted = PyJson.parse(wanted_text(files^))
    var meshes = _paths(wanted, wanted.at(wanted.root, "meshes"))
    var materials = _paths(wanted, wanted.at(wanted.root, "materials"))
    var raw = join(root, "raw_town")
    var umodel = join(root, "umodel/umodel_64.exe")
    var content = join(root, "release/CarlaUE4/Content")
    var plan = PyJson.parse(
        pending_text(_pending_json(raw, batch, meshes, materials))
    )
    var todo = _whole(plan, plan.at(plan.root, "todo"))
    print(
        String(len(meshes))
        + " meshes, "
        + String(len(materials))
        + " materials, "
        + String(todo)
        + " to export"
    )
    _export_groups(
        plan,
        plan.at(plan.root, "mesh_batches"),
        True,
        "meshes",
        umodel,
        content,
        raw,
        limit,
    )
    _export_groups(
        plan,
        plan.at(plan.root, "material_batches"),
        False,
        "materials",
        umodel,
        content,
        raw,
        limit,
    )
    var again = PyJson.parse(
        pending_text(_pending_json(raw, batch, meshes, materials))
    )
    var missing_meshes = _paths(again, again.at(again.root, "meshes"))
    var missing_materials = _paths(again, again.at(again.root, "materials"))
    print(
        String(len(missing_meshes) + len(missing_materials)) + " not exported"
    )
    var shown = 0
    for index in range(len(missing_meshes)):
        if shown == 20:
            break
        print("   " + missing_meshes[index])
        shown += 1
    for index in range(len(missing_materials)):
        if shown == 20:
            break
        print("   " + missing_materials[index])
        shown += 1


def _pending_json(
    raw: String, batch: Int, meshes: List[String], materials: List[String]
) -> String:
    """Return the pending request for `raw`."""
    var out = String('{"root":')
    out += quote_ascii(raw)
    out += ',"batch":'
    out += String(batch)
    out += ',"meshes":'
    out += _json_strings(meshes)
    out += ',"materials":'
    out += _json_strings(materials)
    out += "}"
    return out


def _json_strings(items: List[String]) -> String:
    """Return a compact JSON list of strings."""
    var out = String("[")
    for index in range(len(items)):
        if index > 0:
            out += ","
        out += quote_ascii(items[index])
    out += "]"
    return out


def _export_groups(
    doc: PyJson,
    node: Int,
    mesh: Bool,
    label: String,
    umodel: String,
    content: String,
    raw: String,
    limit: Float64,
) raises:
    """Run each batch and print how many of `label` are done."""
    var total = 0
    var count = doc.length(node)
    for index in range(count):
        total += doc.length(doc.item(node, index))
    var done = 0
    for index in range(count):
        var packages = _paths(doc, doc.item(node, index))
        var size = len(packages)
        _run_batch(packages, mesh, umodel, content, raw, limit)
        done += size
        print("exported " + String(done) + " of " + String(total) + " " + label)


def _run_batch(
    packages: List[String],
    mesh: Bool,
    umodel: String,
    content: String,
    raw: String,
    limit: Float64,
) raises:
    """Run one batch, and split it when UModel takes too long."""
    var payload = String('{"umodel":')
    payload += quote_ascii(umodel)
    payload += ',"content":'
    payload += quote_ascii(content)
    payload += ',"out":'
    payload += quote_ascii(raw)
    payload += ',"mesh":'
    if mesh:
        payload += "true"
    else:
        payload += "false"
    payload += ',"packages":'
    payload += _json_strings(packages)
    payload += "}"
    var encoded = PyJson.parse(command_text(payload))
    var command = _paths(encoded, encoded.root)
    var ran = run_program(command, limit)
    if not ran.timed_out:
        return
    var plan = PyJson.parse(split_text(_json_strings(packages)))
    var action = plan.text(plan.at(plan.root, "action"))
    if action == "gave_up":
        print(
            "gave up on " + plan.text(plan.at(plan.root, "path")),
            file=stderr,
        )
        return
    var left = _paths(plan, plan.at(plan.root, "left"))
    var right = _paths(plan, plan.at(plan.root, "right"))
    _run_batch(left, mesh, umodel, content, raw, limit)
    _run_batch(right, mesh, umodel, content, raw, limit)


def _absolute(path: String) raises -> String:
    """Return `path` as an absolute path, as `os.path.abspath` does for `.`."""
    if path.startswith("/"):
        return path
    var here = String(cwd())
    if path == "." or path.byte_length() == 0:
        return here
    return join(here, path)


def _drive_cli(arguments: List[String]) raises:
    """Read `drive` options and export the named towns."""
    var root = String()
    var limit = Float64(55)
    var batch = 40
    var towns = List[String]()
    var index = 2
    while index < len(arguments):
        var word = arguments[index]
        if word == "--root" or word == "--limit" or word == "--batch":
            if index + 1 >= len(arguments):
                raise Error(word + " needs a value")
            var value = arguments[index + 1]
            if word == "--root":
                root = value
            elif word == "--limit":
                limit = parse_float(value)
            else:
                batch = _batch_arg(value)
            index += 2
            continue
        if word.startswith("--"):
            raise Error("unknown argument " + word)
        towns.append(word)
        index += 1
    if root.byte_length() == 0:
        root = getenv("CARLA_EXPORT_DIR", ".")
    if len(towns) == 0:
        towns = _default_towns()
    drive(_absolute(root), towns, batch, limit)


def _batch_arg(text: String) raises -> Int:
    """Return a positive decimal batch size."""
    var raw = text.as_bytes()
    if len(raw) == 0:
        raise Error("batch is not an integer")
    var value = 0
    for index in range(len(raw)):
        var byte = raw[index]
        if byte < 48 or byte > 57:
            raise Error("batch is not an integer")
        value = value * 10 + Int(byte - 48)
    return value


def _default_towns() -> List[String]:
    """Return Town01 through Town05 and Town10HD."""
    var towns = List[String]()
    towns.append("Town01")
    towns.append("Town02")
    towns.append("Town03")
    towns.append("Town04")
    towns.append("Town05")
    towns.append("Town10HD")
    return towns^


def _usage() raises:
    """Print the usage line and stop."""
    print(
        (
            "usage: carla_town_paths object TEXT | relative TEXT | wanted [FILE"
            " ...] | pending FILE | export ROOT GAME_PATH SUFFIX | split FILE |"
            " command FILE | drive [--root DIR] [--batch N] [--limit SECONDS]"
            " [TOWN ...]"
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
    if arguments[1] == "command" and len(arguments) == 3:
        try:
            print(command_text(Path(arguments[2]).read_text()))
        except error:
            print("carla_town_paths:", error, file=stderr)
            exit(1)
        return
    if arguments[1] == "split" and len(arguments) == 3:
        try:
            print(split_text(Path(arguments[2]).read_text()))
        except error:
            print("carla_town_paths:", error, file=stderr)
            exit(1)
        return
    if arguments[1] == "export" and len(arguments) == 5:
        print(export_path(arguments[2], arguments[3], arguments[4]))
        return
    if arguments[1] == "drive":
        var copied = List[String]()
        for index in range(len(arguments)):
            copied.append(String(arguments[index]))
        try:
            _drive_cli(copied)
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
