# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live lane-geometry inventory.

Four directed-point calls keep the SI constructor. Restoring those calls
matches the pinned use digest. A bare constructor or a changed use is refused.
"""

from std.pathlib import Path

from tools._python_json import PY_STR, PyJson
from tools.sum2_guard_inventory import _digest


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _LANE = "extensions/carla/lane_geometry.mojo"
comptime _LIVE = "DirectedPoint._from_si("
comptime _PIN = "DirectedPoint("
comptime _MESSAGE = (
    "global protected-helper use/import inventory changed: lane_geometry"
)


def _fail(message: String) raises:
    """Raise a lane-geometry inventory error.

    Args:
        message: The failure text.

    Raises:
        Error: The live lane-geometry inventory changed.
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


def sum2_geometry_inventory(root: String) raises:
    """Require the live lane-geometry inventory.

    Args:
        root: The repository root.

    Raises:
        Error: A directed-point constructor or the use digest changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    var inventory = doc.at(doc.root, "protected_inventory")
    var pinned = doc.at(inventory, _LANE)
    if doc.kind(pinned) != PY_STR:
        _fail(_MESSAGE)
    var source = Path(base + "/" + _LANE).read_text()
    if _count(source, _LIVE) != 4:
        _fail(_MESSAGE)
    var restored = source.replace(_LIVE, _PIN)
    if _digest(restored) != doc.text(pinned):
        _fail(_MESSAGE)
