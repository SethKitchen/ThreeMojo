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
from std.pathlib import Path, cwd
from std.sys import argv, exit, stderr

from tools._python_json import PY_LIST, PY_STR, PyJson


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
    var folder = _join(root, _dirname(relative))
    var want = _lower(_basename(relative)) + ".uasset"
    for name in listdir(folder):
        if _lower(name) == want:
            return _join(folder, name)
    var names = List[String]()
    for name in listdir(folder):
        names.append(name)
    var ordered = _sorted(names)
    for index in range(len(ordered)):
        var name = ordered[index]
        var low = _lower(name)
        if (
            low.startswith("bp_")
            and low.endswith(".uasset")
            and not _wheel(low)
        ):
            return _join(folder, name)
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
    var path = _join_all(content, _split(rel))
    if Path(path).exists():
        return path
    var folder = _dirname(path)
    if not Path(folder).is_dir():
        return String("")
    var stem = _basename(game_path) + "_"
    var found = List[String]()
    for name in listdir(folder):
        if (
            name.startswith(stem)
            and name.endswith(".uasset")
            and not _excluded(name)
        ):
            found.append(name)
    if len(found) == 1:
        return _join(folder, found[0])
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
    var parts = _split(slash)
    var stem = parts[len(parts) - 1]
    if stem.endswith(".uasset"):
        var end = stem.byte_length() - 7
        var trimmed = String(stem[byte=0:end])
        stem = trimmed
    var folder = raw
    for index in range(len(parts) - 1):
        folder = _join(folder, parts[index])
    return _join(folder, stem + ".gltf")


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
        var folder = _dirname(package)
        if not _has(seen, folder):
            seen.append(folder)
            folders.append(folder)
    var ordered = _sorted(folders)
    var out = String("[")
    var first = True
    for index in range(len(ordered)):
        var files = List[String]()
        for name in listdir(ordered[index]):
            files.append(name)
        var sorted_files = _sorted(files)
        for file_index in range(len(sorted_files)):
            var file = sorted_files[file_index]
            if not file.endswith(".uasset") or _excluded(file):
                continue
            if not first:
                out += ","
            first = False
            var full = _join(ordered[index], file)
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


def _has(names: List[String], text: String) -> Bool:
    """Return whether `names` already holds `text`."""
    for index in range(len(names)):
        if names[index] == text:
            return True
    return False


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
    var low = _lower(name)
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
        full = _join(String(cwd()), path)
    var absolute = True
    var stack = List[String]()
    var parts = _split(full)
    for index in range(len(parts)):
        var part = parts[index]
        if part.byte_length() == 0 or part == ".":
            continue
        if part == "..":
            if len(stack) > 0:
                _ = stack.pop()
            continue
        stack.append(part^)
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
    var parts = _split(path)
    var out = List[String]()
    for index in range(len(parts)):
        if parts[index].byte_length() > 0:
            out.append(parts[index])
    return out^


def _join_all(base: String, parts: List[String]) -> String:
    """Join `parts` onto `base`, as `os.path.join` does."""
    var out = base
    for index in range(len(parts)):
        out = _join(out, parts[index])
    return out


def _join(base: String, part: String) -> String:
    """Join two path parts, as `os.path.join` does."""
    if part.startswith("/"):
        return part
    if part.byte_length() == 0:
        if base.endswith("/"):
            return base
        return base + "/"
    if base.byte_length() == 0 or base.endswith("/"):
        return base + part
    return base + "/" + part


def _split(text: String) -> List[String]:
    """Split `text` on `/`, keeping empty parts."""
    var out = List[String]()
    var raw = text.as_bytes()
    var start = 0
    for index in range(len(raw)):
        if raw[index] == 47:
            out.append(String(text[byte=start:index]))
            start = index + 1
    out.append(String(text[byte=start:]))
    return out^


def _dirname(path: String) -> String:
    """Return the directory of `path`."""
    var slash = path.rfind("/")
    if slash < 0:
        return String("")
    if slash == 0:
        return String("/")
    return String(path[byte=:slash])


def _basename(path: String) -> String:
    """Return the last part of `path`."""
    var slash = path.rfind("/")
    if slash < 0:
        return path
    return String(path[byte = slash + 1 :])


def _sorted(names: List[String]) -> List[String]:
    """Return `names` in code-point order."""
    var out = List[String]()
    for index in range(len(names)):
        _insert(out, names[index])
    return out^


def _insert(mut found: List[String], text: String):
    """Insert `text` in code-point order."""
    var index = 0
    while index < len(found):
        if not _before(text, found[index]):
            index += 1
            continue
        break
    found.insert(index, text)


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


def _lower(text: String) -> String:
    """Return `text` with ASCII letters folded to lower case."""
    var out = String()
    for codepoint in text.codepoints():
        var code = Int(codepoint.to_u32())
        if code >= 65 and code <= 90:
            out += chr(code + 32)
        else:
            out += chr(code)
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
