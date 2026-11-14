# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `bindAnalyticNoise`: its four numbers against
`assets/ssr_denoise/reference.py`, a transcription of three.js r186's
`RNoise.js`, and the denoiser's first number."""

from postprocessing.rnoise import analytic_noise4
from postprocessing.temporal_denoise import analytic_noise
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)


def test_the_four_numbers_are_three_js_s() raises:
    # The SSR node's march seed, on its first frame.
    var first = analytic_noise4(0, 0, 1, 47)
    assert_almost_equal(first.x, 0.5523872, atol=1e-4)
    assert_almost_equal(first.y, 0.3997803, atol=1e-4)
    assert_almost_equal(first.z, 0.7034073, atol=1e-4)
    assert_almost_equal(first.w, 0.4620361, atol=1e-4)
    var later = analytic_noise4(5, 7, 3, 47)
    assert_almost_equal(later.x, 0.6730728, atol=1e-4)
    assert_almost_equal(later.y, 0.7966003, atol=1e-4)
    assert_almost_equal(later.z, 0.6150665, atol=1e-4)
    assert_almost_equal(later.w, 0.8830719, atol=1e-4)
    # A pixel past the tile wraps into it. The seed is the environment's.
    var wrapped = analytic_noise4(40, 3, 1, 59)
    assert_almost_equal(wrapped.x, 0.9614944, atol=1e-4)
    assert_almost_equal(wrapped.y, 0.1930237, atol=1e-4)
    assert_almost_equal(wrapped.z, 0.4217377, atol=1e-4)
    assert_almost_equal(wrapped.w, 0.4230347, atol=1e-4)


def test_the_denoiser_s_noise_is_the_first_number() raises:
    for index in range(4):
        for y in range(3):
            for x in range(40):
                assert_equal(
                    analytic_noise4(x, y * 13, index, 83).x,
                    analytic_noise(x, y * 13, index),
                )


def test_each_number_is_a_fraction() raises:
    for index in range(3):
        for x in range(34):
            var noise = analytic_noise4(x, 33 - x, index, 47)
            assert_true(noise.x >= 0 and noise.x < 1)
            assert_true(noise.y >= 0 and noise.y < 1)
            assert_true(noise.z >= 0 and noise.z < 1)
            assert_true(noise.w >= 0 and noise.w < 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
