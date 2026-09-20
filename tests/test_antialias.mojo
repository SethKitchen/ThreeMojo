# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.antialias` and the renderer's `antialias`: the
average of four samples in linear light, and an edge that is no longer a
staircase."""

from cameras.array_camera import ArrayCamera
from cameras.cube_camera import CubeCamera
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.sphere import sphere
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.antialias import SUPERSAMPLE, downsample
from render.framebuffer import Color, Framebuffer
from render.rect import Rect
from renderers.renderer import Renderer
from std.math import inf
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime WIDTH = 32
comptime HEIGHT = 24
comptime CLEAR = Color(0, 0, 0)


def assert_color(got: Color, want: Color) raises:
    """Assert two colors match in red, green and blue."""
    assert_equal(got.r, want.r)
    assert_equal(got.g, want.g)
    assert_equal(got.b, want.b)


# --- the average -------------------------------------------------------------


def test_four_pixels_average_in_linear_light() raises:
    # Two white and two black pixels average to half the light, which
    # encodes to 188, not to the 128 that averaging bytes would give.
    var big = Framebuffer(2, 2, Color(0, 0, 0))
    big.set_pixel(0, 0, Color(255, 255, 255))
    big.set_pixel(1, 1, Color(255, 255, 255))
    var small = downsample(big, 2)
    assert_equal(small.width, 1)
    assert_equal(small.height, 1)
    assert_color(small.get_pixel(0, 0), Color(188, 188, 188))
    assert_equal(small.get_pixel(0, 0).a, UInt8(255))


def test_a_transparent_pixel_lends_no_color() raises:
    # Premultiplied: an opaque red beside three transparent greens is a
    # quarter-covered red, with no green in it.
    var big = Framebuffer(2, 2, Color(0, 255, 0, 0))
    big.set_pixel(0, 0, Color(255, 0, 0, 255))
    var small = downsample(big, 2)
    var shown = small.get_pixel(0, 0)
    assert_equal(shown.r, UInt8(255))
    assert_equal(shown.g, UInt8(0))
    assert_equal(shown.a, UInt8(64))


def test_the_depth_is_the_nearest_of_the_block() raises:
    var pixels = List[UInt8](length=4 * 4, fill=0)
    var depth: List[Float32] = [
        0.5,
        inf[DType.float32](),
        0.25,
        0.75,
    ]
    var big = Framebuffer(2, 2, pixels^, depth^)
    var small = downsample(big, 2)
    assert_equal(small.depth_at(0, 0), Float32(0.25))


def test_a_factor_of_one_copies_and_a_bad_factor_is_refused() raises:
    var big = Framebuffer(4, 2, Color(10, 20, 30))
    var same = downsample(big, 1)
    assert_equal(same.width, 4)
    assert_color(same.get_pixel(3, 1), Color(10, 20, 30))
    var half = downsample(big, 2)
    assert_equal(half.width, 2)
    assert_equal(half.height, 1)
    with assert_raises():
        _ = downsample(big, 0)
    with assert_raises():
        _ = downsample(big, 3)
    with assert_raises():
        _ = downsample(big, 4)


# --- the renderer ----------------------------------------------------------------


def a_scene(mut assets: Assets) raises -> Scene:
    """Return a white sphere at the origin, unlit."""
    var scene = Scene()
    var node = scene.add(Object3D())
    var paint = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    scene.add_mesh(
        Mesh(
            assets.geometries.add(sphere(Length(0.9, METER), 12, 8)),
            paint,
            node,
        )
    )
    scene.update()
    return scene^


def a_camera() raises -> PerspectiveCamera:
    """Return a camera up the z axis, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.1, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def edge_levels(image: Framebuffer) raises -> Int:
    """Return how many pixels are neither black nor white."""
    var between = 0
    for y in range(image.height):
        for x in range(image.width):
            var r = image.get_pixel(x, y).r
            if r > 0 and r < 255:
                between += 1
    return between


def test_an_antialiased_edge_has_pixels_between_the_two_colors() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(CLEAR)
    var assets = Assets()
    var scene = a_scene(assets)
    assert_false(renderer.antialias)
    var hard = renderer.render(scene, assets, a_camera())
    assert_equal(hard.width, WIDTH)
    assert_equal(edge_levels(hard), 0)
    renderer.set_antialias(True)
    assert_true(renderer.antialias)
    var soft = renderer.render(scene, assets, a_camera())
    assert_equal(soft.width, WIDTH)
    assert_equal(soft.height, HEIGHT)
    assert_true(edge_levels(soft) > 10, "no edge pixel was averaged")
    # The middle of the sphere and the corner of the image are unchanged.
    assert_color(soft.get_pixel(WIDTH // 2, HEIGHT // 2), Color(255, 255, 255))
    assert_color(soft.get_pixel(0, 0), CLEAR)
    # And the depth comes back, nearest of the four.
    assert_true(soft.depth_at(WIDTH // 2, HEIGHT // 2) < 1)
    assert_equal(soft.depth_at(0, 0), inf[DType.float32]())


def test_the_viewport_and_scissor_are_scaled_with_the_frame() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(CLEAR)
    renderer.set_antialias(True)
    var assets = Assets()
    var scene = a_scene(assets)
    renderer.set_viewport(Rect(0, 0, WIDTH // 2, HEIGHT))
    var half = renderer.render(scene, assets, a_camera())
    # The sphere is squeezed into the left half; the right half is clear.
    assert_color(half.get_pixel(WIDTH // 4, HEIGHT // 2), Color(255, 255, 255))
    assert_color(half.get_pixel(WIDTH * 3 // 4, HEIGHT // 2), CLEAR)
    var big = renderer.supersampled()
    assert_equal(big.width, WIDTH * SUPERSAMPLE)
    assert_equal(big.viewport.width, WIDTH // 2 * SUPERSAMPLE)
    assert_false(big.antialias)
    renderer.set_viewport(Rect.whole(WIDTH, HEIGHT))
    renderer.set_scissor(Rect(0, 0, WIDTH, HEIGHT // 2))
    renderer.set_scissor_test(True)
    var cut = renderer.render(scene, assets, a_camera())
    # The bottom half is drawn; the top half, sphere and all, is not.
    assert_color(
        cut.get_pixel(WIDTH // 2, HEIGHT // 2 + 2), Color(255, 255, 255)
    )
    assert_color(cut.get_pixel(WIDTH // 2, HEIGHT // 2 - 2), CLEAR)
    assert_equal(renderer.supersampled().scissor.height, HEIGHT // 2 * 2)


def test_an_array_camera_and_a_cube_camera_are_antialiased_too() raises:
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(CLEAR)
    renderer.set_antialias(True)
    var assets = Assets()
    var scene = a_scene(assets)
    var array = ArrayCamera()
    array.add(a_camera(), Rect(0, 0, WIDTH // 2, HEIGHT))
    array.add(a_camera(), Rect(WIDTH // 2, 0, WIDTH // 2, HEIGHT))
    var pair = renderer.render_array(scene, assets, array)
    assert_equal(pair.width, WIDTH)
    assert_color(pair.get_pixel(WIDTH // 4, HEIGHT // 2), Color(255, 255, 255))
    assert_color(
        pair.get_pixel(WIDTH * 3 // 4, HEIGHT // 2), Color(255, 255, 255)
    )
    assert_true(edge_levels(pair) > 10, "no edge pixel was averaged")
    # An array of no cameras is the background alone, at the output size.
    var empty = renderer.render_array(scene, assets, ArrayCamera())
    assert_equal(empty.width, WIDTH)
    assert_color(empty.get_pixel(WIDTH // 2, HEIGHT // 2), CLEAR)
    var eye = CubeCamera(Length(0.1, METER), Length(10.0, METER), 16)
    eye.place(Vector3(0, 0, 3))
    var seen = renderer.render_cube(scene, assets, eye)
    assert_equal(seen.size, 16)
    # The -z face looks at the sphere; its middle is white and some of
    # its edge is averaged.
    ref face = seen.face(5)
    var between = 0
    for y in range(16):
        for x in range(16):
            var r = face.texel(x, y).r
            if r > 0 and r < 255:
                between += 1
    assert_true(between > 4, "the cube's faces were not averaged")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
