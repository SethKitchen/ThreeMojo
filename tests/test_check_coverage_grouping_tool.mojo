# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Boolean grouping reference matches the former Python model."""

from std.testing import TestSuite, assert_equal

from tools._sha256 import sha256_hex
from tools.check_coverage_grouping import (
    cases,
    expected_records,
    expected_rows,
    fixture_source,
)


def test_the_fixture_source_matches_the_pinned_text() raises:
    var made = fixture_source()
    assert_equal(len(cases()), 23)
    assert_equal(len(made[1]), 23)
    assert_equal(
        sha256_hex(made[0].as_bytes()),
        "17b0f20eaeb194f0ebc9c477f1cf56a020deb6de4833fb99b007a4bacac19c88",
    )


def test_every_mask_and_throwing_position_has_a_result_row() raises:
    var fail = -1
    while fail < 6:
        var rows = expected_rows(fail)
        assert_equal(len(rows), 23 * 64)
        fail += 1
    var rows = expected_rows(-1)
    assert_equal(rows[0], "RESULT 0 0 -1 F 01")
    assert_equal(rows[1], "RESULT 1 0 -1 T 0")
    assert_equal(rows[2], "RESULT 2 0 -1 F 01")
    var made = fixture_source()
    var records = expected_records(-1, made[1])
    assert_equal(len(records[0]), 23)
    assert_equal(len(records[1]), 23)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
