# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed score-family predecessor.

The deviation, station, and score endpoints project to one frontier. Each
endpoint keeps its token digest. The score endpoint reverses through the
two score edits. A third Map variant is refused.
"""

from std.pathlib import Path

from tests._map_score_predecessor import (
    restored_deviation,
    score_endpoint,
    station_endpoint,
)
from tests._python_tokens import token_sha256
from tools._sha256 import sha256_hex
from tools.score_predecessor import score_predecessor_source


comptime _MAP = "extensions/carla/map.mojo"
comptime _DEVIATION_SHA = (
    "0e2d282fcd6c70217e7413b7febe40619af070f7adbeaefa3fd56d95562c404b"
)
comptime _DEVIATION_TOKEN = (
    "8e900de7c4c82cba9ced3e09fa2360e39d1474f0a715d2bebf1ebc1603bd9977"
)
comptime _STATION_SHA = (
    "96611c1a85a89720cf739404924005aad4408e6868e1058f724675a6ad58630e"
)
comptime _STATION_TOKEN = (
    "2d93f5be33becf4f2e6476a88b8e222119a408a3fea13684b5161347395e5cfd"
)
comptime _DEVIATION = (
    "reviewed Map deviation successor: unknown complete deviation endpoint"
)
comptime _STATION = (
    "reviewed Map station successor: unknown complete station endpoint"
)


def _fail(message: String) raises:
    """Raise a score-family error.

    Args:
        message: The failure text.

    Raises:
        Error: The score-family check failed.
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


def score_family_predecessor_source(text: String) raises -> String:
    """Project a deviation, station, or score endpoint to the frontier.

    Args:
        text: One reviewed score-family Map endpoint.

    Returns:
        The frontier endpoint.

    Raises:
        Error: The endpoint is a third variant or its token digest changed.
    """
    var current = text
    if sha256_hex(current.as_bytes()) == _DEVIATION_SHA:
        _require(token_sha256(current), _DEVIATION_TOKEN, _DEVIATION)
        current = station_endpoint(current)
    if sha256_hex(current.as_bytes()) == _STATION_SHA:
        _require(token_sha256(current), _STATION_TOKEN, _STATION)
        current = score_endpoint(current)
    return score_predecessor_source(current)


def score_family_check(root: String) raises:
    """Require the live deviation, station, and score endpoints.

    Args:
        root: The repository root.

    Raises:
        Error: The live Map or one score-family endpoint changed.
    """
    var live = Path(_root(root) + "/" + _MAP).read_text()
    var deviation = restored_deviation(live)
    var station = station_endpoint(deviation)
    var score = score_endpoint(station)
    var from_deviation = score_family_predecessor_source(deviation)
    var from_station = score_family_predecessor_source(station)
    var from_score = score_family_predecessor_source(score)
    if from_deviation != from_station or from_station != from_score:
        _fail(_DEVIATION)


def main() raises:
    """Check the score-family predecessor of this repository.

    Raises:
        Error: The live Map or the frontier endpoint changed.
    """
    score_family_check(".")
