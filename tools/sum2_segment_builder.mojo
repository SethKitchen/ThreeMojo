# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live segment builder.

The builder stays a Map method. The waypoint and the section length keep
the SI helpers. The other tokens match the pinned caller.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256
from tools._python_json import PY_STR, PyJson


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _MAP = "extensions/carla/map.mojo"
comptime _NAME = "_create_segments"
comptime _LIVE_POINT = "Waypoint._from_si("
comptime _PIN_POINT = "Waypoint("
comptime _LIVE_LENGTH = "self.roads[at[0]]._section_length_si("
comptime _PIN_LENGTH = "self.roads[at[0]].section_length("
comptime _BODY = "Sum2 complete guarded caller changed: map:_create_segments"
comptime _OWNER = "guard caller owner/scope changed: _create_segments"


def _fail(message: String) raises:
    """Raise a segment-builder error.

    Args:
        message: The failure text.

    Raises:
        Error: The live segment builder changed.
    """
    raise Error(message)


def _count(text: String, needle: String) -> Int:
    """Return how many times `needle` occurs in `text`.

    Args:
        text: The source.
        needle: The exact byte sequence.

    Returns:
        The number of non-overlapping matches.
    """
    var count = 0
    var offset = 0
    var size = text.byte_length()
    var step = needle.byte_length()
    while offset < size:
        var rest = String(text[byte=offset:])
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        offset += at + step
    return count


def _lead(line: String) -> Int:
    """Return the number of leading spaces.

    Args:
        line: One source line.

    Returns:
        The space count before the first other byte.
    """
    var raw = line.as_bytes()
    var count = 0
    while count < len(raw) and raw[count] == 32:
        count += 1
    return count


def _struct_name(line: String) -> String:
    """Return the name in a top-level struct header.

    Args:
        line: A line that starts with `struct `.

    Returns:
        The struct name.
    """
    var rest = String(line[byte=7:])
    var raw = rest.as_bytes()
    var end = 0
    while end < len(raw):
        var byte = raw[end]
        if byte == 40 or byte == 32 or byte == 58:
            break
        end += 1
    return String(rest[byte=0:end])


def _is_create(line: String) -> Bool:
    """Return whether `line` declares `_create_segments`.

    Args:
        line: One source line.

    Returns:
        True for that declaration.
    """
    var body = String(line[byte = _lead(line) :])
    var needle = "def _create_segments"
    if body.byte_length() <= needle.byte_length():
        return False
    if String(body[byte = 0 : needle.byte_length()]) != needle:
        return False
    var mark = body.as_bytes()[needle.byte_length()]
    return mark == 40 or mark == 91


def _blank(line: String) -> Bool:
    """Return whether `line` has no code.

    Args:
        line: One source line.

    Returns:
        True when the line is empty or spaces.
    """
    var raw = line.as_bytes()
    var index = 0
    while index < len(raw):
        var byte = raw[index]
        if byte != 32 and byte != 9 and byte != 10 and byte != 13:
            return False
        index += 1
    return True


def _closer(line: String) -> Bool:
    """Return whether `line` continues a signature.

    Args:
        line: One source line.

    Returns:
        True when the first code byte closes a bracket.
    """
    var raw = line.as_bytes()
    var index = 0
    while index < len(raw) and raw[index] == 32:
        index += 1
    if index >= len(raw):
        return False
    var mark = raw[index]
    return mark == 41 or mark == 93 or mark == 125


def _lines(text: String) -> List[String]:
    """Split `text` into lines, keeping each newline.

    Args:
        text: The module source.

    Returns:
        The lines.
    """
    var rows = List[String]()
    var rest = text
    while rest.byte_length() > 0:
        var nl = rest.find("\n")
        if nl < 0:
            rows.append(rest)
            return rows^
        rows.append(String(rest[byte = 0 : nl + 1]))
        var tail = String(rest[byte = nl + 1 :])
        rest = tail
    return rows^


def _method_text(source: String) raises -> String:
    """Return `_create_segments` with its original indent.

    Args:
        source: The map module.

    Returns:
        The method text.

    Raises:
        Error: The method is missing or repeated.
    """
    var rows = _lines(source)
    var found = -1
    var indent = 0
    var index = 0
    while index < len(rows):
        if _is_create(rows[index]):
            if found >= 0:
                _fail(_OWNER)
            found = index
            indent = _lead(rows[index])
        index += 1
    if found < 0:
        _fail(_OWNER)
    var end = found + 1
    while end < len(rows):
        var line = rows[end]
        if _blank(line) or _closer(line) or _lead(line) > indent:
            end += 1
        else:
            break
    var chunk = String("")
    index = found
    while index < end:
        chunk += rows[index]
        index += 1
    return chunk


def _require_map_method(source: String) raises:
    """Require one `_create_segments` method on `Map`.

    Args:
        source: The map module.

    Raises:
        Error: The method moved or is repeated.
    """
    var rest = source
    var owner = String("")
    var found = 0
    while rest.byte_length() > 0:
        var nl = rest.find("\n")
        var line = rest
        if nl >= 0:
            line = String(rest[byte=0:nl])
            var tail = String(rest[byte = nl + 1 :])
            rest = tail
        else:
            rest = ""
        if line.startswith("struct "):
            owner = _struct_name(line)
        elif _is_create(line):
            found += 1
            if _lead(line) == 0 or owner != "Map":
                _fail(_OWNER)
    if found != 1:
        _fail(_OWNER)


def sum2_segment_builder(root: String) raises:
    """Require the live segment builder.

    Args:
        root: The repository root.

    Raises:
        Error: The owner, an SI helper, or the body changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    var callers = doc.at(doc.root, "callers")
    var record = doc.at(callers, "map")
    var functions = doc.at(record, "functions")
    var pinned = doc.at(functions, _NAME)
    if doc.kind(pinned) != PY_STR:
        _fail(_BODY)
    var source = Path(base + "/" + _MAP).read_text()
    _require_map_method(source)
    var live = _method_text(source)
    if _count(live, _LIVE_POINT) != 1:
        _fail(_BODY)
    if _count(live, _LIVE_LENGTH) != 1:
        _fail(_BODY)
    var restored = live.replace(_LIVE_POINT, _PIN_POINT)
    restored = restored.replace(_LIVE_LENGTH, _PIN_LENGTH)
    if token_sha256(restored) != token_sha256(doc.text(pinned)):
        _fail(_BODY)
