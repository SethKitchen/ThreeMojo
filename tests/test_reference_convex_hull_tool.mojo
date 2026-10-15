# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The exact convex hull controls in assets/convex_hull/ are current."""

from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_false, assert_true

from tools._fraction import Fraction
from tools.reference_convex_hull import contains, decode, facets, render, word


def test_the_saved_fixture_matches_the_exact_oracle() raises:
    var made = render()
    assert_equal(made[1], 19)
    assert_equal(made[2], 210)
    assert_true(Path("assets/convex_hull/exact.txt").read_text() == made[0])


def test_a_tetrahedron_has_four_outward_facets() raises:
    var points: List[Tuple[Float64, Float64, Float64]] = [
        (0.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 0.0, 1.0),
    ]
    var found = facets(points)
    assert_equal(len(found[1]), 4)
    assert_true(contains(found[0], found[1], (0.25, 0.25, 0.25), 0.0))
    assert_false(contains(found[0], found[1], (1.0, 1.0, 1.0), 0.0))
    # The point (1, 1, 1) is 2 / sqrt(3), about 1.155, outside the slanted face.
    assert_true(contains(found[0], found[1], (1.0, 1.0, 1.0), 1.2))


def test_words_and_decoding() raises:
    assert_equal(word(1.0), 4607182418800017408)
    assert_equal(word(-0.0), -9223372036854775807 - 1)
    assert_true(decode(5e-324) > Fraction(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
