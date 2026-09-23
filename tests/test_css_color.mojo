# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.css_color` and the `FloatColor` members that use it.

The expected numbers come from three.js 0.180's `Color`, run in node on
the same strings.
"""

from render.css_color import (
    COLOR_NAMES,
    COLOR_NAME_HEXES,
    color_name_hex,
    format_style,
    hex_string,
    parse_style,
)
from render.framebuffer import FloatColor
from render.srgb import LINEAR, SRGB, ColorSpace
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(2e-6)


def assert_color(got: FloatColor, r: Float64, g: Float64, b: Float64) raises:
    """Assert a color's three channels, within tolerance, and that it is
    opaque.

    Args:
        got: The color to check.
        r: Expected red, linear.
        g: Expected green, linear.
        b: Expected blue, linear.

    Raises:
        Error: If a channel differs.
    """
    assert_almost_equal(Float64(got.r), r, atol=TOLERANCE)
    assert_almost_equal(Float64(got.g), g, atol=TOLERANCE)
    assert_almost_equal(Float64(got.b), b, atol=TOLERANCE)
    assert_equal(got.a, Float32(1))


def check(
    style: String,
    r: Float64,
    g: Float64,
    b: Float64,
    css: String,
    hex: String,
    linear: String,
) raises:
    """Assert what three.js reads from a string and writes back.

    Args:
        style: The string to read.
        r: Expected red, linear.
        g: Expected green, linear.
        b: Expected blue, linear.
        css: Expected `getStyle()`.
        hex: Expected `getHexString()`.
        linear: Expected `getStyle(LinearSRGBColorSpace)`.

    Raises:
        Error: If anything differs.
    """
    var color = FloatColor(style=style)
    assert_color(color, r, g, b)
    assert_equal(color.style(), css)
    assert_equal(color.hex_string(), hex)
    assert_equal(color.style(LINEAR), linear)


def test_rgb() raises:
    check(
        "rgb(255,0,0)",
        1,
        0,
        0,
        "rgb(255,0,0)",
        "ff0000",
        "color(srgb-linear 1.000 0.000 0.000)",
    )
    check(
        "rgba(255, 128, 0, 0.5)",
        1,
        0.21586050010324415,
        0,
        "rgb(255,128,0)",
        "ff8000",
        "color(srgb-linear 1.000 0.216 0.000)",
    )
    check(
        "rgb(300,0,0)",
        1,
        0,
        0,
        "rgb(255,0,0)",
        "ff0000",
        "color(srgb-linear 1.000 0.000 0.000)",
    )
    check(
        "rgb( 10 , 20 , 30 )trail",
        0.0030352698352941175,
        0.0069954101845983935,
        0.012983032338510335,
        "rgb(10,20,30)",
        "0a141e",
        "color(srgb-linear 0.003 0.007 0.013)",
    )


def test_rgb_percent() raises:
    check(
        "rgb(100%,50%,0%)",
        1,
        0.2140411404715882,
        0,
        "rgb(255,128,0)",
        "ff8000",
        "color(srgb-linear 1.000 0.214 0.000)",
    )
    assert_color(FloatColor(style="rgba(200%, 0%, 0%, .25)"), 1, 0, 0)


def test_hsl() raises:
    check(
        "hsl(120,50%,50%)",
        0.05087608816465111,
        0.5225215539594343,
        0.050876088164650994,
        "rgb(64,191,64)",
        "40bf40",
        "color(srgb-linear 0.051 0.523 0.051)",
    )
    check(
        "hsla(240, 100%, 25.5%, 0.3)",
        0,
        0,
        0.22341399351416436,
        "rgb(0,0,130)",
        "000082",
        "color(srgb-linear 0.000 0.000 0.223)",
    )
    check(
        "hsl(.5,20%,30%)",
        0.10653922394175404,
        0.04734718935909914,
        0.04696420068244409,
        "rgb(92,61,61)",
        "5c3d3d",
        "color(srgb-linear 0.107 0.047 0.047)",
    )


def test_hex() raises:
    check(
        "#f80",
        1,
        0.24620132669705552,
        0,
        "rgb(255,136,0)",
        "ff8800",
        "color(srgb-linear 1.000 0.246 0.000)",
    )
    check(
        "#12ab9C",
        0.0060488330203860696,
        0.407240211891531,
        0.33245153633549385,
        "rgb(18,171,156)",
        "12ab9c",
        "color(srgb-linear 0.006 0.407 0.332)",
    )


def test_names() raises:
    check(
        "RebeccaPurple",
        0.13286832154414627,
        0.033104766565152086,
        0.31854677811435356,
        "rgb(102,51,153)",
        "663399",
        "color(srgb-linear 0.133 0.033 0.319)",
    )
    assert_equal(len(materialize[COLOR_NAMES]()), 148)
    assert_equal(materialize[COLOR_NAME_HEXES]()[0], 0xF0F8FF)
    assert_equal(color_name_hex("yellowgreen").value(), 0x9ACD32)
    assert_false(Bool(color_name_hex("transparent")))


def test_linear_space() raises:
    assert_color(parse_style("#336699", LINEAR), 0.2, 0.4, 0.6)
    assert_color(parse_style("#fff", LINEAR), 1, 1, 1)
    assert_color(parse_style("rgb(51,102,153)", LINEAR), 0.2, 0.4, 0.6)
    assert_color(parse_style("hsl(0,0%,50%)", LINEAR), 0.5, 0.5, 0.5)
    with assert_raises():
        _ = parse_style("#336699", ColorSpace(9))


def test_out_of_range_style() raises:
    var over = FloatColor(1.5, -0.02, 0.5)
    assert_equal(format_style(over), "rgb(305,-66,188)")
    assert_equal(
        format_style(over, LINEAR), "color(srgb-linear 1.500 -0.020 0.500)"
    )
    assert_equal(hex_string(FloatColor(0, 0, 0)), "000000")
    with assert_raises():
        _ = format_style(over, ColorSpace(9))
    # A tiny negative keeps its sign, as toFixed writes it.
    assert_equal(
        format_style(FloatColor(-0.0001, 0, 0), LINEAR),
        "color(srgb-linear -0.000 0.000 0.000)",
    )


def test_refuses_what_three_js_ignores() raises:
    var bad: List[String] = [
        "",
        "#",
        "#ff",
        "#ff00",
        "#ggg",
        "#1-2",
        "notacolor",
        "RGB(1,2,3)",
        "rgb (1,2,3)",
        "rgb(1,2,3",
        "cmyk(1,2,3,4)",
        "rgb(1,2)",
        "rgb(1,2,3,)",
        "rgb(1,2,3,4,5)",
        "rgb(1.5,2,3)",
        "rgb(a,2,3)",
        "rgb(1,2,3%)",
        "rgb(1%,2%,3)",
        "rgb(1%,2,3%)",
        "rgb(1 2 3)",
        "hsl(120,50,50%)",
        "hsl(120,50%,50)",
        "hsl(1.,50%,50%)",
        "hsl(x,50%,50%)",
        "hsl(120 50% 50%)",
        "hsl(120,50% 50%)",
        "hsla(120,50%,50%,.)",
        "hsl(120,50%,50%) ",
        "(1,2,3)",
    ]
    var ok = 0
    for index in range(len(bad)):
        try:
            _ = parse_style(bad[index])
        except:
            ok += 1
    # "hsl(120,50%,50%) " is read: text after the parenthesis is ignored.
    assert_equal(ok, len(bad) - 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
