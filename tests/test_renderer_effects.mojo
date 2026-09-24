# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the effects that wrap a renderer: the stereo effects, the
ASCII effect and the outline effect."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import box
from geometries.sphere import sphere
from lights.light import ambient_light
from materials.material import Material, MaterialId
from math.matrix3 import Matrix3
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor, Framebuffer
from renderers.ascii_effect import (
    ASCII_CHARACTERS,
    ASCII_COLOR_FALLBACK,
    ASCII_FALLBACK,
    AsciiEffect,
    AsciiImage,
    ascii_brightness,
    ascii_characters,
    ascii_index,
    ascii_size,
    shrink,
)
from renderers.outline_effect import (
    OUTLINE_THICKNESS,
    OutlineEffect,
    OutlineParameters,
    check_outline_parameters,
)
from renderers.renderer import Renderer
from renderers.stereo_effects import (
    AnaglyphEffect,
    ParallaxBarrierEffect,
    StereoEffect,
    anaglyph_pixel,
    barrier_row_is_left,
    dubois_left,
    dubois_right,
)
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime WHITE = Color(255, 255, 255)
comptime BLACK = Color(0, 0, 0)


def meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


def near(a: Float32, b: Float32, tolerance: Float32 = 1e-5) raises:
    """Assert two floats agree."""
    assert_almost_equal(a, b, atol=Float64(tolerance))


def a_camera() raises -> PerspectiveCamera:
    """Return a camera four meters back, looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, meters(0.1), meters(20.0)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def a_ball(mut assets: Assets) raises -> Scene:
    """Return a gray ball at the origin, lit evenly."""
    var scene = Scene()
    scene.add_light(ambient_light(WHITE, 1))
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    var ball = assets.geometries.add(sphere(meters(1)))
    scene.add_mesh(Mesh(ball, paint, scene.add(Object3D())))
    scene.update()
    return scene^


def a_renderer(size: Int = 16) raises -> Renderer:
    """Return a renderer on a white background."""
    var renderer = Renderer(size, size)
    renderer.set_background(WHITE)
    return renderer^


def same_image(a: Framebuffer, b: Framebuffer) raises -> Bool:
    """Return True if two images match in every pixel."""
    for y in range(a.height):
        for x in range(a.width):
            var p = a.get_pixel(x, y)
            var q = b.get_pixel(x, y)
            if p.r != q.r or p.g != q.g or p.b != q.b or p.a != q.a:
                return False
    return True


# --- stereo --------------------------------------------------------------------


def test_the_dubois_matrices_are_three_js_s() raises:
    near(dubois_left().elements[0], 0.4561)
    near(dubois_left().elements[8], -0.00546856)
    near(dubois_right().elements[4], 0.73364)
    near(dubois_right().elements[8], 1.2264)


def test_an_anaglyph_pixel_mixes_the_eyes_through_the_matrices() raises:
    var identity = Matrix3()
    var zero = Matrix3()
    zero.elements = [0, 0, 0, 0, 0, 0, 0, 0, 0]
    var left = FloatColor(0.4, 0.2, 0.1, 0.5)
    var right = FloatColor(0.1, 0.1, 0.1, 1)
    # The left eye alone, straight, then premultiplied by the larger alpha.
    var only_left = anaglyph_pixel(left, right, identity, zero)
    near(only_left.r, 0.8)
    near(only_left.g, 0.4)
    near(only_left.a, 1)
    # Summed and clamped to one.
    var both = anaglyph_pixel(left, right, identity, identity)
    near(both.r, 0.9)
    var bright = anaglyph_pixel(
        FloatColor(1, 1, 1, 1), FloatColor(1, 1, 1, 1), identity, identity
    )
    near(bright.r, 1)
    # And to zero.
    var negative = Matrix3()
    negative.elements = [-1, 0, 0, 0, -1, 0, 0, 0, -1]
    near(anaglyph_pixel(left, right, negative, zero).g, 0)


def test_the_barrier_alternates_rows_from_the_bottom() raises:
    # Four rows: the bottom row is even, so it is the right eye.
    assert_false(barrier_row_is_left(3, 4))
    assert_true(barrier_row_is_left(2, 4))
    assert_false(barrier_row_is_left(1, 4))
    assert_true(barrier_row_is_left(0, 4))


def test_an_anaglyph_of_a_ball_is_drawn_through_the_curve() raises:
    var assets = Assets()
    var scene = a_ball(assets)
    var renderer = a_renderer()
    var effect = AnaglyphEffect()
    near(effect.color_matrix_left.elements[0], 0.4561)
    var image = effect.render(renderer, scene, assets, a_camera())
    assert_equal(image.width, 16)
    # Each Dubois row sums to about one, so the ball stays about gray.
    var middle = image.get_pixel(8, 8)
    assert_true(abs(Int(middle.r) - Int(middle.b)) < 8)
    assert_equal(Int(middle.a), 255)
    # With the left eye through the identity and the right through zero,
    # the image is the left eye's.
    var zero = Matrix3()
    zero.elements = [0, 0, 0, 0, 0, 0, 0, 0, 0]
    effect.color_matrix_left = Matrix3()
    effect.color_matrix_right = zero^
    var left_only = effect.render(renderer, scene, assets, a_camera())
    var left = renderer.render(scene, assets, effect.stereo.left)
    for y in range(16):
        for x in range(16):
            var a = left_only.get_pixel(x, y)
            var b = left.get_pixel(x, y)
            assert_true(abs(Int(a.r) - Int(b.r)) <= 1)


def test_a_parallax_barrier_takes_alternate_rows_from_each_eye() raises:
    var assets = Assets()
    var scene = a_ball(assets)
    var renderer = a_renderer()
    var effect = ParallaxBarrierEffect()
    var camera = a_camera()
    var image = effect.render(renderer, scene, assets, camera)
    # Each row is one of the two eyes' rows.
    var left = renderer.render(scene, assets, effect.stereo.left)
    var right = renderer.render(scene, assets, effect.stereo.right)
    for y in range(16):
        for x in range(16):
            var expected = right.get_pixel(x, y)
            if barrier_row_is_left(y, 16):
                expected = left.get_pixel(x, y)
            assert_equal(Int(image.get_pixel(x, y).r), Int(expected.r))


def test_a_stereo_pair_puts_the_eyes_side_by_side() raises:
    var assets = Assets()
    var scene = a_ball(assets)
    var renderer = a_renderer(15)
    var effect = StereoEffect()
    near(effect.stereo.aspect, 0.5)
    var image = effect.render(renderer, scene, assets, a_camera())
    assert_equal(image.width, 15)
    # The ball shows in each half.
    var left_gray = image.get_pixel(4, 7)
    var right_gray = image.get_pixel(11, 7)
    assert_true(Int(left_gray.r) < 255)
    assert_true(Int(right_gray.r) < 255)
    effect.set_eye_separation(meters(0.1))
    near(effect.stereo.eye_separation.value, 0.1)
    with assert_raises(contains="negative"):
        effect.set_eye_separation(meters(-1))
    near(effect.stereo.eye_separation.value, 0.1)
    var narrow = Renderer(1, 4)
    with assert_raises(contains="two columns"):
        _ = effect.render(narrow, scene, assets, a_camera())


# --- ASCII ---------------------------------------------------------------------


def test_the_brightness_and_the_character_it_picks() raises:
    near(ascii_brightness(BLACK), 0)
    near(ascii_brightness(WHITE), 1, 1e-4)
    near(ascii_brightness(Color(255, 0, 0)), 0.3)
    near(ascii_brightness(Color(0, 0, 0, 0)), 1)
    assert_equal(ascii_index(0, 10, False), 9)
    assert_equal(ascii_index(1, 10, False), 0)
    assert_equal(ascii_index(0.5, 10, False), 4)
    assert_equal(ascii_index(0, 10, True), 0)
    assert_equal(ascii_index(1, 10, True), 9)


def test_a_character_set_splits_and_falls_back() raises:
    var set = ascii_characters(ASCII_CHARACTERS, False)
    assert_equal(len(set), 10)
    assert_equal(set[9], "#")
    assert_equal(len(ascii_characters("", False)), 15)
    assert_equal(ascii_characters("", False)[14], "@")
    assert_equal(len(ascii_characters("", True)), 7)
    assert_equal(ascii_characters("", True)[1], "C")
    # A character past ASCII is one character.
    assert_equal(len(ascii_characters(" ░█", False)), 3)
    assert_equal(ascii_size(100, 0.15), 15)
    assert_equal(ascii_size(3, 0.15), 0)


def test_shrink_averages_by_alpha() raises:
    var image = Framebuffer(4, 2, BLACK)
    image.set_pixel(0, 0, WHITE)
    image.set_pixel(1, 1, Color(0, 0, 0, 0))
    image.set_pixel(2, 0, Color(0, 0, 0, 0))
    image.set_pixel(3, 0, Color(0, 0, 0, 0))
    image.set_pixel(2, 1, Color(0, 0, 0, 0))
    image.set_pixel(3, 1, Color(0, 0, 0, 0))
    var small = shrink(image, 2, 1)
    # The left half: one white and two black pixels count, one clear does
    # not weigh.
    assert_equal(Int(small[0].r), 85)
    assert_equal(Int(small[0].a), 191)
    # The right half is clear.
    assert_equal(Int(small[1].a), 0)
    with assert_raises(contains="one pixel"):
        _ = shrink(image, 0, 1)
    with assert_raises(contains="one pixel"):
        _ = shrink(image, 5, 1)
    with assert_raises(contains="one pixel"):
        _ = shrink(image, 1, 3)
    with assert_raises(contains="one pixel"):
        _ = shrink(image, 1, 0)


def test_asciify_reads_every_other_row() raises:
    var image = Framebuffer(4, 4, BLACK)
    for x in range(4):
        image.set_pixel(x, 0, WHITE)
        image.set_pixel(x, 2, Color(100, 100, 100))
    var effect = AsciiEffect(" .#", resolution=1)
    var ascii = effect.asciify(image)
    assert_equal(ascii.columns, 4)
    assert_equal(ascii.rows, 2)
    assert_equal(ascii.text(), "    \n....\n")
    assert_equal(ascii.html(), "&nbsp;&nbsp;&nbsp;&nbsp;<br/>....<br/>")
    var inverted = AsciiEffect(" .#", resolution=1, invert=True).asciify(image)
    assert_equal(inverted.text(), "####\n....\n")
    with assert_raises(contains="too small"):
        _ = AsciiEffect(resolution=0.1).asciify(image)
    var tall = Framebuffer(10, 1, BLACK)
    with assert_raises(contains="too small"):
        _ = AsciiEffect(resolution=0.5).asciify(tall)


def test_the_html_colors_blocks_and_fades_each_character() raises:
    var image = Framebuffer(1, 1, Color(255, 0, 0, 255))
    var plain = AsciiEffect("ab", resolution=1, color=True).asciify(image)
    assert_equal(
        plain.html(), "<span style='color:rgb(255,0,0);'>a</span><br/>"
    )
    var block = AsciiEffect(
        "ab", resolution=1, color=True, block=True, alpha=True
    ).asciify(image)
    assert_equal(
        block.html(),
        "<span style='color:rgb(255,0,0);background-color:rgb(255,0,0);"
        + "opacity:1.0;'>a</span><br/>",
    )
    var cells = AsciiImage(1, 1, ["x"], [BLACK])
    assert_false(cells.color)
    assert_equal(cells.html(), "x<br/>")


def test_an_ascii_effect_refuses_a_bad_resolution_and_draws_a_scene() raises:
    with assert_raises(contains="resolution"):
        _ = AsciiEffect(resolution=0)
    with assert_raises(contains="resolution"):
        _ = AsciiEffect(resolution=1.5)
    with assert_raises(contains="resolution"):
        _ = AsciiEffect(resolution=nan[DType.float32]())
    var assets = Assets()
    var scene = a_ball(assets)
    var effect = AsciiEffect(resolution=0.5)
    near(effect.resolution, 0.5)
    var ascii = effect.render(a_renderer(), scene, assets, a_camera())
    assert_equal(ascii.columns, 8)
    assert_equal(ascii.rows, 4)
    var text = ascii.text()
    # The white background is spaces; the gray ball is not.
    assert_true(text.startswith("        \n"))
    assert_true(
        text.find("-") >= 0 or text.find(":") >= 0 or text.find("+") >= 0
    )


# --- outline -------------------------------------------------------------------


def test_outline_parameters_are_three_js_s_and_checked() raises:
    var parameters = OutlineParameters()
    near(parameters.thickness, OUTLINE_THICKNESS)
    assert_equal(Int(parameters.color.r), 0)
    near(parameters.alpha, 1)
    assert_true(parameters.visible)
    check_outline_parameters(parameters)
    with assert_raises(contains="finite"):
        check_outline_parameters(OutlineParameters(nan[DType.float32]()))
    with assert_raises(contains="finite"):
        check_outline_parameters(OutlineParameters(alpha=inf[DType.float32]()))
    with assert_raises(contains="negative"):
        check_outline_parameters(OutlineParameters(-0.1))
    with assert_raises(contains="zero to one"):
        check_outline_parameters(OutlineParameters(alpha=-0.1))
    with assert_raises(contains="zero to one"):
        check_outline_parameters(OutlineParameters(alpha=1.1))
    with assert_raises(contains="negative"):
        _ = OutlineEffect(-1)


def test_a_material_can_have_its_own_outline() raises:
    var effect = OutlineEffect(0.01, Color(255, 0, 0), 0.5)
    near(effect.parameters(MaterialId(3)).thickness, 0.01)
    effect.set_parameters(MaterialId(3), OutlineParameters(0.05))
    near(effect.parameters(MaterialId(3)).thickness, 0.05)
    near(effect.parameters(MaterialId(2)).alpha, 0.5)
    with assert_raises(contains="name a material"):
        effect.set_parameters(MaterialId(-1), OutlineParameters())
    with assert_raises(contains="negative"):
        effect.set_parameters(MaterialId(0), OutlineParameters(-1))


def count_black(image: Framebuffer) raises -> Int:
    """Return how many pixels are black."""
    var count = 0
    for y in range(image.height):
        for x in range(image.width):
            var p = image.get_pixel(x, y)
            if p.r == 0 and p.g == 0 and p.b == 0:
                count += 1
    return count


def test_an_outline_rims_the_ball_and_leaves_the_scene_as_it_was() raises:
    var assets = Assets()
    var scene = a_ball(assets)
    var renderer = a_renderer(32)
    var camera = a_camera()
    var plain = renderer.render(scene, assets, camera)
    var effect = OutlineEffect(0.2)
    var inked = effect.render(renderer, scene, assets, camera)
    assert_equal(count_black(plain), 0)
    assert_true(count_black(inked) > 20)
    # The rim is around the ball: the middle is as it was.
    assert_equal(Int(inked.get_pixel(16, 16).r), Int(plain.get_pixel(16, 16).r))
    # The outline meshes, programs and materials are taken out again.
    assert_equal(len(scene.meshes), 1)
    assert_equal(assets.materials.count(), 1)
    assert_equal(assets.programs.count(), 0)
    # Disabled, it draws the scene alone.
    effect.enabled = False
    assert_true(
        same_image(effect.render(renderer, scene, assets, camera), plain)
    )
    # Hidden for the ball's material, no rim.
    effect.enabled = True
    effect.set_parameters(MaterialId(0), OutlineParameters(0.2, visible=False))
    assert_true(
        same_image(effect.render(renderer, scene, assets, camera), plain)
    )
    # A half-clear rim blends: gray, not black.
    effect.set_parameters(MaterialId(0), OutlineParameters(0.2, alpha=0.5))
    var faded = effect.render(renderer, scene, assets, camera)
    assert_equal(count_black(faded), 0)
    assert_false(same_image(faded, plain))


def test_a_mesh_without_normals_or_with_a_flat_matrix_is_not_outlined() raises:
    var assets = Assets()
    var scene = Scene()
    scene.add_light(ambient_light(WHITE, 1))
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    var bare = BufferGeometry()
    bare.set_attribute(
        String(POSITION),
        BufferAttribute([-1.0, -1.0, 0.0, 1.0, -1.0, 0.0, 0.0, 1.0, 0.0], 3),
    )
    var triangle = assets.geometries.add(bare^)
    scene.add_mesh(Mesh(triangle, paint, scene.add(Object3D())))
    scene.update()
    var renderer = a_renderer()
    var camera = a_camera()
    var plain = renderer.render(scene, assets, camera)
    var effect = OutlineEffect(0.2)
    assert_true(
        same_image(effect.render(renderer, scene, assets, camera), plain)
    )
    # A collapsed mesh gets no outline, and the renderer refuses it as it
    # refuses it without the effect.
    var flat = Object3D()
    flat.set_scale(0, 1, 1)
    var cube = assets.geometries.add(box(meters(1), meters(1), meters(1)))
    scene.add_mesh(Mesh(cube, paint, scene.add(flat^)))
    scene.update()
    with assert_raises(contains="collapses"):
        _ = effect.render(renderer, scene, assets, camera)
    assert_equal(len(scene.meshes), 2)
    assert_equal(assets.materials.count(), 1)


def test_an_outline_that_fails_to_draw_leaves_the_scene_as_it_was() raises:
    var assets = Assets()
    var scene = a_ball(assets)
    scene.add_mesh(
        Mesh(scene.meshes[0].geometry, MaterialId(7), scene.meshes[0].node)
    )
    var effect = OutlineEffect()
    with assert_raises(contains="No material"):
        _ = effect.render(a_renderer(), scene, assets, a_camera())
    assert_equal(len(scene.meshes), 2)
    assert_equal(assets.materials.count(), 1)
    assert_equal(assets.programs.count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
