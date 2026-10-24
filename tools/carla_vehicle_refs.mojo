# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""List static packages named by a vehicle blueprint.

    carla_vehicle_refs FILE

Prints the sorted `/Game/Carla/Static/...` paths in `FILE`, once each.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tree import JsonTree


def reference_text(path: String) raises -> String:
    """Return the static packages named in a blueprint, as JSON.

    Args:
        path: The blueprint file.

    Returns:
        A sorted JSON array of `/Game/Carla/Static/...` paths. Each path
        appears once.

    Raises:
        Error: If the file cannot be read.
    """
    var found = List[String]()
    _collect(found, Path(path).read_bytes())
    var tree = JsonTree()
    var array = tree.array()
    for index in range(len(found)):
        tree.append(array, tree.string(found[index]))
    return tree.dumps(array, False)


def _collect(mut found: List[String], data: List[UInt8]):
    """Add each static package path in sorted order."""
    var prefix = "/Game/Carla/Static/".as_bytes()
    var index = 0
    while index < len(data):
        if _at(data, index, prefix):
            var end = index + len(prefix)
            while end < len(data) and _path_byte(data[end]):
                end += 1
            if end > index + len(prefix):
                var text = String()
                for offset in range(index, end):
                    text += chr(Int(data[offset]))
                _add(found, text^)
                index = end
                continue
        index += 1


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


def _at(data: List[UInt8], index: Int, prefix: Span[UInt8, _]) -> Bool:
    """Return whether `prefix` occurs at `index`."""
    if len(data) - index < len(prefix):
        return False
    for offset in range(len(prefix)):
        if data[index + offset] != prefix[offset]:
            return False
    return True


def _path_byte(byte: UInt8) -> Bool:
    """Return whether a byte can continue a static package path."""
    return (
        (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
        or byte == 47
        or byte == 45
    )


def main() raises:
    """Print the static packages named in the file on the command line."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_vehicle_refs FILE", file=stderr)
        exit(2)
    try:
        print(reference_text(arguments[1]))
    except error:
        print("carla_vehicle_refs:", error, file=stderr)
        exit(1)
