# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a light's shadow camera, its shadow's intensity and updates,
and a light's power: three.js's `LightShadow`, `DirectionalLightShadow`,
`PointLight.power`, `SpotLight.power` and `RectAreaLight.power`."""

from core.assets import Assets
from core.object3d import NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import (
    LuminousPower,
    ambient_light,
    directional_light,
    point_light,
    rect_area_light,
    shadows_drawn,
    spot_light,
)
from lights.lighting import Lighting
from lights.shadow import (
    CUBE_FACES,
    FULL_SHADOW,
    ShadowMap,
    shadow_strength,
)
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer
from std.math import inf, pi, sqrt
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
comptime UP = Vector3(0, 0, 1)


def flat_frame() -> SIMD[DType.float32, 16]:
    """Return an orthographic frame down -z over the unit square."""
    var frame = SIMD[DType.float32, 16](0)
    frame[0] = 1
    frame[5] = 1
    frame[10] = -1
    frame[15] = 1
    return frame


def dark_map(intensity: Float32) raises -> ShadowMap:
    """Return a four-texel map with a caster at z = 0.5 everywhere."""
    var depths = List[Float32](length=16, fill=-0.5)
    return ShadowMap(0, 4, flat_frame(), depths^, 0, 0, 0, intensity=intensity)


def dark_cube(intensity: Float32) raises -> ShadowMap:
    """Return a cube with a caster one meter out on every face."""
    var depths = List[Float32](length=CUBE_FACES * 16, fill=0.1)
    return ShadowMap(
        cube_of=0,
        size=4,
        origin=Vector3(0, 0, 0),
        near=0,
        far=10,
        depths=depths^,
        bias=0,
        normal_bias=0,
        radius=0,
        intensity=intensity,
    )


def same(a: SIMD[DType.float32, 16], b: SIMD[DType.float32, 16]) -> Bool:
    """Return True if two frames hold the same sixteen numbers."""
    for index in range(16):
        if a[index] != b[index]:
            return False
    return True


# --- the intensity ----------------------------------------------------------


def test_a_shadow_intensity_mixes_toward_full_light() raises:
    assert_equal(shadow_strength(0.25, FULL_SHADOW), 0.25)
    assert_equal(shadow_strength(0, 0.5), 0.5)
    assert_equal(shadow_strength(1, 0.3), 1)
    assert_equal(shadow_strength(0, 0), 1)
    assert_almost_equal(shadow_strength(0.5, 0.5), 0.75, atol=1e-7)


def test_a_map_weakens_its_shadow_by_its_intensity() raises:
    var under = Vector3(0.5, 0.5, 0)
    assert_equal(dark_map(1).lit(under, UP), 0)
    assert_almost_equal(dark_map(0.4).lit(under, UP), 0.6, atol=1e-6)
    assert_equal(dark_map(0).lit(under, UP), 1)
    # Off the map a weak shadow still lights in full.
    assert_equal(dark_map(0.4).lit(Vector3(3, 0, 0), UP), 1)
    var beyond = Vector3(5, 0, 0)
    assert_equal(dark_cube(1).lit(beyond, Vector3(-1, 0, 0)), 0)
    assert_almost_equal(
        dark_cube(0.25).lit(beyond, Vector3(-1, 0, 0)), 0.75, atol=1e-6
    )
    # A new map takes all the light, three.js's default.
    var plain = ShadowMap(
        0, 4, flat_frame(), List[Float32](length=16, fill=0), 0, 0, 0
    )
    assert_equal(plain.intensity, FULL_SHADOW)


# --- the power --------------------------------------------------------------


def test_a_power_is_three_js_lumens() raises:
    var bulb = point_light(WHITE, NodeId(0), 2)
    assert_almost_equal(bulb.power().lumens, 8 * Float32(pi), atol=1e-5)
    bulb.set_power(LuminousPower(4 * Float32(pi)))
    assert_almost_equal(bulb.intensity, 1, atol=1e-6)
    var spot = spot_light(WHITE, NodeId(0), 3)
    assert_almost_equal(spot.power().lumens, 3 * Float32(pi), atol=1e-5)
    spot.set_power(LuminousPower(Float32(pi) / 2))
    assert_almost_equal(spot.intensity, 0.5, atol=1e-6)
    var panel = rect_area_light(
        WHITE,
        NodeId(0),
        2,
        Length(3.0, METER),
        Length(0.5, METER),
    )
    assert_almost_equal(panel.power().lumens, 3 * Float32(pi), atol=1e-5)
    panel.set_power(LuminousPower(1.5 * Float32(pi)))
    assert_almost_equal(panel.intensity, 1, atol=1e-6)


def test_a_power_is_refused_where_three_js_has_none() raises:
    var sun = directional_light(WHITE, NodeId(0))
    with assert_raises():
        _ = sun.power()
    with assert_raises():
        sun.set_power(LuminousPower(1))
    with assert_raises():
        _ = ambient_light(WHITE).power()
    # A power that makes a refused intensity leaves the light as it was.
    var bulb = point_light(WHITE, NodeId(0), 2)
    with assert_raises():
        bulb.set_power(LuminousPower(-1))
    assert_equal(bulb.intensity, 2)
    with assert_raises():
        bulb.set_power(LuminousPower(inf[DType.float32]()))
    assert_equal(bulb.intensity, 2)


# --- the four edges and the updates, through the renderer -------------------


def sun_over_block(mut assets: Assets) raises -> Scene:
    """Return a floor and a block under a casting sun straight above."""
    var scene = Scene()
    var ground = Object3D()
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var ground_node = scene.add(ground^)
    var lift = Object3D()
    lift.set_position(0, 1, 0)
    var lift_node = scene.add(lift^)
    var floor = assets.geometries.add(
        plane(Length(6.0, METER), Length(6.0, METER), 1, 1)
    )
    var block = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    scene.add_mesh(Mesh(floor, paint, ground_node, receive_shadow=True))
    scene.add_mesh(Mesh(block, paint, lift_node, cast_shadow=True))
    var lamp = Object3D()
    lamp.set_position(0, 5, 0)
    var sun = directional_light(WHITE, scene.add(lamp^), 2)
    sun.cast_shadow = True
    sun.shadow.map_size = 16
    scene.add_light(sun)
    var bulb = Object3D()
    bulb.set_position(2, 3, 0)
    var lamp_bulb = point_light(WHITE, scene.add(bulb^), 5)
    lamp_bulb.cast_shadow = True
    lamp_bulb.shadow.map_size = 4
    lamp_bulb.shadow.intensity = 0.5
    scene.add_light(lamp_bulb)
    scene.update()
    return scene^


def test_a_sun_draws_its_map_between_its_four_edges() raises:
    var assets = Assets()
    var scene = sun_over_block(assets)
    var renderer = Renderer(8, 8)
    var square = renderer.shadow_maps(scene, assets)
    assert_equal(len(square), 2)
    assert_equal(square[0].intensity, 1)
    assert_equal(square[1].intensity, 0.5)
    assert_true(square[1].cube)
    # Slid a meter along x, the camera's frame moves, and the block under
    # the sun lands elsewhere in the map.
    scene.lights[0].shadow.left = Length(-4.0, METER)
    scene.lights[0].shadow.right = Length(6.0, METER)
    scene.lights[0].shadow.bottom = Length(-2.0, METER)
    var moved = renderer.shadow_maps(scene, assets)
    assert_false(same(moved[0].frame, square[0].frame))
    var edges = moved[0].frame
    # three.js's orthographic x: 2 / (right - left), -(right + left) / width.
    assert_almost_equal(edges[0], 0.2, atol=1e-6)
    assert_almost_equal(edges[12], -0.2, atol=1e-6)
    # A wrong edge is refused before a map is drawn.
    scene.lights[0].shadow.right = Length(-5.0, METER)
    with assert_raises():
        _ = renderer.shadow_maps(scene, assets)


def _y_scale(frame: SIMD[DType.float32, 16]) -> Float32:
    """Return the length of a frame's second row's rotation part."""
    return sqrt(frame[1] * frame[1] + frame[5] * frame[5] + frame[9] * frame[9])


def test_a_spot_shadow_focus_narrows_its_camera() raises:
    # three.js 0.180: a spot light of angle pi / 6 with a focus of a half
    # gives its shadow camera a field of view of 30 degrees.
    var lamp = spot_light(WHITE, NodeId(0), angle=Angle(30.0, DEGREE))
    assert_equal(lamp.shadow.focus, 1)
    assert_almost_equal(
        lamp.shadow.spot_field_of_view(lamp.angle).to(DEGREE),
        Float32(60),
        atol=1e-4,
    )
    lamp.shadow.focus = 0.5
    assert_almost_equal(
        lamp.shadow.spot_field_of_view(lamp.angle).to(DEGREE),
        Float32(29.999999999999996),
        atol=1e-4,
    )
    lamp.shadow.validate()
    # The map's camera narrows with it: its y scale is 1 / tan(fov / 2),
    # the length of the frame's y row with the translation left out.
    var assets = Assets()
    var scene = Scene()
    var bulb = Object3D()
    bulb.set_position(0, 5, 0)
    var spot = spot_light(WHITE, scene.add(bulb^), 5, angle=Angle(30.0, DEGREE))
    spot.cast_shadow = True
    spot.shadow.map_size = 4
    scene.add_light(spot)
    scene.update()
    var renderer = Renderer(4, 4)
    var wide = renderer.shadow_maps(scene, assets)
    scene.lights[0].shadow.focus = 0.5
    var narrow = renderer.shadow_maps(scene, assets)
    assert_almost_equal(
        _y_scale(wide[0].frame), Float32(1 / 0.5773502691896257), atol=1e-4
    )
    assert_almost_equal(
        _y_scale(narrow[0].frame), Float32(1 / 0.2679491924311227), atol=1e-4
    )
    for bad in [Float32(0), Float32(-1), inf[DType.float32]()]:
        scene.lights[0].shadow.focus = bad
        with assert_raises(contains="focus"):
            _ = renderer.shadow_maps(scene, assets)


def test_a_frozen_shadow_keeps_the_map_it_was_given() raises:
    var assets = Assets()
    var scene = sun_over_block(assets)
    var renderer = Renderer(8, 8)
    var first = renderer.shadow_maps(scene, assets)
    # Frozen, and handed last frame's maps: the sun keeps its old map
    # although its camera moved; the bulb, still updating, draws anew.
    scene.lights[0].shadow.auto_update = False
    var before = first[0].frame
    scene.lights[0].shadow.set_extent(Length(9.0, METER))
    var kept = renderer.shadow_maps(scene, assets, kept=first^)
    assert_true(same(kept[0].frame, before))
    assert_equal(len(kept), 2)
    # Asked for one more map, it draws one, and `shadows_drawn` freezes it
    # again.
    scene.lights[0].shadow.needs_update = True
    var again = renderer.shadow_maps(scene, assets, kept=kept^)
    assert_false(same(again[0].frame, before))
    shadows_drawn(scene.lights, again)
    assert_false(scene.lights[0].shadow.needs_update)
    assert_true(scene.lights[0].shadow.is_frozen())
    # Frozen with no map kept, the map is drawn.
    var fresh = renderer.shadow_maps(scene, assets)
    assert_equal(len(fresh), 2)
    # No maps clear nothing.
    scene.lights[0].shadow.needs_update = True
    shadows_drawn(scene.lights, List[ShadowMap]())
    assert_true(scene.lights[0].shadow.needs_update)
    # A kept map naming a light that is not there is refused.
    var stray = List[ShadowMap]()
    stray.append(dark_map(1))
    stray[0].light = 7
    with assert_raises():
        shadows_drawn(scene.lights, stray)
    stray[0].light = -1
    with assert_raises():
        shadows_drawn(scene.lights, stray)


def test_a_weak_shadow_darkens_less() raises:
    var assets = Assets()
    var scene = sun_over_block(assets)
    var renderer = Renderer(16, 16)
    var maps = renderer.shadow_maps(scene, assets)
    var lighting = Lighting(scene, shadows=maps^)
    var under = Vector3(0, 0, 0)
    var full = lighting.intensity_at(Vector3(0, 1, 0), under).r
    scene.lights[0].shadow.intensity = 0.5
    var half_maps = renderer.shadow_maps(scene, assets)
    var weak = Lighting(scene, shadows=half_maps^)
    assert_true(weak.intensity_at(Vector3(0, 1, 0), under).r > full)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
