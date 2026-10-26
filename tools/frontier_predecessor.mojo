# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed frontier predecessor.

The frontier endpoint keeps its file digest and its token digest. The two
frontier edits keep their reviewed names. Reversing those edits restores
the support endpoint. A changed frontier endpoint is refused.
"""

from std.pathlib import Path

from tests._map_score_predecessor import (
    _frontier_spans,
    restored_deviation,
    score_endpoint,
    station_endpoint,
    support_endpoint,
)
from tests._python_tokens import token_sha256
from tools._sha256 import sha256_hex
from tools.score_predecessor import score_predecessor_source


comptime _MAP = "extensions/carla/map.mojo"
comptime _FRONTIER_SHA = (
    "37dcfb47476001ba8633a2c9dbb78b2d5f83bc069a0c4551d32ca6fdbb4c60bf"
)
comptime _FRONTIER_TOKEN = (
    "214a759d7cb2f804b214bf7324e621d36c83be40af1ecb497550609f6b6bc063"
)
comptime _SUPPORT_SHA = (
    "b9acf04cb54a84b89928739ea9c4e1098843149b6e926cf043b3333a1cdff518"
)
comptime _SUPPORT_TOKEN = (
    "57b5ab51af0a83edabbfa783a9857c8f88f435244f0f171649e4290da69c58d3"
)
comptime _EDIT_NAMES = (
    "bounded_winner_frontier_guard\nsaturating_winner_frontier_reservation"
)
comptime _UNKNOWN = (
    "reviewed seed-count successor: unknown frontier-reservation successor"
)
comptime _INVENTORY = (
    "reviewed seed-count successor: frontier-reservation inverse inventory"
    " changed"
)
comptime _SUPPORT = (
    "reviewed seed-count successor: frontier inverse does not reconstruct"
    " separate support endpoint"
)


def _fail(message: String) raises:
    """Raise a frontier-predecessor error.

    Args:
        message: The failure text.

    Raises:
        Error: The frontier predecessor check failed.
    """
    raise Error(message)


def _require(actual: String, expected: String, message: String) raises:
    """Refuse a value that differs from `expected`.

    Args:
        actual: The measured value.
        expected: The required value.
        message: The failure text.

    Raises:
        Error: The values differ.
    """
    if actual != expected:
        _fail(message)


def _edit_names() -> String:
    """Return the frontier edit names, one per line.

    Returns:
        The names in forward order.
    """
    var names = List[String]()
    var befores = List[String]()
    var afters = List[String]()
    _frontier_spans(names, befores, afters)
    var joined = ""
    var index = 0
    while index < len(names):
        if index > 0:
            joined += "\n"
        joined += names[index]
        index += 1
    return joined


def _root(root: String) -> String:
    """Return `root` without a trailing slash.

    Args:
        root: The repository root.

    Returns:
        The root used to join the Map path.
    """
    if root.byte_length() > 1 and root.endswith("/"):
        var end = root.byte_length() - 1
        return String(root[byte=0:end])
    return root


def frontier_predecessor_source(text: String) raises -> String:
    """Invert the two frontier edits to the support endpoint.

    Args:
        text: The frontier endpoint.

    Returns:
        The support endpoint.

    Raises:
        Error: The endpoint, an edit name, or the support bytes differ.
    """
    _require(token_sha256(text), _FRONTIER_TOKEN, _UNKNOWN)
    _require(sha256_hex(text.as_bytes()), _FRONTIER_SHA, _UNKNOWN)
    _require(_edit_names(), _EDIT_NAMES, _INVENTORY)
    var support = support_endpoint(text)
    _require(sha256_hex(support.as_bytes()), _SUPPORT_SHA, _SUPPORT)
    _require(token_sha256(support), _SUPPORT_TOKEN, _SUPPORT)
    return support


def frontier_predecessor(root: String) raises:
    """Require the live Map frontier predecessor.

    Args:
        root: The repository root.

    Raises:
        Error: The live Map, the frontier endpoint, or the support changed.
    """
    var live = Path(_root(root) + "/" + _MAP).read_text()
    var score = score_endpoint(station_endpoint(restored_deviation(live)))
    var frontier = score_predecessor_source(score)
    _ = frontier_predecessor_source(frontier)


def main() raises:
    """Check the frontier predecessor of this repository.

    Raises:
        Error: The live Map or the support endpoint changed.
    """
    frontier_predecessor(".")
