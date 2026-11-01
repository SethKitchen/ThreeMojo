# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village game's compass: the way the camera looks, and the places
that matter."""

from extensions.village.compass import (
    COMPASS_SHARE,
    CompassMark,
    _wrap,
    bearing,
    clock_text,
    draw_compass,
)
from extensions.village.hud import GOLD_TEXT, Rgb
from math.vector3 import Vector3
from render.framebuffer import Framebuffer
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import DEGREE, RADIAN, Angle


def _frame() raises -> Framebuffer:
    """Return a black frame of 400 by 240 pixels."""
    return Framebuffer(400, 240, List[UInt8](length=400 * 240 * 4, fill=0))


def _red(frame: Framebuffer, x: Int, y: Int) -> Int:
    """Return a pixel's red."""
    return Int(frame.pixels[(y * frame.width + x) * 4])


def test_a_bearing_is_the_turn_from_the_camera_s_way() raises:
    var origin = Vector3(1, 0, 1)
    var look = Angle(0.0, RADIAN)
    # Ahead, along minus z, to the left, along minus x, and behind.
    assert_almost_equal(bearing(origin, Vector3(1, 0, -5), look), 0, atol=1e-6)
    assert_almost_equal(
        bearing(origin, Vector3(-5, 0, 1), look), Float32(pi / 2), atol=1e-6
    )
    assert_almost_equal(
        bearing(origin, Vector3(7, 0, 1), look), -Float32(pi / 2), atol=1e-6
    )
    # A turn past a half turn is wrapped either way.
    assert_almost_equal(_wrap(4), Float32(4 - 2 * pi), atol=1e-5)
    assert_almost_equal(_wrap(-4), Float32(2 * pi - 4), atol=1e-5)
    var turned = Angle(170.0, DEGREE)
    var b = bearing(origin, Vector3(1, 0, -5), turned)
    assert_almost_equal(b, Float32(-170.0 * pi / 180), atol=1e-5)
    var back = Angle(-170.0, DEGREE)
    assert_almost_equal(
        bearing(origin, Vector3(1, 0, -5), back),
        Float32(170.0 * pi / 180),
        atol=1e-5,
    )


def test_a_clock_reads_twelve_hours() raises:
    assert_equal(clock_text(14), "2:00 PM")
    assert_equal(clock_text(0), "12:00 AM")
    assert_equal(clock_text(12.5), "12:30 PM")
    assert_equal(clock_text(9.0 + 5.0 / 60.0), "9:05 AM")


def test_the_compass_points_to_its_marks() raises:
    var frame = _frame()
    var red = Rgb(255, 0, 0)
    var marks: List[CompassMark] = [
        CompassMark(Vector3(0, 0, -10), red),
        # Behind: past the strip's end, at its end.
        CompassMark(Vector3(-0.1, 0, 10), GOLD_TEXT),
    ]
    draw_compass(
        frame, Vector3(0, 0, 0), Angle(0.0, RADIAN), marks, "2:00 PM CLEAR"
    )
    # The mark ahead stands in the middle of the strip, over the north.
    var at = (10 * 400 + 200) * 4
    assert_equal(Int(frame.pixels[at]), 255)
    assert_equal(Int(frame.pixels[at + 1]), 0)
    # The mark behind stands at the strip's left end, half as bright.
    var half = Int(400 * COMPASS_SHARE / 2)
    assert_true(_red(frame, 200 - half + 1, 10) > 100)
    # The caption and the letters show; nothing shows below the caption.
    var lit = 0
    for x in range(400):
        if _red(frame, x, 20) > 100:
            lit += 1
    assert_true(lit > 0)
    assert_equal(_red(frame, 10, 200), 0)
    # With no marks and no caption, only the strip shows.
    var plain = _frame()
    draw_compass(
        plain,
        Vector3(0, 0, 0),
        Angle(90.0, DEGREE),
        List[CompassMark](),
        String(),
    )
    assert_equal(_red(plain, 200, 30), 0)
    # Dropped under a bar, the strip stands lower.
    var low = _frame()
    draw_compass(
        low,
        Vector3(0, 0, 0),
        Angle(0.0, RADIAN),
        marks,
        String(),
        40,
    )
    assert_equal(_red(low, 200, 10), 0)
    assert_equal(_red(low, 200, 50), 255)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
