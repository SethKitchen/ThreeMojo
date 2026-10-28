# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read the class UModel lists for one package.

    carla_umodel_class NAME LISTING

`LISTING` is the text of `umodel -list`. The program prints the class on
the first line whose last word is `NAME` and that has at least five
words. The class is the word before that name. No match prints an empty
line.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr


def class_text(name: String, listing: String) -> String:
    """Return the class UModel lists for `name`.

    Args:
        name: The package name, without `.uasset`.
        listing: The text of one `umodel -list` run.

    Returns:
        The class, or empty text when no line names that package.
    """
    var lines = _lines(listing)
    for index in range(len(lines)):
        var words = _words(lines[index])
        if len(words) >= 5 and words[len(words) - 1] == name:
            return words[len(words) - 2]
    return String("")


def _lines(text: String) -> List[String]:
    """Split `text` into lines, dropping a trailing carriage return."""
    var out = List[String]()
    var raw = text.as_bytes()
    var start = 0
    for index in range(len(raw)):
        if raw[index] != 10:
            continue
        var end = index
        if end > start and raw[end - 1] == 13:
            end -= 1
        out.append(String(text[byte=start:end]))
        start = index + 1
    if start < len(raw) or len(raw) == 0:
        var end = len(raw)
        if end > start and raw[end - 1] == 13:
            end -= 1
        if start < len(raw):
            out.append(String(text[byte=start:end]))
    return out^


def _words(line: String) -> List[String]:
    """Split `line` on whitespace, dropping empty words."""
    var out = List[String]()
    var raw = line.as_bytes()
    var start = -1
    for index in range(len(raw)):
        if _space(raw[index]):
            if start >= 0:
                out.append(String(line[byte=start:index]))
                start = -1
        elif start < 0:
            start = index
    if start >= 0:
        out.append(String(line[byte=start:]))
    return out^


def _space(byte: UInt8) -> Bool:
    """Return whether `byte` is ASCII whitespace."""
    return (
        byte == 9
        or byte == 10
        or byte == 11
        or byte == 12
        or byte == 13
        or byte == 32
    )


def main() raises:
    """Print the class for the listing file on the command line.

    Raises:
        Error: If the standard streams cannot be written.
    """
    var arguments = argv()
    if len(arguments) != 3:
        print("usage: carla_umodel_class NAME LISTING", file=stderr)
        exit(2)
    try:
        print(class_text(arguments[1], Path(arguments[2]).read_text()))
    except error:
        print("carla_umodel_class:", error, file=stderr)
        exit(1)
