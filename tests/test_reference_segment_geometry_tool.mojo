# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The segment oracle confirms the retained native words and expectations.

The model's path counts depend on fused multiply-adds, so this test checks
the oracle's verdicts, not the summary's digits.
"""

from std.testing import TestSuite, assert_equal, assert_true

from tools.reference_segment_geometry import bits, distance, run, slab, val


def test_the_native_fixture_matches_the_exact_oracle() raises:
    var summary = run(0)
    assert_true(
        summary.find('"native_fixture_words_and_expectations_verified": true')
        >= 0
    )
    assert_true(summary.find('"distance_cases": 226') >= 0)
    assert_true(summary.find('"slab_cases": 157') >= 0)


def test_float32_words_round_as_struct_pack_does() raises:
    assert_equal(bits(1.0), UInt32(0x3F800000))
    assert_equal(val(UInt32(1)), 1.401298464324817e-45)
    var refused = False
    try:
        _ = bits(1e39)
    except:
        refused = True
    assert_true(refused)


def test_exact_distance_and_slab() raises:
    # p = (0, 1, 0) is one unit from the segment from (0, 0, 0) to (1, 0, 0).
    var words: List[UInt32] = [0, 0, 0, 0x3F800000, 0, 0, 0, 0x3F800000, 0]
    assert_equal(distance(words).to_float(), 1.0)
    var box: List[UInt32] = [
        0,
        0,
        0,
        0x3F800000,
        0x3F800000,
        0,
        0x3F000000,
        0,
        0,
        0x3F800000,
        0x3F800000,
        0,
    ]
    assert_true(slab(box))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
