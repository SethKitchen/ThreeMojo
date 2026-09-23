# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.lut`, three.js's `Lut`: color maps.

The expected colors were calculated by three.js 0.180, by node on
`examples/jsm/math/Lut.js`: the nine samples of each preset at eight steps,
lookups in a range, and the pixels `updateCanvas` draws.
"""

from render.framebuffer import FloatColor
from render.lut import (
    BLACKBODY,
    COOL_TO_WARM,
    GRAYSCALE,
    RAINBOW,
    ColorMapName,
    ColorStop,
    Lut,
    check_color_map,
    color_map,
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

comptime TOLERANCE = Float64(1e-6)


def assert_color(c: FloatColor, r: Float64, g: Float64, b: Float64) raises:
    """Assert a color's channels, within the tolerance."""
    assert_almost_equal(Float64(c.r), r, atol=TOLERANCE)
    assert_almost_equal(Float64(c.g), g, atol=TOLERANCE)
    assert_almost_equal(Float64(c.b), b, atol=TOLERANCE)


def assert_table(lut: Lut, expected: List[Float64]) raises:
    """Assert every sample of a table, three numbers each."""
    assert_equal(len(lut.lut), len(expected) // 3)
    for index in range(len(lut.lut)):
        assert_color(
            lut.lut[index],
            expected[index * 3],
            expected[index * 3 + 1],
            expected[index * 3 + 2],
        )


def assert_bytes(found: List[UInt8], expected: List[Int]) raises:
    """Assert a list of bytes."""
    assert_equal(len(found), len(expected))
    for index in range(len(expected)):
        assert_equal(Int(found[index]), expected[index])


def test_rainbow_matches_three() raises:
    """The default map."""
    var lut = Lut(RAINBOW, 8)
    assert_equal(lut.n, 8)
    assert_table(
        lut,
        [
            0,
            0,
            1,
            0,
            0.625,
            1,
            0,
            1,
            0.83333333333333337,
            0,
            1,
            0.41666666666666663,
            0,
            1,
            0,
            0.41666666666666663,
            1,
            0,
            0.83333333333333326,
            1,
            0,
            1,
            0.62500000000000022,
            0,
            1,
            0,
            0,
        ],
    )
    var default = Lut()
    assert_equal(default.n, 32)
    assert_equal(len(default.lut), 33)


def test_cool_to_warm_decodes_its_ends_as_three_does() raises:
    """The first and last samples are decoded from sRGB, the rest not."""
    assert_table(
        Lut(COOL_TO_WARM, 8),
        [
            0.045186204379104991,
            0.076185381473219113,
            0.53947948900337483,
            0.46813725490196079,
            0.57549019607843144,
            0.91029411764705881,
            0.65032679738562083,
            0.75816993464052296,
            0.97712418300653592,
            0.75653594771241828,
            0.81045751633986929,
            0.91993464052287588,
            0.86274509803921573,
            0.86274509803921573,
            0.86274509803921573,
            0.90522875816993464,
            0.76960784313725494,
            0.72058823529411775,
            0.94771241830065356,
            0.67647058823529416,
            0.57843137254901966,
            0.86764705882352944,
            0.40539215686274516,
            0.38186274509803930,
            0.45641102317066595,
            0.0012141079341176470,
            0.019382360952473074,
        ],
    )


def test_blackbody_and_grayscale_match_three() raises:
    """The other two presets."""
    assert_table(
        Lut(BLACKBODY, 8),
        [
            0,
            0,
            0,
            0.29411764705882354,
            0,
            0,
            0.54248366013071891,
            0.032679738562091498,
            0,
            0.72222222222222232,
            0.11437908496732027,
            0,
            0.90196078431372551,
            0.19607843137254902,
            0,
            0.94281045751633985,
            0.53104575163398693,
            0,
            0.98366013071895420,
            0.86601307189542476,
            0,
            1,
            1,
            0.37499999999999983,
            1,
            1,
            1,
        ],
    )
    assert_table(
        Lut(GRAYSCALE, 8),
        [
            0,
            0,
            0,
            0.15686274509803921,
            0.15686274509803921,
            0.15686274509803921,
            0.29215686274509800,
            0.29215686274509800,
            0.29281045751633983,
            0.39509803921568631,
            0.39509803921568631,
            0.39738562091503271,
            0.49803921568627452,
            0.49803921568627452,
            0.50196078431372548,
            0.60261437908496729,
            0.60261437908496729,
            0.60490196078431369,
            0.70718954248366006,
            0.70718954248366006,
            0.70784313725490189,
            0.84313725490196079,
            0.84313725490196079,
            0.84313725490196079,
            1,
            1,
            1,
        ],
    )


def test_a_long_table_matches_three() raises:
    """Five hundred and twelve steps."""
    var lut = Lut(RAINBOW, 512)
    assert_equal(len(lut.lut), 513)
    assert_color(lut.lut[137], 0, 1, 0.77473958333333337)


def test_get_color_matches_three() raises:
    """A value is clamped to the range and rounded to the nearest sample."""
    var lut = Lut(COOL_TO_WARM, 32)
    lut.set_min(-2)
    lut.set_max(6)
    var first = FloatColor(
        0.045186204379104991, 0.076185381473219113, 0.53947948900337483
    )
    var last = FloatColor(
        0.45641102317066595, 0.0012141079341176470, 0.019382360952473074
    )
    assert_color(
        lut.get_color(-5), Float64(first.r), Float64(first.g), Float64(first.b)
    )
    assert_color(
        lut.get_color(-2), Float64(first.r), Float64(first.g), Float64(first.b)
    )
    assert_color(
        lut.get_color(0),
        0.65032679738562083,
        0.75816993464052296,
        0.97712418300653592,
    )
    assert_color(
        lut.get_color(1.3),
        0.78308823529411764,
        0.82352941176470595,
        0.90563725490196079,
    )
    assert_color(
        lut.get_color(2),
        0.86274509803921573,
        0.86274509803921573,
        0.86274509803921573,
    )
    assert_color(
        lut.get_color(5.99), Float64(last.r), Float64(last.g), Float64(last.b)
    )
    assert_color(
        lut.get_color(6), Float64(last.r), Float64(last.g), Float64(last.b)
    )
    assert_color(
        lut.get_color(9), Float64(last.r), Float64(last.g), Float64(last.b)
    )


def test_a_range_upside_down_gives_the_first_color() raises:
    """With the minimum above the maximum, three.js's clamp gives the
    minimum, and so the first sample."""
    var lut = Lut(RAINBOW, 4)
    lut.set_min(5)
    lut.set_max(1)
    assert_color(lut.get_color(3), 0, 0, 1)
    assert_color(lut.get_color(-7), 0, 0, 1)


def test_canvas_matches_three() raises:
    """The pixels three.js's `updateCanvas` draws."""
    assert_bytes(
        Lut(COOL_TO_WARM, 8).canvas_pixels(),
        [
            221,
            103,
            97,
            255,
            242,
            173,
            148,
            255,
            231,
            196,
            184,
            255,
            220,
            220,
            220,
            255,
            193,
            207,
            235,
            255,
            166,
            193,
            249,
            255,
            119,
            147,
            232,
            255,
            60,
            78,
            194,
            255,
        ],
    )
    assert_bytes(
        Lut(RAINBOW, 5).canvas_pixels(),
        [
            255,
            255,
            0,
            255,
            85,
            255,
            0,
            255,
            0,
            255,
            85,
            255,
            0,
            255,
            255,
            255,
            0,
            0,
            255,
            255,
        ],
    )
    assert_bytes(
        Lut(GRAYSCALE, 10).canvas_pixels(),
        [
            223,
            223,
            223,
            255,
            191,
            191,
            191,
            255,
            170,
            170,
            170,
            255,
            148,
            148,
            149,
            255,
            127,
            127,
            128,
            255,
            106,
            106,
            107,
            255,
            85,
            85,
            85,
            255,
            64,
            64,
            64,
            255,
            32,
            32,
            32,
            255,
            0,
            0,
            0,
            255,
        ],
    )


def test_one_step() raises:
    """One step holds the two ends."""
    var lut = Lut(GRAYSCALE, 1)
    assert_equal(len(lut.lut), 2)
    assert_color(lut.get_color(0.4), 0, 0, 0)
    assert_color(lut.get_color(0.5), 1, 1, 1)


def test_a_custom_map() raises:
    """A map of its own, three.js's `addColorMap`."""
    var stops: List[ColorStop] = [
        ColorStop(0, 0x000000),
        ColorStop(0.5, 0xFF0000),
        ColorStop(0.5, 0x00FF00),
        ColorStop(1, 0xFFFFFF),
    ]
    var lut = Lut(stops^, 4)
    assert_equal(len(lut.lut), 5)
    assert_color(lut.lut[1], 0.5, 0, 0)
    assert_color(lut.lut[2], 1, 0, 0)
    assert_color(lut.lut[3], 0.5, 1, 0.5)
    lut.set_color_map(BLACKBODY, 8)
    assert_equal(len(lut.map), 5)
    assert_equal(lut.map[1].hex, 0x780000)


def test_presets() raises:
    """Each preset has five stops, from zero to one."""
    for value in range(4):
        var stops = color_map(ColorMapName(value))
        assert_equal(len(stops), 5)
        assert_equal(stops[0].position, 0)
        assert_equal(stops[4].position, 1)
        check_color_map(stops)
    assert_true(GRAYSCALE.is_valid())
    assert_false(ColorMapName(4).is_valid())
    assert_false(ColorMapName(-1).is_valid())


def test_refusals() raises:
    """What three.js cannot give a color for is refused."""
    with assert_raises(contains="Not a color map"):
        _ = Lut(ColorMapName(4), 8)
    with assert_raises(contains="one step"):
        _ = Lut(RAINBOW, 0)
    var lut = Lut(RAINBOW, 8)
    with assert_raises(contains="finite"):
        lut.set_min(nan[DType.float64]())
    with assert_raises(contains="finite"):
        lut.set_max(inf[DType.float64]())
    with assert_raises(contains="not a number"):
        _ = lut.get_color(nan[DType.float64]())
    lut.set_max(0)
    with assert_raises(contains="width"):
        _ = lut.get_color(0)
    var short: List[ColorStop] = [ColorStop(0, 0)]
    with assert_raises(contains="two stops"):
        check_color_map(short)
    var late: List[ColorStop] = [ColorStop(0.1, 0), ColorStop(1, 0)]
    with assert_raises(contains="start at zero"):
        check_color_map(late)
    var early: List[ColorStop] = [ColorStop(0, 0), ColorStop(0.9, 0)]
    with assert_raises(contains="start at zero"):
        check_color_map(early)
    var backwards: List[ColorStop] = [
        ColorStop(0, 0),
        ColorStop(0.6, 0),
        ColorStop(0.4, 0),
        ColorStop(1, 0),
    ]
    with assert_raises(contains="go from zero"):
        check_color_map(backwards)
    var not_a_number: List[ColorStop] = [
        ColorStop(0, 0),
        ColorStop(nan[DType.float64](), 0),
        ColorStop(1, 0),
    ]
    with assert_raises(contains="go from zero"):
        check_color_map(not_a_number)
    var too_bright: List[ColorStop] = [ColorStop(0, 0), ColorStop(1, 0x1000000)]
    with assert_raises(contains="0xRRGGBB"):
        check_color_map(too_bright)
    var negative: List[ColorStop] = [ColorStop(0, -1), ColorStop(1, 0)]
    with assert_raises(contains="0xRRGGBB"):
        check_color_map(negative)
    with assert_raises(contains="two stops"):
        _ = Lut(short^, 8)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
