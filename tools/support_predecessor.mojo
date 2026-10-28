# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed support predecessor.

The support endpoint keeps its file digest and its token digest. The three
support edits keep their reviewed names. Reversing those edits restores the
optional endpoint. A changed support endpoint is refused.
"""

from std.pathlib import Path

from tests._map_score_predecessor import (
    _support_spans,
    optional_endpoint,
    restored_deviation,
    score_endpoint,
    station_endpoint,
)
from tests._python_tokens import token_sha256
from tools._sha256 import sha256_hex
from tools.frontier_predecessor import frontier_predecessor_source
from tools.score_predecessor import score_predecessor_source


comptime _MAP = "extensions/carla/map.mojo"
comptime _SUPPORT_SHA = (
    "b9acf04cb54a84b89928739ea9c4e1098843149b6e926cf043b3333a1cdff518"
)
comptime _SUPPORT_TOKEN = (
    "57b5ab51af0a83edabbfa783a9857c8f88f435244f0f171649e4290da69c58d3"
)
comptime _OPTIONAL_SHA = (
    "e4498a5180821de4a1611cbe3c0751bda36d2e80b84c3c53caac2ca1ca0a367c"
)
comptime _OPTIONAL_TOKEN = (
    "7cd2f4af3f6ad9f12f610a5c0dfcbf9fc781c46f9bcf39c2755bf3867d251685"
)
comptime _EDIT_NAMES = (
    "nonnegative_stored_difference_error\n"
    + "bounded_finite_rounded_distance\n"
    + "positive_finite_minimizer_support"
)
comptime _UNKNOWN = (
    "reviewed seed-count successor: unknown support-guard successor"
)
comptime _INVENTORY = (
    "reviewed seed-count successor: support-guard inverse inventory changed"
)
comptime _OPTIONAL = (
    "reviewed seed-count successor: support-guard inverse does not"
    " reconstruct published optional source"
)


def _fail(message: String) raises:
    """Raise a support-predecessor error.

    Args:
        message: The failure text.

    Raises:
        Error: The support predecessor check failed.
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
    """Return the support edit names, one per line.

    Returns:
        The names in forward order.
    """
    var names = List[String]()
    var befores = List[String]()
    var afters = List[String]()
    _support_spans(names, befores, afters)
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


def support_predecessor_source(text: String) raises -> String:
    """Invert the three support edits to the optional endpoint.

    Args:
        text: The support endpoint.

    Returns:
        The optional endpoint.

    Raises:
        Error: The endpoint, an edit name, or the optional bytes differ.
    """
    _require(token_sha256(text), _SUPPORT_TOKEN, _UNKNOWN)
    _require(sha256_hex(text.as_bytes()), _SUPPORT_SHA, _UNKNOWN)
    _require(_edit_names(), _EDIT_NAMES, _INVENTORY)
    var optional = optional_endpoint(text)
    _require(sha256_hex(optional.as_bytes()), _OPTIONAL_SHA, _OPTIONAL)
    _require(token_sha256(optional), _OPTIONAL_TOKEN, _OPTIONAL)
    return optional


def support_predecessor(root: String) raises:
    """Require the live Map support predecessor.

    Args:
        root: The repository root.

    Raises:
        Error: The live Map, the support endpoint, or the optional changed.
    """
    var live = Path(_root(root) + "/" + _MAP).read_text()
    var score = score_endpoint(station_endpoint(restored_deviation(live)))
    var frontier = score_predecessor_source(score)
    var support = frontier_predecessor_source(frontier)
    _ = support_predecessor_source(support)


def main() raises:
    """Check the support predecessor of this repository.

    Raises:
        Error: The live Map or the optional endpoint changed.
    """
    support_predecessor(".")
