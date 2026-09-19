# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.rect`, the scissor on `render.target`, and the
viewport and scissor on `renderers.renderer`."""

from cameras.orthographic_camera import centered
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.geometry_store import GeometryId
from core.object3d import NodeId, Object3D
from materials.material import MaterialId
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from objects.line import Line, STRIP
from materials.material import BASIC, BLEND, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor, Framebuffer
from render.rasterizer import SHADE_UV
from render.rect import Rect
from render.target import RenderTarget
from render.tonemap import ACES_FILMIC_TONE_MAPPING, NO_TONE_MAPPING
from renderers.renderer import Renderer
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime TOLERANCE = Float64(1e-5)
comptime WIDTH = 32
comptime HEIGHT = 24
comptime BACKGROUND = Color(0, 0, 0)
comptime RED = Color(255, 0, 0)


def a_camera() raises -> PerspectiveCamera:
    """Return a camera looking at the origin from along +z."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def a_cube_scene(mut assets: Assets) raises -> Scene:
    """Return a scene with one red, unlit cube at the origin."""
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.update()
    var block = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(RED, kind=BASIC))
    scene.add_mesh(Mesh(block, paint, node))
    return scene^


def a_renderer() raises -> Renderer:
    """Return a renderer of the test size with a black background."""
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(BACKGROUND)
    return renderer^


def red_pixels(image: Framebuffer, rect: Rect) raises -> Int:
    """Return how many pixels inside `rect` are red."""
    var count = 0
    for y in range(image.height):
        for x in range(image.width):
            if rect.contains_pixel(x, y, image.height):
                if image.get_pixel(x, y).r > 128:
                    count += 1
    return count


# --- Rect --------------------------------------------------------------------


def test_a_rect_covers_the_whole_image_by_default() raises:
    var whole = Rect.whole(8, 6)
    assert_equal(whole.x, 0)
    assert_equal(whole.y, 0)
    assert_equal(whole.width, 8)
    assert_equal(whole.height, 6)
    assert_true(whole.is_valid())
    assert_true(whole.fits(8, 6))
    assert_equal(whole.top(6), 0)


def test_a_rect_needs_a_size_and_a_scissor_needs_to_fit() raises:
    assert_false(Rect(0, 0, 0, 6).is_valid())
    assert_false(Rect(0, 0, 8, -1).is_valid())
    # A negative corner is a rectangle, and one hanging off the image.
    assert_true(Rect(-2, -2, 4, 4).is_valid())
    assert_false(Rect(-2, -2, 4, 4).fits(8, 6))
    assert_false(Rect(6, 0, 4, 6).fits(8, 6))
    assert_false(Rect(0, 4, 8, 4).fits(8, 6))
    assert_false(Rect(0, 0, 0, 6).fits(8, 6))
    assert_true(Rect(2, 1, 4, 4).fits(8, 6))
    assert_true(Rect(4, 2, 4, 4).fits(8, 6))


def test_a_rect_counts_up_from_the_bottom() raises:
    # A two-row rectangle at the bottom of a six-row image is rows 4 and
    # 5 from the top, and its top edge is row 4.
    var bottom = Rect(0, 0, 8, 2)
    assert_equal(bottom.top(6), 4)
    assert_true(bottom.contains_pixel(0, 5, 6))
    assert_true(bottom.contains_pixel(7, 4, 6))
    assert_false(bottom.contains_pixel(0, 3, 6))
    assert_false(bottom.contains_pixel(8, 5, 6))
    assert_false(bottom.contains_pixel(-1, 5, 6))
    # And a rectangle reaching above the image has a negative top.
    assert_equal(Rect(0, 4, 8, 4).top(6), -2)
    assert_true(Rect(0, 4, 8, 4).contains_pixel(3, 0, 6))
    assert_false(Rect(0, 4, 8, 4).contains_pixel(3, 2, 6))


# --- the target --------------------------------------------------------------


def test_a_target_scissor_must_fit() raises:
    var target = RenderTarget(8, 6, BACKGROUND)
    with assert_raises(contains="inside the target"):
        target.set_scissor(Rect(4, 0, 8, 6))
    with assert_raises(contains="inside the target"):
        target.clear_inside(Rect(0, 0, 0, 6), BACKGROUND)


def test_a_target_ignores_what_falls_outside_its_scissor() raises:
    # The scissor keeps the right half. A write, a blend, a depth test and
    # a claim on the left half all leave the pixel as it was, and the
    # same four on the right half take.
    var target = RenderTarget(8, 6, BACKGROUND)
    target.set_scissor(Rect(4, 0, 4, 6))
    var white = FloatColor(1, 1, 1, 1)
    target.write(1, 1, white)
    target.blend(1, 2, FloatColor(1, 1, 1, 0.5))
    assert_false(target.test_depth(1, 3, 0.5))
    assert_false(target.depth_passes(1, 3, 0.5))
    target.claim_depth(1, 4, 0.5)
    assert_equal(target.color_at(1, 1).r, Float32(0))
    assert_equal(target.color_at(1, 2).r, Float32(0))
    assert_equal(target.depth_at(1, 3), inf[DType.float32]())
    assert_equal(target.depth_at(1, 4), inf[DType.float32]())
    target.write(5, 1, white)
    target.blend(5, 2, FloatColor(1, 1, 1, 0.5))
    assert_true(target.depth_passes(5, 3, 0.5))
    assert_true(target.test_depth(5, 3, 0.5))
    target.claim_depth(5, 4, 0.5)
    assert_equal(target.color_at(5, 1).r, Float32(1))
    assert_almost_equal(target.color_at(5, 2).r, Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(target.depth_at(5, 3), Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(target.depth_at(5, 4), Float32(0.5), atol=TOLERANCE)
    # A coordinate off the target is still an error, scissor or not.
    with assert_raises():
        target.write(9, 1, white)
    with assert_raises():
        _ = target.depth_passes(1, 9, 0.5)


def test_clearing_inside_a_rectangle_leaves_the_rest() raises:
    var target = RenderTarget(8, 6, BACKGROUND)
    var white = FloatColor(1, 1, 1, 1)
    for y in range(6):
        for x in range(8):
            target.write(x, y, white, True)
            _ = target.test_depth(x, y, 0.25)
    # The bottom two rows, cleared to blue.
    target.clear_inside(Rect(0, 0, 8, 2), Color(0, 0, 255))
    assert_equal(target.color_at(3, 5).r, Float32(0))
    assert_equal(target.color_at(3, 5).b, Float32(1))
    assert_equal(target.depth_at(3, 5), inf[DType.float32]())
    assert_false(target.is_data(3, 5))
    assert_equal(target.color_at(3, 3).r, Float32(1))
    assert_almost_equal(target.depth_at(3, 3), Float32(0.25), atol=TOLERANCE)
    assert_true(target.is_data(3, 3))


# --- the renderer ------------------------------------------------------------


def test_a_renderer_starts_with_the_whole_target_and_no_scissor() raises:
    var renderer = a_renderer()
    assert_true(renderer.viewport == Rect.whole(WIDTH, HEIGHT))
    assert_true(renderer.scissor == Rect.whole(WIDTH, HEIGHT))
    assert_false(renderer.scissor_test)


def test_a_viewport_needs_a_size_and_a_scissor_must_fit() raises:
    var renderer = a_renderer()
    with assert_raises(contains="positive width and height"):
        renderer.set_viewport(Rect(0, 0, 0, HEIGHT))
    with assert_raises(contains="inside the target"):
        renderer.set_scissor(Rect(WIDTH // 2, 0, WIDTH, HEIGHT))
    # A viewport hanging off the target is allowed.
    renderer.set_viewport(Rect(-WIDTH // 2, 0, WIDTH, HEIGHT))
    assert_equal(renderer.viewport.x, -WIDTH // 2)


def test_a_viewport_puts_the_image_where_it_says() raises:
    # The cube fills the middle of the whole image. In a viewport on the
    # left half it lands in the left half, squeezed to half its width,
    # and the right half is untouched.
    var assets = Assets()
    var scene = a_cube_scene(assets)
    var renderer = a_renderer()
    var whole = renderer.render(scene, assets, a_camera())
    var left = Rect(0, 0, WIDTH // 2, HEIGHT)
    var right = Rect(WIDTH // 2, 0, WIDTH // 2, HEIGHT)
    assert_true(red_pixels(whole, left) > 0)
    assert_true(red_pixels(whole, right) > 0)
    renderer.set_viewport(left)
    var half = renderer.render(scene, assets, a_camera())
    assert_true(red_pixels(half, left) > 0)
    assert_equal(red_pixels(half, right), 0)
    # Squeezed: about half as many pixels, since the height is the same
    # and the width is halved.
    var before = red_pixels(whole, Rect.whole(WIDTH, HEIGHT))
    var after = red_pixels(half, Rect.whole(WIDTH, HEIGHT))
    assert_true(after < before)
    assert_true(after * 3 > before)


def test_a_viewport_counts_up_from_the_bottom() raises:
    # A viewport in the bottom half draws in the bottom rows of the image.
    var assets = Assets()
    var scene = a_cube_scene(assets)
    var renderer = a_renderer()
    renderer.set_viewport(Rect(0, 0, WIDTH, HEIGHT // 2))
    var image = renderer.render(scene, assets, a_camera())
    assert_true(red_pixels(image, Rect(0, 0, WIDTH, HEIGHT // 2)) > 0)
    assert_equal(red_pixels(image, Rect(0, HEIGHT // 2, WIDTH, HEIGHT // 2)), 0)


def test_a_viewport_off_the_target_draws_what_is_on_it() raises:
    var assets = Assets()
    var scene = a_cube_scene(assets)
    var renderer = a_renderer()
    renderer.set_viewport(Rect(WIDTH // 2, 0, WIDTH, HEIGHT))
    var image = renderer.render(scene, assets, a_camera())
    # The cube is centered in the viewport, which is centered on the
    # right edge: half of it is on the image.
    assert_true(red_pixels(image, Rect(WIDTH // 2, 0, WIDTH // 2, HEIGHT)) > 0)
    assert_equal(red_pixels(image, Rect(0, 0, WIDTH // 2, HEIGHT)), 0)


def test_a_scissor_cuts_the_image_when_its_test_is_on() raises:
    var assets = Assets()
    var scene = a_cube_scene(assets)
    var renderer = a_renderer()
    var left = Rect(0, 0, WIDTH // 2, HEIGHT)
    var right = Rect(WIDTH // 2, 0, WIDTH // 2, HEIGHT)
    renderer.set_scissor(left)
    # Off, the scissor is kept and ignored.
    var ignored = renderer.render(scene, assets, a_camera())
    assert_true(red_pixels(ignored, right) > 0)
    renderer.set_scissor_test(True)
    var cut = renderer.render(scene, assets, a_camera())
    assert_true(red_pixels(cut, left) > 0)
    assert_equal(red_pixels(cut, right), 0)
    # The cube is not squeezed, only cut: the left half holds the same
    # pixels it held before.
    assert_equal(red_pixels(cut, left), red_pixels(ignored, left))
    renderer.set_scissor_test(False)
    var back = renderer.render(scene, assets, a_camera())
    assert_true(red_pixels(back, right) > 0)


def test_two_viewports_share_one_target() raises:
    # A split screen: the cube drawn once in each half, each half cleared
    # to its own background and neither clearing the other. The one
    # image is resolved as `render` would resolve it.
    var assets = Assets()
    var scene = a_cube_scene(assets)
    var renderer = a_renderer()
    var left = Rect(0, 0, WIDTH // 2, HEIGHT)
    var right = Rect(WIDTH // 2, 0, WIDTH // 2, HEIGHT)
    var target = RenderTarget(WIDTH, HEIGHT, Color(255, 255, 255))
    renderer.set_scissor_test(True)
    renderer.set_background(Color(0, 0, 255))
    renderer.set_viewport(left)
    renderer.set_scissor(left)
    renderer.render_into(target, scene, assets, a_camera())
    renderer.set_background(Color(0, 255, 0))
    renderer.set_viewport(right)
    renderer.set_scissor(right)
    renderer.render_into(target, scene, assets, a_camera())
    var image = target.resolve(
        renderer.workers, renderer.tone_curve(), renderer.tone_mapping_exposure
    )
    assert_true(red_pixels(image, left) > 0)
    assert_true(red_pixels(image, right) > 0)
    assert_equal(red_pixels(image, left), red_pixels(image, right))
    # The left corner is blue and the right corner is green: each half
    # was cleared by its own draw and not by the other's.
    assert_equal(image.get_pixel(0, 0).b, 255)
    assert_equal(image.get_pixel(0, 0).g, 0)
    assert_equal(image.get_pixel(WIDTH - 1, 0).g, 255)
    assert_equal(image.get_pixel(WIDTH - 1, 0).b, 0)


def test_a_sub_viewport_keeps_a_surface_past_the_view_edge_off_the_target() raises:
    # A twelve by eight target, a four by four viewport in its middle,
    # and a plane far wider than the camera's two-meter view: with no
    # scissor, only the camera's own image lands on the target, sixteen
    # pixels, because the plane is cut at the side planes before it is
    # projected. Without that cut the plane covered all ninety-six.
    var assets = Assets()
    var sheet = assets.geometries.add(
        plane(Length(6.0, METER), Length(6.0, METER), 1, 1)
    )
    var paint = assets.materials.add(Material(RED, kind=BASIC))
    var scene = Scene()
    var node = Object3D()
    node.set_position(0, 0, -2)
    _ = scene.add(node^)
    scene.update()
    scene.add_mesh(Mesh(sheet, paint, NodeId(0)))
    var renderer = Renderer(12, 8)
    renderer.set_background(BACKGROUND)
    renderer.set_viewport(Rect(4, 2, 4, 4))
    var camera = centered(
        Length(2.0, METER), 1.0, Length(1.0, METER), Length(10.0, METER)
    )
    camera.place(Vector3(0, 0, 0), Vector3(0, 0, -1))
    var image = renderer.render(scene, assets, camera)
    assert_equal(red_pixels(image, Rect.whole(12, 8)), 16)
    assert_equal(red_pixels(image, Rect(4, 2, 4, 4)), 16)
    assert_false(image.get_pixel(10, 4).r > 128)
    # A line across the same view is cut the same way.
    var path = BufferGeometry()
    path.set_attribute(
        String(POSITION), BufferAttribute([-5.0, 0.0, -2.0, 5.0, 0.0, -2.0], 3)
    )
    var stroke = assets.geometries.add(path^)
    scene.meshes = List[Mesh]()
    scene.add_line(Line(stroke, paint, NodeId(0), mode=STRIP))
    var drawn = renderer.render(scene, assets, camera)
    assert_equal(red_pixels(drawn, Rect(4, 2, 4, 4)), 4)
    # A line lights the pixel each of its ends lands in, and the cut end
    # lands exactly on the viewport's right edge: one pixel past it is
    # lit, and no more. See the line rule on the Lines page.
    assert_equal(red_pixels(drawn, Rect.whole(12, 8)), 5)
    assert_true(drawn.get_pixel(8, 4).r > 128)
    # And a viewport hanging off the target draws what lands on it and
    # nothing beyond the camera's image.
    scene.lines = List[Line]()
    scene.add_mesh(Mesh(sheet, paint, NodeId(0)))
    renderer.set_viewport(Rect(10, 6, 4, 4))
    var corner = renderer.render(scene, assets, camera)
    assert_equal(red_pixels(corner, Rect.whole(12, 8)), 4)
    assert_equal(red_pixels(corner, Rect(10, 6, 2, 2)), 4)


def test_render_into_leaves_the_target_alone_when_the_scene_is_refused() raises:
    # A mesh naming a material that is not there is refused before a
    # pixel is touched, so the view drawn before it survives.
    var assets = Assets()
    var scene = a_cube_scene(assets)
    var renderer = a_renderer()
    var target = RenderTarget(WIDTH, HEIGHT, Color(255, 255, 255))
    renderer.render_into(target, scene, assets, a_camera())
    var before = target.resolve()
    var broken = Scene()
    _ = broken.add(Object3D())
    broken.update()
    broken.add_mesh(Mesh(GeometryId(0), MaterialId(9), NodeId(0)))
    renderer.set_background(Color(0, 255, 0))
    with assert_raises():
        renderer.render_into(target, broken, assets, a_camera())
    var after = target.resolve()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            assert_equal(before.get_pixel(x, y).r, after.get_pixel(x, y).r)
            assert_equal(before.get_pixel(x, y).g, after.get_pixel(x, y).g)


def test_render_into_needs_a_target_of_the_renderer_size() raises:
    var assets = Assets()
    var scene = a_cube_scene(assets)
    var renderer = a_renderer()
    var narrow = RenderTarget(WIDTH // 2, HEIGHT, BACKGROUND)
    with assert_raises(contains="renderer's size"):
        renderer.render_into(narrow, scene, assets, a_camera())
    var short = RenderTarget(WIDTH, HEIGHT // 2, BACKGROUND)
    with assert_raises(contains="renderer's size"):
        renderer.render_into(short, scene, assets, a_camera())


def test_render_into_clears_the_whole_target_without_a_scissor() raises:
    var assets = Assets()
    var scene = a_cube_scene(assets)
    var renderer = a_renderer()
    var target = RenderTarget(WIDTH, HEIGHT, Color(255, 255, 255))
    renderer.render_into(target, scene, assets, a_camera())
    var image = target.resolve()
    assert_equal(image.get_pixel(0, 0).r, 0)
    assert_equal(image.get_pixel(WIDTH - 1, HEIGHT - 1).r, 0)


def test_the_tone_curve_is_the_one_render_resolves_through() raises:
    var renderer = a_renderer()
    assert_true(renderer.tone_curve() == NO_TONE_MAPPING)
    renderer.set_tone_mapping(ACES_FILMIC_TONE_MAPPING)
    assert_true(renderer.tone_curve() == ACES_FILMIC_TONE_MAPPING)
    renderer.set_shading(SHADE_UV)
    assert_true(renderer.tone_curve() == NO_TONE_MAPPING)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
