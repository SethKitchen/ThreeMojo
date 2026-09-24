# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `loaders.ies`.

`assets/ies/fixture.json` is a digest of what three.js 0.180's
`IESLoader` gives for `assets/ies/quadrant.ies` and `assets/ies/full.ies`
in node, for each of its three types: every 37th value, the sum of all
of them, and how many are NaN.
"""

from loaders.ies import (
    IES_FLOAT,
    IES_HALF_FLOAT,
    IES_UNSIGNED_BYTE,
    IesLamp,
    IesType,
    ies_byte,
    ies_texture,
    ies_values,
    parse_ies,
    read_ies,
    to_half_float,
)
from loaders.json import JsonDocument, parse_json
from render.exr import half_to_float
from std.math import isnan, nan
from std.pathlib import Path
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)


def near(got: Float64, want: Float64, tolerance: Float64 = 1e-6) raises:
    """Assert two numbers agree within a relative tolerance."""
    var scale = max(Float64(1), abs(want))
    if not (abs(got - want) <= tolerance * scale):
        raise Error("got " + String(got) + ", want " + String(want))


def typed(values: List[Float64], kind: String) -> List[Float64]:
    """Return the values as three.js's typed array holds them."""
    var out = List[Float64]()
    for v in values:
        if kind == "byte":
            out.append(Float64(ies_byte(v)))
        elif kind == "half":
            out.append(0 if isnan(v) else Float64(to_half_float(v)))
        else:
            out.append(Float64(Float32(v)))
    return out^


def check(file: String) raises:
    """Compare one file's digest with three.js's."""
    var values = ies_values(read_ies("assets/ies/" + file))
    var doc = parse_json(Path("assets/ies/fixture.json").read_text())
    var want = doc.get(doc.root(), file)
    for kind in ["byte", "half", "float"]:
        var w = doc.get(want, kind)
        var got = typed(values, kind)
        assert_equal(len(got), doc.integer(doc.get(w, "length")))
        var sum = Float64(0)
        var nans = 0
        for v in got:
            if isnan(v):
                nans += 1
            else:
                sum += v
        assert_equal(nans, doc.integer(doc.get(w, "nans")))
        near(sum, doc.number(doc.get(w, "sum")), 1e-9)
        var sample = doc.get(w, "sample")
        for i in range(doc.length(sample)):
            var cell = doc.at(sample, i)
            if doc.is_null(cell):
                assert_true(isnan(got[i * 37]))
            else:
                near(got[i * 37], doc.number(cell))


def test_the_fixtures_match_three_js() raises:
    check("quadrant.ies")
    check("full.ies")
    check("backward.ies")
    check("fraction.ies")


def test_the_lamp() raises:
    var lamp = read_ies("assets/ies/quadrant.ies")
    near(lamp.lamp_to_lum_geometry, 1)
    assert_equal(len(lamp.tilt_angles), 5)
    near(lamp.tilt_factors[4], 0.8)
    near(lamp.multiplier, 2.5)
    assert_equal(lamp.num_ver_angles, 7)
    assert_equal(lamp.num_hor_angles, 2)
    near(lamp.input_watts, 60)
    near(lamp.candela[1][0], 1)
    near(lamp.count, 1)
    near(lamp.lumens, 1000)
    near(lamp.gonio_type, 1)
    near(lamp.units, 2)
    near(lamp.width, 0.3)
    near(lamp.length, 0.3)
    near(lamp.height, 0.1)
    near(lamp.ball_factor, 1)
    near(lamp.blp_factor, 1)
    var full = read_ies("assets/ies/full.ies")
    assert_equal(len(full.tilt_angles), 0)
    near(full.candela[1][4], 0)


def test_textures() raises:
    var lamp = read_ies("assets/ies/full.ies")
    var bytes = ies_texture(lamp, IES_UNSIGNED_BYTE)
    assert_equal(bytes.width, 180)
    assert_equal(bytes.height, 360)
    assert_equal(Int(bytes.pixels[0]), 255)
    var halves = ies_texture(lamp)
    assert_equal(halves.data[0], 1)
    var floats = ies_texture(read_ies("assets/ies/quadrant.ies"), IES_FLOAT)
    assert_equal(floats.data[4 * 180 * 359], 0)
    with assert_raises(contains="not valid"):
        _ = ies_texture(lamp, IesType(3))
    assert_false(IesType(-1).is_valid())
    assert_equal(ies_byte(-0.0347222238779068), 248)
    assert_equal(ies_byte(2), 255)
    # Halves: zero, a tiny value, a subnormal, a normal one, one past the
    # range and a negative one.
    assert_equal(to_half_float(0), 0)
    assert_equal(to_half_float(1e-10), 0)
    assert_equal(to_half_float(-1e-10), 0x8000)
    assert_equal(half_to_float(to_half_float(2.0**-20)), Float32(2.0**-20))
    assert_equal(to_half_float(1), 0x3C00)
    assert_equal(to_half_float(1e6), 0x7BFF)
    assert_equal(to_half_float(-2), 0xC000)
    assert_equal(to_half_float(-1e6), 0xFBFF)
    assert_equal(to_half_float(nan[DType.float64]()), 0x7E00)


def test_refusals() raises:
    with assert_raises(contains="ends early"):
        _ = parse_ies("IESNA\nno tilt\n")
    var head = String("TILT=NONE\n1 1 1 2 1 1 1 0 0 0\n1 1 1\n")
    with assert_raises(contains="more numbers"):
        _ = parse_ies(head + "0 90 180\n")
    with assert_raises(contains="is not a number"):
        _ = parse_ies(head + "0 x\n")
    with assert_raises(contains="is not a number"):
        _ = parse_ies(head + "0\tinf\n")
    with assert_raises(contains="is not a number"):
        _ = parse_ies(head + "0 1e999\n")
    with assert_raises(contains="vertical angles is not a whole number"):
        _ = parse_ies("TILT=NONE\n1 1 1 2.5 1 1 1 0 0 0\n1 1 1\n")
    with assert_raises(contains="horizontal angles is not a whole number"):
        _ = parse_ies("TILT=NONE\n1 1 1 2 -1 1 1 0 0 0\n1 1 1\n")
    with assert_raises(contains="tilt angles is not a whole number"):
        _ = parse_ies("TILT=INCLUDE\n1\n-2\n")
    with assert_raises(contains="no horizontal angle"):
        _ = ies_values(IesLamp())
    # A tilt file three.js does not read, a lamp of one vertical angle,
    # and one of zero candela.
    var single = parse_ies(
        "TILT=lamp.tlt\n1 1 1 1 1 1 1 0 0 0\n1 1 1\n0\n0\n5\n"
    )
    var values = ies_values(single)
    assert_equal(values[0], 0)
    var dark = parse_ies(
        "TILT=NONE\n1 1 1 2 1 1 1 0 0 0\n1 1 1\n0 90\n0\n0 0\n"
    )
    assert_equal(dark.candela[0][0], 0)
    with assert_raises():
        _ = read_ies("assets/ies/missing.ies")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
