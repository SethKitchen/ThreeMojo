# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Refuse a town package that names an engine or an engine path.

    carla_town_clean OUT_DIR

A file name is refused when it contains `unreal`, a whole word `ue4` or
`ue5`, `epic games`, `umodel`, `/game/`, `/engine/`, `.uasset` or `.umap`,
in any letter case. The text of a `.gltf` or `.xodr` file is refused for
the same words. The program prints the refusal and exits 1.
"""

from std.os import listdir
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import py_repr


struct _Span(Movable):
    """A match, or none."""

    var found: Bool
    """True when a forbidden word was found."""
    var start: Int
    """The first byte of the match."""
    var end: Int
    """The byte after the match."""

    def __init__(out self, found: Bool, start: Int, end: Int):
        """Store one match."""
        self.found = found
        self.start = start
        self.end = end


def refusal(root: String) raises -> String:
    """Return the refusal for `root`, or empty text when the tree is clean.

    Args:
        root: The package directory.

    Returns:
        The same text `check_clean` raises, or `""` when nothing matches.

    Raises:
        Error: If a `.gltf` or `.xodr` file cannot be read.
    """
    if not Path(root).exists():
        return String("")
    return _walk(root)


def _walk(path: String) raises -> String:
    """Return the first refusal under `path`, in directory order."""
    var files = List[String]()
    var dirs = List[String]()
    for name in listdir(path):
        var child = String(name)
        var full = path + "/" + child
        if Path(full).is_dir():
            dirs.append(child)
        else:
            files.append(child)
    for index in range(len(files)):
        var message = _file(path, files[index])
        if message.byte_length() > 0:
            return message
    for index in range(len(dirs)):
        var message = _walk(path + "/" + dirs[index])
        if message.byte_length() > 0:
            return message
    return String("")


def _file(directory: String, name: String) raises -> String:
    """Return this file's refusal, or empty text."""
    var hit = _find(name)
    if hit.found:
        return "unclean file name: " + directory + "/" + name
    if not (name.endswith(".gltf") or name.endswith(".xodr")):
        return String("")
    var text = Path(directory + "/" + name).read_text()
    var found = _find(text)
    if not found.found:
        return String("")
    var start = found.start - 60
    if start < 0:
        start = 0
    var end = found.end + 60
    if end > text.byte_length():
        end = text.byte_length()
    var snippet = String(text[byte=start:end])
    return "unclean text in " + name + ": " + py_repr(snippet)


def _find(text: String) -> _Span:
    """Return the first forbidden word, using the regex alternative order."""
    var raw = text.as_bytes()
    for index in range(len(raw)):
        if _literal(raw, index, "unreal"):
            return _Span(True, index, index + 6)
        if _word(raw, index, "ue4"):
            return _Span(True, index, index + 3)
        if _word(raw, index, "ue5"):
            return _Span(True, index, index + 3)
        if _literal(raw, index, "epic games"):
            return _Span(True, index, index + 10)
        if _literal(raw, index, "umodel"):
            return _Span(True, index, index + 6)
        if _literal(raw, index, "/game/"):
            return _Span(True, index, index + 6)
        if _literal(raw, index, "/engine/"):
            return _Span(True, index, index + 8)
        if _literal(raw, index, ".uasset"):
            return _Span(True, index, index + 7)
        if _literal(raw, index, ".umap"):
            return _Span(True, index, index + 5)
    return _Span(False, 0, 0)


def _literal(raw: Span[UInt8, _], index: Int, needle: String) -> Bool:
    """Return whether `needle` matches at `index`, ignoring ASCII case."""
    var head = needle.as_bytes()
    if index < 0 or len(raw) - index < len(head):
        return False
    for offset in range(len(head)):
        if _lower(raw[index + offset]) != head[offset]:
            return False
    return True


def _word(raw: Span[UInt8, _], index: Int, needle: String) -> Bool:
    """Return whether `needle` matches as a whole word."""
    var head = needle.as_bytes()
    if not _literal(raw, index, needle):
        return False
    if index > 0 and _word_byte(raw[index - 1]):
        return False
    var after = index + len(head)
    if after < len(raw) and _word_byte(raw[after]):
        return False
    return True


def _word_byte(byte: UInt8) -> Bool:
    """Return whether a byte is a Python word character for these names."""
    return (
        (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
        or byte >= 128
    )


def _lower(byte: UInt8) -> UInt8:
    """Return `byte` folded to ASCII lowercase."""
    if byte >= 65 and byte <= 90:
        return byte + 32
    return byte


def main() raises:
    """Refuse the package directory named on the command line."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_clean OUT_DIR", file=stderr)
        exit(2)
    try:
        var message = refusal(arguments[1])
        if message.byte_length() > 0:
            print(message, file=stderr)
            exit(1)
    except error:
        print("carla_town_clean:", error, file=stderr)
        exit(1)
