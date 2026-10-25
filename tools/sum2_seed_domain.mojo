# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live seed-domain caller.

The error guard keeps the upper bound only. The rounded guard keeps the
low and high tests. The other tokens match the pinned caller.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256
from tools._python_json import PY_STR, PyJson
from tools.sum2_guard_callers import _function_text


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _MAP = "extensions/carla/map.mojo"
comptime _NAME = "_seed_reference_domain"
comptime _LIVE_ERROR = (
    "if not _seed_exact_interval(d.value) or not d.error < 1.0:"
)
comptime _PIN_ERROR = (
    "if not _seed_exact_interval(d.value) or not (\n"
    + "        0.0 <= d.error and d.error < 1.0\n"
    + "    ):"
)
comptime _LIVE_ROUNDED = (
    "if rounded.low <= 0.0 or rounded.high >= geometry.length:"
)
comptime _PIN_ROUNDED = (
    "if (\n"
    + "        not rounded.is_finite()\n"
    + "        or rounded.low <= 0.0\n"
    + "        or rounded.high >= geometry.length\n"
    + "    ):"
)
comptime _MESSAGE = (
    "Sum2 complete guarded caller changed: map:_seed_reference_domain"
)


def _fail(message: String) raises:
    """Raise a seed-domain error.

    Args:
        message: The failure text.

    Raises:
        Error: The live seed-domain caller changed.
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


def sum2_seed_domain(root: String) raises:
    """Require the live seed-domain caller.

    Args:
        root: The repository root.

    Raises:
        Error: A guard or the caller body changed.
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
        _fail(_MESSAGE)
    var live = _function_text(Path(base + "/" + _MAP).read_text(), _NAME)
    if _count(live, _LIVE_ERROR) != 1:
        _fail(_MESSAGE)
    if _count(live, _LIVE_ROUNDED) != 1:
        _fail(_MESSAGE)
    var restored = live.replace(_LIVE_ERROR, _PIN_ERROR)
    restored = restored.replace(_LIVE_ROUNDED, _PIN_ROUNDED)
    if token_sha256(restored) != token_sha256(doc.text(pinned)):
        _fail(_MESSAGE)
