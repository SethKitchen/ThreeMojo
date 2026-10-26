# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed score predecessor.

The score endpoint keeps its file digest and its token digest. The two
score declarations keep their reviewed token digests. Reversing the two
score edits restores the frontier endpoint. A changed score endpoint is
refused.
"""

from std.pathlib import Path

from tests._map_score_predecessor import (
    _score_spans,
    frontier_endpoint,
    restored_deviation,
    score_endpoint,
    station_endpoint,
)
from tests._python_tokens import token_sha256
from tools._sha256 import sha256_hex
from tools.score_operation_graphs import score_operation_graphs


comptime _MAP = "extensions/carla/map.mojo"
comptime _SCORE_SHA = (
    "70ec94630e2530e9389fdb6388ff4c139bb268f5549f1a9f06602b6dfebecb94"
)
comptime _SCORE_TOKEN = (
    "56e9801cd0b87c07b67ff96286cac37ef621cee7c2967fb16bd979c1f6981b06"
)
comptime _FRONTIER_SHA = (
    "37dcfb47476001ba8633a2c9dbb78b2d5f83bc069a0c4551d32ca6fdbb4c60bf"
)
comptime _FRONTIER_TOKEN = (
    "214a759d7cb2f804b214bf7324e621d36c83be40af1ecb497550609f6b6bc063"
)
comptime _EDIT_NAMES = "extract_finite_winner_score\ncall_finite_winner_score"
comptime _UNKNOWN = (
    "reviewed seed-count successor: unknown score-helper successor"
)
comptime _INVENTORY = (
    "reviewed seed-count successor: score-helper inverse inventory changed"
)
comptime _FRONTIER = (
    "reviewed seed-count successor: score-helper inverse does not"
    " reconstruct frontier endpoint"
)


def _fail(message: String) raises:
    """Raise a score-predecessor error.

    Args:
        message: The failure text.

    Raises:
        Error: The score predecessor check failed.
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
    """Return the score edit names, one per line.

    Returns:
        The names in forward order.
    """
    var names = List[String]()
    var befores = List[String]()
    var afters = List[String]()
    _score_spans(names, befores, afters)
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


def score_predecessor_source(text: String) raises -> String:
    """Invert the two score edits to the frontier endpoint.

    Args:
        text: The score endpoint.

    Returns:
        The frontier endpoint.

    Raises:
        Error: The endpoint, a declaration, or the frontier bytes differ.
    """
    _require(token_sha256(text), _SCORE_TOKEN, _UNKNOWN)
    _require(sha256_hex(text.as_bytes()), _SCORE_SHA, _UNKNOWN)
    score_operation_graphs(text)
    _require(_edit_names(), _EDIT_NAMES, _INVENTORY)
    var frontier = frontier_endpoint(text)
    _require(sha256_hex(frontier.as_bytes()), _FRONTIER_SHA, _FRONTIER)
    _require(token_sha256(frontier), _FRONTIER_TOKEN, _FRONTIER)
    return frontier


def score_predecessor(root: String) raises:
    """Require the live Map score predecessor.

    Args:
        root: The repository root.

    Raises:
        Error: The live Map, the score endpoint, or the frontier changed.
    """
    var live = Path(_root(root) + "/" + _MAP).read_text()
    var score = score_endpoint(station_endpoint(restored_deviation(live)))
    _ = score_predecessor_source(score)


def main() raises:
    """Check the score predecessor of this repository.

    Raises:
        Error: The live Map or the frontier endpoint changed.
    """
    score_predecessor(".")
