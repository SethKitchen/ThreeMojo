# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the spot lights three.js shapes by other means than a cone:
`lights.ies_spot_light`, three.js's `IESSpotLight`, and
`lights.projector_light`, its `ProjectorLight`, with `lights.spot_profile`
and their place in `Lighting` and the renderer.

The expected numbers are three.js's formulas worked by hand. An IES
profile is read at `acos(angleCos) / pi` across its first row, linearly.
A projector's beam is `saturate(-2 * sdBox(uv - 0.5, 0.5) / acos(pc))`.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.layers import Layers
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from geometries.plane import plane
from lights.ies_spot_light import ies_coordinate, ies_spot_light
from lights.light import (
    ASPECT_FROM_MAP,
    CONE_SPOT,
    IES_SPOT,
    PROJECTOR_SPOT,
    SpotShape,
    ambient_light,
    point_light,
    spot_light,
)
from lights.lighting import RECIPROCAL_PI, Lighting, falloff
from lights.projector_light import (
    PROJECTOR_PENUMBRA_CAP,
    projector_aspect,
    projector_attenuation,
    projector_light,
    sd_box,
)
from lights.spot_profile import SpotProfile, needs_profile
from loaders.ies import IES_FLOAT, ies_texture, read_ies
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from render.texture import Texture, checkerboard, float_texture
from render.texture_store import NO_TEXTURE, TextureId, TextureStore
from renderers.renderer import Renderer
from std.math import acos, cos, inf, nan, pi, sqrt
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
comptime UP = Vector3(0, 1, 0)


def a_ramp_profile() raises -> Texture:
    """Return a profile 180 texels wide and two high: the first row's
    texel `i` is `i / 180`, and the second row is nine everywhere, so a
    read of the second row shows."""
    var data = List[Float32]()
    for row in range(2):
        for column in range(180):
            var red = Float32(column) / 180 if row == 0 else Float32(9)
            data.append(red)
            data.append(0)
            data.append(0)
            data.append(1)
    return float_texture(180, 2, data^)


def a_frame(angle: Angle, aspect: Float32) raises -> SIMD[DType.float32, 16]:
    """Return a projector's frame: a camera at the origin looking down
    -z, twice `angle` high and `aspect` times as wide."""
    var camera = PerspectiveCamera(
        angle.scaled(2), aspect, Length(0.5, METER), Length(50.0, METER)
    )
    camera.place(Vector3(0, 0, 0), Vector3(0, 0, -1))
    var matrix = camera.projection_matrix()
    matrix.multiply(camera.view_matrix())
    var frame = SIMD[DType.float32, 16](0)
    for element in range(16):
        frame[element] = matrix.elements[element]
    return frame


def a_lamp(
    mut scene: Scene, x: Float32, y: Float32, z: Float32
) raises -> NodeId:
    """Add a node at a point and return it."""
    var lamp = Object3D()
    lamp.set_position(x, y, z)
    return scene.add(lamp^)


# --- the shape type ---------------------------------------------------------


def test_a_spot_shape_is_one_of_three() raises:
    assert_true(CONE_SPOT.is_valid())
    assert_true(IES_SPOT.is_valid())
    assert_true(PROJECTOR_SPOT.is_valid())
    assert_false(SpotShape(-1).is_valid())
    assert_false(SpotShape(3).is_valid())


def test_every_light_starts_as_a_cone() raises:
    var spot = spot_light(WHITE, NodeId(0))
    assert_equal(spot.spot_shape, CONE_SPOT)
    assert_equal(spot.ies_map, NO_TEXTURE)
    assert_equal(spot.aspect, ASPECT_FROM_MAP)
    assert_equal(ambient_light(WHITE).spot_shape, CONE_SPOT)


def test_validate_refuses_a_shape_where_it_cannot_be() raises:
    var spot = spot_light(WHITE, NodeId(0))
    spot.spot_shape = SpotShape(3)
    with assert_raises(contains="none of the three"):
        spot.validate()
    var bulb = point_light(WHITE, NodeId(0))
    bulb.spot_shape = PROJECTOR_SPOT
    with assert_raises(contains="Only a spot light"):
        bulb.validate()
    # A cone that names an IES map is refused: only an IES light reads one.
    var cone = spot_light(WHITE, NodeId(0))
    cone.ies_map = TextureId(0)
    with assert_raises(contains="IES map"):
        cone.validate()


def test_validate_refuses_a_projectors_wrong_aspect() raises:
    var projector = projector_light(WHITE, NodeId(0), aspect=2)
    projector.validate()
    projector.aspect = -1
    with assert_raises(contains="aspect"):
        projector.validate()
    projector.aspect = nan[DType.float32]()
    with assert_raises(contains="aspect"):
        projector.validate()
    with assert_raises(contains="aspect"):
        _ = projector_light(WHITE, NodeId(0), aspect=inf[DType.float32]())
    # A cone does not read its aspect, so a wrong one is not checked.
    var cone = spot_light(WHITE, NodeId(0))
    cone.aspect = -1
    cone.validate()


# --- IES spot lights --------------------------------------------------------


def test_an_ies_spot_light_keeps_the_spot_lights_numbers() raises:
    var light = ies_spot_light(
        Color(255, 200, 100),
        NodeId(3),
        TextureId(2),
        4.0,
        9.0,
        Angle(40.0, DEGREE),
        0.25,
        1.5,
        NodeId(4),
    )
    assert_equal(light.spot_shape, IES_SPOT)
    assert_equal(light.ies_map, TextureId(2))
    assert_equal(light.intensity, 4.0)
    assert_equal(light.distance, 9.0)
    assert_almost_equal(light.angle.to(DEGREE), 40.0, atol=1e-4)
    assert_equal(light.penumbra, 0.25)
    assert_equal(light.decay, 1.5)
    assert_equal(light.target, NodeId(4))
    with assert_raises():
        _ = ies_spot_light(WHITE, NodeId(0), TextureId(0), intensity=-1)


def test_the_ies_coordinate_is_the_angle_over_pi_on_the_first_row() raises:
    # three.js: `vec2( angleCosine.acos().mul( 1.0 / Math.PI ), 0 )`.
    var on_axis = ies_coordinate(1, True)
    assert_almost_equal(on_axis.u, 0, atol=1e-6)
    # Under `flip_y`, v counts up from the bottom, so the first row is one.
    assert_equal(on_axis.v, 1)
    assert_equal(ies_coordinate(1, False).v, 0)
    assert_almost_equal(ies_coordinate(0, False).u, 0.5, atol=1e-6)
    assert_almost_equal(ies_coordinate(-1, False).u, 1, atol=1e-6)
    assert_almost_equal(
        ies_coordinate(Float32(cos(pi / 3)), False).u,
        Float32(1.0 / 3.0),
        atol=1e-6,
    )
    # Past one or below minus one, the cosine is clamped.
    assert_almost_equal(ies_coordinate(1.5, False).u, 0, atol=1e-6)
    assert_almost_equal(ies_coordinate(-1.5, False).u, 1, atol=1e-6)


def test_an_ies_profile_reads_its_first_row_linearly() raises:
    var profile = SpotProfile(
        0, IES_SPOT, TextureId(0), a_ramp_profile(), SIMD[DType.float32, 16](0)
    )
    # At sixty degrees, u is a third: texel 59.5, halfway between 59 and
    # 60 of 180. The second row's nines are never read.
    var sixty = profile.attenuation(
        Float32(cos(pi / 3)), Vector3(0, 0, 0), 0.5
    )
    assert_almost_equal(sixty, Float32(59.5 / 180), atol=1e-4)
    # On the axis the read is clamped to the first texel.
    assert_almost_equal(
        profile.attenuation(1, Vector3(0, 0, 0), 0.5), 0, atol=1e-6
    )
    # Straight back, to the last.
    assert_almost_equal(
        profile.attenuation(-1, Vector3(0, 0, 0), 0.5),
        Float32(179.0 / 180),
        atol=1e-5,
    )


def test_a_spot_profile_refuses_what_is_no_profile() raises:
    var frame = SIMD[DType.float32, 16](0)
    with assert_raises(contains="IES profile or a projector"):
        _ = SpotProfile(0, CONE_SPOT, NO_TEXTURE, Texture(), frame)
    with assert_raises(contains="must hold a texture"):
        _ = SpotProfile(0, IES_SPOT, NO_TEXTURE, a_ramp_profile(), frame)
    with assert_raises(contains="must hold a texture"):
        _ = SpotProfile(0, IES_SPOT, TextureId(0), Texture(), frame)
    # A projector holds no texture.
    var projector = SpotProfile(0, PROJECTOR_SPOT, NO_TEXTURE, Texture(), frame)
    var copied = SpotProfile(copy=projector)
    assert_equal(copied.shape, PROJECTOR_SPOT)
    assert_equal(copied.light, 0)
    assert_equal(copied.texture, NO_TEXTURE)


def test_which_lights_need_a_profile() raises:
    assert_false(needs_profile(point_light(WHITE, NodeId(0))))
    assert_false(needs_profile(spot_light(WHITE, NodeId(0))))
    # An IES light with no profile keeps its cone, as three.js's does.
    assert_false(needs_profile(ies_spot_light(WHITE, NodeId(0), NO_TEXTURE)))
    assert_true(needs_profile(ies_spot_light(WHITE, NodeId(0), TextureId(0))))
    assert_true(needs_profile(projector_light(WHITE, NodeId(0))))


# --- projectors -------------------------------------------------------------


def test_sd_box_is_three_js_signed_distance() raises:
    assert_almost_equal(sd_box(0, 0, 0.5), -0.5, atol=1e-6)
    assert_almost_equal(sd_box(0.25, 0, 0.5), -0.25, atol=1e-6)
    assert_almost_equal(sd_box(-0.1, 0.3, 0.5), -0.2, atol=1e-6)
    assert_almost_equal(sd_box(1, 0, 0.5), 0.5, atol=1e-6)
    assert_almost_equal(sd_box(1, -1, 0.5), Float32(sqrt(0.5)), atol=1e-6)


def test_a_projectors_beam_is_three_js_fade() raises:
    # A cone of sixty degrees and no penumbra: the penumbra cosine is a
    # half, its arc a third of pi, and the angle factor 3 / pi.
    var frame = a_frame(Angle(60.0, DEGREE), 1)
    var factor = Float32(3 / pi)
    var middle = projector_attenuation(frame, Vector3(0, 0, -5), 0.5)
    assert_almost_equal(middle, factor, atol=1e-5)
    # Halfway to the right edge the box distance is a quarter.
    var edge = Float32(5 * sqrt(3.0))
    var half = projector_attenuation(frame, Vector3(edge * 0.5, 0, -5), 0.5)
    assert_almost_equal(half, factor * 0.5, atol=1e-5)
    # Past the edge, nothing; behind the light, nothing.
    assert_equal(
        projector_attenuation(frame, Vector3(edge * 1.5, 0, -5), 0.5), 0
    )
    assert_equal(projector_attenuation(frame, Vector3(0, 0, 5), 0.5), 0)
    # A narrow cone saturates: the factor passes one.
    var narrow = a_frame(Angle(20.0, DEGREE), 1)
    assert_equal(
        projector_attenuation(
            narrow, Vector3(0, 0, -5), Float32(cos(pi / 9))
        ),
        1,
    )


def test_a_projectors_penumbra_cosine_is_capped() raises:
    # A penumbra of one gives a cosine of one, capped at 0.99999, whose arc
    # is small: the fade is a thin band at the edge.
    var frame = a_frame(Angle(60.0, DEGREE), 1)
    var factor = Float32(1) / acos(PROJECTOR_PENUMBRA_CAP)
    var edge = Float32(5 * sqrt(3.0))
    var near_edge = projector_attenuation(
        frame, Vector3(edge * 0.9999, 0, -5), 1
    )
    assert_almost_equal(near_edge, 0.0001 * 0.5 * 2 * factor, atol=2e-3)
    assert_equal(
        projector_attenuation(frame, Vector3(edge * 0.5, 0, -5), 1), 1
    )


def test_a_projectors_aspect_comes_from_it_or_its_map() raises:
    var textures = TextureStore()
    var wide = textures.add(checkerboard(32, 2, WHITE, Color(0, 0, 0)))
    var projector = projector_light(WHITE, NodeId(0), aspect=1.5)
    assert_equal(projector_aspect(projector, textures), 1.5)
    projector.aspect = ASPECT_FROM_MAP
    assert_equal(projector_aspect(projector, textures), 1)
    var slide = Texture(
        4, 2, List[UInt8](length=4 * 2 * 4, fill=UInt8(255))
    )
    projector.map = textures.add(slide^)
    assert_equal(projector_aspect(projector, textures), 2)
    # Every other spot light is square, whatever it holds.
    var cone = spot_light(WHITE, NodeId(0))
    cone.aspect = 3
    cone.map = wide
    assert_equal(projector_aspect(cone, textures), 1)
    projector.map = TextureId(9)
    with assert_raises():
        _ = projector_aspect(projector, textures)


# --- in the lighting --------------------------------------------------------


def a_shaped_scene(mut assets: Assets) raises -> Scene:
    """Return a scene with a cone, an IES light with a ramp profile, and a
    projector, each two meters up over the origin, pointing down."""
    var scene = Scene()
    var profile = assets.textures.add(a_ramp_profile())
    scene.add_light(
        spot_light(WHITE, a_lamp(scene, 0, 2, 0), 3.0, angle=Angle(60.0, DEGREE))
    )
    scene.add_light(
        ies_spot_light(
            WHITE,
            a_lamp(scene, 0, 2, 0),
            profile,
            3.0,
            angle=Angle(60.0, DEGREE),
        )
    )
    scene.add_light(
        projector_light(
            WHITE, a_lamp(scene, 0, 2, 0), 3.0, angle=Angle(60.0, DEGREE)
        )
    )
    scene.update()
    return scene^


def test_the_renderer_builds_a_profile_for_each_shaped_light() raises:
    var assets = Assets()
    var scene = a_shaped_scene(assets)
    var profiles = Renderer(8, 8).spot_profiles(scene, assets)
    assert_equal(len(profiles), 2)
    assert_equal(profiles[0].light, 1)
    assert_equal(profiles[0].shape, IES_SPOT)
    assert_equal(profiles[0].texture, TextureId(0))
    assert_equal(profiles[0].image.width, 180)
    assert_equal(profiles[1].light, 2)
    assert_equal(profiles[1].shape, PROJECTOR_SPOT)
    assert_equal(profiles[1].texture, NO_TEXTURE)
    # The projector's frame is its shadow camera: two meters up looking
    # down, so the origin lands in the middle, but for the ten-thousandth
    # `look_at` turns a camera by when it looks along its up vector.
    var middle = projector_attenuation(
        profiles[1].frame, Vector3(0, 0, 0), Float32(cos(pi / 3))
    )
    assert_almost_equal(middle, Float32(3 / pi), atol=1e-3)


def test_a_light_off_the_cameras_layers_or_hidden_has_no_profile() raises:
    var assets = Assets()
    var scene = a_shaped_scene(assets)
    scene.lights[1].layers.set(1)
    var renderer = Renderer(8, 8)
    var profiles = renderer.spot_profiles(scene, assets, Layers())
    assert_equal(len(profiles), 1)
    assert_equal(profiles[0].light, 2)
    var hidden = scene.lights[2].node
    scene.node(hidden).visible = False
    scene.update()
    assert_equal(len(renderer.spot_profiles(scene, assets, Layers())), 0)


def test_an_ies_profile_shapes_the_light_in_the_lighting() raises:
    # A surface at (2, 0, 0) facing up sees the bulb forty-five degrees
    # off its axis: the ramp gives 44.5 / 180, where the cone gives one.
    var assets = Assets()
    var scene = a_shaped_scene(assets)
    var renderer = Renderer(8, 8)
    var lighting = Lighting(
        scene, profiles=renderer.spot_profiles(scene, assets)
    )
    var at = Vector3(2, 0, 0)
    var angle_cos = Float32(sqrt(0.5))
    assert_equal(lighting.spot_attenuation(0, angle_cos, at), 1)
    var shaped = lighting.spot_attenuation(1, angle_cos, at)
    assert_almost_equal(shaped, Float32(44.5 / 180), atol=1e-4)
    # And the whole sum: the cone, the profile and the projector, each
    # times its Lambert cosine and its falloff, over pi.
    var distance = Float32(sqrt(8.0))
    var bare = Float32(sqrt(0.5)) * falloff(distance, 2, 0)
    var projected = lighting.spot_attenuation(2, angle_cos, at)
    var radiance = scene.lights[0].radiance().r
    var expected = (radiance * bare * (1 + shaped + projected)) * RECIPROCAL_PI
    assert_almost_equal(
        lighting.intensity_at(UP, at).r, expected, atol=1e-5
    )


def test_a_projector_shapes_the_light_in_the_lighting() raises:
    var assets = Assets()
    var scene = a_shaped_scene(assets)
    var profiles = Renderer(8, 8).spot_profiles(scene, assets)
    var frame = profiles[1].frame
    var lighting = Lighting(scene, profiles=profiles^)
    var at = Vector3(0.5, 0, 0.25)
    var shaped = lighting.spot_attenuation(2, 0.9, at)
    assert_equal(
        shaped,
        projector_attenuation(frame, at, lighting.penumbra_cosines[2]),
    )
    assert_true(shaped > 0.5, "the projector did not reach the floor")


def test_the_lighting_refuses_a_missing_or_wrong_profile() raises:
    var assets = Assets()
    var scene = a_shaped_scene(assets)
    with assert_raises(contains="needs its profile"):
        _ = Lighting(scene)
    var profiles = Renderer(8, 8).spot_profiles(scene, assets)
    var frame = SIMD[DType.float32, 16](0)
    var stray = profiles.copy()
    stray.append(SpotProfile(5, PROJECTOR_SPOT, NO_TEXTURE, Texture(), frame))
    with assert_raises(contains="not there"):
        _ = Lighting(scene, profiles=stray^)
    var negative = profiles.copy()
    negative.append(
        SpotProfile(-1, PROJECTOR_SPOT, NO_TEXTURE, Texture(), frame)
    )
    with assert_raises(contains="not there"):
        _ = Lighting(scene, profiles=negative^)
    # A profile on a light of another kind, or another shape.
    var bulb = Scene()
    bulb.add_light(ambient_light(WHITE))
    var one = List[SpotProfile]()
    one.append(SpotProfile(0, PROJECTOR_SPOT, NO_TEXTURE, Texture(), frame))
    with assert_raises(contains="not a spot of its shape"):
        _ = Lighting(bulb, profiles=one^)
    var crossed = List[SpotProfile]()
    crossed.append(
        SpotProfile(1, PROJECTOR_SPOT, NO_TEXTURE, Texture(), frame)
    )
    with assert_raises(contains="not a spot of its shape"):
        _ = Lighting(scene, profiles=crossed^)
    # An IES light with no profile keeps its cone and needs none.
    var plain = Scene()
    plain.add_light(
        ies_spot_light(WHITE, a_lamp(plain, 0, 2, 0), NO_TEXTURE, 3.0)
    )
    plain.update()
    var lighting = Lighting(plain)
    assert_equal(lighting.spot_attenuation(0, 1, Vector3(0, 0, 0)), 1)


def test_the_uniform_lighting_has_no_profile() raises:
    var lighting = Lighting.uniform()
    assert_equal(len(lighting.spot_profiles), 0)
    assert_equal(len(lighting.spot_profile_slots), 0)


# --- drawn ------------------------------------------------------------------


def a_floor_under(mut assets: Assets, var scene: Scene) raises -> Scene:
    """Add a gray floor twelve meters wide at y = 0 to a scene."""
    var ground = Object3D()
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var floor = assets.geometries.add(
        plane(Length(12.0, METER), Length(12.0, METER), 4, 4)
    )
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    scene.add_mesh(Mesh(floor, paint, scene.add(ground^)))
    scene.update()
    return scene^


def a_top_camera() raises -> PerspectiveCamera:
    """Return a camera eight meters up looking straight down."""
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1.0, Length(0.1, METER), Length(50.0, METER)
    )
    camera.place(Vector3(0, 8, 0.001), Vector3(0, 0, 0))
    return camera^


def test_a_wide_projector_lights_a_wide_rectangle() raises:
    # A projector twice as wide as high lights the floor further along x
    # than along z, where a square one lights both alike.
    var assets = Assets()
    var scene = Scene()
    scene.add_light(
        projector_light(
            WHITE,
            a_lamp(scene, 0, 2, 0),
            20.0,
            angle=Angle(30.0, DEGREE),
            aspect=2,
            target=a_lamp(scene, 0, 0, 0),
        )
    )
    scene = a_floor_under(assets, scene^)
    var renderer = Renderer(32, 32)
    var image = renderer.render(scene, assets, a_top_camera())
    var across = 0
    var down = 0
    for step in range(32):
        if image.get_pixel(step, 16).r > 0:
            across += 1
        if image.get_pixel(16, step).r > 0:
            down += 1
    assert_true(across > down + 2, "the rectangle is not wider than high")
    assert_true(down > 0, "the projector lit nothing")
    # Its map is projected through the same wide camera.
    var maps_scene = Scene()
    var slide = assets.textures.add(checkerboard(8, 2, WHITE, Color(0, 0, 0)))
    var mapped = projector_light(
        WHITE, a_lamp(maps_scene, 0, 2, 0), 20.0, angle=Angle(30.0, DEGREE)
    )
    mapped.map = slide
    maps_scene.add_light(mapped)
    maps_scene.update()
    var maps = renderer.spot_light_maps(maps_scene, assets)
    var profiles = renderer.spot_profiles(maps_scene, assets)
    assert_equal(maps[0].frame, profiles[0].frame)


def test_an_ies_light_draws_in_every_shading_mode() raises:
    # The profile is the light's, not a surface's texture, so the lit
    # shading reads it too: the floor under the axis is dark, as the ramp
    # starts at zero, and brighter away from it.
    var assets = Assets()
    var scene = Scene()
    var profile = assets.textures.add(a_ramp_profile())
    scene.add_light(
        ies_spot_light(
            WHITE, a_lamp(scene, 0, 2, 0), profile, 40.0, angle=Angle(80.0, DEGREE)
        )
    )
    scene = a_floor_under(assets, scene^)
    var image = Renderer(32, 32).render(scene, assets, a_top_camera())
    var middle = image.get_pixel(16, 16).r
    var aside = image.get_pixel(22, 16).r
    assert_true(aside > middle, "the profile did not brighten off the axis")


def test_a_real_ies_lamp_lights_the_floor() raises:
    # three.js's own path: a file read, its texture made, and the light.
    var assets = Assets()
    var scene = Scene()
    var lamp = read_ies("assets/ies/full.ies")
    var profile = assets.textures.add(ies_texture(lamp, IES_FLOAT))
    scene.add_light(
        ies_spot_light(WHITE, a_lamp(scene, 0, 2, 0), profile, 40.0)
    )
    scene = a_floor_under(assets, scene^)
    var image = Renderer(16, 16).render(scene, assets, a_top_camera())
    var lit = 0
    for y in range(16):
        for x in range(16):
            if image.get_pixel(x, y).r > 0:
                lit += 1
    assert_true(lit > 0, "the lamp lit nothing")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
