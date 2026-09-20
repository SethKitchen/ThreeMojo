# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `cameras.array_camera`, `cameras.stereo_camera`,
`PerspectiveCamera.view_shift` and `Renderer.render_array`."""

from cameras.array_camera import ArrayCamera
from cameras.perspective_camera import NO_SHIFT, PerspectiveCamera
from cameras.stereo_camera import (
    DEFAULT_EYE_SEPARATION,
    DEFAULT_FOCUS,
    StereoCamera,
)
from core.assets import Assets
from core.layers import Layers
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.rect import Rect
from render.target import RenderTarget
from renderers.renderer import Renderer
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-4)
comptime WIDTH = 32
comptime HEIGHT = 16


def a_camera(view_shift: Length = NO_SHIFT) raises -> PerspectiveCamera:
    """Return a square right-angle camera four meters back from the origin.

    Args:
        view_shift: How far its frustum is moved along x.

    Returns:
        The camera.

    Raises:
        Error: If its parameters are invalid.
    """
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE),
        1.0,
        Length(1.0, METER),
        Length(100.0, METER),
        view_shift=view_shift,
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def a_red_square() raises -> Tuple[Scene, Assets]:
    """Return a scene holding one red square at the origin, facing +z."""
    var assets = Assets()
    var square = assets.geometries.add(
        plane(Length(2.0, METER), Length(2.0, METER))
    )
    var red = assets.materials.add(Material(Color(255, 0, 0), kind=BASIC))
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    scene.add_mesh(Mesh(square, red, node))
    return (scene^, assets^)


# --- the view shift ---------------------------------------------------------


def test_a_camera_looks_straight_ahead_unless_shifted() raises:
    var camera = a_camera()
    assert_true(camera.view_shift == NO_SHIFT)
    # The origin, straight ahead, lands at the image's center.
    var middle = camera.project(Vector3(0, 0, 0), 100, 100)
    assert_almost_equal(Float64(middle.x), 50.0, atol=TOLERANCE)
    # Shifted by half the near plane's half-width, it lands a quarter of
    # the image to the left: the frustum looks to the right.
    var skewed = a_camera(Length(0.5, METER))
    var moved = skewed.project(Vector3(0, 0, 0), 100, 100)
    assert_almost_equal(Float64(moved.x), 25.0, atol=TOLERANCE)
    assert_almost_equal(Float64(moved.y), 50.0, atol=TOLERANCE)
    # And the other way.
    var other = a_camera(Length(-0.5, METER))
    assert_almost_equal(
        Float64(other.project(Vector3(0, 0, 0), 100, 100).x),
        75.0,
        atol=TOLERANCE,
    )


def test_a_view_shift_must_be_finite() raises:
    with assert_raises(contains="shift must be finite"):
        _ = a_camera(Length(nan[DType.float32](), METER))


# --- the array --------------------------------------------------------------


def test_an_array_holds_cameras_and_their_rectangles() raises:
    var array = ArrayCamera()
    assert_equal(array.count(), 0)
    array.add(a_camera(), Rect(0, 0, 16, 16))
    array.add(a_camera(), Rect(16, 0, 16, 16))
    assert_equal(array.count(), 2)
    assert_equal(array.viewports[1].x, 16)
    with assert_raises(contains="positive size"):
        array.add(a_camera(), Rect(0, 0, 0, 16))
    # The lists are open; one edited alone no longer pairs up.
    array.viewports.append(Rect(0, 0, 4, 4))
    with assert_raises(contains="one viewport per camera"):
        _ = array.count()
    var pair = a_red_square()
    var renderer = Renderer(WIDTH, HEIGHT)
    with assert_raises(contains="one viewport per camera"):
        _ = renderer.render_array(pair[0], pair[1], array)


def test_each_camera_draws_its_own_rectangle() raises:
    # The left camera looks at the square, the right one looks away: red
    # fills the left half and the background the right.
    var pair = a_red_square()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 40))
    var array = ArrayCamera()
    array.add(a_camera(), Rect(0, 0, WIDTH // 2, HEIGHT))
    var away = a_camera()
    away.place(Vector3(0, 0, 4), Vector3(0, 0, 8))
    array.add(away, Rect(WIDTH // 2, 0, WIDTH // 2, HEIGHT))
    var image = renderer.render_array(pair[0], pair[1], array)
    assert_true(image.get_pixel(8, 8).r > 128)
    assert_equal(image.get_pixel(24, 8).r, UInt8(0))
    assert_equal(image.get_pixel(24, 8).b, UInt8(40))
    # The renderer's own viewport, scissor and test are back as they were.
    assert_true(renderer.viewport == Rect.whole(WIDTH, HEIGHT))
    assert_false(renderer.scissor_test)
    var whole = renderer.render(pair[0], pair[1], a_camera())
    assert_true(whole.get_pixel(16, 8).r > 128)


def test_an_empty_array_draws_the_background_alone() raises:
    var pair = a_red_square()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 40))
    var image = renderer.render_array(pair[0], pair[1], ArrayCamera())
    assert_equal(image.get_pixel(8, 8).b, UInt8(40))
    # A target of the wrong size is refused even with no camera to draw,
    # whichever dimension is wrong.
    var small = RenderTarget(8, 8, Color(0, 0, 0))
    with assert_raises(contains="renderer's size"):
        renderer.render_array_into(small, pair[0], pair[1], ArrayCamera())
    var short = RenderTarget(WIDTH, 8, Color(0, 0, 0))
    with assert_raises(contains="renderer's size"):
        renderer.render_array_into(short, pair[0], pair[1], ArrayCamera())


def test_a_camera_refused_after_another_drew_puts_the_settings_back() raises:
    # The second camera rides a node the scene does not have, so it is
    # refused after the first has drawn its half: the renderer's own
    # viewport, scissor and test come back, and the first half stays.
    var pair = a_red_square()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 40))
    var array = ArrayCamera()
    array.add(a_camera(), Rect(0, 0, WIDTH // 2, HEIGHT))
    var stray = a_camera()
    stray.attach(NodeId(99))
    array.add(stray, Rect(WIDTH // 2, 0, WIDTH // 2, HEIGHT))
    var target = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0))
    with assert_raises():
        renderer.render_array_into(target, pair[0], pair[1], array)
    assert_true(target.shown(8, 8).r > 128)
    assert_equal(target.shown(24, 8).r, UInt8(0))
    assert_true(renderer.viewport == Rect.whole(WIDTH, HEIGHT))
    assert_true(renderer.scissor == Rect.whole(WIDTH, HEIGHT))
    assert_false(renderer.scissor_test)


def test_a_rectangle_outside_the_target_is_refused_before_drawing() raises:
    var pair = a_red_square()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 40))
    var array = ArrayCamera()
    array.add(a_camera(), Rect(0, 0, WIDTH // 2, HEIGHT))
    array.add(a_camera(), Rect(WIDTH // 2, 0, WIDTH, HEIGHT))
    var target = RenderTarget(WIDTH, HEIGHT, Color(0, 0, 0))
    with assert_raises(contains="inside the target"):
        renderer.render_array_into(target, pair[0], pair[1], array)
    # Nothing was drawn, not even the first camera's half.
    assert_equal(target.shown(8, 8).r, UInt8(0))
    # A target of another size is refused too, with the settings put back.
    var small = RenderTarget(8, 8, Color(0, 0, 0))
    var fine = ArrayCamera()
    fine.add(a_camera(), Rect(0, 0, 8, 8))
    with assert_raises(contains="renderer's size"):
        renderer.render_array_into(small, pair[0], pair[1], fine)
    assert_true(renderer.viewport == Rect.whole(WIDTH, HEIGHT))
    assert_true(renderer.scissor == Rect.whole(WIDTH, HEIGHT))
    assert_false(renderer.scissor_test)


# --- the stereo pair --------------------------------------------------------


def test_a_stereo_camera_takes_threejs_defaults() raises:
    var stereo = StereoCamera()
    assert_true(stereo.eye_separation == DEFAULT_EYE_SEPARATION)
    assert_true(stereo.focus == DEFAULT_FOCUS)
    assert_almost_equal(
        Float64(stereo.eye_separation.to(METER)), 0.064, atol=TOLERANCE
    )
    assert_almost_equal(Float64(stereo.focus.to(METER)), 10.0, atol=TOLERANCE)
    assert_equal(stereo.aspect, Float32(1))
    with assert_raises(contains="cannot be negative"):
        _ = StereoCamera(eye_separation=Length(-1.0, METER))
    with assert_raises(contains="in front of the camera"):
        _ = StereoCamera(focus=Length(0.0, METER))
    with assert_raises(contains="aspect must be positive"):
        _ = StereoCamera(aspect=0)
    with assert_raises(contains="cannot be negative"):
        _ = StereoCamera(eye_separation=Length(nan[DType.float32](), METER))
    with assert_raises(contains="in front of the camera"):
        _ = StereoCamera(focus=Length(nan[DType.float32](), METER))
    with assert_raises(contains="aspect must be positive"):
        _ = StereoCamera(aspect=nan[DType.float32]())


def test_settings_edited_after_construction_are_refused_by_update() raises:
    # The fields are open. A value the constructor refused is refused
    # again before an eye is placed, and the pair is left as it was.
    var scene = Scene()
    var stereo = StereoCamera(Length(0.2, METER), Length(4.0, METER))
    stereo.update(a_camera(), scene)
    stereo.focus = Length(-4.0, METER)
    with assert_raises(contains="in front of the camera"):
        stereo.update(a_camera(), scene)
    assert_almost_equal(
        Float64(stereo.left.view_shift.to(METER)), 0.025, atol=TOLERANCE
    )
    stereo.focus = Length(4.0, METER)
    stereo.eye_separation = Length(-0.2, METER)
    with assert_raises(contains="cannot be negative"):
        stereo.update(a_camera(), scene)
    stereo.eye_separation = Length(0.2, METER)
    stereo.aspect = 0
    with assert_raises(contains="aspect must be positive"):
        stereo.update(a_camera(), scene)
    assert_almost_equal(Float64(stereo.left.position.x), -0.1, atol=TOLERANCE)


def test_the_baseline_holds_a_thousand_meters_from_the_origin() raises:
    # A stereo scene lives within a few thousand meters of the origin:
    # there a Float32 steps in tenths of a millimeter, and the pair's
    # sixty-four millimeters survive to a part in a hundred. This pins
    # that promise; see the module docstring for what lies beyond it.
    var scene = Scene()
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(1000, 0, 4), Vector3(1000, 0, 0))
    var stereo = StereoCamera(focus=Length(4.0, METER))
    stereo.update(camera, scene)
    var baseline = stereo.right.position.x - stereo.left.position.x
    assert_almost_equal(Float64(baseline), 0.064, atol=0.00064)
    # And a point at the focus still lands on one column in both eyes.
    var focused = Vector3(1000, 0, 0)
    var left = stereo.left.project(focused, 2048, 2048)
    var right = stereo.right.project(focused, 2048, 2048)
    assert_almost_equal(Float64(left.x), Float64(right.x), atol=0.1)


def test_the_eyes_stand_either_side_of_the_camera_and_converge() raises:
    var scene = Scene()
    var stereo = StereoCamera(
        Length(0.2, METER), Length(4.0, METER), aspect=0.5
    )
    stereo.update(a_camera(), scene)
    # Each eye a tenth of a meter to its side, at the camera's height and
    # depth, looking the same way.
    assert_almost_equal(Float64(stereo.left.position.x), -0.1, atol=TOLERANCE)
    assert_almost_equal(Float64(stereo.right.position.x), 0.1, atol=TOLERANCE)
    assert_almost_equal(Float64(stereo.left.position.z), 4.0, atol=TOLERANCE)
    assert_almost_equal(Float64(stereo.left.target.z), 3.0, atol=TOLERANCE)
    assert_almost_equal(Float64(stereo.left.up.y), 1.0, atol=TOLERANCE)
    # The frustums skew toward each other by half the separation scaled
    # to the near plane: 0.1 * 1 / 4.
    assert_almost_equal(
        Float64(stereo.left.view_shift.to(METER)), 0.025, atol=TOLERANCE
    )
    assert_almost_equal(
        Float64(stereo.right.view_shift.to(METER)), -0.025, atol=TOLERANCE
    )
    assert_almost_equal(Float64(stereo.left.aspect), 0.5, atol=TOLERANCE)
    assert_almost_equal(
        Float64(stereo.left.fov.to(DEGREE)), 90.0, atol=TOLERANCE
    )
    # A point at the focus lands on the same column in both eyes; one
    # nearer lands further apart, which is the parallax.
    var focused = Vector3(0, 0, 0)
    var left = stereo.left.project(focused, 100, 100)
    var right = stereo.right.project(focused, 100, 100)
    assert_almost_equal(Float64(left.x), Float64(right.x), atol=TOLERANCE)
    var near = Vector3(0, 0, 2)
    var left_near = stereo.left.project(near, 100, 100)
    var right_near = stereo.right.project(near, 100, 100)
    assert_true(left_near.x > right_near.x + 1)


def test_the_eyes_follow_a_camera_riding_a_node() raises:
    var scene = Scene()
    var seat = Object3D()
    seat.set_position(0, 0, 4)
    seat.rotate_y(Angle(90.0, DEGREE))
    var seat_node = scene.add(seat^)
    scene.update()
    var camera = a_camera()
    camera.attach(seat_node)
    var hidden = Layers()
    hidden.set(2)
    camera.layers = hidden
    var stereo = StereoCamera(Length(0.2, METER))
    stereo.update(camera, scene)
    # Turned a quarter turn about y, the camera's x axis is the world's
    # -z: the eyes stand along z, and look along -x.
    assert_almost_equal(Float64(stereo.left.position.z), 4.1, atol=TOLERANCE)
    assert_almost_equal(Float64(stereo.right.position.z), 3.9, atol=TOLERANCE)
    assert_almost_equal(Float64(stereo.left.position.x), 0.0, atol=TOLERANCE)
    assert_almost_equal(Float64(stereo.left.target.x), -1.0, atol=TOLERANCE)
    assert_true(stereo.left.layers.test(hidden))
    assert_false(stereo.left.layers.test(Layers()))
    # A stale scene is refused, as the camera's own view is.
    scene.node(seat_node).set_position(1, 0, 4)
    with assert_raises():
        stereo.update(camera, scene)


def test_a_stereo_pair_renders_side_by_side_through_an_array() raises:
    var pair = a_red_square()
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 40))
    var stereo = StereoCamera(Length(0.5, METER), Length(4.0, METER), 0.5)
    stereo.update(a_camera(), pair[0])
    var array = ArrayCamera()
    array.add(stereo.left, Rect(0, 0, WIDTH // 2, HEIGHT))
    array.add(stereo.right, Rect(WIDTH // 2, 0, WIDTH // 2, HEIGHT))
    var image = renderer.render_array(pair[0], pair[1], array)
    # Both halves show the square in their middle.
    assert_true(image.get_pixel(8, 8).r > 128)
    assert_true(image.get_pixel(24, 8).r > 128)
    assert_equal(image.get_pixel(0, 0).b, UInt8(40))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
