# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the velocity attachment, three.js's `VelocityNode`: what a
target keeps, reads back and resolves, and what the renderer writes when
the camera or an object moves between frames."""

from cameras.orthographic_camera import OrthographicCamera, centered
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from materials.material import BASIC, BLEND, Material
from math.vector2 import Vector2
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from postprocessing.composer import (
    MOTION_BLUR,
    Pass,
    EffectComposer,
    frame_outputs,
    motion_blur_pass,
    render_pass,
    ssr_pass,
)
from postprocessing.display_nodes import (
    DisplaySettings,
    check_display,
    motion_blur_light,
)
from render.rasterizer import fragment_velocity
from render.rect import Rect
from render.target import (
    FLOAT_TARGET,
    HALF_FLOAT_TARGET,
    OUTPUT_COLOR,
    OUTPUT_NORMAL,
    OUTPUT_VELOCITY,
    UNSIGNED_BYTE_TARGET,
    RenderTarget,
    TargetOutput,
)
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


comptime SIZE = 16


def moving() -> List[TargetOutput]:
    """Return the outputs of a target with a velocity attachment."""
    return [OUTPUT_COLOR, OUTPUT_VELOCITY]


# --- the attachment ----------------------------------------------------------


def test_a_write_keeps_its_velocity_and_a_blend_leaves_it() raises:
    var target = RenderTarget(2, 2, Color(0, 0, 0), FLOAT_TARGET, moving())
    assert_true(target.has_velocities())
    assert_false(target.has_normals())
    assert_equal(target.velocity_at(0, 0).x, 0)
    target.write(0, 0, FloatColor(1, 0, 0, 1), velocity=Vector2(0.5, -0.25))
    assert_equal(target.velocity_at(0, 0).x, 0.5)
    assert_equal(target.velocity_in(0).y, -0.25)
    target.blend(0, 0, FloatColor(0, 0, 1, 0.5))
    assert_equal(target.velocity_at(0, 0).x, 0.5)
    # A write with no velocity -- a line, a point -- leaves none.
    target.write(1, 0, FloatColor(1, 0, 0, 1), velocity=Vector2(1, 1))
    target.write(1, 0, FloatColor(1, 0, 0, 1))
    assert_equal(target.velocity_at(1, 0).x, 0)
    # A clear resets the velocities inside it and leaves the rest.
    target.write(0, 1, FloatColor(1, 0, 0, 1), velocity=Vector2(0, 2))
    target.clear_inside(Rect(0, 1, 1, 1), Color(0, 0, 0))
    assert_equal(target.velocity_at(0, 0).x, 0)
    assert_equal(target.velocity_at(0, 1).y, 2)
    # Clearing the depth alone keeps them.
    target.write(0, 0, FloatColor(1, 0, 0, 1), velocity=Vector2(3, 0))
    target.clear_inside(Rect(0, 0, 2, 2), Color(0, 0, 0), color=False)
    assert_equal(target.velocity_at(0, 0).x, 3)


def test_a_plain_target_has_no_velocity_attachment() raises:
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    assert_false(target.has_velocities())
    target.write(0, 0, FloatColor(1, 0, 0, 1), velocity=Vector2(1, 0))
    assert_equal(target.velocity_in(0).x, 0)
    with assert_raises(contains="no velocity attachment"):
        _ = target.velocity_at(0, 0)
    with assert_raises(contains="out of bounds"):
        _ = target.velocity_at(1, 0)


def test_the_velocity_attachment_reads_back_by_type() raises:
    var outputs: List[TargetOutput] = [
        OUTPUT_COLOR,
        OUTPUT_NORMAL,
        OUTPUT_VELOCITY,
    ]
    var exact = RenderTarget(2, 1, Color(0, 0, 0), FLOAT_TARGET, outputs)
    var bytes = RenderTarget(
        2, 1, Color(0, 0, 0), UNSIGNED_BYTE_TARGET, outputs
    )
    var half = RenderTarget(2, 1, Color(0, 0, 0), HALF_FLOAT_TARGET, outputs)
    var moved = Vector2(0.25, -0.5)
    exact.write(0, 0, FloatColor(1, 1, 1, 1), velocity=moved)
    bytes.write(0, 0, FloatColor(1, 1, 1, 1), velocity=moved)
    half.write(0, 0, FloatColor(1, 1, 1, 1), velocity=moved)
    var raw = exact.attachment(2)
    assert_equal(raw.get_pixel(0, 0)[0], 0.25)
    assert_equal(raw.get_pixel(0, 0)[1], -0.5)
    assert_equal(raw.get_pixel(0, 0)[2], 0)
    assert_equal(raw.get_pixel(0, 0)[3], 1)
    # A byte cannot be negative.
    assert_almost_equal(bytes.attachment(2).get_pixel(0, 0)[0], 64.0 / 255)
    assert_equal(bytes.attachment(2).get_pixel(0, 0)[1], 0)
    assert_equal(half.attachment(2).get_pixel(0, 0)[1], -0.5)
    assert_equal(exact.attachment_texture(2).width, 2)


def test_a_downsample_and_a_resolve_average_the_velocities() raises:
    var target = RenderTarget(4, 2, Color(0, 0, 0), FLOAT_TARGET, moving())
    target.write(0, 0, FloatColor(1, 1, 1, 1), velocity=Vector2(4, 0))
    target.write(1, 1, FloatColor(1, 1, 1, 1), velocity=Vector2(0, 8))
    var small = target.downsampled(2)
    assert_true(small.has_velocities())
    assert_equal(small.velocity_at(0, 0).x, 1)
    assert_equal(small.velocity_at(0, 0).y, 2)
    assert_equal(small.velocity_at(1, 0).x, 0)
    # A multisampled target starts its samples as its pixels, and
    # resolves them to their average.
    var sampled = RenderTarget(
        2, 2, Color(0, 0, 0), FLOAT_TARGET, moving(), samples=4
    )
    sampled.write(1, 1, FloatColor(1, 1, 1, 1), velocity=Vector2(2, 2))
    var buffer = sampled.multisample_buffer()
    assert_equal(buffer.velocity_at(3, 3).x, 2)
    buffer.write(2, 2, FloatColor(1, 1, 1, 1), velocity=Vector2(6, 6))
    sampled.resolve_samples(buffer, Rect.whole(2, 2))
    assert_equal(sampled.velocity_at(1, 1).x, 3)
    # A buffer without the attachment is refused.
    with assert_raises(contains="the target's outputs"):
        sampled.resolve_samples(
            RenderTarget(4, 4, Color(0, 0, 0), FLOAT_TARGET),
            Rect.whole(2, 2),
        )


def test_a_fragment_moves_by_the_difference_of_its_places() raises:
    # Now at (0.5, 0.25) in normalized device coordinates, at a w of one.
    var now = Vector3(0.5, 0.25, 1)
    # The last frame had the corners a quarter to the left, at a w of 2.
    var then = Vector3(0.5, 0.5, 2)
    var shares = SIMD[DType.float32, 4](0.25, 0.25, 0.5, 0)
    var moved = fragment_velocity(now, now, now, then, then, then, shares)
    assert_almost_equal(moved.x, 0.25)
    assert_almost_equal(moved.y, 0)
    # Corners with no place, either frame's, have not moved.
    var none = Vector3(0, 0, 0)
    var still = fragment_velocity(now, now, now, none, none, none, shares)
    assert_equal(still.x, 0)
    assert_equal(still.y, 0)
    still = fragment_velocity(none, none, none, then, then, then, shares)
    assert_equal(still.x, 0)


# --- the renderer -------------------------------------------------------------


def a_camera(x: Float32 = 0) raises -> OrthographicCamera:
    """Return a camera looking down -z at a two-meter square of world,
    from `x` along the x axis."""
    var camera = centered(
        Length(2.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    camera.place(Vector3(x, 0, 4), Vector3(x, 0, 0))
    return camera^


def a_square(mut assets: Assets, mut scene: Scene, x: Float32 = 0) raises:
    """Add a meter-wide square facing the camera at `x`."""
    var stand = Object3D()
    stand.set_position(x, 0, 0)
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                plane(Length(1.0, METER), Length(1.0, METER))
            ),
            assets.materials.add(Material(Color(255, 255, 255), kind=BASIC)),
            scene.add(stand^),
        )
    )
    scene.update()


def drawn(
    renderer: Renderer, scene: Scene, assets: Assets, camera: OrthographicCamera
) raises -> RenderTarget:
    """Return a velocity target the renderer drew the scene into."""
    var target = RenderTarget(
        SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET, moving()
    )
    renderer.render_into(target, scene, assets, camera)
    return target^


def move(mut scene: Scene, node: Int, x: Float32) raises:
    """Move a node along x and update the scene."""
    var id = scene.meshes[node].node
    var held = scene.get(id)
    held.set_position(x, 0, 0)
    scene.set(id, held^)
    scene.update()


def test_the_first_frame_has_not_moved() raises:
    var assets = Assets()
    var scene = Scene()
    a_square(assets, scene)
    var target = drawn(Renderer(SIZE, SIZE), scene, assets, a_camera())
    assert_equal(target.velocity_at(8, 8).x, 0)
    assert_equal(target.velocity_at(8, 8).y, 0)


def test_an_object_that_moved_leaves_its_velocity() raises:
    var assets = Assets()
    var scene = Scene()
    a_square(assets, scene)
    var renderer = Renderer(SIZE, SIZE)
    _ = drawn(renderer, scene, assets, a_camera())
    # A quarter meter right, on a two-meter view: a quarter of the way
    # across normalized device coordinates, which span two.
    move(scene, 0, 0.25)
    var target = drawn(renderer, scene, assets, a_camera())
    assert_almost_equal(target.velocity_at(9, 8).x, 0.25, atol=1e-5)
    assert_almost_equal(target.velocity_at(9, 8).y, 0, atol=1e-5)
    # Where no surface is, nothing moved.
    assert_equal(target.velocity_at(0, 0).x, 0)
    # Still, the next frame has not moved.
    target = drawn(renderer, scene, assets, a_camera())
    assert_almost_equal(target.velocity_at(9, 8).x, 0, atol=1e-6)


def test_a_camera_that_moved_moves_the_world_the_other_way() raises:
    var assets = Assets()
    var scene = Scene()
    a_square(assets, scene)
    var renderer = Renderer(SIZE, SIZE)
    _ = drawn(renderer, scene, assets, a_camera())
    var target = drawn(renderer, scene, assets, a_camera(0.25))
    assert_almost_equal(target.velocity_at(7, 8).x, -0.25, atol=1e-5)


def test_a_frame_without_the_attachment_keeps_no_velocity() raises:
    var assets = Assets()
    var scene = Scene()
    a_square(assets, scene)
    var renderer = Renderer(SIZE, SIZE)
    _ = drawn(renderer, scene, assets, a_camera())
    move(scene, 0, 0.25)
    # A plain frame between does not move the history on.
    var plain = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET)
    renderer.render_into(plain, scene, assets, a_camera())
    var target = drawn(renderer, scene, assets, a_camera())
    assert_almost_equal(target.velocity_at(9, 8).x, 0.25, atol=1e-5)
    # Nor does a frame prepared without one.
    move(scene, 0, 0.5)
    _ = renderer.prepare_frame(scene, assets, a_camera())
    target = drawn(renderer, scene, assets, a_camera())
    assert_almost_equal(target.velocity_at(10, 8).x, 0.25, atol=1e-5)


def test_a_draw_with_nothing_in_view_and_a_light_map_move_nothing() raises:
    var assets = Assets()
    var scene = Scene()
    a_square(assets, scene)
    # Turned away and single-sided: every triangle is culled.
    var turned = plane(Length(1.0, METER), Length(1.0, METER))
    turned.rotate_y(Angle(180.0, DEGREE))
    scene.add_mesh(
        Mesh(
            assets.geometries.add(turned^),
            assets.materials.add(Material(Color(255, 0, 0))),
            scene.meshes[0].node,
        )
    )
    var renderer = Renderer(SIZE, SIZE)
    _ = drawn(renderer, scene, assets, a_camera())
    move(scene, 0, 0.25)
    var target = drawn(renderer, scene, assets, a_camera())
    assert_almost_equal(target.velocity_at(9, 8).x, 0.25, atol=1e-5)
    # A light map's frame is not seen through the camera.
    renderer.uv_space_meshes = [0]
    move(scene, 0, 0.5)
    target = drawn(renderer, scene, assets, a_camera())
    assert_equal(target.velocity_at(8, 8).x, 0)


def test_a_velocity_projection_takes_the_camera_s_place() raises:
    # A jittered camera draws the square a pixel to the right each frame,
    # and the velocity is measured with the projection before the jitter,
    # as TRAA measures it: nothing moved.
    from postprocessing.antialiasing import JitteredCamera

    var assets = Assets()
    var scene = Scene()
    a_square(assets, scene)
    var renderer = Renderer(SIZE, SIZE)
    var camera = a_camera()
    renderer.set_velocity_projection(camera.projection_matrix())
    for frame in range(2):
        var jittered = JitteredCamera(
            camera, scene, Float32(frame) * -1, 0, SIZE, SIZE
        )
        var target = RenderTarget(
            SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET, moving()
        )
        renderer.render_into(target, scene, assets, jittered)
        assert_almost_equal(target.velocity_at(8, 8).x, 0, atol=1e-6)
    # Without it, the jitter is motion: a pixel is 2 / 16 across.
    renderer.set_velocity_projection(None)
    var jittered = JitteredCamera(camera, scene, -1, 0, SIZE, SIZE)
    _ = drawn(renderer, scene, assets, a_camera())
    var target = RenderTarget(
        SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET, moving()
    )
    renderer.render_into(target, scene, assets, jittered)
    assert_almost_equal(target.velocity_at(8, 8).x, 0.125, atol=1e-5)


def test_a_refused_frame_keeps_the_history() raises:
    var assets = Assets()
    var scene = Scene()
    a_square(assets, scene)
    var renderer = Renderer(SIZE, SIZE)
    _ = drawn(renderer, scene, assets, a_camera())
    # A mesh that names no material refuses the frame.
    scene.add_mesh(
        Mesh(
            scene.meshes[0].geometry,
            assets.materials.add(Material(Color(0, 0, 0))),
            scene.meshes[0].node,
        )
    )
    scene.meshes[1].material.value = 99
    with assert_raises(contains="No material"):
        _ = drawn(renderer, scene, assets, a_camera())
    _ = scene.meshes.pop()
    move(scene, 0, 0.25)
    var target = drawn(renderer, scene, assets, a_camera())
    assert_almost_equal(target.velocity_at(9, 8).x, 0.25, atol=1e-5)


# --- the motion blur -----------------------------------------------------------


def a_bright_column() raises -> RenderTarget:
    """Return a black frame with a velocity attachment and one bright
    column, every pixel moving two pixels to the right."""
    var frame = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET, moving())
    for y in range(SIZE):
        frame.colors[y * SIZE + 8] = FloatColor(3, 3, 3, 1)
    for slot in range(SIZE * SIZE):
        frame.velocities[slot] = Vector2(2 / Float32(SIZE), 0)
    return frame^


def test_a_motion_blur_spreads_light_along_the_velocity() raises:
    var frame = a_bright_column()
    var settings = DisplaySettings()
    # Three samples, as three.js takes them: the pixel, then the pixel
    # again, half the velocity ahead and the whole of it ahead, divided
    # by three. The alpha is summed so too, to four thirds, and the frame
    # holds the light scaled by it.
    settings.motion_samples = 3
    motion_blur_light(frame, settings)
    var third = Float32(4) / 3
    assert_almost_equal(frame.colors[4 * SIZE + 6].r, third, atol=1e-5)
    assert_almost_equal(frame.colors[4 * SIZE + 7].r, third, atol=1e-5)
    assert_almost_equal(frame.colors[4 * SIZE + 8].r, 2 * third, atol=1e-5)
    assert_equal(frame.colors[4 * SIZE + 9].r, 0)
    # An amount of zero takes the pixel seventeen times, over sixteen.
    frame = a_bright_column()
    settings.motion_samples = 16
    settings.motion_amount = 0
    motion_blur_light(frame, settings)
    var over = Float32(17) / 16
    assert_almost_equal(
        frame.colors[4 * SIZE + 8].r, 3 * over * over, atol=1e-5
    )
    # A velocity up the image reads the rows below, as three.js's does.
    frame = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET, moving())
    for x in range(SIZE):
        frame.colors[8 * SIZE + x] = FloatColor(3, 3, 3, 1)
    for slot in range(SIZE * SIZE):
        frame.velocities[slot] = Vector2(0, 2 / Float32(SIZE))
    settings.motion_samples = 3
    settings.motion_amount = 1
    motion_blur_light(frame, settings)
    assert_almost_equal(frame.colors[7 * SIZE + 4].r, third, atol=1e-5)
    assert_equal(frame.colors[9 * SIZE + 4].r, 0)
    # A frame with no velocities cannot be blurred by them.
    var plain = RenderTarget(SIZE, SIZE, Color(0, 0, 0))
    with assert_raises(contains="velocity attachment"):
        motion_blur_light(plain, settings)


def test_the_motion_blur_settings_and_the_frame_are_checked() raises:
    var bad = DisplaySettings()
    bad.motion_samples = 1
    with assert_raises(contains="at least two samples"):
        check_display(bad)
    bad = DisplaySettings()
    bad.motion_amount = Float32.MAX * 2
    with assert_raises(contains="finite"):
        check_display(bad)
    with assert_raises(contains="at least two samples"):
        _ = motion_blur_pass(1, 1)
    assert_true(motion_blur_pass().kind == MOTION_BLUR)
    # The frame keeps velocities while a motion blur is enabled.
    var steps: List[Pass] = [render_pass(), motion_blur_pass()]
    var outputs = frame_outputs(steps)
    assert_equal(len(outputs), 2)
    assert_true(outputs[1] == OUTPUT_VELOCITY)
    steps.append(ssr_pass())
    outputs = frame_outputs(steps)
    assert_equal(len(outputs), 3)
    assert_true(outputs[1] == OUTPUT_NORMAL)
    steps[1].enabled = False
    assert_equal(len(frame_outputs(steps)), 2)


def test_the_composer_blurs_a_moving_camera_s_frame() raises:
    var assets = Assets()
    var scene = Scene()
    a_square(assets, scene)
    var renderer = Renderer(SIZE, SIZE)
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(motion_blur_pass(1, 8))
    var first = composer.render(renderer, scene, assets, a_camera())
    var second = composer.render(renderer, scene, assets, a_camera(0.5))
    var still = EffectComposer()
    still.add_pass(render_pass())
    # The first frame has not moved, so it is sharp.
    var sharp = still.render(Renderer(SIZE, SIZE), scene, assets, a_camera())
    assert_equal(first.get_pixel(11, 8).r, sharp.get_pixel(11, 8).r)
    # Once the camera moved, the square's pixels by its right edge read
    # the dark beyond it.
    sharp = still.render(Renderer(SIZE, SIZE), scene, assets, a_camera(0.5))
    assert_true(second.get_pixel(7, 8).r < sharp.get_pixel(7, 8).r)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
