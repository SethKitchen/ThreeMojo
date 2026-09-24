# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `helpers.view`, three.js's `ViewHelper`.

The hits and the turns were calculated by three.js 0.180, by node: a
`Raycaster` from the helper's `OrthographicCamera` against six `Sprite`s
turned against a camera at (3, 4, 5) looking at the origin, and the steps
of `prepareAnimationData` and `update` for that camera.
"""

from controls.camera_frame import CameraFrame
from helpers.view import (
    NEGATIVE_X,
    NEGATIVE_Y,
    NEGATIVE_Z,
    POSITIVE_X,
    POSITIVE_Y,
    POSITIVE_Z,
    VIEW_HELPER_DIM,
    ViewAxis,
    ViewHelper,
    axis_direction,
    axis_turn,
    disk_image,
)
from math.quaternion import Quaternion
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor, Framebuffer
from render.target import RenderTarget
from render.tonemap import NO_TONE_MAPPING
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Duration, SECOND

comptime TOLERANCE = Float64(1e-5)
comptime WIDTH = 400
comptime HEIGHT = 300


def frame_at(x: Float32, y: Float32, z: Float32) raises -> CameraFrame:
    """Return a camera at a point looking at the origin, +y up."""
    return CameraFrame(Vector3(x, y, z), Vector3(0, 0, 0), Vector3(0, 1, 0))


def assert_vector(v: Vector3, x: Float64, y: Float64, z: Float64) raises:
    """Assert a vector's components."""
    assert_almost_equal(Float64(v.x), x, atol=TOLERANCE)
    assert_almost_equal(Float64(v.y), y, atol=TOLERANCE)
    assert_almost_equal(Float64(v.z), z, atol=TOLERANCE)


def assert_turned(camera: CameraFrame, turn: Quaternion) raises:
    """Assert a camera's axes are those a rotation gives."""
    var right = turn.rotate(Vector3(1, 0, 0))
    var above = turn.rotate(Vector3(0, 1, 0))
    var back = turn.rotate(Vector3(0, 0, 1))
    assert_vector(
        camera.right, Float64(right.x), Float64(right.y), Float64(right.z)
    )
    assert_vector(
        camera.above, Float64(above.x), Float64(above.y), Float64(above.z)
    )
    assert_vector(
        camera.back, Float64(back.x), Float64(back.y), Float64(back.z)
    )


def test_each_axis_has_a_direction_and_a_turn() raises:
    assert_vector(axis_direction(POSITIVE_X), 1, 0, 0)
    assert_vector(axis_direction(POSITIVE_Y), 0, 1, 0)
    assert_vector(axis_direction(POSITIVE_Z), 0, 0, 1)
    assert_vector(axis_direction(NEGATIVE_X), -1, 0, 0)
    assert_vector(axis_direction(NEGATIVE_Y), 0, -1, 0)
    assert_vector(axis_direction(NEGATIVE_Z), 0, 0, -1)
    # A camera turned so looks along -axis, at the center from the axis.
    for index in range(6):
        var axis = ViewAxis(index)
        var ahead = axis_turn(axis).rotate(Vector3(0, 0, -1))
        var direction = axis_direction(axis)
        assert_vector(
            ahead,
            Float64(-direction.x),
            Float64(-direction.y),
            Float64(-direction.z),
        )
    assert_true(axis_turn(POSITIVE_Z) == Quaternion.identity())
    assert_false(ViewAxis(6).is_valid())
    assert_false(ViewAxis(-1).is_valid())
    with assert_raises(contains="none of the six"):
        _ = axis_direction(ViewAxis(6))
    with assert_raises(contains="none of the six"):
        _ = axis_turn(ViewAxis(-1))


def test_a_disk_is_a_filled_circle() raises:
    var disk = disk_image(Color(0x44, 0x88, 0xFF))
    assert_equal(disk.width, 64)
    assert_equal(disk.height, 64)
    var center = disk.texel(32, 32)
    assert_equal(center.b, 0xFF)
    assert_equal(center.a, 255)
    var corner = disk.texel(0, 0)
    assert_equal(corner.a, 0)
    assert_equal(corner.r, 0)
    # Radius fourteen: a texel across the edge is partly covered.
    var edge = disk.texel(42, 41)
    assert_true(edge.a > 0 and edge.a < 255)
    assert_equal(edge.g, 0x88)


def test_the_helper_holds_three_sticks_and_six_disks() raises:
    var helper = ViewHelper()
    assert_equal(len(helper.scene.meshes), 3)
    assert_equal(len(helper.scene.sprites), 6)
    assert_false(helper.animating)
    assert_vector(helper.center, 0, 0, 0)


def test_a_click_finds_three_s_disk() raises:
    var helper = ViewHelper()
    var camera = frame_at(3, 4, 5)
    var corner = Float32(VIEW_HELPER_DIM // 2)
    # The middle of the helper falls between the disks for this camera.
    assert_false(
        Bool(
            helper.axis_at(
                WIDTH - corner, HEIGHT - corner, WIDTH, HEIGHT, camera
            )
        )
    )
    var hit = helper.axis_at(
        WIDTH - corner + 20, HEIGHT - corner - 20, WIDTH, HEIGHT, camera
    )
    assert_true(hit.value() == NEGATIVE_Z)
    assert_false(Bool(helper.axis_at(390, 290, WIDTH, HEIGHT, camera)))
    assert_false(Bool(helper.axis_at(100, 100, WIDTH, HEIGHT, camera)))


def test_a_click_takes_the_nearest_disk() raises:
    var helper = ViewHelper()
    var corner = Float32(VIEW_HELPER_DIM // 2)
    # Seen from behind, -z is nearer than +z, and three.js takes it.
    var behind = helper.axis_at(
        WIDTH - corner, HEIGHT - corner, WIDTH, HEIGHT, frame_at(0, 0, -5)
    )
    assert_true(behind.value() == NEGATIVE_Z)
    var front = helper.axis_at(
        WIDTH - corner, HEIGHT - corner, WIDTH, HEIGHT, frame_at(0, 0, 5)
    )
    assert_true(front.value() == POSITIVE_Z)
    with assert_raises(contains="size"):
        _ = helper.axis_at(0, 0, 0, HEIGHT, frame_at(0, 0, 5))
    with assert_raises(contains="size"):
        _ = helper.axis_at(0, 0, WIDTH, 0, frame_at(0, 0, 5))


def test_a_click_starts_one_turn_at_a_time() raises:
    var helper = ViewHelper()
    var camera = frame_at(3, 4, 5)
    var corner = Float32(VIEW_HELPER_DIM // 2)
    assert_false(
        helper.handle_click(
            WIDTH - corner, HEIGHT - corner, WIDTH, HEIGHT, camera
        )
    )
    assert_false(helper.animating)
    assert_true(
        helper.handle_click(
            WIDTH - corner + 20, HEIGHT - corner - 20, WIDTH, HEIGHT, camera
        )
    )
    assert_true(helper.animating)
    # A second click while turning is not taken.
    assert_false(
        helper.handle_click(
            WIDTH - corner + 20, HEIGHT - corner - 20, WIDTH, HEIGHT, camera
        )
    )


def test_a_turn_toward_x_matches_three() raises:
    var helper = ViewHelper()
    var camera = frame_at(3, 4, 5)
    helper.turn_toward(POSITIVE_X, camera)
    assert_true(helper.animating)
    helper.update(Duration(0.05, SECOND), camera)
    assert_vector(
        camera.position, 4.757584644606877, 3.046011108449319, 4.252905439414829
    )
    assert_turned(
        camera,
        Quaternion(
            -0.21513012623876238,
            0.39114345346554924,
            0.05958759534546944,
            0.8928466531697831,
        ),
    )
    assert_true(helper.animating)
    helper.update(Duration(0.05, SECOND), camera)
    assert_vector(
        camera.position,
        6.097122682480992,
        1.9475815284504252,
        3.005332125541952,
    )
    helper.update(Duration(1.0, SECOND), camera)
    assert_vector(camera.position, 7.0710678118654755, 0, 0)
    assert_turned(
        camera, Quaternion(0, 0.7071067811865475, 0, 0.7071067811865476)
    )
    assert_false(helper.animating)
    # A turn toward where the camera already looks has arrived at once.
    var front = frame_at(0, 0, 5)
    helper.turn_toward(POSITIVE_Z, front)
    helper.update(Duration(0.1, SECOND), front)
    assert_vector(front.position, 0, 0, 5)
    assert_false(helper.animating)


def test_a_turn_toward_minus_y_matches_three() raises:
    var helper = ViewHelper()
    var camera = frame_at(3, 4, 5)
    helper.turn_toward(NEGATIVE_Y, camera)
    helper.update(Duration(0.1, SECOND), camera)
    assert_vector(
        camera.position,
        2.818739929003079,
        -0.06092009906871468,
        6.484673773920566,
    )
    helper.update(Duration(1.0, SECOND), camera)
    assert_vector(camera.position, 0, -7.071067776510136, 0.0007071067776506214)
    assert_turned(
        camera, Quaternion(0.7071067811865475, 0, 0, 0.7071067811865476)
    )
    assert_false(helper.animating)


def test_a_turn_refuses_a_bad_axis_or_time() raises:
    var helper = ViewHelper()
    var camera = frame_at(3, 4, 5)
    with assert_raises(contains="none of the six"):
        helper.turn_toward(ViewAxis(7), camera)
    assert_false(helper.animating)
    helper.turn_toward(POSITIVE_Y, camera)
    with assert_raises(contains="negative time"):
        helper.update(Duration(-0.1, SECOND), camera)


def image_of(target: RenderTarget) raises -> Framebuffer:
    """Resolve a target with no tone curve."""
    return target.resolve(1, NO_TONE_MAPPING, 1)


def test_the_helper_is_drawn_over_the_corner() raises:
    var helper = ViewHelper()
    var background = Color(200, 180, 160)
    var target = RenderTarget(200, 150, background)
    helper.render(target, frame_at(0, 0, 5))
    var image = image_of(target)
    # Away from the corner the image is as it was.
    var away = image.get_pixel(10, 10)
    assert_equal(away.r, background.r)
    # The +z disk faces the camera in the middle of the corner.
    var middle = image.get_pixel(200 - 64, 150 - 64)
    assert_true(abs(Int(middle.r) - 0x44) <= 2)
    assert_true(abs(Int(middle.g) - 0x88) <= 2)
    assert_true(abs(Int(middle.b) - 0xFF) <= 2)
    # The -x disk is black at a fifth of its opacity, blended over the
    # image: a fifth of the light is taken away.
    var faint = image.get_pixel(200 - 128 + 32, 150 - 64)
    var expected = FloatColor(srgb=background)
    var kept = FloatColor(
        expected.r * 0.8, expected.g * 0.8, expected.b * 0.8
    ).encode()
    assert_true(abs(Int(faint.r) - Int(kept.r)) <= 1)
    assert_true(abs(Int(faint.b) - Int(kept.b)) <= 1)


def test_a_small_target_gets_the_part_that_fits() raises:
    var camera = frame_at(3, 4, 5)
    var whole = RenderTarget(200, 200, Color(0, 0, 0))
    var first = ViewHelper()
    first.render(whole, camera)
    var full = image_of(whole)
    var helper = ViewHelper()
    var narrow = RenderTarget(100, 200, Color(0, 0, 0))
    helper.render(narrow, camera)
    var short = RenderTarget(200, 100, Color(0, 0, 0))
    helper.render(short, camera)
    var tiny = RenderTarget(40, 40, Color(0, 0, 0))
    helper.render(tiny, camera, 2)
    # Each gets the helper's bottom right corner, as the big target does.
    var cut = image_of(tiny)
    var tall = image_of(narrow)
    var wide = image_of(short)
    for y in range(40):
        for x in range(40):
            assert_equal(
                cut.get_pixel(x, y).r, full.get_pixel(160 + x, 160 + y).r
            )
    for y in range(200):
        for x in range(100):
            assert_equal(tall.get_pixel(x, y).g, full.get_pixel(100 + x, y).g)
    for y in range(100):
        for x in range(200):
            assert_equal(wide.get_pixel(x, y).b, full.get_pixel(x, 100 + y).b)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
