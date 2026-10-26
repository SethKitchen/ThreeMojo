# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed count source.

The historical Map and the count endpoint stay the admitted sources. The
count endpoint reverses to the historical Map. Each admitted source keeps
its token digest. A third Map variant is refused.
"""

from std.pathlib import Path

from tests._map_score_predecessor import (
    restored_deviation,
    score_endpoint,
    station_endpoint,
)
from tests._python_tokens import token_sha256
from tools._sha256 import sha256_hex
from tools.count_predecessor import count_predecessor, count_predecessor_source
from tools.frontier_predecessor import frontier_predecessor_source
from tools.optional_predecessor import optional_predecessor_source
from tools.score_predecessor import score_predecessor_source
from tools.support_predecessor import support_predecessor_source


comptime _MAP = "extensions/carla/map.mojo"
comptime _COUNT_SHA = (
    "9e29cdd57fc37ffa9dc9c09ed9b263ddb7ced5781f938ff13d7fd9b2c6c997a5"
)
comptime _COUNT_TOKEN = (
    "ef1e317a812dec93adc1e47857825cfc747eae7117dd3f9664b7e4dda646b938"
)
comptime _HISTORICAL_SHA = (
    "52dd32213d64275be94ba714bc9b6a57c28f5ba1303525ef1a1aac20b4743c07"
)
comptime _HISTORICAL_TOKEN = (
    "0524759d2516ef9b269c2286cd0bbc01ed8b462718ac33ac276db510739de0c0"
)
comptime _UNKNOWN = (
    "reviewed seed-count successor: unknown complete Map variant"
)
comptime _TOKENS = "reviewed seed-count successor: actual Map tokens changed"


def _fail(message: String) raises:
    """Raise a count-source error.

    Args:
        message: The failure text.

    Raises:
        Error: The count source check failed.
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


def count_source(text: String) raises -> String:
    """Admit the historical Map or reverse the count endpoint to it.

    Args:
        text: One reviewed Map source.

    Returns:
        The historical Map.

    Raises:
        Error: The source is a third variant or its token digest changed.
    """
    var digest = sha256_hex(text.as_bytes())
    var token = token_sha256(text)
    if digest == _HISTORICAL_SHA:
        _require(token, _HISTORICAL_TOKEN, _TOKENS)
        return text
    if digest == _COUNT_SHA:
        _require(token, _COUNT_TOKEN, _TOKENS)
        return count_predecessor_source(text)
    _fail(_UNKNOWN)
    return text


def count_source_check(root: String) raises:
    """Require the live count endpoint and its historical Map.

    Args:
        root: The repository root.

    Raises:
        Error: The live Map, the count endpoint, or the historical Map changed.
    """
    count_predecessor(root)
    var live = Path(_root(root) + "/" + _MAP).read_text()
    var score = score_endpoint(station_endpoint(restored_deviation(live)))
    var frontier = score_predecessor_source(score)
    var support = frontier_predecessor_source(frontier)
    var optional = support_predecessor_source(support)
    var count = optional_predecessor_source(optional)
    var historical = count_source(count)
    _ = count_source(historical)


def main() raises:
    """Check the count source of this repository.

    Raises:
        Error: The live Map or the historical Map changed.
    """
    count_source_check(".")
