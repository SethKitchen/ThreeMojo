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
    single_generic_case,
    single_generic_expected,
    single_generic_trace,
    identity_last_use_source,
    identity_source,
    lifetime_source,
    reduce_text,
    repeated_truth_source,
    temporary_identity_source,
    truth_accepted_traces,
    truth_log,
    truth_model_rows,
    truth_records,
    mixed_truth_numbers,
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


def test_the_single_generic_fixture_matches_the_pinned_text() raises:
    var source = Path("tools/fixtures/coverage_generic_single.txt").read_text()
    assert_equal(
        sha256_hex(source.as_bytes()),
        "211b828675bff5954aad8863d14ab195198638a132b665ae4f8e811db26f9422",
    )
    var expected = single_generic_expected(164)
    var trace = single_generic_trace(164)
    assert_equal(
        sha256_hex(expected.as_bytes()),
        "f33782a8594219db463613900fb9f729b101be5ed1a8c13a96d792aa6e2f997c",
    )
    assert_equal(
        sha256_hex(trace.as_bytes()),
        "3a0e90f53e245ba663b5e15e232e35ece2d1e9c9d3002971e331a1e86d649afd",
    )
    var stable = single_generic_case("Probe", 0, False, 164)
    assert_equal(stable[0], "GENERIC Probe 0 False False 0~011~1 1 2 0")
    var flipped = single_generic_case("Probe", 1, True, 164)
    assert_equal(flipped[0], "GENERIC Probe 1 True False 00~0 2 0 0")


def test_the_custom_truth_model_matches_the_pinned_rows() raises:
    assert_equal(truth_log(0, 0, -1, False), "+00~0+11~1|F")
    assert_equal(truth_log(0, 5, -1, False), "+000~0|T")
    assert_equal(truth_log(0, 5, 0, True), "+0|E")
    assert_equal(truth_log(4, 1, -1, True), "+000~0|F")
    assert_equal(truth_log(12, 5, -1, False), "0|T~0")
    assert_equal(truth_log(15, 1, -1, False), "+1+33~3+00~0|T")
    assert_equal(truth_log(23, 1, 1, False), "+1|E~2~3")
    assert_equal(truth_log(30, 7, 2, True), "00|F")
    assert_equal(truth_log(36, 5, 0, True), "0+222|F")
    assert_equal(truth_log(39, 2, -1, False), "+00~0=111~1|T~1~2")
    assert_equal(truth_log(41, 4, -1, False), "+00~0+1=33~3|F~2~3")
    assert_equal(truth_log(42, 5, 0, True), "+0|E~1")
    var source = Path("tools/fixtures/coverage_truth_native.txt").read_text()
    assert_equal(
        sha256_hex(source.as_bytes()),
        "6f45fbda2c547306d100449921a34d47866fb74a5f50e3da9ff52f6b8fe90d98",
    )
    assert_true(source.find("def truth_0(") >= 0)
    assert_true(source.find("def truth_42(") >= 0)
    assert_equal(
        sha256_hex(truth_model_rows().as_bytes()),
        "25f58af42cbb9e5d2118a66f0b95c71d7158d20f5b9f86fdc8b80c46d57c9d85",
    )


def test_the_accepted_truth_traces_match_the_pinned_text() raises:
    assert_equal(
        truth_records(0, 0, -1, False, 166),
        "COVLINE:truth:166.0:F\nCOVLINE:truth:166.1:F\nCOVLINE:truth:166:F\nCOVEVAL2:truth:166:F:FF;\n",
    )
    assert_equal(
        truth_records(1, 0, -1, False, 180),
        "COVLINE:truth:180.0:F\nCOVLINE:truth:180:F\nCOVEVAL2:truth:180:F:F-;\n",
    )
    assert_equal(
        sha256_hex(truth_accepted_traces(False).as_bytes()),
        "f4cd305b17bbbadf58da1cd073318940d95f97868a76ec7c63c747fb3f435a55",
    )
    assert_equal(
        sha256_hex(truth_accepted_traces(True).as_bytes()),
        "376665be098e1d326ed55ef9445d0892297a2b2cb397cf32b99aabdaa5d92fd5",
    )
    assert_equal(
        sha256_hex(truth_accepted_traces(False, "collision").as_bytes()),
        "d8218fcc54619926f4c438593781c36faad27ac0bd87e94f033c3eb4d09486be",
    )
    assert_equal(
        sha256_hex(truth_accepted_traces(True, "collision").as_bytes()),
        "401a776c06d8e86af92bdfd03b321341edb0db4f5ea2f780e14772ed22038774",
    )
    var collision_native = Path(
        "tools/fixtures/coverage_truth_collision_native.txt"
    ).read_text()
    var collision_accepted = Path(
        "tools/fixtures/coverage_truth_collision_accepted.txt"
    ).read_text()
    assert_equal(
        sha256_hex(collision_native.as_bytes()),
        "e5700acdb074d5895d3c73f12e7b29b3a2340cf973866e8fa0a7e348dceabdb6",
    )
    assert_equal(
        sha256_hex(collision_accepted.as_bytes()),
        "b0ae675b225e8361b804b6eb9ad07942ba4348a09fb662a45a00957fa5642d6c",
    )
    assert_true(collision_native.find("def _cov_eval_leaf(") >= 0)
    assert_true(collision_accepted.find("var List = ") >= 0)
    var source = Path("tools/fixtures/coverage_truth_accepted.txt").read_text()
    assert_equal(
        sha256_hex(source.as_bytes()),
        "46007ecd43f76f6d43a8c18730970718b72629968264d111c0d0bddc2ddeee00",
    )


def test_the_mixed_truth_fixtures_match_the_native_functions() raises:
    assert_equal(len(mixed_truth_numbers()), 30)
    var native = Path("tools/fixtures/coverage_truth_native.txt").read_text()
    var blob = String()
    for number in mixed_truth_numbers():
        var source = Path(
            "tools/fixtures/coverage_truth_mixed_" + String(number) + ".txt"
        ).read_text()
        blob += source
        var signature = "def truth_" + String(number) + "("
        assert_true(native.find(signature) >= 0, signature)
        assert_true(source.find(signature) >= 0, signature)
    assert_equal(
        sha256_hex(blob.as_bytes()),
        "c6cd61b271f639733d1bbd7c87fe831bd76c558288aa5c08e70ecd5857410482",
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
