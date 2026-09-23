# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.noise`: `ImprovedNoise` and `SimplexNoise`.

Every expected value was calculated by three.js 0.180, by node on
`examples/jsm/math/ImprovedNoise.js` and `SimplexNoise.js`. The simplex
generator is `MathUtils.seededRandom` seeded with 42. The values are
compared exactly: the port computes in `Float64` in three.js's order.
"""

from math.noise import ImprovedNoise, SimplexNoise
from math.utils import SeededRandom
from std.math import inf, nan
from std.testing import TestSuite, assert_equal, assert_raises


def simplex() -> SimplexNoise:
    """Return simplex noise seeded as the reference values were."""
    var random = SeededRandom(42)
    return SimplexNoise(random)


def test_improved_noise_matches_three() raises:
    """Perlin's noise gives three.js's values bit for bit, far from the
    origin too."""
    var n = ImprovedNoise()
    assert_equal(n.noise(0.5, 0.25, 0.75), -0.40987873077392578)
    assert_equal(n.noise(1.3, -2.7, 3.1), 0.50434089134499827)
    assert_equal(n.noise(-10.25, 4.5, -0.125), -0.44666663557291031)
    assert_equal(n.noise(123.456, -78.9, 0.001), 0.090444367610078236)
    assert_equal(n.noise(1e10 + 0.5, -3e12 + 0.25, 7.75), 0.25669717788696289)
    assert_equal(n.noise(-0.3, -0.6, -0.9), -0.49057741941288968)


def test_improved_noise_is_zero_on_the_lattice() raises:
    """At a whole-number point every gradient meets a zero offset."""
    assert_equal(ImprovedNoise().noise(3, 4, 5), 0.0)


def test_improved_noise_refuses_what_is_not_a_number() raises:
    """A coordinate that is not finite is refused; three.js gives NaN."""
    var n = ImprovedNoise()
    with assert_raises(contains="finite"):
        _ = n.noise(nan[DType.float64](), 0, 0)
    with assert_raises(contains="finite"):
        _ = n.noise(0, inf[DType.float64](), 0)
    with assert_raises(contains="finite"):
        _ = n.noise(0, 0, -inf[DType.float64]())


def test_simplex_permutation_matches_three() raises:
    """The seeded generator gives three.js's permutation, doubled."""
    var s = simplex()
    assert_equal(len(s.perm), 512)
    assert_equal(s.perm[0], 153)
    assert_equal(s.perm[1], 114)
    assert_equal(s.perm[2], 218)
    assert_equal(s.perm[7], 159)
    assert_equal(s.perm[256], 153)
    assert_equal(s.perm[263], 159)


def test_simplex_2d_matches_three() raises:
    """2D simplex noise, both halves of the cell."""
    var s = simplex()
    assert_equal(s.noise(0.5, 0.25), -0.41346061660535521)
    assert_equal(s.noise(1.3, -2.7), -0.41863785574835971)
    assert_equal(s.noise(-10.25, 4.5), -0.54181296289383774)
    assert_equal(s.noise(123.456, -78.9), 0.43094062907321384)
    assert_equal(s.noise(0.9, 0.1), -0.27414504982915522)
    assert_equal(s.noise(0.1, 0.9), -0.12589043002299857)
    assert_equal(s.noise(1e10 + 0.5, -3e12 + 0.25), -0.70979755638886977)


def test_simplex_3d_matches_three() raises:
    """3D simplex noise, in each of the six tetrahedra of a cell."""
    var s = simplex()
    assert_equal(s.noise3d(0.5, 0.25, 0.75), 0.36624687499999981)
    assert_equal(s.noise3d(1.3, -2.7, 3.1), 0.54146587891357900)
    assert_equal(s.noise3d(-10.25, 4.5, -0.125), -0.61381120696519342)
    assert_equal(s.noise3d(123.456, -78.9, 0.001), 0.19948331623663831)
    assert_equal(s.noise3d(1e10 + 0.5, -3e12 + 0.25, 7.75), 0.22631964258041426)
    assert_equal(s.noise3d(3, 4, 5), 0.0)
    assert_equal(s.noise3d(-0.3, -0.6, -0.9), -0.10931742933333334)
    assert_equal(s.noise3d(0.3, 0.2, 0.1), 0.74331016533333305)
    assert_equal(s.noise3d(0.3, 0.1, 0.2), 0.62922482133333313)
    assert_equal(s.noise3d(0.2, 0.1, 0.3), 0.46361887999999990)
    assert_equal(s.noise3d(0.1, 0.2, 0.3), 0.40398972799999988)
    assert_equal(s.noise3d(0.1, 0.3, 0.2), 0.51030239999999982)
    assert_equal(s.noise3d(0.2, 0.3, 0.1), 0.68299692799999978)


def test_simplex_4d_matches_three() raises:
    """4D simplex noise."""
    var s = simplex()
    assert_equal(s.noise4d(0.5, 0.25, 0.75, 0.1), -0.18385993415074964)
    assert_equal(s.noise4d(1.3, -2.7, 3.1, -4.2), -0.16298272193319951)
    assert_equal(s.noise4d(-10.25, 4.5, -0.125, 8.5), -0.095032636664826364)
    assert_equal(s.noise4d(0.4, 0.3, 0.2, 0.1), 0.055948498271178489)
    assert_equal(s.noise4d(0.1, 0.2, 0.3, 0.4), -0.20456748271170994)
    assert_equal(s.noise4d(0.2, 0.4, 0.1, 0.3), 0.099531922723750818)
    assert_equal(s.noise4d(5.5, -6.25, 7.125, 1e9 + 0.5), -0.26888646814376860)


def test_simplex_refuses_what_is_not_a_number() raises:
    """Every coordinate of every dimension is checked."""
    var s = simplex()
    var bad = nan[DType.float64]()
    with assert_raises(contains="finite"):
        _ = s.noise(bad, 0)
    with assert_raises(contains="finite"):
        _ = s.noise(0, bad)
    with assert_raises(contains="finite"):
        _ = s.noise3d(bad, 0, 0)
    with assert_raises(contains="finite"):
        _ = s.noise3d(0, bad, 0)
    with assert_raises(contains="finite"):
        _ = s.noise3d(0, 0, bad)
    with assert_raises(contains="finite"):
        _ = s.noise4d(bad, 0, 0, 0)
    with assert_raises(contains="finite"):
        _ = s.noise4d(0, bad, 0, 0)
    with assert_raises(contains="finite"):
        _ = s.noise4d(0, 0, bad, 0)
    with assert_raises(contains="finite"):
        _ = s.noise4d(0, 0, 0, bad)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
