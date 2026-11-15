# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The hydrophobic moment of amphipathic helices, and helical wheels.

`assets/amphipathic/amphipathic_expected.txt` holds the values of the
Python package peptides for four peptides. See
`assets/amphipathic/make_amphipathic.py`.
"""

from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from extensions.molecule.amphipathic import (
    MAX_WHEEL,
    eisenberg_hydrophobicity,
    helical_wheel,
    hydrophobic_moment,
    sequence_hydrophobicity,
    window_moment,
)
from render.framebuffer import Color, Framebuffer
from std.math import cos, floor, inf, nan, sin, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle64, DEGREE64


def _degrees(value: Float64) -> Angle64:
    return Angle64(value, DEGREE64)


def _close(a: Float64, b: Float64, tolerance: Float64) raises:
    assert_almost_equal(a, b, atol=tolerance * abs(b), rtol=0)


def _pixel(
    image: Framebuffer, x: Float64, y: Float64
) -> Tuple[UInt8, UInt8, UInt8]:
    var at = (Int(floor(y + 0.5)) * image.width + Int(floor(x + 0.5))) * 4
    return (image.pixels[at], image.pixels[at + 1], image.pixels[at + 2])


def _bytes(color: Rgba) raises -> Tuple[UInt8, UInt8, UInt8]:
    var probe = Framebuffer(1, 1, Color(0, 0, 0))
    draw_line(probe, 0, 0, 0, 0, color)
    return (probe.pixels[0], probe.pixels[1], probe.pixels[2])


def test_against_peptides() raises:
    var text = open("assets/amphipathic/amphipathic_expected.txt", "r").read()
    var checked = 0
    for line in text.splitlines():
        var parts = line.split(" ")
        var row = List[Float64]()
        for at in range(1, len(parts)):
            row.append(atof(String(parts[at])))
        var values = sequence_hydrophobicity(String(parts[0]))
        var whole = hydrophobic_moment(values, _degrees(100.0))
        _close(whole.mean, row[0], 1e-13)
        _close(whole.moment, row[1], 1e-13)
        assert_almost_equal(whole.direction.to(DEGREE64), row[2], atol=1e-11)
        assert_equal(whole.start, 0)
        assert_equal(whole.length, len(values))
        var window = window_moment(values, _degrees(100.0), 11)
        _close(window.moment, row[3], 1e-13)
        assert_equal(window.start, Int(row[4]))
        assert_equal(window.length, 11)
        var strand = hydrophobic_moment(values, _degrees(160.0))
        _close(strand.moment, row[5], 1e-12)
        checked += 1
    assert_equal(checked, 4)


def test_by_hand() raises:
    var isoleucine = eisenberg_hydrophobicity("I")
    assert_true(isoleucine[0])
    assert_equal(isoleucine[1], 1.38)
    assert_equal(eisenberg_hydrophobicity("R")[1], -2.53)
    assert_false(eisenberg_hydrophobicity("X")[0])
    assert_false(eisenberg_hydrophobicity("II")[0])
    assert_false(eisenberg_hydrophobicity("")[0])
    # One residue has its own value as its moment.
    var one = hydrophobic_moment([-0.5], _degrees(100.0))
    assert_equal(one.moment, 0.5)
    _close(one.direction.to(DEGREE64), 180.0, 1e-15)
    # Two equal residues opposite each other cancel.
    var opposite = hydrophobic_moment([1.0, 1.0], _degrees(180.0))
    assert_almost_equal(opposite.moment, 0.0, atol=1e-16)
    # Two faces of a turn of four: the moment points between the first two.
    var faces = hydrophobic_moment([1.0, 1.0, -1.0, -1.0], _degrees(90.0))
    _close(faces.moment, sqrt(8.0) / 4.0, 1e-15)
    _close(faces.direction.to(DEGREE64), 45.0, 1e-14)
    assert_equal(faces.mean, 0)
    # A window of one residue finds the first residue of largest size.
    var single = window_moment([0.5, -2.0, 2.0, 1.0], _degrees(100.0), 1)
    assert_equal(single.moment, 2.0)
    assert_equal(single.start, 1)
    # A window past the end takes the whole sequence.
    var whole = window_moment([0.5, -2.0], _degrees(100.0), 30)
    assert_equal(whole.length, 2)
    assert_equal(whole.start, 0)


def test_wheel() raises:
    var values = sequence_hydrophobicity("LKKLLKLLKKLLKLLKKLLKL")
    var wheel = helical_wheel(values, _degrees(100.0), 200)
    assert_equal(wheel.image.width, 200)
    assert_equal(len(wheel.xs), 21)
    # The first residue sits straight up, 12 percent of the side out.
    assert_equal(wheel.xs[0], 99.5)
    assert_equal(wheel.ys[0], 99.5 - 24.0)
    var turns = 20.0 * 100.0 / 360.0
    _close(wheel.radius, (0.47 * 200.0 - 24.0) / (1.0 + 2.0 * turns), 1e-15)
    # Leucine is orange and lysine blue, at the center of each disc.
    var leucine = _pixel(wheel.image, wheel.xs[0], wheel.ys[0])
    var lysine = _pixel(wheel.image, wheel.xs[1], wheel.ys[1])
    assert_true(leucine[0] > leucine[2])
    assert_true(lysine[2] > lysine[0])
    # The arrow leaves the center along the moment.
    var moment = hydrophobic_moment(values, _degrees(100.0))
    var d = moment.direction.to(DEGREE64) * 3.141592653589793 / 180.0
    var dark = _bytes(Rgba(0.24, 0.24, 0.26, 1))
    var near = _pixel(wheel.image, 99.5 + 6.0 * sin(d), 99.5 - 6.0 * cos(d))
    assert_equal(near[0], dark[0])
    # One residue on the smallest image draws no joining line.
    var lone = helical_wheel([2.0], _degrees(100.0), 64)
    assert_equal(len(lone.xs), 1)
    var orange = _pixel(lone.image, lone.xs[0], lone.ys[0])
    assert_equal(orange[0], _bytes(Rgba(0.95, 0.55, 0.1, 1))[0])


def test_errors() raises:
    with assert_raises(contains="one residue or more"):
        _ = sequence_hydrophobicity("")
    with assert_raises(contains="twenty one-letter codes"):
        _ = sequence_hydrophobicity("AXB")
    with assert_raises(contains="one residue or more"):
        _ = hydrophobic_moment(List[Float64](), _degrees(100.0))
    with assert_raises(contains="finite"):
        _ = hydrophobic_moment([1.0, nan[DType.float64]()], _degrees(100.0))
    with assert_raises(contains="finite"):
        _ = hydrophobic_moment([inf[DType.float64]()], _degrees(100.0))
    var angles: List[Float64] = [0.0, 360.0, -10.0]
    for a in angles:
        with assert_raises(contains="between 0 and 360"):
            _ = window_moment([1.0], _degrees(a), 3)
    with assert_raises(contains="one residue or more"):
        _ = window_moment([1.0], _degrees(100.0), 0)
    var many = List[Float64](length=MAX_WHEEL + 1, fill=0.5)
    with assert_raises(contains="100 residues"):
        _ = helical_wheel(many, _degrees(100.0), 200)
    with assert_raises(contains="64 to 4096"):
        _ = helical_wheel([1.0], _degrees(100.0), 63)
    with assert_raises(contains="64 to 4096"):
        _ = helical_wheel([1.0], _degrees(100.0), 4097)
    with assert_raises(contains="between 0 and 360"):
        _ = helical_wheel([1.0], _degrees(400.0), 100)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
