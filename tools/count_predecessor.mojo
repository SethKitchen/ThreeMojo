# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the reviewed count predecessor.

The count endpoint keeps its file digest and its token digest. The three
count edits keep their reviewed names. Reversing those edits restores the
historical Map. A changed count endpoint is refused.
"""

from std.pathlib import Path

from tests._map_score_predecessor import (
    _count_spans,
    historical_map,
    restored_deviation,
    score_endpoint,
    station_endpoint,
)
from tests._python_tokens import token_sha256
from tools._python_json import PY_INT, loads
from tools._sha256 import sha256_hex
from tools.frontier_predecessor import frontier_predecessor_source
from tools.optional_predecessor import optional_predecessor_source
from tools.score_predecessor import score_predecessor_source
from tools.support_predecessor import support_predecessor_source


comptime _MAP = "extensions/carla/map.mojo"
comptime _RECORD = "tools/carla_lane_oracle/seed-count-successor.json"
comptime _RECORD_SHA = (
    "fe8f0b4bba9ddc037113340e06f223d1ee4ed0b8ec4d67752d4e39ea946be271"
)
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
comptime _EDIT_NAMES = (
    "center_count_refusal\n"
    + "retry_count_refusal\n"
    + "proposal_count_refusal"
)
comptime _FIXTURE = "tests/test_carla_winner_seed_recovery.mojo"
comptime _UNKNOWN = "reviewed seed-count successor: unknown complete after Map"
comptime _RECORD_CHANGED = (
    "reviewed seed-count successor: immutable successor record changed"
)
comptime _SCOPE = "reviewed seed-count successor: wrong successor scope"
comptime _ENDPOINTS = (
    "reviewed seed-count successor: reviewed endpoints changed"
)
comptime _NAMES = (
    "reviewed seed-count successor: missing, duplicate, reordered or extra"
    " inverse edit"
)
comptime _FIXTURES = (
    "reviewed seed-count successor: count-control fixture scope changed"
)
comptime _HISTORICAL = (
    "reviewed seed-count successor: inverse does not reconstruct historical Map"
)


def _fail(message: String) raises:
    """Raise a count-predecessor error.

    Args:
        message: The failure text.

    Raises:
        Error: The count predecessor check failed.
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
    """Return the count edit names, one per line.

    Returns:
        The names in forward order.
    """
    var names = List[String]()
    var befores = List[String]()
    var afters = List[String]()
    _count_spans(names, befores, afters)
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
        The root used to join paths.
    """
    if root.byte_length() > 1 and root.endswith("/"):
        var end = root.byte_length() - 1
        return String(root[byte=0:end])
    return root


def _record(root: String) raises:
    """Require the reviewed count-successor record.

    Args:
        root: The repository root.

    Raises:
        Error: The record, its scope, or its edit names changed.
    """
    var raw = Path(_root(root) + "/" + _RECORD).read_bytes()
    _require(sha256_hex(raw), _RECORD_SHA, _RECORD_CHANGED)
    var doc = loads(raw)
    var schema = doc.at(doc.root, "schema")
    if doc.kind(schema) != PY_INT:
        _fail(_SCOPE)
    _require(doc.text(schema), "1", _SCOPE)
    _require(doc.text(doc.at(doc.root, "path")), _MAP, _SCOPE)
    _require(
        doc.text(doc.at(doc.root, "before_sha256")), _HISTORICAL_SHA, _ENDPOINTS
    )
    _require(doc.text(doc.at(doc.root, "after_sha256")), _COUNT_SHA, _ENDPOINTS)
    _require(
        doc.text(doc.at(doc.root, "before_token_sha256")),
        _HISTORICAL_TOKEN,
        _ENDPOINTS,
    )
    _require(
        doc.text(doc.at(doc.root, "after_token_sha256")),
        _COUNT_TOKEN,
        _ENDPOINTS,
    )
    var edits = doc.at(doc.root, "edits")
    var names = ""
    var index = 0
    var count = doc.length(edits)
    while index < count:
        if index > 0:
            names += "\n"
        names += doc.text(doc.at(doc.item(edits, index), "name"))
        index += 1
    _require(names, _EDIT_NAMES, _NAMES)
    _require(_edit_names(), _EDIT_NAMES, _NAMES)
    var tests = doc.at(doc.root, "after_correctness_tests")
    var fixture = ""
    index = 0
    count = doc.length(tests)
    while index < count:
        if index > 0:
            fixture += "\n"
        fixture += doc.key(tests, index)
        index += 1
    _require(fixture, _FIXTURE, _FIXTURES)


def count_predecessor_source(text: String) raises -> String:
    """Invert the three count edits to the historical Map.

    Args:
        text: The count endpoint.

    Returns:
        The historical Map.

    Raises:
        Error: The endpoint or the historical bytes differ.
    """
    _require(token_sha256(text), _COUNT_TOKEN, _UNKNOWN)
    _require(sha256_hex(text.as_bytes()), _COUNT_SHA, _UNKNOWN)
    var historical = historical_map(text)
    _require(sha256_hex(historical.as_bytes()), _HISTORICAL_SHA, _HISTORICAL)
    _require(token_sha256(historical), _HISTORICAL_TOKEN, _HISTORICAL)
    return historical


def count_predecessor(root: String) raises:
    """Require the live Map count predecessor.

    Args:
        root: The repository root.

    Raises:
        Error: The record, the live Map, or the historical Map changed.
    """
    _record(root)
    var live = Path(_root(root) + "/" + _MAP).read_text()
    var score = score_endpoint(station_endpoint(restored_deviation(live)))
    var frontier = score_predecessor_source(score)
    var support = frontier_predecessor_source(frontier)
    var optional = support_predecessor_source(support)
    var count = optional_predecessor_source(optional)
    _ = count_predecessor_source(count)


def main() raises:
    """Check the count predecessor of this repository.

    Raises:
        Error: The live Map or the historical Map changed.
    """
    count_predecessor(".")
