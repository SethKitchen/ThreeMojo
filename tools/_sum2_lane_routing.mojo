# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live lane-refinement routing.

The module keeps the road-info alias. The expansion block and the Variant
import stay in place. Restoring those spans matches the pinned routing.
"""

from std.pathlib import Path

from tools._python_json import PY_STR, PyJson
from tools._sha256 import sha256_hex
from tools._sum2_guard_callers import _routing


comptime _PINS = "tools/carla_lane_oracle/sum2-guard-pins.json"
comptime _LANE = "extensions/carla/lane_refinement.mojo"
comptime _ALIAS = (
    "from extensions.carla.road_info import _info_index_si as info_index\n"
)
comptime _BARE = "from extensions.carla.road_info import info_index\n"
comptime _VARIANT = "from std.utils import Variant\n"
comptime _START = "def _same_cache_key(\n"
comptime _END = "def _run_lane_search(\n"
comptime _BLOCK_SHA = (
    "0aa9e276fb4a24b536af7fa839c993a989d25421277c7ae7bbcdc335e201f9f1"
)
comptime _MESSAGE = (
    "Sum2 guard import/declaration routing changed: lane_refinement"
)


def _fail(message: String) raises:
    """Raise a lane-routing error.

    Args:
        message: The failure text.

    Raises:
        Error: The live lane-refinement routing changed.
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


def _block(source: String) raises -> String:
    """Return the expansion block that precedes the lane search.

    Args:
        source: The lane-refinement module.

    Returns:
        The source from `_same_cache_key` through the line before the search.

    Raises:
        Error: The block markers moved.
    """
    if _count(source, _START) != 1 or _count(source, _END) != 1:
        _fail(_MESSAGE)
    var start = source.find(_START)
    var tail = String(source[byte=start:])
    var rel = tail.find(_END)
    if rel < 0:
        _fail(_MESSAGE)
    return String(source[byte = start : start + rel])


def sum2_lane_routing(root: String) raises:
    """Require the live lane-refinement routing.

    Args:
        root: The repository root.

    Raises:
        Error: A reviewed span or the pinned routing changed.
    """
    var base = root
    if base.byte_length() > 1 and base.endswith("/"):
        var end = base.byte_length() - 1
        var trimmed = String(base[byte=0:end])
        base = trimmed
    var doc = PyJson.parse(Path(base + "/" + _PINS).read_text())
    var callers = doc.at(doc.root, "callers")
    var record = doc.at(callers, "lane_refinement")
    var routing = doc.at(record, "routing")
    if doc.kind(routing) != PY_STR:
        _fail(_MESSAGE)
    var source = Path(base + "/" + _LANE).read_text()
    if _count(source, _ALIAS) != 1 or _count(source, _VARIANT) != 1:
        _fail(_MESSAGE)
    var block = _block(source)
    if sha256_hex(block.as_bytes()) != _BLOCK_SHA:
        _fail(_MESSAGE)
    var restored = (
        source.replace(_ALIAS, _BARE).replace(_VARIANT, "").replace(block, "")
    )
    if _routing(restored) != doc.text(routing):
        _fail(_MESSAGE)
