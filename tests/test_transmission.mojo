# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.transmission`: the refraction a transmissive physical
surface shows, from three.js's `transmission_pars_fragment`.

The numbers are worked out from three.js's GLSL rather than read off the
implementation: a slab of glass looked at head on bends nothing, Beer's law
over two attenuation distances leaves a quarter of a half, and a bicubic
filter over a flat image gives the flat color back.
"""

from lights.lighting import environment_brdf
from math.matrix4 import Matrix4
from math.vector2 import Vector2
from math.vector3 import Vector3
from render.framebuffer import Color, FloatColor
from render.target import RenderTarget
from render.transmission import (
    DISPERSION_SPREAD,
    VIEW_FLOATS,
    HostSource,
    TransmissionTarget,
    bicubic,
    dispersed_iors,
    host_refraction,
    ior_roughness,
    refracted,
    target_coordinate,
    texture_bicubic,
    transmission_alpha,
    transmission_level,
    transmission_ray,
    volume_attenuation,
    volume_refraction,
)
from std.math import inf
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)

comptime TOLERANCE = 1e-5


def a_flat_target(color: Color) raises -> TransmissionTarget:
    """Return an 8x4 target of one color everywhere, over the identity
    view."""
    return TransmissionTarget(RenderTarget(8, 4, color), Matrix4())


def a_striped_target() raises -> TransmissionTarget:
    """Return an 8x8 target whose left half is black and right half white,
    under the identity view, which maps world x and y onto u and v."""
    var drawn = RenderTarget(8, 8, Color(0, 0, 0))
    for y in range(8):
        for x in range(4, 8):
            drawn.write(x, y, FloatColor(1.0, 1.0, 1.0, 1.0), False)
    return TransmissionTarget(drawn, Matrix4())


def test_an_empty_target_is_not_ready() raises:
    var empty = TransmissionTarget()
    assert_false(empty.is_ready())
    assert_equal(empty.view[0], Float32(0))


def test_a_target_holds_the_scene_straight_and_its_chain() raises:
    # A half-covered pixel is stored straight, as it was written, and the
    # chain runs down to one texel as three.js's mipmapped target does.
    var drawn = RenderTarget(4, 2, Color(0, 0, 0, 0))
    drawn.write(0, 0, FloatColor(0.5, 0.0, 0.0, 0.5), False)
    var view = Matrix4()
    view.elements[12] = 3
    var seen = TransmissionTarget(drawn, view)
    assert_true(seen.is_ready())
    assert_equal(seen.image.width, 4)
    assert_equal(seen.image.height, 2)
    assert_equal(seen.image.levels, 3)
    assert_almost_equal(seen.image.data[0], 0.5, atol=TOLERANCE)
    assert_almost_equal(seen.image.data[3], 0.5, atol=TOLERANCE)
    assert_equal(seen.image.data[7], Float32(0))
    assert_equal(seen.view[12], Float32(3))


def test_a_target_refuses_light_that_is_not_finite() raises:
    var drawn = RenderTarget(2, 2, Color(0, 0, 0))
    drawn.write(1, 1, FloatColor(inf[DType.float32](), 0.0, 0.0, 1.0), False)
    with assert_raises(contains="finite"):
        _ = TransmissionTarget(drawn, Matrix4())


def test_refraction_head_on_bends_nothing_and_a_slant_bends_inward() raises:
    var straight = refracted(Vector3(0, 0, -1), Vector3(0, 0, 1), 1 / 1.5)
    assert_almost_equal(straight.x, 0, atol=TOLERANCE)
    assert_almost_equal(straight.z, -1, atol=TOLERANCE)
    # Snell: the sine of 45 degrees over 1.5 inside.
    var slant = refracted(
        Vector3(0.70710678, 0, -0.70710678), Vector3(0, 0, 1), 1 / 1.5
    )
    assert_almost_equal(slant.x, 0.70710678 / 1.5, atol=TOLERANCE)
    assert_almost_equal(slant.length(), 1, atol=TOLERANCE)
    # Leaving a denser medium at a grazing angle reflects totally.
    var none = refracted(Vector3(0.99, 0, -0.14107), Vector3(0, 0, 1), 1.5)
    assert_equal(none.length(), Float32(0))


def test_a_transmission_ray_is_as_long_as_the_slab_on_each_axis() raises:
    var ray = transmission_ray(
        Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(2, 3, 4), 1.5
    )
    assert_almost_equal(ray.z, -4, atol=TOLERANCE)
    assert_almost_equal(ray.x, 0, atol=TOLERANCE)
    # An index below one refracts nothing at a grazing angle.
    var none = transmission_ray(
        Vector3(0, 0, 1), Vector3(-0.99, 0, 0.14107), Vector3(1, 1, 1), 0.5
    )
    assert_equal(none.length(), Float32(0))


def test_the_roughness_is_scaled_by_the_index() raises:
    assert_equal(ior_roughness(0.5, 1.0), Float32(0))
    assert_almost_equal(ior_roughness(0.5, 1.25), 0.25, atol=TOLERANCE)
    assert_equal(ior_roughness(0.5, 2.0), Float32(0.5))
    assert_almost_equal(transmission_level(256, 0.5, 1.5), 4, atol=TOLERANCE)


def test_beers_law_dims_the_light_along_the_path() raises:
    var half = Vector3(0.5, 1.0, 0.25)
    var never = volume_attenuation(3, half, inf[DType.float32]())
    assert_equal(never.x, Float32(1))
    var still = volume_attenuation(0, Vector3(0, 0, 0), 1)
    assert_equal(still.x, Float32(1))
    var twice = volume_attenuation(2, half, 1)
    assert_almost_equal(twice.x, 0.25, atol=TOLERANCE)
    assert_almost_equal(twice.y, 1, atol=TOLERANCE)
    assert_almost_equal(twice.z, 0.0625, atol=TOLERANCE)


def test_a_target_coordinate_divides_by_the_fourth_row() raises:
    var view = SIMD[DType.float32, VIEW_FLOATS](0)
    view[0] = 1
    view[5] = 1
    view[10] = 1
    view[11] = 1
    var place = target_coordinate(view, Vector3(1, 3, 2))
    assert_almost_equal(place.x, 0.5, atol=TOLERANCE)
    assert_almost_equal(place.y, 1.5, atol=TOLERANCE)


def test_dispersion_spreads_the_index_by_three_js_s_fortieth() raises:
    var iors = dispersed_iors(1.5, 2)
    var half = Float32(0.5) * DISPERSION_SPREAD * 2
    assert_almost_equal(iors.x, 1.5 - half, atol=TOLERANCE)
    assert_equal(iors.y, Float32(1.5))
    assert_almost_equal(iors.z, 1.5 + half, atol=TOLERANCE)


def test_a_bicubic_sample_of_a_flat_image_is_the_image() raises:
    var flat = a_flat_target(Color(255, 255, 255))
    var source = HostSource(Pointer(to=flat.image))
    assert_equal(source.level_count(), 4)
    assert_equal(source.level_size(1).x, Float32(4))
    var once = bicubic(source, Vector2(0.3, 0.6), 0)
    assert_almost_equal(once.r, 1, atol=TOLERANCE)
    assert_almost_equal(once.a, 1, atol=TOLERANCE)
    # Between two levels, and past the chain's last level.
    var between = texture_bicubic(source, Vector2(0.3, 0.6), 1.5)
    assert_almost_equal(between.g, 1, atol=TOLERANCE)
    var past = texture_bicubic(source, Vector2(0.3, 0.6), 9.5)
    assert_almost_equal(past.b, 1, atol=TOLERANCE)
    var whole = texture_bicubic(source, Vector2(0.3, 0.6), 2)
    assert_almost_equal(whole.r, 1, atol=TOLERANCE)


def test_a_bicubic_sample_blurs_an_edge_and_a_coarser_level_more() raises:
    var striped = a_striped_target()
    var source = HostSource(Pointer(to=striped.image))
    # Exactly on the edge the two halves meet halfway.
    var edge = bicubic(source, Vector2(0.5, 0.5), 0)
    assert_almost_equal(edge.r, 0.5, atol=1e-4)
    # A texel into the white half is near white at level zero and grayer
    # a level down, where each texel covers two.
    var sharp = texture_bicubic(source, Vector2(0.6875, 0.5), 0)
    var soft = texture_bicubic(source, Vector2(0.6875, 0.5), 1)
    assert_true(sharp.r > soft.r)
    assert_true(sharp.r > 0.9)


def test_a_volume_refraction_is_the_scene_times_the_transmittance() raises:
    # A flat gray scene seen head on through clear glass of diffuse color
    # white: the gray, less what the surface reflects, and opaque where
    # the scene was.
    var gray = a_flat_target(Color(188, 188, 188))
    var specular = Vector3(0.04, 0.04, 0.04)
    var seen = host_refraction(
        gray,
        Vector3(0, 0, 1),
        Vector3(0, 0, 1),
        0.25,
        Vector3(1, 1, 1),
        specular,
        1,
        Vector3(0.5, 0.5, 0),
        Vector3(1, 1, 1),
        0,
        1.5,
        Vector3(1, 1, 1),
        inf[DType.float32](),
    )
    var light = FloatColor(srgb=Color(188, 188, 188))
    var reflected = environment_brdf(1, specular, 1, 0.25)
    assert_almost_equal(seen.r, (1 - reflected.x) * light.r, atol=1e-4)
    assert_almost_equal(seen.a, 1, atol=TOLERANCE)
    # Through a tinted volume the channels are dimmed each by its own.
    var tinted = host_refraction(
        gray,
        Vector3(0, 0, 1),
        Vector3(0, 0, 1),
        0.25,
        Vector3(1, 1, 1),
        specular,
        1,
        Vector3(0.5, 0.5, 0),
        Vector3(1, 1, 2),
        0,
        1.5,
        Vector3(0.5, 1, 1),
        1,
    )
    assert_almost_equal(tinted.r, seen.r * 0.25, atol=1e-4)
    assert_almost_equal(tinted.g, seen.g, atol=1e-4)


def test_dispersion_reads_each_channel_at_its_own_index() raises:
    # With dispersion each channel is refracted apart; on a flat scene
    # the three read alike, so the answer equals the plain one.
    var gray = a_flat_target(Color(188, 188, 188, 128))
    var source = HostSource(Pointer(to=gray.image))
    var plain = volume_refraction(
        source,
        gray.view,
        Vector3(0, 0, 1),
        Vector3(0.3, 0, 0.9539),
        0.25,
        Vector3(1, 0.5, 0.25),
        Vector3(0.04, 0.04, 0.04),
        1,
        Vector3(0.5, 0.5, 0),
        Vector3(0.2, 0.2, 0.2),
        0,
        1.5,
        Vector3(0.5, 0.5, 0.5),
        2,
    )
    var spread = volume_refraction(
        source,
        gray.view,
        Vector3(0, 0, 1),
        Vector3(0.3, 0, 0.9539),
        0.25,
        Vector3(1, 0.5, 0.25),
        Vector3(0.04, 0.04, 0.04),
        1,
        Vector3(0.5, 0.5, 0),
        Vector3(0.2, 0.2, 0.2),
        5,
        1.5,
        Vector3(0.5, 0.5, 0.5),
        2,
    )
    assert_almost_equal(spread.r, plain.r, atol=1e-3)
    assert_almost_equal(spread.g, plain.g, atol=1e-5)
    assert_almost_equal(spread.b, plain.b, atol=1e-3)
    assert_almost_equal(spread.a, plain.a, atol=1e-3)
    # Where the scene is half covered, less light shows through than a
    # clear surface would let pass.
    assert_true(plain.a < 1)


def test_a_transmission_mixes_the_alpha_toward_the_scenes() raises:
    assert_equal(transmission_alpha(0.4, 0), Float32(1))
    assert_almost_equal(transmission_alpha(0.4, 0.5), 0.7, atol=TOLERANCE)
    assert_almost_equal(transmission_alpha(0.4, 1), 0.4, atol=TOLERANCE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()


# --- the transmission pass --------------------------------------------------

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.background import texture_background
from core.buffer_geometry import POSITION, BufferAttribute, BufferGeometry
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from materials.material import (
    BASIC,
    BLEND,
    DOUBLE_SIDE,
    FRONT_SIDE,
    Material,
    Side,
    physical_material,
    points_material,
    sprite_material,
)
from objects.line import Line
from objects.line_segments2 import LineSegments2, line_segments_geometry
from objects.mesh import Mesh
from objects.points import Points
from objects.sprite import Sprite
from render.rasterizer import DRAW_TRIANGLES, SHADE_LIT, SHADE_TEXTURE
from render.rect import Rect
from render.texture import IGNORED, NEAREST, REPEAT, Texture
from render.srgb import LINEAR
from render.texture_store import NO_TEXTURE, TextureId
from renderers.renderer import Renderer
from units.si import Angle, DEGREE, Length, METER

comptime SIZE = 24


def a_glass(
    transmission: Float32 = 1,
    side: Side = FRONT_SIDE,
    transparent: Bool = False,
    transmission_map: TextureId = NO_TEXTURE,
    thickness_map: TextureId = NO_TEXTURE,
) raises -> Material:
    """Return a white, fairly smooth glass that transmits."""
    return physical_material(
        Color(255, 255, 255),
        roughness=0.3,
        transmission=transmission,
        thickness=Length(0.2, METER),
        side=side,
        transparent=transparent,
        transmission_map=transmission_map,
        thickness_map=thickness_map,
    )


def a_data_map(value: UInt8) raises -> Texture:
    """Return a one-texel map stored as data."""
    return Texture(
        1,
        1,
        [value, value, value, UInt8(255)],
        REPEAT,
        NEAREST,
        LINEAR,
        False,
        IGNORED,
    )


def glass_scene(
    mut assets: Assets,
    glass: Material,
    extras: Bool = False,
    solid: Bool = False,
    walled: Bool = True,
) raises -> Scene:
    """Return a scene with a glass sheet at the origin in front of a red
    wall a meter behind it, lit by nothing. With `extras`, a line, some
    points, a sprite and a wide line off to the side, all opaque. With
    `solid`, the glass is a box rather than a sheet; without `walled`,
    there is no wall."""
    var scene = Scene()
    var front = scene.add(Object3D())
    var back = Object3D()
    back.set_position(0, 0, -1)
    var wall_node = scene.add(back^)
    scene.update()
    var sheet = assets.geometries.add(
        plane(Length(1.0, METER), Length(1.0, METER))
    )
    if solid:
        sheet = assets.geometries.add(cube(Length(0.8, METER)))
    var wall = assets.geometries.add(
        plane(Length(8.0, METER), Length(8.0, METER))
    )
    scene.add_mesh(Mesh(sheet, assets.materials.add(glass), front))
    if walled:
        scene.add_mesh(
            Mesh(
                wall,
                assets.materials.add(Material(Color(255, 0, 0), kind=BASIC)),
                wall_node,
            )
        )
    if extras:
        var bare = BufferGeometry()
        bare.set_attribute(
            String(POSITION),
            BufferAttribute([1.2, 0.0, 0.0, 1.4, 0.2, 0.0, 1.3, 0.4, 0.0], 3),
        )
        var shape = assets.geometries.add(bare^)
        var green = assets.materials.add(Material(Color(0, 255, 0), kind=BASIC))
        scene.add_line(Line(shape, green, front))
        scene.add_points(
            Points(
                shape,
                assets.materials.add(points_material(Color(0, 0, 255))),
                front,
            )
        )
        scene.add_sprite(Sprite(assets.materials.add(sprite_material()), front))
        var sticks = assets.geometries.add(
            line_segments_geometry([Vector3(-1.4, 0, 0), Vector3(-1.2, 0.3, 0)])
        )
        scene.add_wide_line(LineSegments2(sticks, green, front))
    return scene^


def a_view() raises -> PerspectiveCamera:
    """Return a camera four meters up +z looking at the origin."""
    var camera = PerspectiveCamera(
        Angle(45.0, DEGREE), 1, Length(0.1, METER), Length(100.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def a_renderer() raises -> Renderer:
    """Return a renderer the test size, cleared to black."""
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    return renderer^


def test_a_glass_sheet_shows_the_wall_behind_it() raises:
    # The glass is lit by nothing, so all it shows is the red wall seen
    # through it; with no transmission it is dark.
    var assets = Assets()
    var scene = glass_scene(assets, a_glass())
    var renderer = a_renderer()
    var through = renderer.render(scene, assets, a_view()).get_pixel(12, 12)
    assert_true(through.r > 200, "the glass showed no wall")
    assert_true(through.g < 20)
    var dull_assets = Assets()
    var dull = glass_scene(dull_assets, a_glass(0))
    var opaque = renderer.render(dull, dull_assets, a_view()).get_pixel(12, 12)
    assert_true(opaque.r < 40, "a glass that transmits nothing showed the wall")
    # Lit shading opens no texture, and draws no transmission pass.
    renderer.set_shading(SHADE_LIT)
    var lit = renderer.render(scene, assets, a_view()).get_pixel(12, 12)
    assert_true(lit.r < 40, "the lit view looked through the glass")


def test_the_pass_holds_the_opaque_scene_and_the_matrix_onto_it() raises:
    var assets = Assets()
    var scene = glass_scene(assets, a_glass(), extras=True)
    var renderer = a_renderer()
    var camera = a_view()
    var seen = renderer.transmission_target(scene, assets, camera)
    assert_true(seen.is_ready())
    assert_equal(seen.image.width, SIZE)
    # The origin is in the middle of the image; the pass drew the wall,
    # and not the glass, which it left out.
    var middle = target_coordinate(seen.view, Vector3(0, 0, 0))
    assert_almost_equal(middle.x, 0.5, atol=1e-4)
    assert_almost_equal(middle.y, 0.5, atol=1e-4)
    var view = renderer.to_target(scene, camera)
    assert_equal(view.elements[5], seen.view[5])
    var wall = seen.image.data[(12 * SIZE + 12) * 4]
    assert_almost_equal(wall, 1, atol=1e-5)
    # A scene with nothing transmissive needs no pass.
    var dull_assets = Assets()
    var dull = glass_scene(dull_assets, a_glass(0), extras=True)
    assert_false(
        renderer.transmission_target(dull, dull_assets, camera).is_ready()
    )
    # And the frame with lines, points, a sprite, a wide line and a
    # wireframe draws.
    var wire = Object3D()
    wire.set_position(0, 1.2, 0)
    var wire_node = scene.add(wire^)
    scene.update()
    var sheet = assets.geometries.add(
        plane(Length(0.3, METER), Length(0.3, METER))
    )
    scene.add_mesh(
        Mesh(
            sheet,
            assets.materials.add(
                Material(Color(255, 255, 0), kind=BASIC, wireframe=True)
            ),
            wire_node,
        )
    )
    var drawn = renderer.render(scene, assets, camera)
    assert_true(drawn.get_pixel(12, 12).r > 200, "the glass showed no wall")


def test_a_two_sided_glass_is_drawn_from_behind_into_the_pass() raises:
    # three.js draws a two-sided transmissive object's back faces into its
    # target, so a second sheet seen through the first shows through it.
    var assets = Assets()
    var scene = glass_scene(
        assets, a_glass(side=DOUBLE_SIDE), extras=True, solid=True
    )
    var renderer = a_renderer()
    var camera = a_view()
    var seen = renderer.transmission_target(scene, assets, camera)
    var one_sided_assets = Assets()
    var one_sided = glass_scene(one_sided_assets, a_glass(), solid=True)
    var plain = renderer.transmission_target(
        one_sided, one_sided_assets, camera
    )
    var at = (12 * SIZE + 12) * 4
    # The back face faces away from the camera and is drawn anyway.
    assert_true(seen.image.data[at] != plain.image.data[at])


def test_the_pass_clears_to_half_white_and_keeps_the_scissor_and_backdrop() raises:
    var assets = Assets()
    var scene = glass_scene(assets, a_glass(), walled=False)
    var renderer = a_renderer()
    renderer.set_background(Color(0, 0, 0, 0))
    renderer.set_scissor(Rect(4, 4, 16, 16))
    renderer.set_scissor_test(True)
    var camera = a_view()
    var seen = renderer.transmission_target(scene, assets, camera)
    # A corner outside the scissor keeps the clear: white at half alpha.
    assert_almost_equal(seen.image.data[0], 1, atol=1e-5)
    assert_almost_equal(seen.image.data[3], 128.0 / 255.0, atol=1e-5)
    # A texture background is painted into the pass as into the frame.
    var sky = assets.textures.add(
        Texture(1, 1, [UInt8(0), 0, 255, 255], REPEAT, NEAREST)
    )
    scene.background = texture_background(sky)
    renderer.set_scissor_test(False)
    var painted = renderer.transmission_target(scene, assets, camera)
    assert_almost_equal(painted.image.data[2], 1, atol=1e-5)


def test_transmissive_runs_draw_between_the_opaque_and_the_blended() raises:
    # three.js's order: opaque, then the transmissive list furthest first,
    # then the transparent list, a transmissive one that blends included.
    var assets = Assets()
    var scene = glass_scene(assets, a_glass())
    var far = Object3D()
    far.set_position(0.2, 0, -0.5)
    var far_node = scene.add(far^)
    var near = Object3D()
    near.set_position(-0.2, 0, 0.5)
    var near_node = scene.add(near^)
    scene.update()
    var sheet = assets.geometries.add(
        plane(Length(0.5, METER), Length(0.5, METER))
    )
    scene.add_mesh(
        Mesh(sheet, assets.materials.add(a_glass(transparent=True)), near_node)
    )
    scene.add_mesh(
        Mesh(
            sheet,
            assets.materials.add(
                Material(
                    Color(0, 0, 255), kind=BASIC, opacity=0.5, transparent=True
                )
            ),
            far_node,
        )
    )
    scene.add_mesh(Mesh(sheet, assets.materials.add(a_glass()), far_node))
    var frame = a_renderer().prepare_frame(scene, assets, a_view())
    var stage = 0
    var last_depth = Float32(-1)
    for index in range(len(frame.draws)):
        ref draw = frame.draws[index]
        assert_equal(draw.kind, DRAW_TRIANGLES)
        ref corner = frame.corners[draw.first * 3]
        var now = 0
        if corner.transmission > 0:
            now = 1
        elif corner.blend.mixes():
            now = 2
        assert_true(now >= stage, "a run was drawn out of three.js's order")
        if now == 1:
            if stage == 1:
                assert_true(corner.z <= last_depth, "glass drawn near first")
            last_depth = corner.z
        stage = now
    assert_equal(stage, 2)


def test_the_thickness_is_stretched_with_the_mesh_and_the_maps_ride_along() raises:
    var assets = Assets()
    var half = assets.textures.add(a_data_map(128))
    var thin = assets.textures.add(a_data_map(64))
    var scene = Scene()
    var holder = Object3D()
    holder.set_scale(2, 1, 3)
    var node = scene.add(holder^)
    scene.update()
    var sheet = assets.geometries.add(
        plane(Length(1.0, METER), Length(1.0, METER))
    )
    scene.add_mesh(
        Mesh(
            sheet,
            assets.materials.add(
                a_glass(transmission_map=half, thickness_map=thin)
            ),
            node,
        )
    )
    var renderer = a_renderer()
    var corners = renderer.prepare(scene, assets, a_view())
    assert_true(len(corners) > 0)
    assert_almost_equal(corners[0].thickness.x, 0.4, atol=1e-5)
    assert_almost_equal(corners[0].thickness.y, 0.2, atol=1e-5)
    assert_almost_equal(corners[0].thickness.z, 0.6, atol=1e-5)
    assert_equal(corners[0].transmission_map, half)
    assert_equal(corners[0].thickness_map, thin)
    assert_equal(corners[0].transmission, Float32(1))
    renderer.set_shading(SHADE_LIT)
    var lit = renderer.prepare(scene, assets, a_view())
    assert_equal(lit[0].transmission_map, NO_TEXTURE)
    assert_equal(lit[0].thickness_map, NO_TEXTURE)
    # A map the store does not hold is refused.
    var missing = Scene()
    _ = missing.add(Object3D())
    missing.update()
    missing.add_mesh(
        Mesh(
            sheet,
            assets.materials.add(a_glass(transmission_map=TextureId(9))),
            NodeId(0),
        )
    )
    with assert_raises(contains="A transmission map is named"):
        _ = renderer.prepare(missing, assets, a_view())
