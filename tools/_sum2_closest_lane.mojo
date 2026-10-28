# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live closest-lane certificate.

The method stays on Map. The walk keeps the candidate deviation skip.
The other tokens match the pinned caller.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256
from tools._python_json import PY_STR, PyJson
from tools._sum2_guard_callers import _function_text


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _MAP = "extensions/carla/map.mojo"
comptime _NAME = "_closest_lane_certificate_with_work"
comptime _DEF = "def _closest_lane_certificate_with_work("
comptime _LIVE = (
    "var key = _segment_distance2(\n"
    + "                segment.start, segment.end, location\n"
    + "            )\n"
    + "            var lower = _indexed_curve_lower(key,"
    " self._curve_deviation)\n"
    + "            if lower > best_radius:\n"
    + "                break\n"
    + "            # The index orders keys only, so the walk keeps the global\n"
    + "            # stop. This candidate's own deviation can still exclude"
    " it.\n"
    + "            if _indexed_curve_lower(key, segment.deviation) >"
    " best_radius:\n"
    + "                continue\n"
    + "            "
)
comptime _PIN = (
    "var lower = _indexed_curve_lower(\n"
    + "                _segment_distance2(segment.start, segment.end,"
    " location),\n"
    + "                self._curve_deviation,\n"
    + "            )\n"
    + "            if lower > best_radius:\n"
    + "                break\n"
    + "            "
)
comptime _BODY = (
    "Sum2 complete guarded caller changed: "
    + "map:_closest_lane_certificate_with_work"
)
comptime _OWNER = (
    "guard caller owner/scope changed: _closest_lane_certificate_with_work"
)


def _fail(message: String) raises:
    """Raise a closest-lane error.

    Args:
        message: The failure text.

    Raises:
        Error: The live closest-lane certificate changed.
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


def _struct_at(source: String, at: Int) -> String:
    """Return the struct name at `at`.

    Args:
        source: The module.
        at: The index of `struct `.

    Returns:
        The struct name.
    """
    var rest = String(source[byte = at + 7 :])
    var raw = rest.as_bytes()
    var end = 0
    while end < len(raw):
        var byte = raw[end]
        if byte == 40 or byte == 32 or byte == 58 or byte == 10:
            break
        end += 1
    return String(rest[byte=0:end])


def _require_map_method(source: String) raises:
    """Require one closest-lane method on `Map`.

    Args:
        source: The map module.

    Raises:
        Error: The method moved or is repeated.
    """
    if _count(source, _DEF) != 1:
        _fail(_OWNER)
    var at = source.find(_DEF)
    var line = at
    while line > 0 and source.as_bytes()[line - 1] != 10:
        line -= 1
    if line == at:
        _fail(_OWNER)
    var owner = String("")
    var cursor = 0
    while True:
        var hit = source.find("struct ", cursor)
        if hit < 0 or hit > at:
            break
        var top = hit == 0 or source.as_bytes()[hit - 1] == 10
        if top:
            owner = _struct_at(source, hit)
        cursor = hit + 7
    if owner != "Map":
        _fail(_OWNER)


def sum2_closest_lane(root: String) raises:
    """Require the live closest-lane certificate.

    Args:
        root: The repository root.

    Raises:
        Error: The owner, the deviation skip, or the body changed.
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
    var live = _function_text(source, _NAME)
    if _count(live, _LIVE) != 1:
        _fail(_BODY)
    var restored = live.replace(_LIVE, _PIN)
    if token_sha256(restored) != token_sha256(doc.text(pinned)):
        _fail(_BODY)
