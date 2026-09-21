# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `lights.shadow`: the map, its coordinate, its taps and the
lighting that reads it, apart from any renderer."""

from core.layers import Layers
from core.object3d import Object3D
from core.scene import Scene
from lights.light import (
    ambient_light,
    directional_light,
    hemisphere_light,
    point_light,
    spot_light,
)
from lights.lighting import Lighting, Reflected, physical_surface
from lights.shadow import (
    DEFAULT_MAP_SIZE,
    DEFAULT_SHADOW_EXTENT,
    DEFAULT_SHADOW_FAR,
    DEFAULT_SHADOW_NEAR,
    DEFAULT_SHADOW_RADIUS,
    MAX_MAP_SIZE,
    PCF_TAPS,
    SHADOW_HEADER,
    LightShadow,
    ShadowMap,
    biased_position,
    inside_shadow_map,
    shadow_coordinate,
    shadow_tap,
    shadow_texel,
)
from math.vector3 import Vector3
from render.framebuffer import Color
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


def test_only_a_directional_or_spot_light_casts() raises:
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
    with assert_raises():
        point.validate()
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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
