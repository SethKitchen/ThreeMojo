# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `renderers.clip`."""

from math.vector3 import Vector3
from render.framebuffer import FloatColor
from renderers.clip import ClipVertex, clip_depth, clip_segment
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
        Vector3(0, 0, 1),
        0,
        0,
    )


def colored(z: Float32, value: Float32) -> ClipVertex:
    """Return a vertex at depth `z` whose red channel is `value`."""
    return ClipVertex(
        Vector3(0, 0, z), FloatColor(value, 0, 0), Vector3(0, 0, 1), 0, 0
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


def test_color_is_carried_to_the_cut() raises:
    # Halfway along the edge in depth, so halfway in color.
    var pieces = clip_depth(
        colored(-3, 0),
        ClipVertex(
            Vector3(1, 0, 1), FloatColor(200, 0, 0), Vector3(0, 0, 1), 0, 0
        ),
        ClipVertex(
            Vector3(0, 1, -3), FloatColor(0, 0, 0), Vector3(0, 0, 1), 0, 0
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


def test_a_near_plane_behind_the_camera_cuts_there() raises:
    # An orthographic camera may put its near plane behind itself, as
    # three.js allows; the clipper cuts at z = +1 as at any other plane.
    var pieces = clip_depth(at(0, 0, -5), at(1, 0, -5), at(0, 1, 5), -1.0, FAR)
    assert_true(len(pieces) > 0)
    for index in range(len(pieces)):
        assert_true(pieces[index].position.z <= Float32(1 + 1e-5))
    var kept = clip_segment(at(0, 0, 3), at(0, 0, -5), -1.0, FAR)
    assert_equal(len(kept), 2)
    assert_almost_equal(kept[0].position.z, Float32(1), atol=Float64(1e-5))


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


def test_color_is_carried_to_a_far_plane_cut() raises:
    # From red 0 at z = -5 to red 200 at z = -15; the plane at z = -10 is
    # halfway, so the new corner is halfway in color too.
    var pieces = clip_depth(
        colored(-5, 0),
        colored(-15, 200),
        ClipVertex(
            Vector3(0, 1, -5), FloatColor(0, 0, 0), Vector3(0, 0, 1), 0, 0
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
        Vector3(0, 0, 1),
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
            Vector3(0, 0, -0.5), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        ClipVertex(
            Vector3(1, 0, -2.0), FloatColor(1, 1, 1), Vector3(0, 0, 1), 1, 0
        ),
        ClipVertex(
            Vector3(0, 1, -2.0), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 1
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
            Vector3(0, 1, -5), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
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
            Vector3(1, 0, -5), FloatColor(1, 1, 1), Vector3(0, 0, 1), 1, 0
        ),
        ClipVertex(
            Vector3(0, 1, -5), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 1
        ),
        NEAR,
        FAR,
    )
    assert_equal(len(pieces), 3)
    assert_equal(pieces[0].u, Float32(0.25))
    assert_equal(pieces[0].v, Float32(0.75))
    assert_equal(pieces[1].u, Float32(1))
    assert_equal(pieces[2].v, Float32(1))


def test_a_cut_carries_the_normal_across() raises:
    # A triangle cut by the near plane keeps the shading of the part that
    # survived. Leaving the normal behind would relight the cut edge, which
    # is the same class of mistake as leaving the texture coordinates behind
    # and slides the lighting across the cut instead of the image.
    var near_end = ClipVertex(
        Vector3(0, 0, -0.5), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
    )
    var far_end = ClipVertex(
        Vector3(0, 0, -2.5), FloatColor(1, 1, 1), Vector3(0, 1, 0), 0, 0
    )
    var side = ClipVertex(
        Vector3(1, 0, -2.5), FloatColor(1, 1, 1), Vector3(0, 1, 0), 0, 0
    )
    var pieces = clip_depth(near_end, far_end, side, NEAR, FAR)
    assert_true(len(pieces) > 0, "the triangle was clipped away entirely")
    # The edge runs from z = -0.5 to z = -2.5 and the plane sits at z = -1,
    # a quarter of the way along it. So the cut normal is a quarter of the way
    # from (0, 0, 1) towards (0, 1, 0): y of 0.25 and z of 0.75. Not
    # renormalized here, because the fragment does that after interpolating
    # anyway.
    var found = False
    for index in range(len(pieces)):
        var corner = pieces[index]
        if corner.position.z > Float32(-1.01) and (
            corner.position.z < Float32(-0.99)
        ):
            assert_almost_equal(
                corner.normal.y, Float32(0.25), atol=Float64(1e-5)
            )
            assert_almost_equal(
                corner.normal.z, Float32(0.75), atol=Float64(1e-5)
            )
            found = True
    assert_true(found, "no corner landed on the near plane")


def test_a_cut_carries_the_emissive_across() raises:
    # The glowing corner is behind the near plane and the dark ones in
    # front; the crossing is halfway along the edge, so half the glow.
    var bright = ClipVertex(
        Vector3(0, 0, 1),
        FloatColor(1, 1, 1),
        Vector3(0, 0, 1),
        0,
        0,
        Vector3(0, 0, 0),
        FloatColor(0.8, 0.4, 0.2),
    )
    var pieces = clip_depth(
        bright,
        ClipVertex(
            Vector3(1, 0, -3), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        ClipVertex(
            Vector3(0, 1, -3), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
        ),
        NEAR,
        FAR,
    )
    var found = False
    for index in range(len(pieces)):
        if pieces[index].position.z == -NEAR:
            assert_almost_equal(
                pieces[index].emissive.r, Float32(0.4), atol=TOLERANCE
            )
            assert_almost_equal(
                pieces[index].emissive.g, Float32(0.2), atol=TOLERANCE
            )
            assert_almost_equal(
                pieces[index].emissive.b, Float32(0.1), atol=TOLERANCE
            )
            found = True
        else:
            # A corner that survives whole keeps its own, which is none.
            assert_equal(pieces[index].emissive.r, Float32(0))
    assert_true(found)


def test_a_cut_carries_the_world_position_across() raises:
    # A point light needs to know where the surface really is, and a cut
    # corner is somewhere between the two it was cut from.
    var near_end = ClipVertex(
        Vector3(0, 0, -0.5),
        FloatColor(1, 1, 1),
        Vector3(0, 0, 1),
        0,
        0,
        Vector3(4, 0, 0),
    )
    var far_end = ClipVertex(
        Vector3(0, 0, -2.5),
        FloatColor(1, 1, 1),
        Vector3(0, 0, 1),
        0,
        0,
        Vector3(0, 0, 8),
    )
    # The third corner shares the far end's world position, so both cut
    # corners land at the same place and one check covers them.
    var side = ClipVertex(
        Vector3(1, 0, -2.5),
        FloatColor(1, 1, 1),
        Vector3(0, 0, 1),
        0,
        0,
        Vector3(0, 0, 8),
    )
    var pieces = clip_depth(near_end, far_end, side, NEAR, FAR)
    var found = False
    for index in range(len(pieces)):
        var corner = pieces[index]
        if corner.position.z > Float32(-1.01) and (
            corner.position.z < Float32(-0.99)
        ):
            # A quarter of the way from (4, 0, 0) towards (0, 0, 8).
            assert_almost_equal(corner.world.x, Float32(3), atol=Float64(1e-5))
            assert_almost_equal(corner.world.z, Float32(2), atol=Float64(1e-5))
            found = True
    assert_true(found, "no corner landed on the near plane")
    # A corner built without a world position sits at the origin.
    var bare = ClipVertex(
        Vector3(1, 0, -2.5), FloatColor(1, 1, 1), Vector3(0, 0, 1), 0, 0
    )
    assert_equal(bare.world.x, Float32(0))
    assert_equal(bare.world.z, Float32(0))


def test_a_cut_carries_the_line_distance_across() raises:
    # A segment from half a meter in front of the camera to two and a
    # half, cut at the near plane a quarter of the way along: its
    # distance is a quarter of the way too, so a dashed line cut at the
    # near plane keeps its dashes where they were.
    var a = ClipVertex(
        Vector3(0, 0, -0.5),
        FloatColor(1, 1, 1),
        Vector3(0, 0, 1),
        0,
        0,
        line_distance=0,
    )
    var b = ClipVertex(
        Vector3(0, 0, -2.5),
        FloatColor(1, 1, 1),
        Vector3(0, 0, 1),
        0,
        0,
        line_distance=4,
    )
    var kept = clip_segment(a, b, NEAR, FAR)
    assert_equal(len(kept), 2)
    assert_almost_equal(
        Float64(kept[0].line_distance), Float64(1), atol=TOLERANCE
    )
    assert_almost_equal(
        Float64(kept[1].line_distance), Float64(4), atol=TOLERANCE
    )
    # A corner of a triangle has no line, and says so.
    assert_equal(at(0, 0, -2).line_distance, Float32(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
