# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.antialias` and the renderer's `antialias`: the
average of four samples in linear light, and an edge that is no longer a
staircase."""

from cameras.array_camera import ArrayCamera
from cameras.cube_camera import CubeCamera
from cameras.orthographic_camera import OrthographicCamera, centered
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.sphere import sphere
from materials.material import (
    BASIC,
    Material,
    PointSize,
    points_material,
)
from math.vector3 import Vector3
from objects.line import Line
from objects.mesh import Mesh
from objects.points import Points
from render.antialias import SUPERSAMPLE, downsample
from render.framebuffer import Color, FloatColor, Framebuffer
from render.rect import Rect
from render.target import RenderTarget
from render.tonemap import NO_TONE_MAPPING, REINHARD_TONE_MAPPING
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


# --- the resolve happens before the image is made ---------------------------


def test_an_hdr_edge_is_averaged_before_it_is_encoded() raises:
    # One subsample of four holds four times the light a display can show,
    # which is a bright emissive edge covering a quarter of an output
    # pixel. The average of the four is a radiance of one, and one encodes
    # to white.
    #
    # Resolving each sample to bytes first cannot reach that answer: the
    # bright one saturates at 255, which decodes to one, so the average
    # becomes a quarter of the light and the pixel comes back at 137. That
    # is the whole reason `downsampled` works on the target and not on the
    # picture.
    var big = RenderTarget(2, 2, Color(0, 0, 0))
    big.write(0, 0, FloatColor(4.0, 4.0, 4.0, 1.0))
    big.write(1, 0, FloatColor(0.0, 0.0, 0.0, 1.0))
    big.write(0, 1, FloatColor(0.0, 0.0, 0.0, 1.0))
    big.write(1, 1, FloatColor(0.0, 0.0, 0.0, 1.0))
    var small = big.downsampled(SUPERSAMPLE)
    assert_equal(small.width, 1)
    assert_equal(small.height, 1)
    # The light itself, before anything is encoded: four averaged to one.
    assert_almost_equal(Float64(small.color_at(0, 0).r), 1.0, atol=1e-6)
    var shown = small.resolve(1, NO_TONE_MAPPING, 1.0)
    assert_color(shown.get_pixel(0, 0), Color(255, 255, 255))
    # And through a curve, which must see the average rather than be
    # averaged itself: Reinhard of one is a half, which encodes to 188.
    var curved = big.downsampled(SUPERSAMPLE).resolve(
        1, REINHARD_TONE_MAPPING, 1.0
    )
    assert_color(curved.get_pixel(0, 0), Color(188, 188, 188))
    # What the byte-first path gives for the same four samples, so that the
    # difference is a number in the record rather than an assertion about
    # an implementation.
    var encoded = big.resolve(1, NO_TONE_MAPPING, 1.0)
    assert_color(
        downsample(encoded, SUPERSAMPLE).get_pixel(0, 0), Color(137, 137, 137)
    )


def test_a_block_is_data_only_when_every_sample_is() raises:
    # A normal is not light, and a tone curve must not touch it -- but a
    # normal half covered by lit smoke is not a normal any more. The flag
    # follows the whole block.
    var all_data = RenderTarget(2, 2, Color(0, 0, 0))
    for y in range(2):
        for x in range(2):
            all_data.write(x, y, FloatColor(0.5, 0.5, 0.5, 1.0), True)
    assert_true(all_data.downsampled(SUPERSAMPLE).is_data(0, 0))
    var mixed = RenderTarget(2, 2, Color(0, 0, 0))
    for y in range(2):
        for x in range(2):
            mixed.write(x, y, FloatColor(0.5, 0.5, 0.5, 1.0), True)
    mixed.write(1, 1, FloatColor(0.5, 0.5, 0.5, 1.0), False)
    assert_false(mixed.downsampled(SUPERSAMPLE).is_data(0, 0))


def test_a_resolved_block_keeps_its_nearest_depth() raises:
    var big = RenderTarget(2, 2, Color(0, 0, 0))
    _ = big.test_depth(0, 0, 0.75)
    _ = big.test_depth(1, 0, 0.25)
    _ = big.test_depth(0, 1, 0.5)
    _ = big.test_depth(1, 1, 0.9)
    assert_almost_equal(
        Float64(big.downsampled(SUPERSAMPLE).depth_at(0, 0)), 0.25, atol=1e-6
    )


def test_downsampling_a_target_refuses_a_factor_that_does_not_fit() raises:
    var target = RenderTarget(3, 2, Color(0, 0, 0))
    with assert_raises(contains="at least one"):
        _ = target.downsampled(0)
    # The width does not divide, which is the first half of the test.
    with assert_raises(contains="must divide"):
        _ = target.downsampled(2)
    # And a target whose width divides while its height does not, so the
    # second half is reached rather than short-circuited past.
    var tall = RenderTarget(2, 3, Color(0, 0, 0))
    with assert_raises(contains="must divide"):
        _ = tall.downsampled(2)
    # One is a copy, not a refusal.
    assert_equal(target.downsampled(1).width, 3)


# --- a size given in pixels survives the round trip -------------------------


def a_point_scene(
    mut assets: Assets, size: Float32, attenuated: Bool
) raises -> Scene:
    """Return a scene holding one white point at the world origin."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION), BufferAttribute([0.0, 0.0, 0.0], 3)
    )
    var dot = assets.geometries.add(geometry^)
    var paint = assets.materials.add(
        points_material(
            Color(255, 255, 255),
            size=PointSize(size),
            size_attenuation=attenuated,
        )
    )
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    scene.add_points(Points(dot, paint, NodeId(0)))
    return scene^


def covered(image: Framebuffer) raises -> Float64:
    """Return how many output pixels a white shape covers on black.

    Counted as *area* rather than as lit pixels, because that is what
    survives the resolve. A square eight output pixels across covers
    sixty-four pixels whether or not the frame was supersampled, but with
    anti-aliasing on its edge lands on part-covered pixels instead of
    whole ones, and counting pixels would call that a different size. The
    light is summed in linear, where white is one and half covered is a
    half; see `render.srgb`.
    """
    var total = Float64(0)
    for y in range(image.height):  # pragma: no branch
        for x in range(image.width):  # pragma: no branch
            total += Float64(FloatColor(srgb=image.get_pixel(x, y)).r)
    return total


def a_point_camera() raises -> PerspectiveCamera:
    """Return a camera five meters back with a right-angle view."""
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(0.5, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return camera^


def a_black_renderer() raises -> Renderer:
    """Return a renderer cleared to black, so that covered area is what
    the red channel sums to."""
    var renderer = Renderer(WIDTH, HEIGHT)
    renderer.set_background(Color(0, 0, 0))
    return renderer^


def test_a_point_keeps_its_size_when_the_frame_is_supersampled() raises:
    # An eight-pixel point with attenuation off covers sixty-four output
    # pixels. It has to cover sixty-four with anti-aliasing on too: the
    # setting is about how cleanly an edge is drawn, not about how large
    # the object is.
    #
    # Before the render scale existed the point stayed eight *raster*
    # pixels across on a doubled frame and averaged down to four, for
    # sixteen pixels of coverage -- a quarter of the area, from turning on
    # a setting that is supposed to preserve appearance.
    var assets = Assets()
    var scene = a_point_scene(assets, 8.0, False)
    var camera = a_point_camera()
    var renderer = a_black_renderer()
    assert_almost_equal(
        covered(renderer.render(scene, assets, camera)), 64.0, atol=1.0
    )
    renderer.set_antialias(True)
    assert_almost_equal(
        covered(renderer.render(scene, assets, camera)), 64.0, atol=1.0
    )


def test_a_point_under_a_parallel_camera_keeps_its_size_too() raises:
    # three.js does not attenuate a point under a parallel projection, so
    # this is the other route through `attenuated_size` -- reached with
    # the material's attenuation *on* -- and it has to scale the same way.
    var assets = Assets()
    var scene = a_point_scene(assets, 8.0, True)
    var camera = centered(
        Length(4.0, METER),
        Float32(WIDTH) / Float32(HEIGHT),
        Length(0.5, METER),
        Length(100.0, METER),
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    var renderer = a_black_renderer()
    assert_almost_equal(
        covered(renderer.render(scene, assets, camera)), 64.0, atol=1.0
    )
    renderer.set_antialias(True)
    assert_almost_equal(
        covered(renderer.render(scene, assets, camera)), 64.0, atol=1.0
    )


def test_an_attenuated_point_is_not_scaled_twice() raises:
    # The perspective branch multiplies by half the image height, which
    # doubles with the frame, so it already grew: scaling it again puts
    # the point at twice its width and four times its area. It must
    # measure against the *output* height and take the render scale once.
    var assets = Assets()
    var scene = a_point_scene(assets, 4.0, True)
    var camera = a_point_camera()
    var renderer = a_black_renderer()
    var plain = covered(renderer.render(scene, assets, camera))
    assert_true(plain > 1.0, "the attenuated point drew nothing to compare")
    renderer.set_antialias(True)
    assert_almost_equal(
        covered(renderer.render(scene, assets, camera)), plain, atol=1.0
    )


def test_a_line_keeps_its_thickness_when_the_frame_is_supersampled() raises:
    # A horizontal white line over black, measured down a column: one
    # output pixel of thickness, whatever the frame was drawn at.
    #
    # Thickness is measured as area for the reason `covered` gives. The
    # run of raster pixels the line lights is centered on where the line
    # actually crosses, so it can straddle two output rows and light
    # neither fully -- that is one pixel of line in the right place, not
    # half a pixel. Before the width existed the line lit one raster
    # pixel and the column summed to a half.
    var assets = Assets()
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION), BufferAttribute([-2.0, 0.0, 0.0, 2.0, 0.0, 0.0], 3)
    )
    var thread = assets.geometries.add(geometry^)
    var paint = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    var scene = Scene()
    _ = scene.add(Object3D())
    scene.update()
    scene.add_line(Line(thread, paint, NodeId(0)))
    var camera = a_point_camera()
    var renderer = a_black_renderer()
    var plain = renderer.render(scene, assets, camera)
    renderer.set_antialias(True)
    var smooth = renderer.render(scene, assets, camera)

    # Down the middle column, which the line crosses.
    var straight = Float64(0)
    var averaged = Float64(0)
    for y in range(HEIGHT):  # pragma: no branch
        straight += Float64(FloatColor(srgb=plain.get_pixel(WIDTH // 2, y)).r)
        averaged += Float64(FloatColor(srgb=smooth.get_pixel(WIDTH // 2, y)).r)
    assert_almost_equal(straight, 1.0, atol=0.05)
    assert_almost_equal(averaged, 1.0, atol=0.05)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
