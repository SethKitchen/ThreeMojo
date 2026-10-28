# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed optional predecessor.

The optional endpoint keeps its file digest and its token digest. The three
optional edits keep their reviewed names. Reversing those edits restores the
count endpoint. A changed optional endpoint is refused.
"""

from std.pathlib import Path

from tests._map_score_predecessor import (
    _optional_spans,
    count_endpoint,
    restored_deviation,
    score_endpoint,
    station_endpoint,
)
from tests._python_tokens import token_sha256
from tools._sha256 import sha256_hex
from tools.frontier_predecessor import frontier_predecessor_source
from tools.score_predecessor import score_predecessor_source
from tools.support_predecessor import support_predecessor_source


comptime _MAP = "extensions/carla/map.mojo"
comptime _OPTIONAL_SHA = (
    "e4498a5180821de4a1611cbe3c0751bda36d2e80b84c3c53caac2ca1ca0a367c"
)
comptime _OPTIONAL_TOKEN = (
    "7cd2f4af3f6ad9f12f610a5c0dfcbf9fc781c46f9bcf39c2755bf3867d251685"
)
comptime _COUNT_SHA = (
    "9e29cdd57fc37ffa9dc9c09ed9b263ddb7ced5781f938ff13d7fd9b2c6c997a5"
)
comptime _COUNT_TOKEN = (
    "ef1e317a812dec93adc1e47857825cfc747eae7117dd3f9664b7e4dda646b938"
)
comptime _EDIT_NAMES = (
    "winner_global_term_refusal\n"
    + "prepaid_retry_step_refusal\n"
    + "retry_midpoint_enclosure"
)
comptime _UNKNOWN = (
    "reviewed seed-count successor: unknown optional-guard successor"
)
comptime _INVENTORY = (
    "reviewed seed-count successor: optional-guard inverse inventory changed"
)
comptime _COUNT = (
    "reviewed seed-count successor: optional-guard inverse does not"
    " reconstruct prior count source"
)


def _fail(message: String) raises:
    """Raise an optional-predecessor error.

    Args:
        message: The failure text.

    Raises:
        Error: The optional predecessor check failed.
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
    """Return the optional edit names, one per line.

    Returns:
        The names in forward order.
    """
    var names = List[String]()
    var befores = List[String]()
    var afters = List[String]()
    _optional_spans(names, befores, afters)
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


def optional_predecessor_source(text: String) raises -> String:
    """Invert the three optional edits to the count endpoint.

    Args:
        text: The optional endpoint.

    Returns:
        The count endpoint.

    Raises:
        Error: The endpoint, an edit name, or the count bytes differ.
    """
    _require(token_sha256(text), _OPTIONAL_TOKEN, _UNKNOWN)
    _require(sha256_hex(text.as_bytes()), _OPTIONAL_SHA, _UNKNOWN)
    _require(_edit_names(), _EDIT_NAMES, _INVENTORY)
    var count = count_endpoint(text)
    _require(sha256_hex(count.as_bytes()), _COUNT_SHA, _COUNT)
    _require(token_sha256(count), _COUNT_TOKEN, _COUNT)
    return count


def optional_predecessor(root: String) raises:
    """Require the live Map optional predecessor.

    Args:
        root: The repository root.

    Raises:
        Error: The live Map, the optional endpoint, or the count changed.
    """
    var live = Path(_root(root) + "/" + _MAP).read_text()
    var score = score_endpoint(station_endpoint(restored_deviation(live)))
    var frontier = score_predecessor_source(score)
    var support = frontier_predecessor_source(frontier)
    var optional = support_predecessor_source(support)
    _ = optional_predecessor_source(optional)


def main() raises:
    """Check the optional predecessor of this repository.

    Raises:
        Error: The live Map or the count endpoint changed.
    """
    optional_predecessor(".")
