# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Reviewed cleanup successors keep their premise order."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_raises

from tests._cleanup_premises import ordered_text, require_cleanup_premises
from tests._python_tokens import def_token_sha256, token_sha256
from tools._cleanup_premises import (
    cleanup_catalog_premises,
    cleanup_declared_premises,
)
from tools._sha256 import sha256_hex
from tests._winner_pin_predecessor import (
    restored_junction_cleanup,
    restored_rounded_arc_cleanup,
    restored_rounded_line_cleanup,
)


comptime _RECORD = "tools/carla_lane_oracle/reviewed-cleanup-migration.json"
"""The reviewed cleanup record."""
comptime _RECORD_SHA256 = (
    "01753344fe01d885eb3bbaf253815bca01816c57c09b6e7cc1c3a233808b42a9"
)
"""The SHA-256 of that record."""
comptime _LINE_TOKEN = (
    "dd1400b11b6bf90dde2198a304d84e40f5527c2a41175fcc49aeba444fb57706"
)
"""The token digest of the rounded-line successor."""
comptime _ARC_TOKEN = (
    "e98252c83b51b5421643d388556efcd839ef64dfddb37cef37084d48782642f9"
)
"""The token digest of the rounded-arc successor."""
comptime _JUNCTION_TOKEN = (
    "35aa94a154256542285a5dc4ab2b1a6378c501fb9cbf737511b129c23f51cb47"
)
"""The token digest of the junction successor."""
comptime _REFERENCE_TOKEN = (
    "a544c51e92396e721b5a2a06e99f4521b7d9d15641c210eb832c301ecd8664c2"
)
"""The token digest of the frozen outward reference."""


def _count(text: String, needle: String) -> Int:
    """Return how many times `needle` occurs.

    Args:
        text: The source.
        needle: The fragment.

    Returns:
        The number of matches.
    """
    var count = 0
    var rest = text
    while True:
        var at = rest.find(needle)
        if at < 0:
            return count
        count += 1
        var tail = String(rest[byte = at + needle.byte_length() :])
        rest = tail


def _replace(text: String, needle: String, replacement: String) -> String:
    """Replace the first `needle`.

    Args:
        text: The source.
        needle: The fragment.
        replacement: The replacement.

    Returns:
        The source with that fragment replaced.
    """
    var at = text.find(needle)
    var head = String(text[byte=:at])
    var tail = String(text[byte = at + needle.byte_length() :])
    return head + replacement + tail


def _mutations(
    mut which: List[Int], mut before: List[String], mut after: List[String]
):
    """Fill the reviewed premise mutations.

    Args:
        which: 0 for the line, 1 for the arc, and 2 for the junction.
        before: The original fragment.
        after: The mutated fragment.
    """
    which.append(0)
    before.append("len(road.info.geometries) != 1")
    after.append("len(road.info.geometries) < 1")
    which.append(0)
    before.append("not _RoundedBox.bounds(low, high).known")
    after.append("False")
    which.append(0)
    before.append("info_index(road.info.geometries, low) != 0")
    after.append("info_index(road.info.geometries, high) != 0")
    which.append(0)
    before.append("info_index(road.info.lane_offsets, high) != offset_at")
    after.append("False")
    which.append(0)
    before.append("info_index(road.info.elevations, high) != elevation_at")
    after.append("False")
    which.append(0)
    before.append("info_index(widths, high) != width_at")
    after.append("False")
    which.append(1)
    before.append("len(road.info.geometries) != 1")
    after.append("len(road.info.geometries) < 1")
    which.append(1)
    before.append("info_index(road.info.geometries, low) != 0")
    after.append("False")
    which.append(1)
    before.append("len(road.info.lane_offsets) != 1")
    after.append("False")
    which.append(1)
    before.append("len(road.info.elevations) != 1")
    after.append("False")
    which.append(1)
    before.append("info_index(road.info.lane_offsets, low) != 0")
    after.append("False")
    which.append(1)
    before.append("info_index(road.info.elevations, low) != 0")
    after.append("False")
    which.append(1)
    before.append("len(widths) != 1")
    after.append("len(widths) < 1")
    which.append(1)
    before.append("info_index(widths, low) != 0")
    after.append("False")
    which.append(1)
    before.append("and low <= high")
    after.append("and low >= high")
    which.append(1)
    before.append("if not half.known:")
    after.append("if False:")
    which.append(1)
    before.append("selector.low < 0.0")
    after.append("selector.low < -1.0")
    which.append(1)
    before.append("selector.high >= 1.0")
    after.append("selector.high > 1.0")
    which.append(2)
    before.append("outside = Float64(result) > value")
    after.append("outside = Float64(result) < value")
    which.append(2)
    before.append("outside = Float64(result) < value")
    after.append("outside = Float64(result) > value")
    which.append(2)
    before.append("UInt32(0x80000001) if lower else UInt32(1)")
    after.append("UInt32(1) if lower else UInt32(0x80000001)")
    which.append(2)
    before.append("if (result > 0.0) == lower:")
    after.append("if (result > 0.0) != lower:")


def test_cleanup_successors_keep_their_premises() raises:
    """The three successors keep their token digests and premise order."""
    var record = Path(_RECORD).read_text()
    assert_equal(sha256_hex(record.as_bytes()), _RECORD_SHA256)
    var line = restored_rounded_line_cleanup()
    var arc = restored_rounded_arc_cleanup()
    var junction = restored_junction_cleanup()
    assert_equal(token_sha256(line), _LINE_TOKEN)
    assert_equal(token_sha256(arc), _ARC_TOKEN)
    assert_equal(token_sha256(junction), _JUNCTION_TOKEN)
    require_cleanup_premises(line, arc, junction)
    var reference = Path(
        "tests/test_carla_outward_float_equivalence.mojo"
    ).read_text()
    assert_equal(
        def_token_sha256(reference, "_reference_outward_float"),
        _REFERENCE_TOKEN,
    )


def test_a_changed_premise_is_refused() raises:
    """A premise edit or a comment decoy changes the contract."""
    var record = Path(_RECORD).read_text()
    _changed_record(record)
    var line = restored_rounded_line_cleanup()
    var arc = restored_rounded_arc_cleanup()
    var junction = restored_junction_cleanup()
    var which = List[Int]()
    var before = List[String]()
    var after = List[String]()
    _mutations(which, before, after)
    assert_equal(len(which), 22)
    for index in range(len(which)):
        var source = line
        if which[index] == 1:
            source = arc
        elif which[index] == 2:
            source = junction
        assert_equal(_count(source, before[index]), 1)
        var changed = _replace(source, before[index], after[index])
        var next_line = line
        var next_arc = arc
        var next_junction = junction
        if which[index] == 0:
            next_line = changed
        elif which[index] == 1:
            next_arc = changed
        else:
            next_junction = changed
        with assert_raises(contains="reviewed cleanup source contract:"):
            require_cleanup_premises(next_line, next_arc, next_junction)
    var fragments = List[String]()
    fragments.append("if len(widths) != 1: return None")
    with assert_raises(contains="missing singleton"):
        ordered_text(
            "# if len(widths) != 1: return None\n",
            fragments,
            "missing singleton",
        )


def _changed_record(record: String) raises:
    """Require a changed cleanup record to change its digest.

    Args:
        record: The record text.

    Raises:
        Error: The changed record keeps the recorded digest.
    """
    if sha256_hex((record + " ").as_bytes()) == _RECORD_SHA256:
        raise Error("reviewed cleanup source contract: unreviewed migration")


def test_a_missing_declared_premise_is_refused() raises:
    """A missing function fails before the premise fragments are checked."""
    var payload = (
        '{"sources":["def f():\\n    return 1\\n"],'
        + '"declarations":[{"source":0,"name":"absent","owner":[],'
        + '"key":"line"}]}'
    )
    with assert_raises(
        contains="missing or ambiguous actual guard declaration: absent"
    ):
        cleanup_declared_premises(payload)


def test_the_catalog_names_the_first_premise() raises:
    """The declaration catalog supplies the first function name."""
    with assert_raises(
        contains=(
            "missing or ambiguous actual guard declaration: "
            "_rounded_line_axis_context"
        )
    ):
        cleanup_catalog_premises('["def f():\\n    return 1\\n"]')


def main() raises:
    """Run the cleanup premise tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
