# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live scalar spiral caller.

The function keeps the SI directed-point constructor. The other tokens
match the pinned caller.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256
from tools._python_json import PY_STR, PyJson
from tools._sum2_guard_callers import _function_text


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _LANE = "extensions/carla/lane_geometry.mojo"
comptime _NAME = "_lane_spiral"
comptime _LIVE = "DirectedPoint._from_si("
comptime _PIN = "DirectedPoint("
comptime _MESSAGE = (
    "Sum2 complete guarded caller changed: lane_geometry:_lane_spiral"
)


def _fail(message: String) raises:
    """Raise a scalar-caller error.

    Args:
        message: The failure text.

    Raises:
        Error: The live scalar spiral changed.
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


def sum2_scalar_caller(root: String) raises:
    """Require the live scalar spiral caller.

    Args:
        root: The repository root.

    Raises:
        Error: The constructor or the caller body changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    var callers = doc.at(doc.root, "callers")
    var record = doc.at(callers, "lane_geometry")
    var functions = doc.at(record, "functions")
    var pinned = doc.at(functions, _NAME)
    if doc.kind(pinned) != PY_STR:
        _fail(_MESSAGE)
    var live = _function_text(Path(base + "/" + _LANE).read_text(), _NAME)
    if _count(live, _LIVE) != 1:
        _fail(_MESSAGE)
    var restored = live.replace(_LIVE, _PIN)
    if token_sha256(restored) != token_sha256(doc.text(pinned)):
        _fail(_MESSAGE)
