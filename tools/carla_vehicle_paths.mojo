# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Find a vehicle blueprint and its cooked package.

    carla_vehicle_paths blueprint ROOT RELATIVE
    carla_vehicle_paths package CONTENT GAME_PATH
    carla_vehicle_paths game CONTENT FILE
    carla_vehicle_paths gltf RAW CONTENT PACKAGE
    carla_vehicle_paths folders CONTENT NAMES

`blueprint` prints the `.uasset` for a vehicle. `package` prints the cooked
file for a `/Game/...` path, or an empty line when there is none. `game`
prints the `/Game/...` path of a cooked file. `gltf` prints the exported
glTF path of a cooked package. `folders` reads a JSON list of `/Game/...`
names and prints the other `.uasset` files in those folders. A pedestrian
path is left out. A skeleton or physics asset is left out. The comparison
ignores case.
"""

from std.os import listdir
from std.os.path import basename, dirname, join
from std.pathlib import Path, cwd
from std.sys import argv, exit, stderr

from tools._python_json import PY_LIST, PY_STR, PyJson
from tools._text import ascii_lower


def blueprint_path(root: String, relative: String) raises -> String:
    """Return the blueprint file, matching its name without case.

    Args:
        root: The `Blueprints/Vehicles` directory.
        relative: The blueprint path inside that directory, without
            `.uasset`.

    Returns:
        The blueprint file. A name that differs only by case matches. When
        no name matches, the first `BP_` file that is not a wheel is used.

    Raises:
        Error: If the directory cannot be read, or no blueprint is there.
    """
    var folder = join(root, dirname(relative))
    var want = ascii_lower(basename(relative)) + ".uasset"
    var names = listdir(folder)
    for name in names:
        if ascii_lower(name) == want:
            return join(folder, name)
    sort(names)
    for name in names:
        var low = ascii_lower(name)
        if (
            low.startswith("bp_")
            and low.endswith(".uasset")
            and not _wheel(low)
        ):
            return join(folder, name)
    raise Error("not found")


def package_path(content: String, game_path: String) raises -> String:
    """Return the cooked `.uasset` for a `/Game/...` package.

    Args:
        content: The cooked `Content` directory.
        game_path: A package path. The first six characters are removed,
            as `path[len("/Game/"):]` does.

    Returns:
        The cooked file, or empty text when it is missing. A missing name
        falls back to the one file in that folder whose name extends the
        package with `_` and is not a skeleton or a physics asset.

    Raises:
        Error: If a directory cannot be read.
    """
    var rel = _after_game(game_path) + ".uasset"
    var path = _join_all(content, rel)
    if Path(path).exists():
        return path
    var folder = dirname(path)
    if not Path(folder).is_dir():
        return String("")
    var stem = basename(game_path) + "_"
    var found = List[String]()
    for name in listdir(folder):
        if (
            name.startswith(stem)
            and name.endswith(".uasset")
            and not _excluded(name)
        ):
            found.append(name)
    if len(found) == 1:
        return join(folder, found[0])
    return String("")


def gltf_path(raw: String, content: String, package: String) raises -> String:
    """Return the exported glTF path of a cooked package.

    Args:
        raw: The directory UModel writes.
        content: The cooked `Content` directory.
        package: The cooked `.uasset` file.

    Returns:
        `raw` joined with the package's path under `content`, with
        `.uasset` replaced by `.gltf`.

    Raises:
        Error: If the package path cannot be made relative to `content`.
    """
    var rel = _relpath(package, content)
    var slash = String("")
    var raw_rel = rel.as_bytes()
    for index in range(len(raw_rel)):
        var byte = raw_rel[index]
        if byte == 92:
            slash += "/"
        else:
            slash += String(rel[byte = index : index + 1])
    var parts = slash.split("/")
    var stem = String(parts[len(parts) - 1])
    if stem.endswith(".uasset"):
        var end = stem.byte_length() - 7
        var trimmed = String(stem[byte=0:end])
        stem = trimmed
    var folder = raw
    for index in range(len(parts) - 1):
        folder = join(folder, String(parts[index]))
    return join(folder, stem + ".gltf")


def folder_candidates(content: String, text: String) raises -> String:
    """Return the other cooked meshes in the folders `text` names.

    Args:
        content: The cooked `Content` directory.
        text: A JSON list of `/Game/...` package paths.

    Returns:
        A JSON list of `path` and `name`. Folders are sorted, then the
        file names in each folder. A pedestrian path is left out. A file
        whose name contains `skeleton` or `physics` is left out.

    Raises:
        Error: If `text` is not a list of strings, or a directory cannot
            be read.
    """
    var doc = PyJson.parse(text)
    if doc.kind(doc.root) != PY_LIST:
        raise Error("names are not a list")
    var folders = List[String]()
    var seen = List[String]()
    for index in range(doc.length(doc.root)):
        var item = doc.item(doc.root, index)
        if doc.kind(item) != PY_STR:
            raise Error("name is not text")
        var game = doc.text(item)
        if game.find("/Pedestrian/") >= 0:
            continue
        var package = package_path(content, game)
        if package.byte_length() == 0:
            continue
        var folder = dirname(package)
        if folder not in seen:
            seen.append(folder)
            folders.append(folder)
    sort(folders)
    var out = String("[")
    var first = True
    for index in range(len(folders)):
        var files = listdir(folders[index])
        sort(files)
        for file in files:
            if not file.endswith(".uasset") or _excluded(file):
                continue
            if not first:
                out += ","
            first = False
            var full = join(folders[index], file)
            out += '{"path":'
            out += _quote(game_path(content, full))
            out += ',"name":'
            out += _quote(file)
            out += "}"
    out += "]"
    return out^


def game_path(content: String, file: String) raises -> String:
    """Return the `/Game/...` package path of a cooked `.uasset`.

    Args:
        content: The cooked `Content` directory.
        file: The cooked file.

    Returns:
        `/Game/` plus the path of `file` inside `content`, with the last
        seven characters removed, as `path[:-len(".uasset")]` does.

    Raises:
        Error: If the working directory cannot be read while making a
            relative path absolute.
    """
    var rel = _relpath(file, content)
    rel = rel.replace("\\", "/")
    if rel.byte_length() <= 7:
        rel = String("")
    else:
        var end = rel.byte_length() - 7
        var chopped = String(rel[byte=:end])
        rel = chopped
    return "/Game/" + rel


def _after_game(game_path: String) -> String:
    """Drop the first six characters, which are `/Game/` on a real path."""
    var raw = game_path.as_bytes()
    if len(raw) <= 6:
        return String("")
    return String(game_path[byte=6:])


def _wheel(low: String) -> Bool:
    """Return whether a lowercased name is a wheel `.uasset`."""
    if not low.endswith("w.uasset") or low.byte_length() < 9:
        return False
    var stem = String(low[byte = : low.byte_length() - 8])
    if stem.endswith("_f") or stem.endswith("_r"):
        return True
    if stem.byte_length() < 3:
        return False
    var tail = String(stem[byte = stem.byte_length() - 3 :])
    if not tail.startswith("_"):
        return False
    var mid = String(tail[byte=1:2])
    var end = String(tail[byte=2:3])
    return (mid == "f" or mid == "r") and (end == "l" or end == "r")


def _quote(text: String) -> String:
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


def _excluded(name: String) -> Bool:
    """Return whether a file name is a skeleton or a physics asset."""
    var low = ascii_lower(name)
    return low.find("skeleton") >= 0 or low.find("physics") >= 0


def _relpath(path: String, start: String) raises -> String:
    """Return `path` relative to `start`, as `os.path.relpath` does."""
    var left = _parts(_abspath(start))
    var right = _parts(_abspath(path))
    var index = 0
    while (
        index < len(left) and index < len(right) and left[index] == right[index]
    ):
        index += 1
    var out = String()
    for _ in range(len(left) - index):
        if out.byte_length() > 0:
            out += "/"
        out += ".."
    for part in range(index, len(right)):
        if out.byte_length() > 0:
            out += "/"
        out += right[part]
    if out.byte_length() == 0:
        return String(".")
    return out


def _abspath(path: String) raises -> String:
    """Return an absolute path with `.` and `..` removed."""
    var full = path
    if not path.startswith("/"):
        full = join(String(cwd()), path)
    var absolute = True
    var stack = List[String]()
    for part in full.split("/"):
        if part.byte_length() == 0 or part == ".":
            continue
        if part == "..":
            if len(stack) > 0:
                _ = stack.pop()
            continue
        stack.append(String(part))
    if not absolute:
        return String("")
    if len(stack) == 0:
        return String("/")
    var out = String()
    for index in range(len(stack)):
        out += "/"
        out += stack[index]
    return out


def _parts(path: String) -> List[String]:
    """Return the nonempty parts of an absolute path."""
    var out = List[String]()
    for part in path.split("/"):
        if part.byte_length() > 0:
            out.append(String(part))
    return out^


def _join_all(base: String, path: String) -> String:
    """Join the `/` parts of `path` onto `base`, as `os.path.join` does."""
    var out = base
    for part in path.split("/"):
        out = join(out, String(part))
    return out


def _usage() raises:
    """Print the usage line and stop."""
    print(
        (
            "usage: carla_vehicle_paths blueprint ROOT RELATIVE | package"
            " CONTENT GAME_PATH | game CONTENT FILE | gltf RAW CONTENT"
            " PACKAGE | folders CONTENT NAMES"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Print one blueprint, cooked package, or `/Game/...` path."""
    var arguments = argv()
    if len(arguments) == 5 and arguments[1] == "gltf":
        try:
            print(gltf_path(arguments[2], arguments[3], arguments[4]))
        except error:
            print("carla_vehicle_paths:", error, file=stderr)
            exit(1)
        return
    if len(arguments) != 4:
        _usage()
    try:
        if arguments[1] == "blueprint":
            print(blueprint_path(arguments[2], arguments[3]))
        elif arguments[1] == "package":
            print(package_path(arguments[2], arguments[3]))
        elif arguments[1] == "game":
            print(game_path(arguments[2], arguments[3]))
        elif arguments[1] == "folders":
            print(
                folder_candidates(arguments[2], Path(arguments[3]).read_text())
            )
        else:
            _usage()
    except error:
        print("carla_vehicle_paths:", error, file=stderr)
        exit(1)
