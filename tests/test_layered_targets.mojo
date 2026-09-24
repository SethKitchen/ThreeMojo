# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for multisampled render targets, `render.layered_target` and the
renderer's draws into a layer and a level."""

from cameras.cube_camera import CubeCamera
from cameras.orthographic_camera import OrthographicCamera, centered
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.cube_texture import cube_from_equirectangular
from render.framebuffer import Color, FloatColor
from render.layered_target import (
    TARGET_2D,
    TARGET_3D,
    TARGET_ARRAY,
    TARGET_CUBE,
    LayeredRenderTarget,
    TargetKind,
    array_render_target,
    cube_render_target,
    full_chain,
    level_extent,
    mipmapped_render_target,
    render_target_3d,
)
from render.raster_state import REVERSED_DEPTH
from render.rect import Rect
from render.target import (
    FLOAT_TARGET,
    HALF_FLOAT_TARGET,
    MAX_SAMPLES,
    OUTPUT_COLOR,
    OUTPUT_NORMAL,
    RenderTarget,
    TargetOutput,
    check_samples,
    resolve_block,
    sample_grid,
)
from render.texture import FLOAT_TYPE, NEAREST, Texture, float_texture
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


def normal_outputs() -> List[TargetOutput]:
    """Return the outputs of a G-buffer: the color, then the normal."""
    return [OUTPUT_COLOR, OUTPUT_NORMAL]


# --- samples -----------------------------------------------------------------


def test_a_sample_count_is_a_square_grid() raises:
    assert_equal(sample_grid(0), 1)
    assert_equal(sample_grid(1), 1)
    assert_equal(sample_grid(4), 2)
    assert_equal(sample_grid(9), 3)
    assert_equal(sample_grid(MAX_SAMPLES), 4)
    check_samples(0)
    check_samples(1)
    check_samples(16)
    with assert_raises(contains="zero through sixteen"):
        check_samples(-1)
    with assert_raises(contains="zero through sixteen"):
        check_samples(25)
    with assert_raises(contains="a square"):
        check_samples(2)
    with assert_raises(contains="zero through sixteen"):
        _ = RenderTarget(2, 2, Color(0, 0, 0), samples=17)
    assert_equal(RenderTarget(2, 2, Color(0, 0, 0), samples=4).samples, 4)


def test_a_block_resolves_to_its_average_light() raises:
    var buffer = RenderTarget(2, 2, Color(0, 0, 0, 0))
    buffer.write(0, 0, FloatColor(4, 0, 0, 1))
    var resolved = resolve_block(buffer, 2, 2, 0, 0, buffer.depth_mode, False)
    assert_almost_equal(resolved.color.r, 1)
    assert_almost_equal(resolved.color.a, 0.25)
    assert_false(resolved.data)
    assert_equal(resolved.normal.length(), Float32(0))
    # A block that is data throughout stays data, stored straight.
    var data = RenderTarget(2, 2, Color(0, 0, 0, 0))
    for y in range(2):
        for x in range(2):
            data.write(x, y, FloatColor(0.5, 0.5, 0.5, 0.5), data=True)
    var kept = resolve_block(data, 2, 2, 0, 0, data.depth_mode, False)
    assert_true(kept.data)
    assert_almost_equal(kept.color.r, 0.5)


def test_a_block_resolves_its_nearest_depth_and_unit_normal() raises:
    var buffer = RenderTarget(
        2, 2, Color(0, 0, 0), FLOAT_TARGET, normal_outputs()
    )
    buffer.write(0, 0, FloatColor(1, 1, 1, 1), normal=Vector3(1, 0, 0))
    buffer.write(1, 0, FloatColor(1, 1, 1, 1), normal=Vector3(0, 1, 0))
    _ = buffer.test_depth(0, 0, 0.5)
    _ = buffer.test_depth(1, 1, 0.25)
    var resolved = resolve_block(buffer, 2, 2, 0, 0, buffer.depth_mode, True)
    assert_almost_equal(resolved.depth, 0.25)
    assert_almost_equal(resolved.normal.length(), 1, atol=1e-5)
    assert_almost_equal(resolved.normal.x, resolved.normal.y)
    # A target without a normal attachment reads no normal.
    assert_equal(RenderTarget(1, 1, Color(0, 0, 0)).normal_in(0).length(), 0)


def test_a_target_resolves_its_samples_inside_a_rectangle() raises:
    var target = RenderTarget(
        2, 2, Color(0, 0, 0), FLOAT_TARGET, normal_outputs(), samples=4
    )
    var buffer = target.multisample_buffer()
    assert_equal(buffer.width, 4)
    assert_equal(buffer.samples, 0)
    buffer.clear_inside(Rect.whole(4, 4), Color(0, 0, 0), REVERSED_DEPTH)
    for x in range(4):
        buffer.write(x, 3, FloatColor(1, 0, 0, 1), normal=Vector3(0, 0, 1))
    # Only the bottom left pixel.
    target.resolve_samples(buffer, Rect(0, 0, 1, 1))
    assert_almost_equal(target.color_at(0, 1).r, 0.5)
    assert_almost_equal(target.normal_at(0, 1).z, 1)
    assert_equal(target.depth_mode, REVERSED_DEPTH)
    # Outside the rectangle the target is as it was.
    assert_almost_equal(target.color_at(1, 1).r, 0)
    with assert_raises(contains="sample grid times"):
        target.resolve_samples(
            RenderTarget(2, 2, Color(0, 0, 0)), Rect(0, 0, 1, 1)
        )
    with assert_raises(contains="sample grid times"):
        target.resolve_samples(
            RenderTarget(4, 2, Color(0, 0, 0)), Rect(0, 0, 1, 1)
        )
    with assert_raises(contains="the target's outputs"):
        target.resolve_samples(
            RenderTarget(4, 4, Color(0, 0, 0)), Rect(0, 0, 1, 1)
        )
    with assert_raises(contains="inside the target"):
        target.resolve_samples(buffer, Rect(0, 0, 3, 1))


def test_a_downsample_takes_the_first_samples_stencil() raises:
    var big = RenderTarget(2, 2, Color(0, 0, 0), samples=4)
    big.stencil[0] = 7
    big.stencil[1] = 9
    var small = big.downsampled(2)
    assert_equal(small.stencil_at(0, 0), 7)
    assert_equal(small.samples, 4)


# --- the renderer -------------------------------------------------------------


def a_camera() raises -> OrthographicCamera:
    """Return a camera looking down -z at a two-meter square of world."""
    var camera = centered(
        Length(2.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def a_turned_square(mut scene: Scene, mut assets: Assets) raises:
    """Add a white square turned about z, so its edges cross pixels."""
    var square = assets.geometries.add(
        plane(Length(1.0, METER), Length(1.0, METER))
    )
    var white = assets.materials.add(Material(Color(255, 255, 255), kind=BASIC))
    var stand = Object3D()
    stand.set_euler(Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(30.0, DEGREE))
    var node = scene.add(stand^)
    scene.update()
    scene.add_mesh(Mesh(square, white, node))


def test_a_multisampled_target_softens_an_edge() raises:
    var assets = Assets()
    var scene = Scene()
    a_turned_square(scene, assets)
    var renderer = Renderer(16, 16)
    var plain = RenderTarget(16, 16, Color(0, 0, 0), FLOAT_TARGET)
    renderer.render_into(plain, scene, assets, a_camera())
    var soft = RenderTarget(16, 16, Color(0, 0, 0), FLOAT_TARGET, samples=4)
    renderer.render_into(soft, scene, assets, a_camera())
    var between = 0
    var hard = 0
    for y in range(16):
        for x in range(16):
            var r = soft.color_at(x, y).r
            if r > 0.05 and r < 0.95:
                between += 1
            var p = plain.color_at(x, y).r
            if p > 0.05 and p < 0.95:
                hard += 1
    assert_equal(hard, 0)
    assert_true(between > 4, "no edge pixel was averaged")
    # The same as drawing four times the size and averaging it down.
    var big = renderer.multisampled(4)
    assert_equal(big.width, 32)
    assert_equal(big.render_scale, 2)
    var drawn = RenderTarget(32, 32, Color(0, 0, 0), FLOAT_TARGET)
    big.render_into(drawn, scene, assets, a_camera())
    var small = drawn.downsampled(2)
    for y in range(16):
        for x in range(16):
            assert_true(small.color_at(x, y) == soft.color_at(x, y))


def test_a_multisampled_draw_keeps_the_pixels_outside_the_scissor() raises:
    var assets = Assets()
    var scene = Scene()
    a_turned_square(scene, assets)
    var renderer = Renderer(16, 16)
    renderer.background = Color(0, 0, 255)
    renderer.set_scissor(Rect(0, 0, 8, 16))
    renderer.set_scissor_test(True)
    var target = RenderTarget(16, 16, Color(255, 0, 0), samples=9)
    renderer.render_into(target, scene, assets, a_camera())
    assert_almost_equal(target.color_at(15, 0).r, 1)
    assert_almost_equal(target.color_at(0, 0).b, 1)
    assert_equal(target.scissor, Rect(0, 0, 8, 16))
    # A target of another size is refused before anything is drawn.
    var wrong = RenderTarget(8, 8, Color(0, 0, 0), samples=4)
    with assert_raises(contains="renderer's size"):
        renderer.render_into(wrong, scene, assets, a_camera())
    with assert_raises(contains="at least one"):
        _ = renderer.scaled(0)
    with assert_raises(contains="a square"):
        _ = renderer.multisampled(3)


def test_a_multisampled_draw_that_clears_nothing_keeps_the_target() raises:
    var assets = Assets()
    var scene = Scene()
    a_turned_square(scene, assets)
    var renderer = Renderer(16, 16)
    renderer.auto_clear = False
    var outputs = normal_outputs()
    var target = RenderTarget(
        16, 16, Color(255, 0, 0), FLOAT_TARGET, outputs, samples=4
    )
    target.write(0, 0, FloatColor(0, 0, 1, 1), normal=Vector3(0, 0, 1))
    target.stencil[0] = 3
    renderer.render_into(target, scene, assets, a_camera())
    # The corners are outside the square, and keep what they held.
    assert_almost_equal(target.color_at(15, 15).r, 1)
    assert_almost_equal(target.color_at(0, 0).b, 1)
    assert_almost_equal(target.normal_at(0, 0).z, 1)
    assert_equal(target.stencil_at(0, 0), 3)
    assert_almost_equal(target.color_at(8, 8).g, 1)


# --- layered targets ----------------------------------------------------------


def test_the_four_kinds_are_valid() raises:
    assert_true(TARGET_2D.is_valid())
    assert_true(TARGET_3D.is_valid())
    assert_true(TARGET_ARRAY.is_valid())
    assert_true(TARGET_CUBE.is_valid())
    assert_false(TargetKind(4).is_valid())
    assert_equal(full_chain(8, 8), 4)
    assert_equal(full_chain(1, 1), 1)
    assert_equal(full_chain(2, 8), 4)
    assert_equal(level_extent(8, 5), 1)


def test_a_layered_target_refuses_what_it_cannot_hold() raises:
    with assert_raises(contains="one of the four"):
        _ = LayeredRenderTarget(TargetKind(9), 2, 2, 1)
    with assert_raises(contains="must be positive"):
        _ = LayeredRenderTarget(TARGET_3D, 0, 2, 1)
    with assert_raises(contains="must be positive"):
        _ = LayeredRenderTarget(TARGET_3D, 2, 0, 1)
    with assert_raises(contains="must be positive"):
        _ = LayeredRenderTarget(TARGET_3D, 2, 2, 0)
    with assert_raises(contains="one layer"):
        _ = LayeredRenderTarget(TARGET_2D, 2, 2, 2)
    with assert_raises(contains="six square faces"):
        _ = LayeredRenderTarget(TARGET_CUBE, 2, 2, 5)
    with assert_raises(contains="six square faces"):
        _ = LayeredRenderTarget(TARGET_CUBE, 2, 4, 6)
    with assert_raises(contains="up to a full chain"):
        _ = mipmapped_render_target(4, 0)
    with assert_raises(contains="up to a full chain"):
        _ = mipmapped_render_target(4, 4)
    with assert_raises(contains="keeps no mip chain"):
        _ = LayeredRenderTarget(TARGET_3D, 4, 4, 2, levels=2)
    with assert_raises(contains="keeps no mip chain"):
        _ = LayeredRenderTarget(TARGET_ARRAY, 4, 4, 2, levels=2)
    with assert_raises(contains="power of two"):
        _ = LayeredRenderTarget(TARGET_2D, 4, 2, 1, levels=2)
    with assert_raises(contains="power of two"):
        _ = mipmapped_render_target(6, 2)
    with assert_raises(contains="a square"):
        _ = cube_render_target(2, samples=2)
    # A 2D target with no chain, and a chain on the other kinds that
    # allow one.
    assert_equal(LayeredRenderTarget(TARGET_2D, 3, 2, 1).levels, 1)
    assert_equal(cube_render_target(4, levels=3).levels, 3)
    assert_equal(len(render_target_3d(2, 2, 3).images), 3)


def test_a_layered_target_hands_out_one_image_per_layer_and_level() raises:
    var cube = cube_render_target(4, Color(0, 0, 0), levels=3)
    assert_equal(len(cube.images), 18)
    assert_equal(cube.image(5, 2).width, 1)
    cube.image(2, 1).write(0, 0, FloatColor(1, 0, 0, 1))
    assert_almost_equal(cube.images[2 * 3 + 1].color_at(0, 0).r, 1)
    with assert_raises(contains="no such layer"):
        _ = cube.image(6, 0).width
    with assert_raises(contains="no such layer"):
        _ = cube.image(-1, 0).width
    with assert_raises(contains="no such level"):
        _ = cube.image(0, 3).width
    with assert_raises(contains="no such level"):
        _ = cube.image(0, -1).width
    var broken = array_render_target(2, 2, 2)
    broken.kind = TargetKind(7)
    with assert_raises(contains="one of the four"):
        broken.validate()
    var short = array_render_target(2, 2, 2)
    _ = short.images.pop()
    with assert_raises(contains="one image per layer"):
        short.validate()


def test_an_image_is_replaced_only_by_one_like_it() raises:
    var target = array_render_target(2, 2, 2, type=FLOAT_TARGET)
    var image = RenderTarget(2, 2, Color(255, 0, 0), FLOAT_TARGET)
    target.set_image(1, 0, image^)
    assert_almost_equal(target.image(1).color_at(0, 0).r, 1)
    with assert_raises(contains="its level's size"):
        target.set_image(0, 0, RenderTarget(3, 2, Color(0, 0, 0), FLOAT_TARGET))
    with assert_raises(contains="its level's size"):
        target.set_image(0, 0, RenderTarget(2, 3, Color(0, 0, 0), FLOAT_TARGET))
    with assert_raises(contains="type, outputs and samples"):
        target.set_image(0, 0, RenderTarget(2, 2, Color(0, 0, 0)))
    with assert_raises(contains="type, outputs and samples"):
        target.set_image(
            0,
            0,
            RenderTarget(2, 2, Color(0, 0, 0), FLOAT_TARGET, normal_outputs()),
        )
    with assert_raises(contains="type, outputs and samples"):
        target.set_image(
            0, 0, RenderTarget(2, 2, Color(0, 0, 0), FLOAT_TARGET, samples=4)
        )


def test_a_cleared_target_and_its_chain() raises:
    var target = mipmapped_render_target(4, 3, Color(0, 0, 0), FLOAT_TARGET)
    target.clear(Color(255, 255, 255))
    assert_almost_equal(target.image(0, 2).color_at(0, 0).r, 1)
    ref first = target.image(0, 0)
    for y in range(4):
        for x in range(4):
            var shade = Float32(0)
            if x < 2:
                shade = 1
            first.write(x, y, FloatColor(shade, shade, shade, 1))
    target.generate_mipmaps()
    assert_almost_equal(target.image(0, 1).color_at(0, 0).r, 1)
    assert_almost_equal(target.image(0, 1).color_at(1, 0).r, 0)
    assert_almost_equal(target.image(0, 2).color_at(0, 0).r, 0.5)
    # A chain read back as one texture keeps every level.
    var texture = target.texture(NEAREST)
    assert_equal(texture.levels, 3)
    assert_equal(texture.texel_type, FLOAT_TYPE)
    assert_almost_equal(texture.wrapped_texel(0, 0, 2).r, 0.5)
    # And a byte chain as bytes.
    var bytes = mipmapped_render_target(2, 2, Color(255, 255, 255))
    var small = bytes.texture()
    assert_equal(small.levels, 2)
    assert_equal(small.pixels[len(small.pixels) - 4], 255)
    # A target of one level reads back as a texture with no chain.
    assert_equal(mipmapped_render_target(2, 1).texture().levels, 1)
    # A target of one level generates nothing.
    var single = array_render_target(2, 2, 1)
    single.generate_mipmaps()
    assert_equal(array_render_target(2, 2, 1).levels, 1)


def test_each_kind_reads_back_only_as_its_own_texture() raises:
    var volume = render_target_3d(2, 2, 2)
    with assert_raises(contains="Only a 2D target"):
        _ = volume.texture()
    with assert_raises(contains="Only a cube target"):
        _ = volume.cube_texture()
    with assert_raises(contains="Only an array target"):
        _ = volume.array_texture()
    with assert_raises(contains="Only a 3D target"):
        _ = array_render_target(2, 2, 2).texture_3d()
    with assert_raises(contains="Only a cube target is filled"):
        volume.from_equirectangular_texture(a_panorama())


def test_a_volume_holds_its_layers_rows_up() raises:
    var volume = render_target_3d(2, 2, 2, Color(0, 0, 0), FLOAT_TARGET)
    # The top left pixel of layer one.
    volume.image(1).write(0, 0, FloatColor(3, 0, 0, 1))
    var texture = volume.texture_3d()
    assert_almost_equal(texture.texel_fetch(0, 1, 1).r, 3)
    assert_almost_equal(texture.texel_fetch(0, 0, 1).r, 0)
    var stack = array_render_target(2, 2, 3, Color(255, 0, 0))
    stack.image(2).write(1, 1, FloatColor(0, 1, 0, 1))
    var layers = stack.array_texture()
    assert_equal(layers.layers(), 3)
    assert_almost_equal(layers.texel_fetch(1, 0, 2).g, 1)
    assert_almost_equal(layers.texel_fetch(0, 0, 0).r, 1)


def a_panorama() raises -> Texture:
    """Return a panorama: bright red above the horizon, blue below."""
    var data = List[Float32]()
    for y in range(4):
        for _x in range(8):
            if y < 2:
                data.append(2)
                data.append(0)
                data.append(0)
            else:
                data.append(0)
                data.append(0)
                data.append(1)
            data.append(1)
    return float_texture(8, 4, data^, filter=NEAREST)


def test_a_cube_target_is_filled_from_a_panorama() raises:
    var cube = cube_render_target(4, type=HALF_FLOAT_TARGET, levels=2)
    cube.from_equirectangular_texture(a_panorama())
    var want = cube_from_equirectangular(a_panorama(), 4)
    var faces = cube.cube_texture(NEAREST)
    assert_equal(faces.levels(), 2)
    for face in range(6):
        for y in range(4):
            for x in range(4):
                assert_true(
                    faces.faces[face].wrapped_texel(x, y)
                    == want.faces[face].wrapped_texel(x, y)
                )
    # The top face looks at the red sky.
    assert_almost_equal(cube.image(2, 1).color_at(0, 0).r, 2)
    with assert_raises(contains="must hold texels"):
        cube.from_equirectangular_texture(Texture())
    var broken = a_panorama()
    broken.mag_filter = NEAREST
    broken.wrap_s = broken.wrap_s
    broken.min_filter = broken.min_filter
    broken.anisotropy = 0
    with assert_raises(contains="anisotropy"):
        cube.from_equirectangular_texture(broken)


def test_the_renderer_draws_into_a_layer_and_a_level() raises:
    var assets = Assets()
    var scene = Scene()
    a_turned_square(scene, assets)
    var target = mipmapped_render_target(16, 2, Color(0, 0, 0), samples=4)
    var small = Renderer(8, 8)
    small.render_into_layer(target, 0, 1, scene, assets, a_camera())
    assert_almost_equal(target.image(0, 1).color_at(4, 4).r, 1)
    assert_almost_equal(target.image(0, 0).color_at(8, 8).r, 0)
    with assert_raises(contains="renderer's size"):
        small.render_into_layer(target, 0, 0, scene, assets, a_camera())
    with assert_raises(contains="no such level"):
        small.render_into_layer(target, 0, 2, scene, assets, a_camera())


def test_a_cube_camera_draws_six_faces_into_a_cube_target() raises:
    var assets = Assets()
    var scene = Scene()
    a_turned_square(scene, assets)
    var camera = CubeCamera(Length(0.1, METER), Length(10.0, METER), 4)
    var renderer = Renderer(4, 4)
    renderer.background = Color(0, 255, 0)
    var cube = cube_render_target(8, Color(0, 0, 0), FLOAT_TARGET)
    renderer.render_cube_into(cube, scene, assets, camera)
    # Every face is drawn, at the target's size, not the camera's.
    for face in range(6):
        assert_almost_equal(cube.image(face).color_at(0, 0).g, 1)
    with assert_raises(contains="into a cube target"):
        var volume = render_target_3d(4, 4, 6)
        renderer.render_cube_into(volume, scene, assets, camera)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
