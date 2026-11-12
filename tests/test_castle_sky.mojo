# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the sky of a picture: the gradient, the glow of the sun, the
cumulus, and the painting of the pixels where nothing else was drawn."""

from cameras.perspective_camera import PerspectiveCamera
from extensions.castle.sky import cloud_at, paint_sky, sky_color
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from std.math import cos, pi, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


def test_the_sky_deepens_from_the_horizon_to_the_zenith() raises:
    var horizon = sky_color(0.0, 0.0)
    var middle = sky_color(pi / 4.0, 0.0)
    var zenith = sky_color(pi / 2.0, 0.0)
    assert_true(horizon[0] > middle[0])
    assert_true(middle[0] > zenith[0])
    assert_true(horizon[2] > zenith[2])
    # Below the horizon and beyond the zenith the ends hold.
    assert_equal(sky_color(-1.0, 0.0)[0], horizon[0])
    assert_equal(sky_color(3.0, 0.0)[0], zenith[0])


def test_the_glow_of_the_sun_brightens_the_sky_up_to_white() raises:
    var plain = sky_color(0.5, 0.0)
    var glowing = sky_color(0.5, 0.1)
    assert_true(glowing[0] > plain[0])
    assert_true(glowing[1] > plain[1])
    var full = sky_color(0.0, 1.0)
    assert_equal(full[0], 255.0)
    assert_equal(full[1], 255.0)
    assert_equal(full[2], 255.0)


def _cover(
    coverage: Float64, sun_east: Float64, sun_north: Float64
) raises -> Int:
    """Count the rays of a fan of directions that meet a cloud, and check
    each answer is a color and an opacity."""
    var met = 0
    for azimuth in range(24):
        for elevation in range(10):
            var a = 2.0 * pi * Float64(azimuth) / 24.0
            var e = (15.0 + 7.0 * Float64(elevation)) * pi / 180.0
            var cloud = cloud_at(
                cos(e) * cos(a),
                cos(e) * sin(a),
                sin(e),
                coverage,
                3,
                sun_east,
                sun_north,
            )
            assert_true(cloud[0] >= 0.0 and cloud[0] <= 255.0)
            assert_true(cloud[1] >= 0.0 and cloud[1] <= 255.0)
            assert_true(cloud[2] >= 0.0 and cloud[2] <= 255.0)
            assert_true(cloud[3] >= 0.0 and cloud[3] <= 1.0)
            if cloud[3] > 0.0:
                met += 1
    return met


def test_more_cover_meets_more_cloud() raises:
    var clear = _cover(0.0, 1.0, 0.0)
    var broken = _cover(0.5, 1.0, 0.0)
    var overcast = _cover(1.0, 1.0, 0.0)
    assert_true(overcast > broken)
    assert_true(broken > clear)
    assert_true(overcast > 40)
    # The sun straight overhead has no heading, and the clouds still come.
    assert_true(_cover(1.0, 0.0, 0.0) > 40)


def test_the_lowest_sky_is_clear() raises:
    # Two degrees over the horizon and lower, the layer is out of reach.
    var low = cloud_at(1.0, 0.0, 0.01, 1.0, 3, 1.0, 0.0)
    assert_equal(low[3], 0.0)
    var cloud_free = cloud_at(0.0, 0.0, 1.0, 0.0, 3, 1.0, 0.0)
    assert_equal(cloud_free[3], 0.0)


def _camera() raises -> PerspectiveCamera:
    """Return a camera that looks at the horizon from above the ground."""
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 2, 0), Vector3(0, 2, -10))
    return camera^


def test_the_sky_is_painted_where_nothing_was_drawn() raises:
    var image = Framebuffer(24, 24, Color(1, 2, 3))
    var painted = paint_sky(image, _camera(), 0.5, 5, 0.0, 1.0, 0.0)
    assert_equal(painted, 24 * 24)
    var top = image.get_pixel(12, 0)
    var bottom = image.get_pixel(12, 23)
    assert_true(Int(top.r) != 1 or Int(top.g) != 2)
    assert_true(Int(bottom.b) > 100)
    # The zenith is deeper than the horizon.
    assert_true(top.r <= bottom.r)


def test_a_pixel_that_was_drawn_keeps_its_color() raises:
    var image = Framebuffer(24, 24, Color(1, 2, 3))
    for column in range(24):
        image.depth[5 * 24 + column] = 0.5
    var painted = paint_sky(image, _camera(), 0.5, 5, 0.3, 0.9, -0.3)
    assert_equal(painted, 24 * 24 - 24)
    var kept = image.get_pixel(7, 5)
    assert_equal(Int(kept.r), 1)
    assert_equal(Int(kept.g), 2)
    assert_equal(Int(kept.b), 3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
