# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.tonemap`.

Every expected number here was worked out from three.js's shader chunk in
double precision, independently of this port, and is asked for to four
figures: the curves are evaluated in `Float32` with `exp2` and `log2`
standing in for `pow`, which agrees to about six.
"""

from render.framebuffer import FloatColor
from render.tonemap import (
    ACES_FILMIC_TONE_MAPPING,
    AGX_TONE_MAPPING,
    CINEON_TONE_MAPPING,
    LINEAR_TONE_MAPPING,
    NEUTRAL_TONE_MAPPING,
    NO_TONE_MAPPING,
    REINHARD_TONE_MAPPING,
    ToneMapping,
    check_tone_mapping,
    tone_map,
)
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(1e-4)


def mapped(
    mode: ToneMapping,
    r: Float32,
    g: Float32,
    b: Float32,
    exposure: Float32 = 1.0,
) -> FloatColor:
    """Return an opaque color through `mode`."""
    return tone_map(FloatColor(r, g, b, 1.0), mode, exposure)


def assert_channels(
    color: FloatColor, r: Float32, g: Float32, b: Float32
) raises:
    """Assert three channels to the tolerance the curves are held to."""
    assert_almost_equal(color.r, r, atol=TOLERANCE)
    assert_almost_equal(color.g, g, atol=TOLERANCE)
    assert_almost_equal(color.b, b, atol=TOLERANCE)


def assert_gray(color: FloatColor, value: Float32) raises:
    """Assert a gray came out gray, at `value`."""
    assert_channels(color, value, value, value)


def test_the_seven_curves_are_valid_and_an_eighth_is_not() raises:
    assert_true(NO_TONE_MAPPING.is_valid())
    assert_true(LINEAR_TONE_MAPPING.is_valid())
    assert_true(REINHARD_TONE_MAPPING.is_valid())
    assert_true(CINEON_TONE_MAPPING.is_valid())
    assert_true(ACES_FILMIC_TONE_MAPPING.is_valid())
    assert_true(AGX_TONE_MAPPING.is_valid())
    assert_true(NEUTRAL_TONE_MAPPING.is_valid())
    assert_false(ToneMapping(9).is_valid())


def test_no_tone_mapping_leaves_the_light_alone_exposure_and_all() raises:
    # Nothing is clamped either: the clamp is `encode`'s, later.
    var kept = mapped(NO_TONE_MAPPING, 2.0, 0.5, 0.1, 3.0)
    assert_channels(kept, 2.0, 0.5, 0.1)
    # And so does a curve that is none of the seven, which the boundaries
    # refuse before this is ever asked.
    var unknown = mapped(ToneMapping(9), 2.0, 0.5, 0.1)
    assert_channels(unknown, 2.0, 0.5, 0.1)


def test_every_curve_keeps_alpha() raises:
    for mode in [
        NO_TONE_MAPPING,
        LINEAR_TONE_MAPPING,
        REINHARD_TONE_MAPPING,
        CINEON_TONE_MAPPING,
        ACES_FILMIC_TONE_MAPPING,
        AGX_TONE_MAPPING,
        NEUTRAL_TONE_MAPPING,
    ]:
        var half = tone_map(FloatColor(2.0, 2.0, 2.0, 0.5), mode, 1.0)
        assert_equal(half.a, Float32(0.5))


def test_linear_scales_by_the_exposure_and_clamps() raises:
    assert_channels(mapped(LINEAR_TONE_MAPPING, 2.0, 0.5, 0.1), 1.0, 0.5, 0.1)
    assert_gray(mapped(LINEAR_TONE_MAPPING, 0.5, 0.5, 0.5, 2.0), 1.0)
    assert_gray(mapped(LINEAR_TONE_MAPPING, 0.5, 0.5, 0.5, 0.5), 0.25)
    assert_gray(mapped(LINEAR_TONE_MAPPING, 0.0, 0.0, 0.0), 0.0)


def test_reinhard_never_reaches_white() raises:
    # `c / (1 + c)`: one is a half, four is four fifths, and the exposure
    # scales first.
    assert_gray(mapped(REINHARD_TONE_MAPPING, 1.0, 1.0, 1.0), 0.5)
    assert_gray(mapped(REINHARD_TONE_MAPPING, 4.0, 4.0, 4.0), 0.8)
    assert_gray(mapped(REINHARD_TONE_MAPPING, 0.18, 0.18, 0.18), 0.152542)
    assert_channels(
        mapped(REINHARD_TONE_MAPPING, 2.0, 0.5, 0.1),
        0.666667,
        0.333333,
        0.090909,
    )
    assert_gray(mapped(REINHARD_TONE_MAPPING, 0.5, 0.5, 0.5, 2.0), 0.5)
    assert_gray(mapped(REINHARD_TONE_MAPPING, 0.0, 0.0, 0.0), 0.0)


def test_cineon_is_hejl_and_burgess_dawsons_curve() raises:
    assert_gray(mapped(CINEON_TONE_MAPPING, 0.0, 0.0, 0.0), 0.0)
    assert_gray(mapped(CINEON_TONE_MAPPING, 0.02, 0.02, 0.02), 0.007471)
    assert_gray(mapped(CINEON_TONE_MAPPING, 0.18, 0.18, 0.18), 0.225400)
    assert_gray(mapped(CINEON_TONE_MAPPING, 1.0, 1.0, 1.0), 0.683542)
    assert_gray(mapped(CINEON_TONE_MAPPING, 4.0, 4.0, 4.0), 0.901862)
    assert_channels(
        mapped(CINEON_TONE_MAPPING, 2.0, 0.5, 0.1), 0.818126, 0.500699, 0.115605
    )
    assert_gray(mapped(CINEON_TONE_MAPPING, 0.5, 0.5, 0.5, 2.0), 0.683542)


def test_aces_filmic_is_the_brightened_hill_fit() raises:
    assert_gray(mapped(ACES_FILMIC_TONE_MAPPING, 0.0, 0.0, 0.0), 0.0)
    assert_gray(mapped(ACES_FILMIC_TONE_MAPPING, 0.02, 0.02, 0.02), 0.007255)
    assert_channels(
        mapped(ACES_FILMIC_TONE_MAPPING, 0.18, 0.18, 0.18),
        0.213105,
        0.213105,
        0.213103,
    )
    assert_channels(
        mapped(ACES_FILMIC_TONE_MAPPING, 1.0, 1.0, 1.0),
        0.763397,
        0.763397,
        0.763390,
    )
    assert_channels(
        mapped(ACES_FILMIC_TONE_MAPPING, 4.0, 4.0, 4.0),
        0.952237,
        0.952237,
        0.952227,
    )
    assert_channels(
        mapped(ACES_FILMIC_TONE_MAPPING, 2.0, 0.5, 0.1),
        0.982304,
        0.604406,
        0.224429,
    )
    assert_channels(
        mapped(ACES_FILMIC_TONE_MAPPING, 0.5, 0.5, 0.5, 2.0),
        0.763397,
        0.763397,
        0.763390,
    )


def test_agx_goes_through_rec_2020_and_the_sigmoid() raises:
    assert_gray(mapped(AGX_TONE_MAPPING, 0.0, 0.0, 0.0), 0.0)
    assert_channels(
        mapped(AGX_TONE_MAPPING, 0.02, 0.02, 0.02), 0.018235, 0.018230, 0.018231
    )
    assert_channels(
        mapped(AGX_TONE_MAPPING, 0.18, 0.18, 0.18), 0.214549, 0.214502, 0.214499
    )
    assert_channels(
        mapped(AGX_TONE_MAPPING, 1.0, 1.0, 1.0), 0.590229, 0.590136, 0.590102
    )
    assert_channels(
        mapped(AGX_TONE_MAPPING, 4.0, 4.0, 4.0), 0.861016, 0.860910, 0.860839
    )
    assert_channels(
        mapped(AGX_TONE_MAPPING, 2.0, 0.5, 0.1), 0.816277, 0.453794, 0.263061
    )
    assert_channels(
        mapped(AGX_TONE_MAPPING, 0.5, 0.5, 0.5, 2.0),
        0.590229,
        0.590136,
        0.590102,
    )


def test_neutral_lifts_the_darks_and_rolls_off_past_the_knee() raises:
    # Below the knee only the offset applies: mid-gray loses four
    # hundredths, and a very dark gray goes through the quadratic. Past
    # the knee the peak is compressed and the color desaturated a little.
    assert_gray(mapped(NEUTRAL_TONE_MAPPING, 0.0, 0.0, 0.0), 0.0)
    assert_gray(mapped(NEUTRAL_TONE_MAPPING, 0.02, 0.02, 0.02), 0.0025)
    assert_gray(mapped(NEUTRAL_TONE_MAPPING, 0.18, 0.18, 0.18), 0.14)
    assert_gray(mapped(NEUTRAL_TONE_MAPPING, 1.0, 1.0, 1.0), 0.869091)
    assert_gray(mapped(NEUTRAL_TONE_MAPPING, 4.0, 4.0, 4.0), 0.983256)
    assert_channels(
        mapped(NEUTRAL_TONE_MAPPING, 2.0, 0.5, 0.1),
        0.960000,
        0.321136,
        0.150772,
    )
    assert_gray(mapped(NEUTRAL_TONE_MAPPING, 0.5, 0.5, 0.5, 2.0), 0.869091)


def test_every_curve_is_monotonic_and_bounded_on_grays() raises:
    # Brighter light never comes out darker, nothing comes out above one or
    # below zero, and a zero exposure is black.
    for mode in [
        LINEAR_TONE_MAPPING,
        REINHARD_TONE_MAPPING,
        CINEON_TONE_MAPPING,
        ACES_FILMIC_TONE_MAPPING,
        AGX_TONE_MAPPING,
        NEUTRAL_TONE_MAPPING,
    ]:
        var previous = Float32(-1)
        for step in range(0, 41):
            var light = Float32(step) * 0.25
            var shown = mapped(mode, light, light, light)
            assert_true(shown.r >= previous - 1e-6, "the curve went down")
            assert_true(
                shown.r >= 0 and shown.r <= 1, "the curve left zero to one"
            )
            previous = shown.r
        assert_gray(mapped(mode, 3.0, 3.0, 3.0, 0.0), 0.0)


def test_the_boundary_check_refuses_an_unknown_curve_or_a_bad_exposure() raises:
    # The one list every boundary asks: a named curve, and an exposure that
    # is finite and not negative. Zero is a legal black.
    check_tone_mapping(NO_TONE_MAPPING, 1.0)
    check_tone_mapping(AGX_TONE_MAPPING, 0.0)
    with assert_raises():
        check_tone_mapping(ToneMapping(9), 1.0)
    with assert_raises():
        check_tone_mapping(REINHARD_TONE_MAPPING, -1.0)
    with assert_raises():
        check_tone_mapping(REINHARD_TONE_MAPPING, inf[DType.float32]())
    with assert_raises():
        check_tone_mapping(REINHARD_TONE_MAPPING, nan[DType.float32]())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
