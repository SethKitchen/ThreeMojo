# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Index material files by their stem.

    carla_file_index ROOT SUFFIX

The program prints a JSON object. Each key is a file name without
`SUFFIX`. The value is that file's path. The first file of a stem is
kept. A missing root prints `{}`.
"""

from std.os import listdir
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tree import JsonTree


def index_text(root: String, suffix: String) raises -> String:
    """Return the stem index of `root` as JSON.

    Args:
        root: The directory to walk. A missing directory is an empty index.
        suffix: The file-name ending to keep, such as `.mat`.

    Returns:
        A JSON object. Keys are insertion order, the first file of each stem.

    Raises:
        Error: If a directory in the walk cannot be read.
    """
    var tree = JsonTree()
    var obj = tree.object()
    if Path(root).is_dir():
        _walk(tree, obj, root, suffix)
    return tree.dumps(obj, False)


def _walk(mut tree: JsonTree, obj: Int, path: String, suffix: String) raises:
    """Add files under `path`, then walk its subdirectories."""
    var files = List[String]()
    var dirs = List[String]()
    for name in listdir(path):
        var child = String(name)
        var full = _join(path, child)
        if Path(full).is_dir():
            dirs.append(child)
        else:
            files.append(child)
    for index in range(len(files)):
        var name = files[index]
        if not name.endswith(suffix):
            continue
        var stem = String(
            name[byte = : name.byte_length() - suffix.byte_length()]
        )
        if tree.has(obj, stem):
            continue
        tree.set(obj, stem, tree.string(_join(path, name)))
    for index in range(len(dirs)):
        _walk(tree, obj, _join(path, dirs[index]), suffix)


def _join(directory: String, name: String) -> String:
    """Join a directory and a file name."""
    if directory.byte_length() == 0 or directory.endswith("/"):
        return directory + name
    return directory + "/" + name


def main() raises:
    """Print the index for the directory and suffix on the command line."""
    var arguments = argv()
    if len(arguments) != 3:
        print("usage: carla_file_index ROOT SUFFIX", file=stderr)
        exit(2)
    try:
        print(index_text(arguments[1], arguments[2]))
    except error:
        print("carla_file_index:", error, file=stderr)
        exit(1)
