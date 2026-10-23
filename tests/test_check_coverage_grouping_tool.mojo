# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The Boolean grouping reference matches the former Python model."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tools._sha256 import sha256_hex
from tools.check_coverage_grouping import (
    cases,
    expected_records,
    expected_rows,
    fixture_source,
    generic_pair_expected,
    generic_pair_line,
    identity_last_use_source,
    identity_source,
    lifetime_source,
    reduce_text,
    repeated_truth_source,
    temporary_identity_source,
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


def test_repeated_truth_keeps_the_value_alive() raises:
    var native = repeated_truth_source(False)
    var probe = repeated_truth_source(True)
    assert_true(native.find('print("FIRST", kept.__bool__())') >= 0)
    assert_equal(native.find("coverage.runtime"), -1)
    assert_true(probe.find("comptime assert _borrowed(") >= 0)
    assert_equal(probe.find("COVEVAL2"), -1)
    assert_true(probe.find('print("COUNT", count, kept.count[])') >= 0)


def test_the_lifetime_fixture_matches_the_pinned_text() raises:
    var made = lifetime_source()
    assert_equal(len(made[1]), 104)
    assert_equal(
        sha256_hex(made[0].as_bytes()),
        "4b673e30bbe631306a27379cf3eb6dd89fdc8bf15713a494bd38d06f611289cd",
    )


def test_repeated_records_reduce_to_the_first_copy() raises:
    var raw = (
        "COVLINE:fixture:1:T\n"
        "COVLINE:fixture:1:T\n"
        "COVEVAL2:fixture:1:T:T;\n"
        "COVEVAL2:fixture:1:T:T;\n"
        "hello\n"
    )
    assert_equal(
        reduce_text(raw),
        "COVLINE:fixture:1:T\nCOVEVAL2:fixture:1:T:T;\nhello\n",
    )


def test_the_identity_fixture_matches_the_pinned_text() raises:
    assert_equal(
        sha256_hex(identity_source("not kept or False").as_bytes()),
        "c5d35a3906009b2f70c7a5cba999dcb97a5be75bc0a35b67253a06d7c5252a7a",
    )


def test_the_last_use_fixture_drops_the_trailing_reads() raises:
    var source = identity_last_use_source("not kept or False")
    assert_equal(source.find("RETAINED"), -1)
    assert_equal(
        sha256_hex(source.as_bytes()),
        "064262fd3be99a794b8d0e497f6c3a978bc9e7c4a2b4b34937eca21460523e3d",
    )


def test_the_temporary_identity_fixture_matches_the_pinned_text() raises:
    var source = temporary_identity_source(
        "Anchored", "not Anchored(7) or False"
    )
    assert_equal(
        sha256_hex(source.as_bytes()),
        "8159a7f5605c3ae2ee16987901c8bbd69bc540058f6a2837a309faaf8a366891",
    )


def test_the_generic_pair_fixture_matches_the_pinned_text() raises:
    var source = Path(
        "tools/fixtures/coverage_generic_pair_isolated.txt"
    ).read_text()
    assert_equal(
        sha256_hex(source.as_bytes()),
        "c224718ba677f218cdf8c2e0c5b47c6b5a7ff358ab996cb010b66f6a1f591d94",
    )
    assert_true(
        source.find("def generic_pair[A: Made, B: Made](state: Cell) -> Bool:")
        >= 0
    )
    var expected = generic_pair_expected()
    assert_equal(
        sha256_hex(expected.as_bytes()),
        "6513143e353280acfbf55293bd983b3782760e1f160de41c4ed9ce9248df96b5",
    )
    assert_equal(
        generic_pair_line("Probe", 0, False),
        "PAIR Probe 0 False False 0~01~1 1 1 0",
    )
    assert_equal(
        generic_pair_line("Other", 1, True),
        "PAIR Other 1 True True 0~0 1 0 0",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
