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
    return ClipVertex(
        Vector3(x, y, z),
        FloatColor(1.0, 1.0, 1.0),
        FloatColor(1.0, 1.0, 1.0),
        0,
        0,
    )


def coloured(z: Float32, value: Float32) -> ClipVertex:
    """Return a vertex at depth `z` whose red channel is `value`."""
    return ClipVertex(
        Vector3(0, 0, z), FloatColor(value, 0, 0), FloatColor(value, 0, 0), 0, 0
    )


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
        ClipVertex(
            Vector3(1, 0, 1), FloatColor(200, 0, 0), FloatColor(200, 0, 0), 0, 0
        ),
        ClipVertex(
            Vector3(0, 1, -3), FloatColor(0, 0, 0), FloatColor(0, 0, 0), 0, 0
        ),
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
        _ = clip_depth(at(0, 0, -5), at(1, 0, -5), at(0, 1, -5), -1.0, FAR)


def test_a_near_plane_at_the_camera_itself_is_allowed() raises:
    # Cutting against two finite ordered planes works as well at z = 0 as
    # anywhere. What cannot survive z = 0 is the perspective *divide*, and
    # that is refused by `perspective` and `PerspectiveCamera`, not here — an
    # orthographic camera is entitled to a near plane of zero and three.js
    # allows one.
    var pieces = clip_depth(at(0, 0, -5), at(1, 0, -5), at(0, 1, -5), 0.0, FAR)
    assert_equal(len(pieces), 3)


def test_a_zero_near_plane_still_cuts_at_the_camera() raises:
    # And it is a real plane, not a disabled one: a corner in front of the
    # camera is removed like any other.
    var pieces = clip_depth(at(0, 0, -5), at(1, 0, -5), at(0, 1, 5), 0.0, FAR)
    assert_true(len(pieces) > 0)
    for index in range(len(pieces)):
        assert_true(pieces[index].position.z <= Float32(1e-5))


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
        ClipVertex(
            Vector3(0, 1, -5), FloatColor(0, 0, 0), FloatColor(0, 0, 0), 0, 0
        ),
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


# --- varyings across a cut --------------------------------------------------


def mapped(z: Float32, u: Float32, v: Float32) -> ClipVertex:
    """Return a white vertex at depth `z` carrying texture coordinates."""
    return ClipVertex(
        Vector3(0, 0, z),
        FloatColor(1.0, 1.0, 1.0),
        FloatColor(1.0, 1.0, 1.0),
        u,
        v,
    )


def test_texture_coordinates_are_carried_to_a_near_plane_cut() raises:
    # Every other clip test uses uv of zero, so the clipper would still pass
    # them all if a new corner silently lost its texture coordinates. The
    # crossing sits a third of the way along each cut edge:
    #     t = (a.z - plane) / (a.z - b.z) = (-0.5 + 1) / (-0.5 + 2) = 1/3
    var pieces = clip_depth(
        ClipVertex(
            Vector3(0, 0, -0.5), FloatColor(1, 1, 1), FloatColor(1, 1, 1), 0, 0
        ),
        ClipVertex(
            Vector3(1, 0, -2.0), FloatColor(1, 1, 1), FloatColor(1, 1, 1), 1, 0
        ),
        ClipVertex(
            Vector3(0, 1, -2.0), FloatColor(1, 1, 1), FloatColor(1, 1, 1), 0, 1
        ),
        NEAR,
        FAR,
    )
    assert_true(len(pieces) > 0)
    # The quad is fanned from its first corner, so a cut vertex can appear in
    # more than one triangle. Both must show up, and nothing else may.
    var saw_u = False
    var saw_v = False
    for index in range(len(pieces)):
        if pieces[index].position.z > -Float32(2) + Float32(1e-5):
            var u = pieces[index].u
            var v = pieces[index].v
            assert_true(u > 0 or v > 0, "a new corner lost its uv")
            if u > 0:
                # From the a->b edge, a third of the way along in u.
                assert_almost_equal(u, Float32(1) / 3, atol=TOLERANCE)
                assert_equal(v, Float32(0))
                saw_u = True
            else:
                # From the c->a edge, a third of the way back down in v.
                assert_almost_equal(v, Float32(1) / 3, atol=TOLERANCE)
                assert_equal(u, Float32(0))
                saw_v = True
    assert_true(saw_u, "the a->b crossing is missing")
    assert_true(saw_v, "the c->a crossing is missing")


def test_texture_coordinates_are_carried_to_a_far_plane_cut() raises:
    # From u = 0 at z = -5 to u = 1 at z = -15; the far plane at z = -10 is
    # halfway, so the new corner carries u = 0.5.
    var pieces = clip_depth(
        mapped(-5, 0, 0),
        mapped(-15, 1, 0),
        ClipVertex(
            Vector3(0, 1, -5), FloatColor(1, 1, 1), FloatColor(1, 1, 1), 0, 0
        ),
        NEAR,
        Float32(10),
    )
    var found = False
    for index in range(len(pieces)):
        if pieces[index].position.z < -Float32(5) - Float32(1e-5):
            assert_almost_equal(pieces[index].u, Float32(0.5), atol=TOLERANCE)
            found = True
    assert_true(found, "no corner landed on the far plane")


def test_a_triangle_that_survives_whole_keeps_its_own_coordinates() raises:
    # Nothing is cut, so the corners must come back untouched.
    var pieces = clip_depth(
        mapped(-5, 0.25, 0.75),
        ClipVertex(
            Vector3(1, 0, -5), FloatColor(1, 1, 1), FloatColor(1, 1, 1), 1, 0
        ),
        ClipVertex(
            Vector3(0, 1, -5), FloatColor(1, 1, 1), FloatColor(1, 1, 1), 0, 1
        ),
        NEAR,
        FAR,
    )
    assert_equal(len(pieces), 3)
    assert_equal(pieces[0].u, Float32(0.25))
    assert_equal(pieces[0].v, Float32(0.75))
    assert_equal(pieces[1].u, Float32(1))
    assert_equal(pieces[2].v, Float32(1))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
