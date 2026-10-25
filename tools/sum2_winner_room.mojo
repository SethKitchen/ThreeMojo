# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live winner-seed room.

The followup uses the capped cell count. The length guard and the early
term return stay absent. The other tokens match the pinned caller.
"""

from std.pathlib import Path

from tests._python_tokens import token_sha256
from tools._python_json import PY_STR, PyJson
from tools.sum2_guard_callers import _function_text


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _MAP = "extensions/carla/map.mojo"
comptime _NAME = "_winner_seed_room"
comptime _LIVE_CELLS = "target_reference <= 0\n        or target_cells < 0"
comptime _PIN_CELLS = (
    "target_reference <= 0\n"
    + "        or len(winner.cells) > 16372\n"
    + "        or target_cells < 0"
)
comptime _LIVE_FOLLOWUP = (
    "var winner_followup = min(len(winner.cells), 16373) + 12"
)
comptime _PIN_FOLLOWUP = "var winner_followup = len(winner.cells) + 12"
comptime _LIVE_TERMS = (
    "terms_left = work.policy.max_terms - work.terms\n"
    + "    terms_left -= winner_units * winner_reference"
)
comptime _PIN_TERMS = (
    "terms_left = work.policy.max_terms - work.terms\n"
    + "    if winner_reference > terms_left // winner_units:\n"
    + "        return False\n"
    + "    terms_left -= winner_units * winner_reference"
)
comptime _MESSAGE = (
    "Sum2 complete guarded caller changed: map:_winner_seed_room"
)


def _fail(message: String) raises:
    """Raise a winner-room error.

    Args:
        message: The failure text.

    Raises:
        Error: The live winner-seed room changed.
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


def sum2_winner_room(root: String) raises:
    """Require the live winner-seed room.

    Args:
        root: The repository root.

    Raises:
        Error: A room edge or the caller body changed.
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
    if _count(live, _LIVE_CELLS) != 1:
        _fail(_MESSAGE)
    if _count(live, _LIVE_FOLLOWUP) != 1:
        _fail(_MESSAGE)
    if _count(live, _LIVE_TERMS) != 1:
        _fail(_MESSAGE)
    var restored = live.replace(_LIVE_CELLS, _PIN_CELLS)
    restored = restored.replace(_LIVE_FOLLOWUP, _PIN_FOLLOWUP)
    restored = restored.replace(_LIVE_TERMS, _PIN_TERMS)
    if token_sha256(restored) != token_sha256(doc.text(pinned)):
        _fail(_MESSAGE)
