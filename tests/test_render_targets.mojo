# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for float and multiple render targets: `TargetType`,
`TargetOutput`, a target's attachments, its float depth texture, and the
normal attachment the rasterizer and the renderer fill."""

from cameras.orthographic_camera import OrthographicCamera, centered
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.lighting import Lighting, view_direction
from materials.material import (
    BASIC,
    BLEND,
    NORMALS,
    Material,
)
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor
from render.rasterizer import (
    SHADE_LIT,
    SHADE_UV,
    RasterVertex,
    data_color,
    rasterize_all,
    rasterize_line,
)
from render.target import (
    FLOAT_TARGET,
    HALF_FLOAT_TARGET,
    HALF_MAX,
    OUTPUT_COLOR,
    OUTPUT_NORMAL,
    UNSIGNED_BYTE_TARGET,
    RenderTarget,
    TargetOutput,
    TargetType,
    check_target,
    color_only,
    stored,
)
from render.raster_state import REVERSED_DEPTH
from render.rect import Rect
from render.texture import FLOAT_TYPE, NEAREST
from renderers.renderer import Renderer, camera_back
from std.math import sqrt
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


def normal_outputs() -> List[TargetOutput]:
    """Return the outputs of a G-buffer: the color, then the normal."""
    return [OUTPUT_COLOR, OUTPUT_NORMAL]


# --- the two types ----------------------------------------------------------


def test_the_three_types_and_the_two_outputs_are_valid() raises:
    assert_true(UNSIGNED_BYTE_TARGET.is_valid())
    assert_true(HALF_FLOAT_TARGET.is_valid())
    assert_true(FLOAT_TARGET.is_valid())
    assert_false(TargetType(3).is_valid())
    assert_true(OUTPUT_COLOR.is_valid())
    assert_true(OUTPUT_NORMAL.is_valid())
    assert_false(TargetOutput(2).is_valid())


def test_a_target_no_attachment_could_hold_is_refused() raises:
    check_target(FLOAT_TARGET, normal_outputs())
    check_target(UNSIGNED_BYTE_TARGET, color_only())
    with assert_raises(contains="type"):
        check_target(TargetType(3), color_only())
    with assert_raises(contains="first output"):
        check_target(FLOAT_TARGET, List[TargetOutput]())
    with assert_raises(contains="first output"):
        check_target(FLOAT_TARGET, [OUTPUT_NORMAL, OUTPUT_COLOR])
    with assert_raises(contains="one of the two"):
        check_target(FLOAT_TARGET, [OUTPUT_COLOR, TargetOutput(2)])
    with assert_raises(contains="repeat"):
        check_target(FLOAT_TARGET, [OUTPUT_COLOR, OUTPUT_COLOR])
    with assert_raises(contains="repeat"):
        check_target(FLOAT_TARGET, [OUTPUT_COLOR, OUTPUT_NORMAL, OUTPUT_NORMAL])
    # The constructor asks, before it allocates anything.
    with assert_raises(contains="type"):
        _ = RenderTarget(2, 2, Color(0, 0, 0), TargetType(7))


def test_each_type_stores_a_channel_its_own_way() raises:
    # A byte clamps and rounds to a 255th.
    assert_equal(stored(4.0, UNSIGNED_BYTE_TARGET), Float32(1))
    assert_equal(stored(-1.0, UNSIGNED_BYTE_TARGET), Float32(0))
    assert_equal(stored(0.5, UNSIGNED_BYTE_TARGET), Float32(128) / 255)
    # A half rounds to eleven bits of fraction and holds at its largest.
    assert_equal(stored(1.0, HALF_FLOAT_TARGET), Float32(1))
    assert_equal(stored(1.0 + 1.0 / 4096, HALF_FLOAT_TARGET), Float32(1))
    assert_equal(stored(70000, HALF_FLOAT_TARGET), HALF_MAX)
    assert_equal(stored(-70000, HALF_FLOAT_TARGET), -HALF_MAX)
    # A float is the number itself.
    assert_equal(stored(70000, FLOAT_TARGET), Float32(70000))


# --- float render targets ---------------------------------------------------


def test_a_float_target_keeps_light_above_one() raises:
    var float_target = RenderTarget(2, 1, Color(0, 0, 0), FLOAT_TARGET)
    var byte_target = RenderTarget(2, 1, Color(0, 0, 0))
    var half_target = RenderTarget(2, 1, Color(0, 0, 0), HALF_FLOAT_TARGET)
    var bright = FloatColor(4.0, 2.0, 0.3, 1.0)
    float_target.write(0, 0, bright)
    byte_target.write(0, 0, bright)
    half_target.write(0, 0, bright)
    var kept = float_target.attachment(0).get_pixel(0, 0)
    assert_almost_equal(kept[0], 4.0, atol=TOLERANCE)
    assert_almost_equal(kept[1], 2.0, atol=TOLERANCE)
    assert_almost_equal(kept[2], 0.3, atol=TOLERANCE)
    assert_almost_equal(kept[3], 1.0, atol=TOLERANCE)
    # A byte target clamps; no curve and no encode either way.
    var clamped = byte_target.attachment(0).get_pixel(0, 0)
    assert_equal(clamped[0], Float32(1))
    assert_equal(clamped[2], Float32(77) / 255)
    var halved = half_target.attachment(0).get_pixel(0, 0)
    assert_equal(halved[0], Float32(4))
    assert_almost_equal(halved[2], 0.3, atol=1e-3)
    # The clear color is light too, straight alpha.
    assert_equal(float_target.attachment(0).get_pixel(1, 0)[3], Float32(1))
    assert_equal(float_target.count(), 1)


def test_a_data_pixel_reads_as_the_fraction_its_bytes_show() raises:
    var target = RenderTarget(1, 1, Color(0, 0, 0), FLOAT_TARGET)
    target.write(0, 0, data_color(0.5, 0.25, 1.0, 1.0), True)
    var read = target.attachment(0).get_pixel(0, 0)
    assert_equal(read[0], Float32(128) / 255)
    assert_equal(read[1], Float32(64) / 255)
    assert_equal(read[2], Float32(1))


def test_an_attachment_texture_samples_the_light_as_stored() raises:
    var target = RenderTarget(2, 2, Color(0, 0, 0), FLOAT_TARGET)
    target.write(0, 0, FloatColor(8.0, 0.0, 0.0, 1.0))
    var texture = target.attachment_texture(0, filter=NEAREST)
    assert_equal(texture.texel_type, FLOAT_TYPE)
    assert_almost_equal(texture.sample(0.25, 0.75).r, 8.0, atol=TOLERANCE)
    with assert_raises(contains="out of range"):
        _ = target.attachment(1)
    with assert_raises(contains="out of range"):
        _ = target.attachment_texture(-1)


def test_a_float_depth_texture_holds_the_depth_itself() raises:
    var target = RenderTarget(2, 1, Color(0, 0, 0))
    _ = target.test_depth(0, 0, 0.99951)
    var exact = target.depth_texture(type=FLOAT_TARGET)
    assert_equal(exact.texel_type, FLOAT_TYPE)
    # The window depth, where eight bits would round it to one.
    var near = exact.sample(0.25, 0.5)
    assert_almost_equal(near.r, 0.999755, atol=1e-6)
    assert_equal(near.a, Float32(1))
    # Nothing drawn is the far plane.
    assert_equal(exact.sample(0.75, 0.5).r, Float32(1))
    var half = target.depth_texture(type=HALF_FLOAT_TARGET)
    assert_almost_equal(half.sample(0.25, 0.5).r, 0.999755, atol=1e-3)
    var preview = target.depth_texture()
    assert_equal(preview.sample(0.25, 0.5).r, Float32(1))
    with assert_raises(contains="type"):
        _ = target.depth_texture(type=TargetType(5))
    # Under a reversed depth the clear is the near end, zero, as three.js's
    # reversed depth texture holds it.
    var reversed = RenderTarget(1, 1, Color(0, 0, 0))
    reversed.clear_inside(Rect(0, 0, 1, 1), Color(0, 0, 0), REVERSED_DEPTH)
    var flipped = reversed.depth_texture(type=FLOAT_TARGET)
    assert_equal(flipped.sample(0.5, 0.5).r, Float32(0))


# --- multiple render targets ------------------------------------------------


def test_a_write_keeps_its_normal_and_a_blend_leaves_it() raises:
    var target = RenderTarget(
        2, 2, Color(0, 0, 0), FLOAT_TARGET, normal_outputs()
    )
    assert_equal(target.count(), 2)
    assert_true(target.has_normals())
    assert_equal(target.normal_at(0, 0).length(), Float32(0))
    target.write(0, 0, FloatColor(1, 0, 0, 1), normal=Vector3(0, 1, 0))
    assert_equal(target.normal_at(0, 0).y, Float32(1))
    target.blend(0, 0, FloatColor(0, 0, 1, 0.5))
    assert_equal(target.normal_at(0, 0).y, Float32(1))
    # A write with no normal -- a line, a point -- leaves none.
    target.write(1, 0, FloatColor(1, 0, 0, 1), normal=Vector3(1, 0, 0))
    target.write(1, 0, FloatColor(1, 0, 0, 1))
    assert_equal(target.normal_at(1, 0).length(), Float32(0))
    # Outside the scissor, nothing is written.
    target.set_scissor(Rect(0, 0, 1, 1))
    target.write(0, 0, FloatColor(1, 0, 0, 1), normal=Vector3(0, 0, 1))
    assert_equal(target.normal_at(0, 0).y, Float32(1))
    # A clear resets the normals inside it and leaves the rest.
    target.write(0, 1, FloatColor(1, 0, 0, 1), normal=Vector3(0, 0, 1))
    target.clear_inside(Rect(0, 1, 1, 1), Color(0, 0, 0))
    assert_equal(target.normal_at(0, 0).length(), Float32(0))
    assert_equal(target.normal_at(0, 1).z, Float32(1))


def test_a_plain_target_has_no_normal_attachment() raises:
    var target = RenderTarget(1, 1, Color(0, 0, 0))
    assert_false(target.has_normals())
    target.write(0, 0, FloatColor(1, 0, 0, 1), normal=Vector3(0, 1, 0))
    target.clear_inside(Rect(0, 0, 1, 1), Color(0, 0, 0))
    with assert_raises(contains="no normal attachment"):
        _ = target.normal_at(0, 0)
    with assert_raises(contains="out of bounds"):
        _ = target.normal_at(1, 0)


def test_the_normal_attachment_reads_raw_or_packed_by_type() raises:
    var exact = RenderTarget(
        2, 1, Color(0, 0, 0), FLOAT_TARGET, normal_outputs()
    )
    var packed = RenderTarget(
        2, 1, Color(0, 0, 0), UNSIGNED_BYTE_TARGET, normal_outputs()
    )
    var down = Vector3(0, -1, 0)
    exact.write(0, 0, FloatColor(1, 1, 1, 1), normal=down)
    packed.write(0, 0, FloatColor(1, 1, 1, 1), normal=down)
    var raw = exact.attachment(1)
    assert_equal(raw.get_pixel(0, 0)[1], Float32(-1))
    assert_equal(raw.get_pixel(0, 0)[3], Float32(1))
    # No surface is zero, alpha included.
    assert_equal(raw.get_pixel(1, 0)[3], Float32(0))
    var bytes = packed.attachment(1)
    assert_equal(bytes.get_pixel(0, 0)[0], Float32(128) / 255)
    assert_equal(bytes.get_pixel(0, 0)[1], Float32(0))
    assert_equal(bytes.get_pixel(1, 0)[0], Float32(0))
    var texture = exact.attachment_texture(1, filter=NEAREST)
    assert_equal(texture.sample(0.25, 0.5).g, Float32(-1))


def test_a_downsample_averages_the_normals_and_keeps_the_type() raises:
    var target = RenderTarget(
        4, 2, Color(0, 0, 0), HALF_FLOAT_TARGET, normal_outputs()
    )
    target.write(0, 0, FloatColor(1, 1, 1, 1), normal=Vector3(1, 0, 0))
    target.write(1, 0, FloatColor(1, 1, 1, 1), normal=Vector3(0, 1, 0))
    var small = target.downsampled(2)
    assert_equal(small.type, HALF_FLOAT_TARGET)
    assert_equal(small.count(), 2)
    var mixed = small.normal_at(0, 0)
    assert_almost_equal(mixed.x, 1 / sqrt(Float32(2)), atol=TOLERANCE)
    assert_almost_equal(mixed.y, 1 / sqrt(Float32(2)), atol=TOLERANCE)
    assert_equal(small.normal_at(1, 0).length(), Float32(0))
    # A plain target downsamples with no attachment.
    var plain = RenderTarget(2, 2, Color(0, 0, 0)).downsampled(2)
    assert_false(plain.has_normals())


# --- the view rotation ------------------------------------------------------


def test_a_direction_turns_into_view_space() raises:
    # The identity: world up and world back.
    var same = view_direction(
        Vector3(0.6, 0, 0.8), Vector3(0, 1, 0), Vector3(0, 0, 1)
    )
    assert_almost_equal(same.x, 0.6, atol=TOLERANCE)
    assert_almost_equal(same.z, 0.8, atol=TOLERANCE)
    # A camera looking down -x from +x: world +x is its back.
    var turned = view_direction(
        Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0)
    )
    assert_almost_equal(turned.z, 1, atol=TOLERANCE)
    var side = view_direction(
        Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)
    )
    # Its right is world -z.
    assert_almost_equal(side.x, 1, atol=TOLERANCE)


def test_lighting_normalizes_the_back_axis_and_keeps_a_zero_one() raises:
    var scene = Scene()
    scene.update()
    var long = Lighting(scene, back=Vector3(0, 0, -3))
    assert_almost_equal(long.back.z, -1, atol=TOLERANCE)
    var none = Lighting(scene, back=Vector3(0, 0, 0))
    assert_equal(none.back.length(), Float32(0))
    assert_equal(Lighting.uniform().back.z, Float32(1))


# --- the rasterizer ---------------------------------------------------------


def a_corner(x: Float32, y: Float32, normal: Vector3) -> RasterVertex:
    """Return a corner of a lit triangle with the given normal."""
    return RasterVertex(
        x, y, 0.5, 1.0, FloatColor(1, 1, 1, 1), 0, 0, normal=normal
    )


def a_triangle(normal: Vector3) -> List[RasterVertex]:
    """Return one triangle covering most of an eight by eight target."""
    return [
        a_corner(0, 0, normal),
        a_corner(8, 0, normal),
        a_corner(0, 8, normal),
    ]


def test_a_triangle_leaves_its_view_space_normal() raises:
    var target = RenderTarget(
        8, 8, Color(0, 0, 0), FLOAT_TARGET, normal_outputs()
    )
    # A camera looking down -x: world +x faces it.
    var scene = Scene()
    scene.update()
    var lighting = Lighting(scene, back=Vector3(1, 0, 0))
    rasterize_all(
        a_triangle(Vector3(1, 0, 0)), target, SHADE_LIT, lighting=lighting
    )
    assert_almost_equal(target.normal_at(1, 1).z, 1, atol=TOLERANCE)
    # Nothing covers the far corner.
    assert_equal(target.normal_at(7, 7).length(), Float32(0))
    # A plain target draws the same light and keeps no normal.
    var plain = RenderTarget(8, 8, Color(0, 0, 0), FLOAT_TARGET)
    rasterize_all(
        a_triangle(Vector3(1, 0, 0)), plain, SHADE_LIT, lighting=lighting
    )
    assert_true(plain.color_at(1, 1) == target.color_at(1, 1))


def test_an_unlit_triangle_and_the_uv_view_leave_a_normal_too() raises:
    var corners = a_triangle(Vector3(0, 1, 0))
    for ref corner in corners:
        corner.kind = BASIC
    var target = RenderTarget(
        8, 8, Color(0, 0, 0), FLOAT_TARGET, normal_outputs()
    )
    rasterize_all(corners, target, SHADE_LIT)
    assert_almost_equal(target.normal_at(1, 1).y, 1, atol=TOLERANCE)
    var uv = RenderTarget(8, 8, Color(0, 0, 0), FLOAT_TARGET, normal_outputs())
    rasterize_all(corners, uv, SHADE_UV)
    assert_almost_equal(uv.normal_at(1, 1).y, 1, atol=TOLERANCE)


def test_a_normal_material_keeps_the_normal_it_was_given() raises:
    # The renderer turned a normal material's normals into view space
    # already, so the rasterizer leaves them as they are.
    var corners = a_triangle(Vector3(0, 0, 1))
    for ref corner in corners:
        corner.kind = NORMALS
    var scene = Scene()
    scene.update()
    var lighting = Lighting(scene, back=Vector3(1, 0, 0))
    var target = RenderTarget(
        8, 8, Color(0, 0, 0), FLOAT_TARGET, normal_outputs()
    )
    rasterize_all(corners, target, SHADE_LIT, lighting=lighting)
    assert_almost_equal(target.normal_at(1, 1).z, 1, atol=TOLERANCE)


def test_a_blended_triangle_leaves_the_normal_behind_it() raises:
    var target = RenderTarget(
        8, 8, Color(0, 0, 0), FLOAT_TARGET, normal_outputs()
    )
    rasterize_all(a_triangle(Vector3(0, 1, 0)), target, SHADE_LIT)
    var glass = a_triangle(Vector3(1, 0, 0))
    for ref corner in glass:
        corner.blend = BLEND
        corner.color = FloatColor(1, 0, 0, 0.5)
        corner.z = 0.2
    rasterize_all(glass, target, SHADE_LIT)
    assert_almost_equal(target.normal_at(1, 1).y, 1, atol=TOLERANCE)


def test_a_line_over_a_surface_leaves_no_normal() raises:
    var target = RenderTarget(
        8, 8, Color(0, 0, 0), FLOAT_TARGET, normal_outputs()
    )
    rasterize_all(a_triangle(Vector3(0, 1, 0)), target, SHADE_LIT)
    var start = a_corner(0, 1.5, Vector3(0, 0, 1))
    var end = a_corner(6, 1.5, Vector3(0, 0, 1))
    start.kind = BASIC
    end.kind = BASIC
    start.z = 0.1
    end.z = 0.1
    rasterize_line(start, end, target)
    assert_equal(target.normal_at(2, 1).length(), Float32(0))
    assert_almost_equal(target.normal_at(1, 4).y, 1, atol=TOLERANCE)


# --- the renderer -----------------------------------------------------------


def a_camera() raises -> OrthographicCamera:
    """Return a camera looking down -z at a two-meter square of world,
    turned a quarter about y so its view is not the world."""
    var camera = centered(
        Length(2.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    camera.place(Vector3(4, 0, 0), Vector3(0, 0, 0))
    return camera^


def test_the_renderer_fills_a_normal_attachment_in_the_same_pass() raises:
    var assets = Assets()
    var square = assets.geometries.add(
        plane(Length(1.0, METER), Length(1.0, METER))
    )
    var white = assets.materials.add(Material(Color(255, 255, 255)))
    var scene = Scene()
    var stand = Object3D()
    # The plane faces +z; turned to face +x, where the camera is.
    stand.set_euler(Angle(0.0, DEGREE), Angle(90.0, DEGREE), Angle(0.0, DEGREE))
    var node = scene.add(stand^)
    scene.update()
    scene.add_mesh(Mesh(square, white, node))
    var camera = a_camera()
    var back = camera_back(scene, camera)
    assert_almost_equal(back.x, 1, atol=TOLERANCE)
    var renderer = Renderer(16, 16)
    var target = RenderTarget(
        16, 16, Color(0, 0, 0), FLOAT_TARGET, normal_outputs()
    )
    renderer.render_into(target, scene, assets, camera)
    # Facing the camera, in view space, though it faces +x in the world.
    var facing = target.normal_at(8, 8)
    assert_almost_equal(facing.z, 1, atol=1e-4)
    assert_equal(target.normal_at(0, 0).length(), Float32(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
