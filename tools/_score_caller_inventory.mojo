# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live score caller inventory.

The score helper name appears twice, only in the Map module. The station
helper name appears three times, only in the Map module. A new executable
name is refused.
"""

from std.os import listdir
from std.os.path import isdir, islink
from std.pathlib import Path

from tests._python_tokens import _tokenize


comptime _NAME = 1
comptime _MAP = "extensions/carla/map.mojo"
comptime _SCORE = "_winner_seed_update_score"
comptime _STATION = "_chord_station_delta"


def _fail(message: String) raises:
    """Raise a score-inventory error.

    Args:
        message: The failure text.

    Raises:
        Error: The caller inventory changed.
    """
    raise Error(message)


def _skipped_top(name: String) -> Bool:
    """Return whether a top-level name is outside production.

    Args:
        name: The directory or file name.

    Returns:
        True for a non-production tree.
    """
    if name == "tests" or name == "examples" or name == "bench":
        return True
    if name == "tools" or name == "docs" or name == "assets":
        return True
    if name == "out" or name == "coverage" or name == "cache":
        return True
    return name == "build" or name == "node_modules"


def _collect(root: String, relative: String, mut paths: List[String]) raises:
    """Append production `.mojo` paths.

    Args:
        root: The repository root.
        relative: The directory to read, relative to `root`.
        paths: The collected paths, appended by this call.

    Raises:
        Error: A directory cannot be read.
    """
    var full = root if relative == "" else root + "/" + relative
    var names = listdir(full)
    for name in names:
        if name.startswith("."):
            continue
        if relative == "" and _skipped_top(name):
            continue
        var child = full + "/" + name
        var path = name if relative == "" else relative + "/" + name
        if isdir(child):
            if not islink(child):
                _collect(root, path, paths)
        elif name.endswith(".mojo"):
            paths.append(path)


def _names(source: String, needle: String) raises -> Int:
    """Return the number of executable uses of `needle`.

    Args:
        source: One module.
        needle: The helper name.

    Returns:
        The number of NAME tokens equal to `needle`.

    Raises:
        Error: The source cannot be tokenized.
    """
    if source.find(needle) < 0:
        return 0
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var count = 0
    var index = 0
    while index < len(kinds):
        if kinds[index] == _NAME and texts[index] == needle:
            count += 1
        index += 1
    return count


def score_caller_inventory(root: String) raises:
    """Require the live score and station caller counts.

    Args:
        root: The repository root.

    Raises:
        Error: A helper name appears in another module or with another count.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var paths = List[String]()
    _collect(base, "", paths)
    var score_files = 0
    var station_files = 0
    var index = 0
    while index < len(paths):
        var path = paths[index]
        var text = Path(base + "/" + path).read_text()
        var score = _names(text, _SCORE)
        var station = _names(text, _STATION)
        if score != 0:
            if path != _MAP or score != 2:
                _fail("score helper production caller inventory changed")
            score_files += 1
        if station != 0:
            if path != _MAP or station != 3:
                _fail("station helper production caller inventory changed")
            station_files += 1
        index += 1
    if score_files != 1:
        _fail("score helper production caller inventory changed")
    if station_files != 1:
        _fail("station helper production caller inventory changed")
