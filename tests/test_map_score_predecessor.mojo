# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The live Map file restores the deviation, station, and score endpoints."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._map_score_predecessor import (
    count_endpoint,
    frontier_endpoint,
    historical_map,
    optional_endpoint,
    restored_deviation_map,
    score_endpoint,
    station_endpoint,
    support_endpoint,
)
from tests._python_tokens import token_sha256
from tools._python_json import PY_INT, PyJson
from tools._sha256 import sha256_hex


comptime _MODULE = "extensions/carla/map.mojo"
"""The live Map module."""
comptime _LIVE_TOKEN = (
    "482b296f13d4f26b242b1700b1ae416e6248ca45b7b599b1640c0a7c172dfe27"
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
comptime _FRONTIER_SHA256 = (
    "37dcfb47476001ba8633a2c9dbb78b2d5f83bc069a0c4551d32ca6fdbb4c60bf"
)
"""The file digest of the frontier endpoint."""
comptime _FRONTIER_TOKEN = (
    "214a759d7cb2f804b214bf7324e621d36c83be40af1ecb497550609f6b6bc063"
)
"""The token digest of the frontier endpoint."""
comptime _SUPPORT_SHA256 = (
    "b9acf04cb54a84b89928739ea9c4e1098843149b6e926cf043b3333a1cdff518"
)
"""The file digest of the support endpoint."""
comptime _SUPPORT_TOKEN = (
    "57b5ab51af0a83edabbfa783a9857c8f88f435244f0f171649e4290da69c58d3"
)
"""The token digest of the support endpoint."""
comptime _OPTIONAL_SHA256 = (
    "e4498a5180821de4a1611cbe3c0751bda36d2e80b84c3c53caac2ca1ca0a367c"
)
"""The file digest of the optional-guard endpoint."""
comptime _OPTIONAL_TOKEN = (
    "7cd2f4af3f6ad9f12f610a5c0dfcbf9fc781c46f9bcf39c2755bf3867d251685"
)
"""The token digest of the optional-guard endpoint."""
comptime _COUNT_SHA256 = (
    "9e29cdd57fc37ffa9dc9c09ed9b263ddb7ced5781f938ff13d7fd9b2c6c997a5"
)
"""The file digest of the count successor."""
comptime _COUNT_TOKEN = (
    "ef1e317a812dec93adc1e47857825cfc747eae7117dd3f9664b7e4dda646b938"
)
"""The token digest of the count successor."""
comptime _HISTORICAL_SHA256 = (
    "52dd32213d64275be94ba714bc9b6a57c28f5ba1303525ef1a1aac20b4743c07"
)
"""The file digest of the historical Map."""
comptime _HISTORICAL_TOKEN = (
    "0524759d2516ef9b269c2286cd0bbc01ed8b462718ac33ac276db510739de0c0"
)
"""The token digest of the historical Map."""
comptime _RECORD = "tools/carla_lane_oracle/seed-count-successor.json"
"""The reviewed seed-count record."""
comptime _RECORD_SHA256 = (
    "fe8f0b4bba9ddc037113340e06f223d1ee4ed0b8ec4d67752d4e39ea946be271"
)
"""The SHA-256 of that record."""


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


def test_score_endpoint_restores_the_historical_map() raises:
    """The score endpoint restores the frontier, support, count, and historical Map.
    """
    var raw = Path(_RECORD).read_bytes()
    if sha256_hex(raw) != _RECORD_SHA256:
        raise Error(
            "reviewed seed-count successor: immutable successor record changed"
        )
    var doc = PyJson.parse(Path(_RECORD).read_text())
    if (
        doc.kind(doc.at(doc.root, "schema")) != PY_INT
        or doc.text(doc.at(doc.root, "schema")) != "1"
    ):
        raise Error("reviewed seed-count successor: wrong successor scope")
    if doc.text(doc.at(doc.root, "path")) != _MODULE:
        raise Error("reviewed seed-count successor: wrong successor scope")
    var edits = doc.at(doc.root, "edits")
    assert_equal(doc.length(edits), 3)
    assert_equal(
        doc.text(doc.at(doc.item(edits, 0), "name")), "center_count_refusal"
    )
    assert_equal(
        doc.text(doc.at(doc.item(edits, 1), "name")), "retry_count_refusal"
    )
    assert_equal(
        doc.text(doc.at(doc.item(edits, 2), "name")), "proposal_count_refusal"
    )
    var score = score_endpoint(station_endpoint(restored_deviation_map()))
    var frontier = frontier_endpoint(score)
    assert_equal(sha256_hex(frontier.as_bytes()), _FRONTIER_SHA256)
    assert_equal(token_sha256(frontier), _FRONTIER_TOKEN)
    var support = support_endpoint(frontier)
    assert_equal(sha256_hex(support.as_bytes()), _SUPPORT_SHA256)
    assert_equal(token_sha256(support), _SUPPORT_TOKEN)
    var optional = optional_endpoint(support)
    assert_equal(sha256_hex(optional.as_bytes()), _OPTIONAL_SHA256)
    assert_equal(token_sha256(optional), _OPTIONAL_TOKEN)
    var count = count_endpoint(optional)
    assert_equal(sha256_hex(count.as_bytes()), _COUNT_SHA256)
    assert_equal(token_sha256(count), _COUNT_TOKEN)
    var historical = historical_map(count)
    assert_equal(sha256_hex(historical.as_bytes()), _HISTORICAL_SHA256)
    assert_equal(token_sha256(historical), _HISTORICAL_TOKEN)
    var changed = score + "\nvar unreviewed = 1\n"
    var refused = False
    try:
        _ = frontier_endpoint(changed)
    except error:
        refused = _saw("unknown score-helper successor", String(error))
    assert_true(refused)
    assert_true(
        sha256_hex((historical + "\n").as_bytes()) != _HISTORICAL_SHA256
    )


def main() raises:
    """Run the Map score predecessor tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
