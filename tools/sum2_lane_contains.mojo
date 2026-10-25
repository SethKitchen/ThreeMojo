# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live lane-certificate caller.

Three width calls keep the SI helper. One call keeps the trailing comma.
The other tokens match the pinned caller.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256
from tools._python_json import PY_STR, PyJson
from tools.sum2_guard_callers import _function_text


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _LANE = "extensions/carla/lane_refinement.mojo"
comptime _NAME = "_lane_certificate_contains"
comptime _SI = "_lane_width_si("
comptime _BARE = "lane_width("
comptime _COMMA = "road._lane_width_si(section, lane, certificate.s),\n    )"
comptime _PLAIN = "road.lane_width(section, lane, certificate.s)\n    )"
comptime _MESSAGE = (
    "Sum2 complete guarded caller changed: "
    + "lane_refinement:_lane_certificate_contains"
)


def _fail(message: String) raises:
    """Raise a lane-contains error.

    Args:
        message: The failure text.

    Raises:
        Error: The live lane-certificate caller changed.
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


def sum2_lane_contains(root: String) raises:
    """Require the live lane-certificate caller.

    Args:
        root: The repository root.

    Raises:
        Error: A width call, the trailing comma, or the body changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    var callers = doc.at(doc.root, "callers")
    var record = doc.at(callers, "lane_refinement")
    var functions = doc.at(record, "functions")
    var pinned = doc.at(functions, _NAME)
    if doc.kind(pinned) != PY_STR:
        _fail(_MESSAGE)
    var live = _function_text(Path(base + "/" + _LANE).read_text(), _NAME)
    if _count(live, _SI) != 3:
        _fail(_MESSAGE)
    if _count(live, _COMMA) != 1:
        _fail(_MESSAGE)
    var restored = live.replace(_COMMA, _PLAIN)
    restored = restored.replace(_SI, _BARE)
    if token_sha256(restored) != token_sha256(doc.text(pinned)):
        _fail(_MESSAGE)
