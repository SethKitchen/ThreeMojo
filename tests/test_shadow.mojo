# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `lights.shadow`: the map, its coordinate, its taps and the
lighting that reads it, apart from any renderer."""

from cameras.perspective_camera import PerspectiveCamera
from core.layers import Layers
from core.object3d import Object3D
from core.scene import Scene
from lights.light import (
    ambient_light,
    directional_light,
    hemisphere_light,
    point_light,
    rect_area_light,
    spot_light,
)
from lights.lighting import Lighting, Reflected, physical_surface
from lights.shadow import (
    DEFAULT_MAP_SIZE,
    DEFAULT_SHADOW_EXTENT,
    DEFAULT_SHADOW_FAR,
    DEFAULT_SHADOW_NEAR,
    DEFAULT_SHADOW_RADIUS,
    CUBE_FACES,
    MAX_MAP_SIZE,
    PCF_TAPS,
    SHADOW_HEADER,
    SPOT_MAP_FLOATS,
    LightShadow,
    ShadowMap,
    SpotLightMap,
    biased_position,
    cube_direction,
    cube_face,
    cube_stored,
    cube_tap,
    cube_texel,
    cube_up,
    inside_point_shadow,
    inside_shadow_map,
    inside_spot_map,
    point_shadow_depth,
    point_shadow_spread,
    point_shadow_tap,
    shadow_coordinate,
    shadow_tap,
    shadow_texel,
)
from math.vector3 import Vector3
from render.framebuffer import Color, Framebuffer
from render.texture import NEAREST, Texture, texture_of
from render.texture_store import NO_TEXTURE, TextureId
from std.math import inf, nan, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER

comptime UP = Vector3(0, 0, 1)
comptime ORIGIN = Vector3(0, 0, 0)
comptime FULL = Float32(pi)


def flat_frame() -> SIMD[DType.float32, 16]:
    """Return the frame of an orthographic light looking down -z from
    z = 1 over the unit square: x and y pass through, and z runs from
    -1 at z = 1 to 1 at z = -1."""
    var frame = SIMD[DType.float32, 16](0)
    frame[0] = 1
    frame[5] = 1
    frame[10] = -1
    frame[15] = 1
    return frame


def half_map(size: Int = 4) raises -> ShadowMap:
    """Return a map over the unit square whose left half holds a caster
    at z = 0.5 and whose right half holds nothing."""
    var depths = List[Float32]()
    for _ in range(size):
        for column in range(size):
            if column < size // 2:
                depths.append(-0.5)
            else:
                depths.append(inf[DType.float32]())
    return ShadowMap(0, size, flat_frame(), depths^, 0, 0, 0)


def scene_with_sun(cast: Bool) raises -> Scene:
    """Return a scene with one white sun up the z axis, casting or not."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    var sun = directional_light(Color(255, 255, 255), node, FULL)
    sun.cast_shadow = cast
    scene.add_light(sun)
    scene.update()
    return scene^


# --- the settings -----------------------------------------------------------


def test_a_light_shadow_starts_at_three_js_defaults() raises:
    var shadow = LightShadow()
    assert_equal(shadow.map_size, DEFAULT_MAP_SIZE)
    assert_equal(shadow.map_size, 512)
    assert_equal(shadow.bias, Float32(0))
    assert_equal(shadow.normal_bias, Float32(0))
    assert_equal(shadow.radius, DEFAULT_SHADOW_RADIUS)
    assert_equal(shadow.near.to(METER), DEFAULT_SHADOW_NEAR.to(METER))
    assert_equal(shadow.far.to(METER), DEFAULT_SHADOW_FAR.to(METER))
    assert_equal(shadow.extent.to(METER), DEFAULT_SHADOW_EXTENT.to(METER))
    shadow.validate()
    # And a light carries one, not casting.
    var scene = scene_with_sun(False)
    assert_false(scene.lights[0].cast_shadow)
    assert_equal(scene.lights[0].shadow.map_size, 512)


def test_a_light_shadow_refuses_what_no_map_can_be_built_from() raises:
    for size in [0, -1, MAX_MAP_SIZE + 1]:
        var shadow = LightShadow()
        shadow.map_size = size
        with assert_raises():
            shadow.validate()
    var edge = LightShadow()
    edge.map_size = MAX_MAP_SIZE
    edge.validate()
    edge.map_size = 1
    edge.validate()
    for wrong in [nan[DType.float32](), inf[DType.float32]()]:
        var bias = LightShadow()
        bias.bias = wrong
        with assert_raises():
            bias.validate()
        var normal = LightShadow()
        normal.normal_bias = wrong
        with assert_raises():
            normal.validate()
        var radius = LightShadow()
        radius.radius = wrong
        with assert_raises():
            radius.validate()
        var near = LightShadow()
        near.near = Length(wrong, METER)
        with assert_raises():
            near.validate()
        var far = LightShadow()
        far.far = Length(wrong, METER)
        with assert_raises():
            far.validate()
        var extent = LightShadow()
        extent.extent = Length(wrong, METER)
        with assert_raises():
            extent.validate()
    var negative = LightShadow()
    negative.radius = -1
    with assert_raises():
        negative.validate()
    var behind = LightShadow()
    behind.near = Length(-1.0, METER)
    with assert_raises():
        behind.validate()
    var crossed = LightShadow()
    crossed.far = Length(0.5, METER)
    with assert_raises():
        crossed.validate()
    var thin = LightShadow()
    thin.extent = Length(0.0, METER)
    with assert_raises():
        thin.validate()
    # A negative bias is allowed: it moves the fragment toward the light.
    var toward = LightShadow()
    toward.bias = -0.01
    toward.radius = 0
    toward.near = Length(0.0, METER)
    toward.validate()


def test_only_a_directional_point_or_spot_light_casts() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    var bulb = Object3D()
    bulb.set_position(0, 0, 1)
    var bulb_node = scene.add(bulb^)
    var sun = directional_light(Color(255, 255, 255), bulb_node)
    sun.cast_shadow = True
    sun.validate()
    var beam = spot_light(Color(255, 255, 255), bulb_node)
    beam.cast_shadow = True
    beam.validate()
    var point = point_light(Color(255, 255, 255), bulb_node)
    point.cast_shadow = True
    point.validate()
    var panel = rect_area_light(Color(255, 255, 255), bulb_node)
    panel.cast_shadow = True
    with assert_raises():
        panel.validate()
    var fill = ambient_light(Color(255, 255, 255))
    fill.cast_shadow = True
    with assert_raises():
        fill.validate()
    var sky = hemisphere_light(Color(255, 255, 255), Color(0, 0, 0), bulb_node)
    sky.cast_shadow = True
    with assert_raises():
        sky.validate()
    # A casting light's shadow is validated with it, and `Lighting` asks.
    sun.shadow.map_size = 0
    with assert_raises():
        sun.validate()
    scene.add_light(sun)
    scene.update()
    with assert_raises():
        _ = Lighting(scene)
    _ = node


# --- the arithmetic ---------------------------------------------------------


def test_a_map_holds_a_square_of_depths() raises:
    var map = half_map(4)
    assert_equal(map.size, 4)
    assert_equal(len(map.depths), 16)
    assert_equal(map.light, 0)
    with assert_raises():
        _ = ShadowMap(0, 0, flat_frame(), List[Float32](), 0, 0, 1)
    with assert_raises():
        _ = ShadowMap(0, 2, flat_frame(), [Float32(0), 0, 0], 0, 0, 1)


def test_a_world_position_lands_on_the_map_by_the_frame() raises:
    # The unit square maps to the whole map, left to right and top to
    # bottom, and z = 0.5 under a light at z = 1 lands a quarter of the
    # way from the near plane.
    var place = shadow_coordinate(flat_frame(), Vector3(-1, 1, 1))
    assert_almost_equal(place.x, Float32(0), atol=1e-6)
    assert_almost_equal(place.y, Float32(0), atol=1e-6)
    assert_almost_equal(place.z, Float32(0), atol=1e-6)
    var corner = shadow_coordinate(flat_frame(), Vector3(1, -1, -1))
    assert_almost_equal(corner.x, Float32(1), atol=1e-6)
    assert_almost_equal(corner.y, Float32(1), atol=1e-6)
    assert_almost_equal(corner.z, Float32(1), atol=1e-6)
    var middle = shadow_coordinate(flat_frame(), Vector3(0, 0, 0.5))
    assert_almost_equal(middle.x, Float32(0.5), atol=1e-6)
    assert_almost_equal(middle.z, Float32(0.25), atol=1e-6)
    assert_true(inside_shadow_map(middle))
    # Off the map, or past the far plane, is not inside.
    assert_false(inside_shadow_map(Vector3(-0.1, 0.5, 0.5)))
    assert_false(inside_shadow_map(Vector3(1.1, 0.5, 0.5)))
    assert_false(inside_shadow_map(Vector3(0.5, -0.1, 0.5)))
    assert_false(inside_shadow_map(Vector3(0.5, 1.1, 0.5)))
    assert_false(inside_shadow_map(Vector3(0.5, 0.5, 1.1)))
    # A position behind the light's camera is put past the far plane.
    var frame = flat_frame()
    frame[15] = 0
    frame[11] = 1
    var behind = shadow_coordinate(frame, Vector3(0, 0, -1))
    assert_equal(behind.z, Float32(2))
    assert_false(inside_shadow_map(behind))
    # The normal bias moves the position along the normal first.
    var moved = biased_position(Vector3(1, 2, 3), Vector3(0, 0, 1), 0.5)
    assert_equal(moved.z, Float32(3.5))
    assert_equal(moved.x, Float32(1))


def test_the_nine_taps_step_across_then_down_and_stop_at_the_edges() raises:
    # At the middle of a four-texel map with a radius of one, the taps
    # read the three-by-three block around texel (2, 2).
    var place = Vector3(0.6, 0.6, 0.5)
    assert_equal(shadow_texel(place, 0, 1, 4), 1 * 4 + 1)
    assert_equal(shadow_texel(place, 1, 1, 4), 1 * 4 + 2)
    assert_equal(shadow_texel(place, 2, 1, 4), 1 * 4 + 3)
    assert_equal(shadow_texel(place, 3, 1, 4), 2 * 4 + 1)
    assert_equal(shadow_texel(place, 4, 1, 4), 2 * 4 + 2)
    assert_equal(shadow_texel(place, 8, 1, 4), 3 * 4 + 3)
    # A radius of zero reads the one texel nine times.
    for tap in range(PCF_TAPS):
        assert_equal(shadow_texel(place, tap, 0, 4), 2 * 4 + 2)
    # Past an edge, the edge.
    assert_equal(shadow_texel(Vector3(0, 0, 0.5), 0, 1, 4), 0)
    assert_equal(shadow_texel(Vector3(1, 1, 0.5), 8, 1, 4), 15)
    assert_equal(shadow_texel(Vector3(0, 1, 0.5), 6, 2, 4), 12)


def test_a_tap_is_lit_when_the_fragment_is_not_beyond_the_stored_depth() raises:
    # Stored -0.5 is a quarter of the way in: a fragment at that depth is
    # lit, one beyond it shadowed, and the bias moves the line.
    assert_equal(shadow_tap(-0.5, 0.25, 0), Float32(1))
    assert_equal(shadow_tap(-0.5, 0.2, 0), Float32(1))
    assert_equal(shadow_tap(-0.5, 0.3, 0), Float32(0))
    assert_equal(shadow_tap(-0.5, 0.3, -0.1), Float32(1))
    assert_equal(shadow_tap(-0.5, 0.2, 0.1), Float32(0))
    # Nothing stored is nothing in the way.
    assert_equal(shadow_tap(inf[DType.float32](), 1, 0), Float32(1))
    assert_equal(SHADOW_HEADER, 20)


def test_a_map_lights_a_surface_by_how_many_taps_find_nothing() raises:
    var map = half_map(4)
    # Under the caster, deeper than it: all nine taps shadowed.
    assert_equal(map.lit(Vector3(-0.75, 0, 0), UP), Float32(0))
    # Above the caster: lit.
    assert_equal(map.lit(Vector3(-0.75, 0, 0.75), UP), Float32(1))
    # Where nothing was drawn: lit.
    assert_equal(map.lit(Vector3(0.75, 0, -0.5), UP), Float32(1))
    # Off the map: lit.
    assert_equal(map.lit(Vector3(3, 0, 0), UP), Float32(1))
    # On the seam with a radius of one, the taps straddle it: a third of
    # them read the lit half.
    var soft = ShadowMap(0, 4, flat_frame(), map.depths.copy(), 0, 0, 1)
    var edge = soft.lit(Vector3(-0.05, 0, 0), UP)
    assert_true(edge > 0 and edge < 1, "the edge was not softened")
    assert_almost_equal(edge, Float32(1) / 3, atol=1e-6)
    # The normal bias lifts the surface out of its own shadow.
    var lifted = ShadowMap(0, 4, flat_frame(), map.depths.copy(), 0, 0.6, 0)
    assert_equal(lifted.lit(Vector3(-0.75, 0, 0), UP), Float32(1))
    # And the depth bias does the same in the map's depth.
    var eased = ShadowMap(0, 4, flat_frame(), map.depths.copy(), -0.3, 0, 0)
    assert_equal(eased.lit(Vector3(-0.75, 0, 0), UP), Float32(1))


# --- through the lighting ---------------------------------------------------


def test_lighting_matches_each_map_to_its_light_and_reads_it() raises:
    var scene = scene_with_sun(True)
    var maps = List[ShadowMap]()
    maps.append(half_map(4))
    var lighting = Lighting(scene, shadows=maps^)
    assert_equal(len(lighting.shadows), 1)
    assert_equal(lighting.direction_shadows[0], 0)
    # Under the caster nothing but the ambient arrives, which is none.
    var dark = lighting.intensity_at(UP, Vector3(-0.75, 0, 0))
    assert_equal(dark.r, Float32(0))
    var bright = lighting.intensity_at(UP, Vector3(0.75, 0, 0))
    assert_almost_equal(bright.r, Float32(1), atol=1e-6)
    # A surface that does not receive is lit whatever the map says.
    var unshadowed = lighting.intensity_at(UP, Vector3(-0.75, 0, 0), False)
    assert_equal(unshadowed.r, bright.r)
    # The mask says the same.
    assert_equal(lighting.shadow_mask(Vector3(-0.75, 0, 0), UP), Float32(0))
    assert_equal(lighting.shadow_mask(Vector3(0.75, 0, 0), UP), Float32(1))
    # A light without a map compares against nothing.
    var plain = Lighting(scene_with_sun(True))
    assert_equal(plain.direction_shadows[0], -1)
    assert_almost_equal(
        plain.intensity_at(UP, Vector3(-0.75, 0, 0)).r, Float32(1), atol=1e-6
    )
    assert_equal(plain.shadow_mask(Vector3(-0.75, 0, 0), UP), Float32(1))
    assert_equal(Lighting.uniform().shadow_mask(ORIGIN, UP), Float32(1))


def test_every_lit_sum_is_shadowed_alike() raises:
    # The toon, the highlight and the physical sums all read the map the
    # diffuse sum reads, and a surface that does not receive skips it in
    # every one.
    var scene = scene_with_sun(True)
    var maps = List[ShadowMap]()
    maps.append(half_map(4))
    var lighting = Lighting(
        scene, Layers.all(), Vector3(0, 0, 4), shadows=maps^
    )
    var under = Vector3(-0.75, 0, 0)
    var clear = Vector3(0.75, 0, 0)
    var ramp = List[Float32]()
    assert_true(
        lighting.toon_at(UP, under, ramp).r
        < lighting.toon_at(UP, clear, ramp).r,
        "the toon sum ignored the shadow",
    )
    assert_equal(
        lighting.toon_at(UP, under, ramp, False).r,
        lighting.toon_at(UP, clear, ramp).r,
    )
    var sheen = Vector3(1, 1, 1)
    assert_equal(lighting.specular_at(UP, under, sheen, 30).r, Float32(0))
    assert_true(
        lighting.specular_at(UP, clear, sheen, 30).r > 0,
        "the clear side lost its highlight",
    )
    assert_equal(
        lighting.specular_at(UP, under, sheen, 30, False).r,
        lighting.specular_at(UP, clear, sheen, 30).r,
    )
    var chalk = physical_surface(
        Vector3(1, 1, 1), Vector3(0.04, 0.04, 0.04), 0, 1
    )
    var shaded = lighting.physical_at(UP, UP, under, chalk, 1, 1, 0.1)
    assert_equal(shaded.diffuse.x, Float32(0))
    assert_equal(shaded.clearcoat.x, Float32(0))
    var lit = lighting.physical_at(UP, UP, clear, chalk, 1, 1, 0.1)
    assert_true(lit.diffuse.x > 0, "the clear side was dark")
    assert_equal(
        lighting.physical_at(UP, UP, under, chalk, 1, 1, 0.1, False).diffuse.x,
        lit.diffuse.x,
    )


def test_a_spot_lights_shadow_is_read_by_the_spot_sums() raises:
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    var beam = spot_light(
        Color(255, 255, 255), node, FULL, angle=Angle(80.0, DEGREE)
    )
    beam.cast_shadow = True
    scene.add_light(beam)
    scene.update()
    var maps = List[ShadowMap]()
    maps.append(half_map(4))
    var lighting = Lighting(
        scene, Layers.all(), Vector3(0, 0, 4), shadows=maps^
    )
    assert_equal(lighting.spot_shadows[0], 0)
    var under = Vector3(-0.3, 0, 0)
    var clear = Vector3(0.3, 0, 0)
    assert_equal(lighting.intensity_at(UP, under).r, Float32(0))
    assert_true(lighting.intensity_at(UP, clear).r > 0, "the spot lit nothing")
    assert_equal(
        lighting.intensity_at(UP, under, False).r,
        lighting.intensity_at(UP, clear).r,
    )
    var ramp = List[Float32]()
    assert_true(
        lighting.toon_at(UP, under, ramp).r
        < lighting.toon_at(UP, clear, ramp).r
    )
    assert_equal(
        lighting.specular_at(UP, under, Vector3(1, 1, 1), 30).r, Float32(0)
    )
    var chalk = physical_surface(
        Vector3(1, 1, 1), Vector3(0.04, 0.04, 0.04), 0, 1
    )
    assert_equal(
        lighting.physical_at(UP, UP, under, chalk, 1, 0, 0.1).diffuse.x,
        Float32(0),
    )
    assert_equal(lighting.shadow_mask(under, UP), Float32(0))


def test_a_map_naming_the_wrong_light_is_refused() raises:
    var scene = scene_with_sun(True)
    scene.add_light(ambient_light(Color(255, 255, 255)))
    var wrong = List[ShadowMap]()
    wrong.append(
        ShadowMap(1, 4, flat_frame(), half_map(4).depths.copy(), 0, 0, 1)
    )
    with assert_raises():
        _ = Lighting(scene, shadows=wrong^)
    var missing = List[ShadowMap]()
    missing.append(
        ShadowMap(7, 4, flat_frame(), half_map(4).depths.copy(), 0, 0, 1)
    )
    with assert_raises():
        _ = Lighting(scene, shadows=missing^)
    var negative = List[ShadowMap]()
    negative.append(
        ShadowMap(-1, 4, flat_frame(), half_map(4).depths.copy(), 0, 0, 1)
    )
    with assert_raises():
        _ = Lighting(scene, shadows=negative^)


def test_two_casting_lights_each_find_their_own_map() raises:
    # The maps arrive in any order, and each light is matched by the
    # index its map names: the spot light's map first, the sun's second.
    var scene = scene_with_sun(True)
    var post = Object3D()
    post.set_position(0, 0, 2)
    var post_node = scene.add(post^)
    var beam = spot_light(Color(255, 255, 255), post_node, FULL)
    beam.cast_shadow = True
    scene.add_light(beam)
    scene.update()
    var maps = List[ShadowMap]()
    var spot_map = half_map(4)
    spot_map.light = 1
    maps.append(spot_map^)
    maps.append(half_map(4))
    var lighting = Lighting(scene, shadows=maps^)
    assert_equal(lighting.direction_shadows[0], 1)
    assert_equal(lighting.spot_shadows[0], 0)
    assert_equal(lighting.shadow_mask(Vector3(-0.75, 0, 0), UP), Float32(0))
    assert_equal(lighting.shadow_mask(Vector3(0.75, 0, 0), UP), Float32(1))


# --- point light shadows ----------------------------------------------------


def test_a_light_with_a_distance_puts_its_shadow_far_plane_there() raises:
    # three.js's `light.distance || camera.far`; a distance at or inside
    # the near plane leaves the camera no depth, and is refused when the
    # light casts or projects a map.
    var scene = Scene()
    var node = scene.add(Object3D())
    var bulb = point_light(Color(255, 255, 255), node)
    assert_equal(bulb.shadow_far().to(METER), DEFAULT_SHADOW_FAR.to(METER))
    bulb.distance = 12
    assert_equal(bulb.shadow_far().to(METER), Float32(12))
    bulb.distance = 0.5
    bulb.validate()
    bulb.cast_shadow = True
    with assert_raises():
        bulb.validate()
    bulb.distance = 0.6
    bulb.validate()
    var beam = spot_light(Color(255, 255, 255), node, distance=0.25)
    beam.validate()
    beam.map = TextureId(0)
    with assert_raises():
        beam.validate()
    beam.distance = 0
    beam.validate()
    # A mapped light's shadow settings are asked even when it does not
    # cast, because its map is projected through the shadow's camera.
    beam.shadow.map_size = 0
    with assert_raises():
        beam.validate()


def test_only_a_spot_light_projects_a_map() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    var bulb = point_light(Color(255, 255, 255), node)
    assert_equal(bulb.map, NO_TEXTURE)
    bulb.map = TextureId(0)
    with assert_raises():
        bulb.validate()
    var beam = spot_light(Color(255, 255, 255), node)
    beam.map = TextureId(0)
    beam.validate()


def test_a_cube_holds_six_squares_of_distances() raises:
    var cube = ShadowMap(
        cube_of=2,
        size=2,
        origin=Vector3(1, 2, 3),
        near=0.5,
        far=10,
        depths=List[Float32](length=24, fill=1),
        bias=0,
        normal_bias=0,
        radius=1,
    )
    assert_true(cube.cube)
    assert_equal(cube.light, 2)
    assert_equal(cube.far, Float32(10))
    assert_equal(cube.origin.y, Float32(2))
    assert_false(half_map(2).cube)
    assert_equal(CUBE_FACES, 6)
    with assert_raises():
        _ = ShadowMap(
            cube_of=0,
            size=0,
            origin=ORIGIN,
            near=0.5,
            far=10,
            depths=List[Float32](),
            bias=0,
            normal_bias=0,
            radius=1,
        )
    with assert_raises():
        _ = ShadowMap(
            cube_of=0,
            size=2,
            origin=ORIGIN,
            near=0.5,
            far=10,
            depths=List[Float32](length=4, fill=1),
            bias=0,
            normal_bias=0,
            radius=1,
        )
    with assert_raises():
        _ = ShadowMap(
            cube_of=0,
            size=2,
            origin=ORIGIN,
            near=10,
            far=10,
            depths=List[Float32](length=24, fill=1),
            bias=0,
            normal_bias=0,
            radius=1,
        )


def test_the_six_faces_look_along_three_js_directions_and_ups() raises:
    # `_cubeDirections`: +x, -x, +z, -z, +y, -y; `_cubeUps`: +y four
    # times, then +z and -z.
    var ways = [
        Vector3(1, 0, 0),
        Vector3(-1, 0, 0),
        Vector3(0, 0, 1),
        Vector3(0, 0, -1),
        Vector3(0, 1, 0),
        Vector3(0, -1, 0),
    ]
    var ups = [
        Vector3(0, 1, 0),
        Vector3(0, 1, 0),
        Vector3(0, 1, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 1),
        Vector3(0, 0, -1),
    ]
    for face in range(CUBE_FACES):
        assert_equal(cube_direction(face).dot(ways[face]), Float32(1))
        assert_equal(cube_up(face).dot(ups[face]), Float32(1))
        # Each direction finds its own face.
        assert_equal(cube_face(ways[face]), face)


def test_a_direction_finds_its_face_z_first_then_x_then_y() raises:
    # The largest component wins; on a tie z beats x and y, and x beats y,
    # the order `cubeToUV` asks in.
    assert_equal(cube_face(Vector3(1, 1, 1)), 2)
    assert_equal(cube_face(Vector3(1, 1, -1)), 3)
    assert_equal(cube_face(Vector3(-1, 1, 0.5)), 1)
    assert_equal(cube_face(Vector3(1, 1, 0.5)), 0)
    assert_equal(cube_face(Vector3(0.2, 1, 0.5)), 4)
    assert_equal(cube_face(Vector3(0.2, -1, 0.5)), 5)
    assert_equal(cube_face(Vector3(1, 0.2, 2)), 2)


def test_a_direction_reads_the_texel_the_face_camera_drew_it_in() raises:
    # Every face's camera, placed at the origin as the renderer places it,
    # projects a direction onto the texel `cube_texel` names.
    var size = 8
    var scene = Scene()
    scene.update()
    var probes = [
        Vector3(0.3, -0.6, 0.1),
        Vector3(-0.7, 0.2, 0.45),
        Vector3(0.05, 0.9, -0.3),
    ]
    for face in range(CUBE_FACES):
        var camera = PerspectiveCamera(
            Angle(90.0, DEGREE), 1.0, Length(0.5, METER), Length(10.0, METER)
        )
        camera.up = cube_up(face)
        camera.place(ORIGIN, cube_direction(face))
        var frame = camera.projection_matrix()
        frame.multiply(camera.view_matrix_in(scene))
        var held = SIMD[DType.float32, 16](0)
        for element in range(16):
            held[element] = frame.elements[element]
        var forward = cube_direction(face)
        for probe in probes:
            # Turned onto this face: the face's own axis, with the probe's
            # other two components beside it, still on this face.
            var way = Vector3(
                forward.x + probe.x * (1 - abs(forward.x)),
                forward.y + probe.y * (1 - abs(forward.y)),
                forward.z + probe.z * (1 - abs(forward.z)),
            )
            assert_equal(cube_face(way), face)
            var place = shadow_coordinate(held, way * 2)
            var expected = face * size * size + shadow_texel(place, 4, 0, size)
            assert_equal(cube_texel(way, size), expected)
    # On the far edges the last column and the last row are read.
    assert_equal(cube_texel(Vector3(-1, 0.1, 1), 4), 2 * 16 + 1 * 4 + 3)
    assert_equal(cube_texel(Vector3(0.1, -1, 1), 4), 2 * 16 + 3 * 4 + 1)


def test_the_nine_cube_taps_follow_three_js_order() raises:
    # xyy, yyy, xyx, yyx, the direction, xxy, yxy, xxx, yxx, where x is
    # minus the spread and y plus it.
    var way = Vector3(0, 0, 1)
    var signs = [
        Vector3(-1, 1, 1),
        Vector3(1, 1, 1),
        Vector3(-1, 1, -1),
        Vector3(1, 1, -1),
        Vector3(0, 0, 0),
        Vector3(-1, -1, 1),
        Vector3(1, -1, 1),
        Vector3(-1, -1, -1),
        Vector3(1, -1, -1),
    ]
    for tap in range(PCF_TAPS):
        var moved = point_shadow_tap(way, tap, 0.25)
        assert_equal(moved.x, signs[tap].x * 0.25)
        assert_equal(moved.y, signs[tap].y * 0.25)
        assert_equal(moved.z, 1 + signs[tap].z * 0.25)
    # One texel of three.js's four-by-two atlas is half a face's texel.
    assert_equal(point_shadow_spread(2, 8), Float32(0.125))


def test_a_cube_compares_distances_between_its_planes() raises:
    assert_equal(point_shadow_depth(5.25, 0.5, 10), Float32(0.5))
    assert_true(inside_point_shadow(5, 0.5, 10))
    assert_true(inside_point_shadow(10, 0.5, 10))
    assert_true(inside_point_shadow(0.5, 0.5, 10))
    assert_false(inside_point_shadow(10.5, 0.5, 10))
    assert_false(inside_point_shadow(0.25, 0.5, 10))
    assert_false(inside_point_shadow(0, 0, 10))
    assert_equal(cube_tap(0.5, 0.5), Float32(1))
    assert_equal(cube_tap(0.5, 0.25), Float32(1))
    assert_equal(cube_tap(0.5, 0.75), Float32(0))


def test_a_cube_stores_the_distance_the_face_camera_saw() raises:
    # A point two meters down the face's axis and one to the side, drawn
    # by the face camera: the depth it leaves recovers its distance.
    var scene = Scene()
    scene.update()
    var camera = PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(0.5, METER), Length(10.0, METER)
    )
    camera.up = cube_up(0)
    camera.place(ORIGIN, cube_direction(0))
    var frame = camera.projection_matrix()
    frame.multiply(camera.view_matrix_in(scene))
    var size = 4
    # The center of texel (3, 1): its ray, taken out two meters along x.
    var across = (Float32(3) + 0.5) / Float32(size) * 2 - 1
    var up = 1 - (Float32(1) + 0.5) / Float32(size) * 2
    var point = Vector3(2, up * 2, across * 2)
    var ndc = frame.transform_point(point)
    var stored = cube_stored(ndc.z, 3, 1, size, 0.5, 10)
    assert_almost_equal(
        stored, point_shadow_depth(point.length(), 0.5, 10), atol=1e-5
    )
    # Nothing drawn is as far as the cube reaches, and a depth before the
    # near plane or past the far saturates.
    assert_equal(cube_stored(inf[DType.float32](), 0, 0, size, 0.5, 10), 1)
    assert_equal(cube_stored(-5, 0, 0, size, 0.5, 10), 0)
    assert_equal(cube_stored(1, 0, 0, size, 0.5, 10), 1)


def a_cube(
    bias: Float32 = 0, normal_bias: Float32 = 0, radius: Float32 = 0
) raises -> ShadowMap:
    """Return a four-texel cube at the origin, near zero and far ten,
    with a caster two meters out along +x filling that face and nothing
    on the other five."""
    var depths = List[Float32]()
    for face in range(CUBE_FACES):
        for _ in range(16):
            if face == 0:
                depths.append(0.2)
            else:
                depths.append(1)
    return ShadowMap(
        cube_of=0,
        size=4,
        origin=ORIGIN,
        near=0,
        far=10,
        depths=depths^,
        bias=bias,
        normal_bias=normal_bias,
        radius=radius,
    )


def test_a_cube_lights_a_surface_by_how_many_taps_find_nothing() raises:
    var toward = Vector3(-1, 0, 0)
    var cube = a_cube()
    # Beyond the caster: shadowed; before it, or on another face: lit.
    assert_equal(cube.lit(Vector3(5, 0, 0), toward), Float32(0))
    assert_equal(cube.lit(Vector3(1, 0, 0), toward), Float32(1))
    assert_equal(cube.lit(Vector3(0, 0, 5), toward), Float32(1))
    # Past the far plane, or on the bulb: lit.
    assert_equal(cube.lit(Vector3(15, 0, 0), toward), Float32(1))
    assert_equal(cube.lit(ORIGIN, toward), Float32(1))
    # The bias moves the fragment toward the bulb in the cube's measure,
    # and the normal bias along the normal in meters.
    assert_equal(a_cube(bias=-0.4).lit(Vector3(5, 0, 0), toward), Float32(1))
    assert_equal(
        a_cube(normal_bias=3.5).lit(Vector3(5, 0, 0), toward), Float32(1)
    )
    # Near the seam with the +z face, a radius of one moves two taps
    # across it: xyy and xxy, which lower x and raise z.
    var seam = a_cube(radius=1).lit(Vector3(5, 0, 4.99), toward)
    assert_almost_equal(seam, Float32(2) / 9, atol=1e-6)


def cube_scene(cast: Bool) raises -> Scene:
    """Return a scene with one white bulb at the origin, casting or not."""
    var scene = Scene()
    var node = scene.add(Object3D())
    var bulb = point_light(Color(255, 255, 255), node, FULL, decay=0)
    bulb.cast_shadow = cast
    scene.add_light(bulb)
    scene.update()
    return scene^


def test_lighting_reads_a_point_lights_cube_in_every_sum() raises:
    var maps = List[ShadowMap]()
    maps.append(a_cube())
    var lighting = Lighting(
        cube_scene(True), Layers.all(), Vector3(-4, 0, 0), shadows=maps^
    )
    assert_equal(lighting.point_shadows[0], 0)
    var facing = Vector3(-1, 0, 0)
    var under = Vector3(5, 0, 0)
    var clear = Vector3(1, 0, 0)
    assert_equal(lighting.intensity_at(facing, under).r, Float32(0))
    assert_true(lighting.intensity_at(facing, clear).r > 0)
    assert_true(lighting.intensity_at(facing, under, False).r > 0)
    var ramp = List[Float32]()
    assert_equal(lighting.toon_at(facing, under, ramp).r, Float32(0))
    assert_true(lighting.toon_at(facing, clear, ramp).r > 0)
    var sheen = Vector3(1, 1, 1)
    assert_equal(lighting.specular_at(facing, under, sheen, 30).r, Float32(0))
    assert_true(lighting.specular_at(facing, clear, sheen, 30).r > 0)
    var chalk = physical_surface(
        Vector3(1, 1, 1), Vector3(0.04, 0.04, 0.04), 0, 1
    )
    assert_equal(
        lighting.physical_at(facing, facing, under, chalk, 1, 0, 0.1).diffuse.x,
        Float32(0),
    )
    assert_true(
        lighting.physical_at(facing, facing, clear, chalk, 1, 0, 0.1).diffuse.x
        > 0
    )
    assert_equal(lighting.shadow_mask(under, facing), Float32(0))
    assert_equal(lighting.shadow_mask(clear, facing), Float32(1))
    # Without a cube the bulb compares against nothing.
    assert_equal(Lighting(cube_scene(True)).point_shadows[0], -1)


def test_a_cube_and_a_square_each_belong_to_their_own_kind() raises:
    # A square map named by a point light, or a cube by a sun, is refused.
    var squares = List[ShadowMap]()
    squares.append(half_map(4))
    with assert_raises():
        _ = Lighting(cube_scene(True), shadows=squares^)
    var cubes = List[ShadowMap]()
    cubes.append(a_cube())
    with assert_raises():
        _ = Lighting(scene_with_sun(True), shadows=cubes^)


# --- spot light maps --------------------------------------------------------


def slide(width: Int = 2, height: Int = 2) raises -> Texture:
    """Return a picture whose left column is red and the rest blue, and
    whose top row is green where it would be blue, read texel by texel."""
    var image = Framebuffer(width, height, Color(0, 0, 255))
    for row in range(height):
        image.set_pixel(0, row, Color(255, 0, 0))
    for column in range(1, width):
        image.set_pixel(column, 0, Color(0, 255, 0))
    return texture_of(image, filter=NEAREST, mipmapped=False)


def test_a_spot_map_is_a_picture_seen_through_the_frame() raises:
    # Through the flat frame: the camera's left is the picture's left,
    # and its top is the picture's top, as three.js reads the map.
    var map = SpotLightMap(0, TextureId(0), slide(), flat_frame(), 0)
    assert_equal(map.light, 0)
    var left = map.tint(Vector3(-0.5, -0.5, 0), UP)
    assert_equal(left.x, Float32(1))
    assert_equal(left.z, Float32(0))
    var bottom_right = map.tint(Vector3(0.5, -0.5, 0), UP)
    assert_equal(bottom_right.z, Float32(1))
    assert_equal(bottom_right.x, Float32(0))
    var top_right = map.tint(Vector3(0.5, 0.5, 0), UP)
    assert_equal(top_right.y, Float32(1))
    # Outside the picture, or not strictly between its planes, the light
    # is as it was.
    var outside = map.tint(Vector3(3, 0, 0), UP)
    assert_equal(outside.x, Float32(1))
    assert_equal(outside.y, Float32(1))
    assert_equal(outside.z, Float32(1))
    assert_true(inside_spot_map(Vector3(0.5, 0.5, 0.5)))
    assert_false(inside_spot_map(Vector3(0, 0.5, 0.5)))
    assert_false(inside_spot_map(Vector3(1, 0.5, 0.5)))
    assert_false(inside_spot_map(Vector3(0.5, 0, 0.5)))
    assert_false(inside_spot_map(Vector3(0.5, 1, 0.5)))
    assert_false(inside_spot_map(Vector3(0.5, 0.5, 0)))
    assert_false(inside_spot_map(Vector3(0.5, 0.5, 1)))
    # The normal bias moves the surface first: a meter to the right
    # crosses from the red column to the blue.
    var moved = SpotLightMap(0, TextureId(0), slide(), flat_frame(), 0.75)
    assert_equal(
        moved.tint(Vector3(-0.5, -0.5, 0), Vector3(1, 0, 0)).z, Float32(1)
    )
    # A blank texture has no picture to project.
    with assert_raises():
        _ = SpotLightMap(0, TextureId(0), Texture(), flat_frame(), 0)
    assert_equal(SPOT_MAP_FLOATS, 18)


def spot_scene() raises -> Scene:
    """Return a scene with one white spot light a meter up the z axis,
    pointing down at the origin, and an ambient light."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    var node = scene.add(lamp^)
    var beam = spot_light(
        Color(255, 255, 255), node, FULL, angle=Angle(80.0, DEGREE)
    )
    beam.map = TextureId(0)
    scene.add_light(ambient_light(Color(255, 255, 255), 0))
    scene.add_light(beam)
    scene.update()
    return scene^


def test_lighting_tints_a_spot_light_by_its_map_in_every_sum() raises:
    var maps = List[SpotLightMap]()
    maps.append(SpotLightMap(1, TextureId(0), slide(), flat_frame(), 0))
    var lighting = Lighting(
        spot_scene(), Layers.all(), Vector3(0, 0, 4), spot_maps=maps^
    )
    assert_equal(lighting.spot_map_slots[0], 0)
    var red = Vector3(-0.3, -0.3, 0)
    var blue = Vector3(0.3, -0.3, 0)
    var diffuse_red = lighting.intensity_at(UP, red)
    assert_true(diffuse_red.r > 0)
    assert_equal(diffuse_red.b, Float32(0))
    var diffuse_blue = lighting.intensity_at(UP, blue)
    assert_equal(diffuse_blue.r, Float32(0))
    assert_true(diffuse_blue.b > 0)
    var ramp = List[Float32]()
    assert_equal(lighting.toon_at(UP, red, ramp).b, Float32(0))
    assert_true(lighting.toon_at(UP, red, ramp).r > 0)
    var sheen = Vector3(1, 1, 1)
    assert_equal(lighting.specular_at(UP, red, sheen, 30).b, Float32(0))
    assert_true(lighting.specular_at(UP, red, sheen, 30).r > 0)
    var chalk = physical_surface(
        Vector3(1, 1, 1), Vector3(0.04, 0.04, 0.04), 0, 1
    )
    var coated = lighting.physical_at(UP, UP, red, chalk, 1, 0, 0.1)
    assert_equal(coated.diffuse.z, Float32(0))
    assert_true(coated.diffuse.x > 0)
    # A map is not a shadow: the mask does not see it.
    assert_equal(lighting.shadow_mask(red, UP), Float32(1))
    # Without its map the light is white.
    var plain = Lighting(spot_scene())
    assert_equal(plain.spot_map_slots[0], -1)
    var white = plain.intensity_at(UP, red)
    assert_equal(white.r, white.b)


def test_each_spot_light_finds_its_own_map_or_none() raises:
    var scene = spot_scene()
    var post = Object3D()
    post.set_position(0, 0, 2)
    var post_node = scene.add(post^)
    scene.add_light(spot_light(Color(255, 255, 255), post_node, FULL))
    scene.update()
    var maps = List[SpotLightMap]()
    maps.append(SpotLightMap(1, TextureId(0), slide(), flat_frame(), 0))
    var lighting = Lighting(scene, spot_maps=maps^)
    assert_equal(lighting.spot_map_slots[0], 0)
    assert_equal(lighting.spot_map_slots[1], -1)


def test_a_spot_map_naming_the_wrong_light_is_refused() raises:
    for owner in [0, 7, -1]:
        var maps = List[SpotLightMap]()
        maps.append(SpotLightMap(owner, TextureId(0), slide(), flat_frame(), 0))
        with assert_raises():
            _ = Lighting(spot_scene(), spot_maps=maps^)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
