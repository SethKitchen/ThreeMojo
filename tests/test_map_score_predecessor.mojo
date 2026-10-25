# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live Map file restores the deviation, station, and score endpoints."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._map_score_predecessor import (
    restored_deviation_map,
    score_endpoint,
    station_endpoint,
)
from tests._python_tokens import token_sha256
from tools._sha256 import sha256_hex


comptime _MODULE = "extensions/carla/map.mojo"
"""The live Map module."""
comptime _LIVE_TOKEN = (
    "6531e0d35cf724f88b0c17c310996830b079056ff173b146504de7850b92dfe1"
)
"""The token digest of the live Map module."""
comptime _DEVIATION_SHA256 = (
    "0e2d282fcd6c70217e7413b7febe40619af070f7adbeaefa3fd56d95562c404b"
)
"""The file digest of the deviation endpoint."""
comptime _DEVIATION_TOKEN = (
    "8e900de7c4c82cba9ced3e09fa2360e39d1474f0a715d2bebf1ebc1603bd9977"
)
"""The token digest of the deviation endpoint."""
comptime _STATION_SHA256 = (
    "96611c1a85a89720cf739404924005aad4408e6868e1058f724675a6ad58630e"
)
"""The file digest of the station endpoint."""
comptime _STATION_TOKEN = (
    "2d93f5be33becf4f2e6476a88b8e222119a408a3fea13684b5161347395e5cfd"
)
"""The token digest of the station endpoint."""
comptime _SCORE_SHA256 = (
    "70ec94630e2530e9389fdb6388ff4c139bb268f5549f1a9f06602b6dfebecb94"
)
"""The file digest of the score endpoint."""
comptime _SCORE_TOKEN = (
    "56e9801cd0b87c07b67ff96286cac37ef621cee7c2967fb16bd979c1f6981b06"
)
"""The token digest of the score endpoint."""


def _saw(message: String, caught: String) raises -> Bool:
    """Return true when `caught` contains `message`.

    Args:
        message: The required refusal text.
        caught: The caught error text.

    Returns:
        True when the refusal is the required one.

    Raises:
        Error: The caught text is a different refusal.
    """
    if caught.find(message) < 0:
        raise Error(caught)
    return True


def test_live_map_restores_the_score_endpoint() raises:
    """Line edits and ten spans restore the deviation, station, and score endpoints.
    """
    var deviation = restored_deviation_map()
    assert_equal(sha256_hex(deviation.as_bytes()), _DEVIATION_SHA256)
    assert_equal(token_sha256(deviation), _DEVIATION_TOKEN)
    assert_equal(token_sha256(Path(_MODULE).read_text()), _LIVE_TOKEN)
    var station = station_endpoint(deviation)
    assert_equal(sha256_hex(station.as_bytes()), _STATION_SHA256)
    assert_equal(token_sha256(station), _STATION_TOKEN)
    var score = score_endpoint(station)
    assert_equal(sha256_hex(score.as_bytes()), _SCORE_SHA256)
    assert_equal(token_sha256(score), _SCORE_TOKEN)


def test_a_changed_map_endpoint_is_refused() raises:
    """A changed deviation or station endpoint is refused."""
    var deviation = restored_deviation_map()
    var changed = deviation + "\nvar unreviewed = 1\n"
    assert_true(sha256_hex(changed.as_bytes()) != _DEVIATION_SHA256)
    assert_true(token_sha256(changed) != _DEVIATION_TOKEN)
    var refused = False
    try:
        _ = station_endpoint(changed)
    except error:
        refused = _saw(
            "unknown complete deviation endpoint",
            String(error),
        )
    assert_true(refused)
    var station = station_endpoint(deviation)
    changed = station + "\nvar unreviewed = 1\n"
    assert_true(token_sha256(changed) != _STATION_TOKEN)
    refused = False
    try:
        _ = score_endpoint(changed)
    except error:
        refused = _saw("unknown complete station endpoint", String(error))
    assert_true(refused)
    var score = score_endpoint(station)
    assert_true(sha256_hex((score + "\n").as_bytes()) != _SCORE_SHA256)


def main() raises:
    """Run the Map score predecessor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
