# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `renderers.clip`."""

from math.vector3 import Vector3
from render.framebuffer import FloatColor
from renderers.clip import ClipVertex, clip_depth
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = Float64(1e-5)
comptime NEAR = Float32(1.0)
# Far enough that the existing near-plane tests are unaffected by it.
comptime FAR = Float32(1000.0)


def at(x: Float32, y: Float32, z: Float32) -> ClipVertex:
    """Return a white vertex at the given camera-space position."""
    return ClipVertex(Vector3(x, y, z), FloatColor(1.0, 1.0, 1.0))


def coloured(z: Float32, value: Float32) -> ClipVertex:
    """Return a vertex at depth `z` whose red channel is `value`."""
    return ClipVertex(Vector3(0, 0, z), FloatColor(value, 0, 0))


def test_a_triangle_entirely_in_front_is_untouched() raises:
    var pieces = clip_depth(at(0, 0, -5), at(1, 0, -5), at(0, 1, -5), NEAR, FAR)
    assert_equal(len(pieces), 3)
    assert_equal(pieces[0].position.z, Float32(-5))


def test_a_triangle_entirely_behind_disappears() raises:
    var pieces = clip_depth(at(0, 0, 5), at(1, 0, 5), at(0, 1, 5), NEAR, FAR)
    assert_equal(len(pieces), 0)


def test_a_triangle_between_the_camera_and_the_near_plane_disappears() raises:
    # In front of the camera but nearer than the near plane.
    var pieces = clip_depth(
        at(0, 0, -0.5), at(1, 0, -0.5), at(0, 1, -0.5), NEAR, FAR
    )
    assert_equal(len(pieces), 0)


def test_one_corner_behind_leaves_a_quadrilateral() raises:
    # Cutting one corner off a triangle leaves four sides, so two triangles.
    var pieces = clip_depth(at(0, 0, -5), at(1, 0, -5), at(0, 1, 5), NEAR, FAR)
    assert_equal(len(pieces), 6)


def test_two_corners_behind_leave_one_triangle() raises:
    var pieces = clip_depth(at(0, 0, -5), at(1, 0, 5), at(0, 1, 5), NEAR, FAR)
    assert_equal(len(pieces), 3)


def test_every_new_corner_lands_exactly_on_the_near_plane() raises:
    var pieces = clip_depth(at(0, 0, -5), at(1, 0, 5), at(0, 1, 5), NEAR, FAR)
    var on_plane = 0
    for index in range(len(pieces)):
        if pieces[index].position.z > -Float32(5):
            assert_almost_equal(pieces[index].position.z, -NEAR, atol=TOLERANCE)
            on_plane += 1
    assert_equal(on_plane, 2)


def test_nothing_survives_behind_the_plane() raises:
    var pieces = clip_depth(at(0, 0, -5), at(1, 0, -5), at(0, 1, 5), NEAR, FAR)
    for index in range(len(pieces)):
        assert_true(pieces[index].position.z <= -NEAR + Float32(1e-5))


def test_a_corner_exactly_on_the_plane_counts_as_in_front() raises:
    var pieces = clip_depth(at(0, 0, -1), at(1, 0, -5), at(0, 1, -5), NEAR, FAR)
    assert_equal(len(pieces), 3)


def test_colour_is_carried_to_the_cut() raises:
    # Halfway along the edge in depth, so halfway in colour.
    var pieces = clip_depth(
        coloured(-3, 0),
        ClipVertex(Vector3(1, 0, 1), FloatColor(200, 0, 0)),
        ClipVertex(Vector3(0, 1, -3), FloatColor(0, 0, 0)),
        NEAR,
        FAR,
    )
    var found = False
    for index in range(len(pieces)):
        if pieces[index].position.z > -Float32(3):
            # Half of the way from 0 to 200 at the crossing.
            assert_almost_equal(
                pieces[index].color.r, Float32(100), atol=Float64(2)
            )
            found = True
    assert_true(found)


def test_position_is_interpolated_across_the_cut() raises:
    # From x = 0 at z = -3 to x = 4 at z = 1; the plane at z = -1 is halfway.
    var pieces = clip_depth(at(0, 0, -3), at(4, 0, 1), at(0, 1, -3), NEAR, FAR)
    var found = False
    for index in range(len(pieces)):
        if pieces[index].position.z > -Float32(3):
            assert_almost_equal(
                pieces[index].position.x, Float32(2), atol=TOLERANCE
            )
            found = True
    assert_true(found)


def test_a_near_plane_behind_the_camera_is_rejected() raises:
    with assert_raises():
        _ = clip_depth(at(0, 0, -5), at(1, 0, -5), at(0, 1, -5), 0.0, FAR)
    with assert_raises():
        _ = clip_depth(at(0, 0, -5), at(1, 0, -5), at(0, 1, -5), -1.0, FAR)


# --- the far plane ----------------------------------------------------------


def test_a_triangle_beyond_the_far_plane_disappears() raises:
    # The depth buffer cannot catch this one: it clears to infinity, and a
    # point past the far plane still projects to a finite depth, so it would
    # win the test and be drawn outside the frustum the camera promised.
    var pieces = clip_depth(
        at(0, 0, -50), at(1, 0, -50), at(0, 1, -50), NEAR, Float32(10)
    )
    assert_equal(len(pieces), 0)


def test_a_triangle_crossing_the_far_plane_keeps_only_the_near_part() raises:
    var pieces = clip_depth(
        at(0, 0, -5), at(1, 0, -5), at(0, 1, -50), NEAR, Float32(10)
    )
    assert_true(len(pieces) > 0)
    for index in range(len(pieces)):
        assert_true(pieces[index].position.z >= -Float32(10) - Float32(1e-5))


def test_a_corner_exactly_on_the_far_plane_counts_as_inside() raises:
    var pieces = clip_depth(
        at(0, 0, -10), at(1, 0, -5), at(0, 1, -5), NEAR, Float32(10)
    )
    assert_equal(len(pieces), 3)


def test_a_triangle_spanning_both_planes_is_cut_at_both() raises:
    # One corner nearer than near, one further than far: both ends come off
    # and every survivor sits between the planes.
    var pieces = clip_depth(
        at(0, 0, 5), at(1, 0, -5), at(0, 1, -50), NEAR, Float32(10)
    )
    assert_true(len(pieces) > 0)
    for index in range(len(pieces)):
        assert_true(pieces[index].position.z <= -NEAR + Float32(1e-5))
        assert_true(pieces[index].position.z >= -Float32(10) - Float32(1e-5))


def test_colour_is_carried_to_a_far_plane_cut() raises:
    # From red 0 at z = -5 to red 200 at z = -15; the plane at z = -10 is
    # halfway, so the new corner is halfway in colour too.
    var pieces = clip_depth(
        coloured(-5, 0),
        coloured(-15, 200),
        ClipVertex(Vector3(0, 1, -5), FloatColor(0, 0, 0)),
        NEAR,
        Float32(10),
    )
    var found = False
    for index in range(len(pieces)):
        if pieces[index].position.z < -Float32(5) - Float32(1e-5):
            assert_almost_equal(
                pieces[index].color.r, Float32(100), atol=Float64(2)
            )
            found = True
    assert_true(found)


def test_a_far_plane_not_beyond_the_near_one_is_rejected() raises:
    with assert_raises():
        _ = clip_depth(at(0, 0, -5), at(1, 0, -5), at(0, 1, -5), NEAR, NEAR)
    with assert_raises():
        _ = clip_depth(
            at(0, 0, -5), at(1, 0, -5), at(0, 1, -5), NEAR, Float32(0.5)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
