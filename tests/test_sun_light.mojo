# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `lights.sun_light`, three.js's `SunLight` and
`SunLightShadow`: a directional light with a direction and no target,
whose shadow camera is fit to what a camera sees.

A camera at the origin looking down -z, ninety degrees wide, from one
meter to three, sees a frustum whose corners are (±1, ±1, -1) and
(±3, ±3, -3). Their middle is (0, 0, -2), and the furthest is
`sqrt(19)` away, 4.359, rounded up to a sixteenth: 4.375.
"""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.box import cube
from geometries.plane import plane
from lights.light import DIRECTIONAL, ambient_light
from lights.sun_light import (
    DEFAULT_SUN_DISTANCE,
    DEFAULT_SUN_MARGIN,
    SUN_RADIUS_STEP,
    SunLight,
    SunLightShadow,
    fit_sun,
)
from materials.material import Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from renderers.renderer import Renderer
from std.math import floor, inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


def assert_at(point: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a point's three coordinates, to within a ten-thousandth."""
    assert_almost_equal(point.x, x, atol=1e-4)
    assert_almost_equal(point.y, y, atol=1e-4)
    assert_almost_equal(point.z, z, atol=1e-4)


def a_short_camera() raises -> PerspectiveCamera:
    """Return a camera at the origin looking down -z, ninety degrees
    wide, from one meter to three."""
    return PerspectiveCamera(
        Angle(90.0, DEGREE), 1.0, Length(1.0, METER), Length(3.0, METER)
    )


def test_the_shadow_has_defaults_and_refuses_wrong_numbers() raises:
    var shadow = SunLightShadow()
    assert_equal(shadow.max_distance.to(METER), DEFAULT_SUN_DISTANCE.to(METER))
    assert_equal(shadow.margin.to(METER), DEFAULT_SUN_MARGIN.to(METER))
    assert_equal(shadow.map_size, 2048)
    shadow.validate()
    with assert_raises(contains="distance"):
        SunLightShadow(max_distance=Length(0.0, METER)).validate()
    with assert_raises(contains="distance"):
        SunLightShadow(
            max_distance=Length(inf[DType.float32](), METER)
        ).validate()
    with assert_raises(contains="margin"):
        SunLightShadow(margin=Length(-1.0, METER)).validate()
    with assert_raises(contains="margin"):
        SunLightShadow(margin=Length(nan[DType.float32](), METER)).validate()
    with assert_raises(contains="texels"):
        SunLightShadow(map_size=0).validate()
    with assert_raises(contains="texels"):
        SunLightShadow(map_size=9000).validate()
    SunLightShadow(margin=Length(0.0, METER), map_size=8192).validate()


def test_a_sun_adds_a_casting_directional_light() raises:
    var scene = Scene()
    var sun = SunLight(scene, Color(255, 240, 220), 2.0, Vector3(0, -2, 0))
    assert_equal(len(scene.lights), 1)
    assert_equal(sun.light, 0)
    ref light = scene.lights[0]
    assert_equal(light.kind, DIRECTIONAL)
    assert_true(light.cast_shadow)
    assert_equal(light.intensity, 2)
    assert_equal(light.node, sun.node)
    assert_equal(light.target, sun.target)
    assert_equal(light.shadow.map_size, 2048)
    assert_at(sun.direction, 0, -1, 0)
    # Before any fit, the light shines along its direction.
    assert_at(scene.world_position(sun.node), 0, 1, 0)
    var quiet = SunLight(scene, cast_shadow=False)
    assert_true(not scene.lights[quiet.light].cast_shadow)


def test_a_sun_refuses_a_direction_of_nothing() raises:
    var scene = Scene()
    with assert_raises(contains="direction"):
        _ = SunLight(scene, direction=Vector3(0, 0, 0))
    with assert_raises(contains="direction"):
        _ = SunLight(scene, direction=Vector3(inf[DType.float32](), 0, 0))
    with assert_raises(contains="distance"):
        _ = SunLight(
            scene, shadow=SunLightShadow(max_distance=Length(-1.0, METER))
        )
    with assert_raises():
        _ = SunLight(scene, intensity=-1)
    var sun = SunLight(scene)
    sun.set_direction(Vector3(3, 0, 4))
    assert_at(sun.direction, 0.6, 0, 0.8)
    with assert_raises(contains="direction"):
        sun.set_direction(Vector3(0, 0, 0))


def test_the_fit_encloses_the_view_in_a_sphere() raises:
    var scene = Scene()
    var fit = fit_sun(
        scene, a_short_camera(), Vector3(0, 0, -1), SunLightShadow()
    )
    assert_almost_equal(fit.radius, 4.375, atol=1e-6)
    # Looking along -z, the light's frame is the world's: the middle is
    # already on whole texels.
    assert_at(fit.target, 0, 0, -2)
    var back = Float32(4.375 + 50)
    assert_at(fit.position, 0, 0, -2 + back)
    assert_almost_equal(fit.far, back + 4.375, atol=1e-4)


def test_the_fit_stops_at_the_shadows_distance() raises:
    # A shadow that reaches two meters cuts the frustum there: the far
    # corners are (±2, ±2, -2), the middle (0, 0, -1.5), and the furthest
    # sqrt(8.25) away, 2.872, rounded up to 2.875.
    var scene = Scene()
    var shadow = SunLightShadow(max_distance=Length(2.0, METER))
    var fit = fit_sun(scene, a_short_camera(), Vector3(0, 0, -1), shadow)
    assert_almost_equal(fit.radius, 2.875, atol=1e-6)
    assert_at(fit.target, 0, 0, -1.5)


def test_the_fit_snaps_to_whole_texels() raises:
    # A camera moved a centimeter along x puts the middle off the texel
    # grid; it is snapped down to the texel below.
    var scene = Scene()
    var camera = a_short_camera()
    camera.place(Vector3(0.01, 0, 0), Vector3(0.01, 0, -1))
    var shadow = SunLightShadow(map_size=64)
    var fit = fit_sun(scene, camera, Vector3(0, 0, -1), shadow)
    var texel = Float32(2 * 4.375 / 64)
    assert_almost_equal(fit.target.x, floor(0.01 / texel) * texel, atol=1e-5)
    assert_true(fit.target.x < 0.01)
    # The radius is a whole number of sixteenths.
    var steps = fit.radius / SUN_RADIUS_STEP
    assert_almost_equal(steps, floor(steps + 0.5), atol=1e-4)


def test_update_places_the_light_and_its_shadow_camera() raises:
    var scene = Scene()
    var sun = SunLight(scene, direction=Vector3(0, 0, -1))
    var camera = a_short_camera()
    sun.update(scene, camera)
    ref shadow = scene.lights[sun.light].shadow
    assert_almost_equal(shadow.left.to(METER), -4.375, atol=1e-6)
    assert_almost_equal(shadow.right.to(METER), 4.375, atol=1e-6)
    assert_almost_equal(shadow.top.to(METER), 4.375, atol=1e-6)
    assert_almost_equal(shadow.bottom.to(METER), -4.375, atol=1e-6)
    assert_equal(shadow.near.to(METER), 0)
    assert_almost_equal(shadow.far.to(METER), 58.75, atol=1e-4)
    assert_at(scene.world_position(sun.node), 0, 0, 52.375)
    assert_at(scene.world_position(sun.target), 0, 0, -2)
    scene.lights[sun.light].validate()


def test_update_refuses_a_scene_without_the_sun() raises:
    var scene = Scene()
    var sun = SunLight(scene)
    var camera = a_short_camera()
    var other = Scene()
    with assert_raises(contains="not in this scene"):
        sun.update(other, camera)
    var swapped = Scene()
    swapped.add_light(ambient_light(Color(255, 255, 255)))
    with assert_raises(contains="not in this scene"):
        sun.update(swapped, camera)


def test_the_sun_casts_a_shadow_where_the_camera_looks() raises:
    # A box on a floor, seen from above, shadows the floor on the side
    # away from the sun; the floor on the sun's side is lit.
    var assets = Assets()
    var scene = Scene()
    var ground = Object3D()
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var floor = assets.geometries.add(
        plane(Length(8.0, METER), Length(8.0, METER), 2, 2)
    )
    var block = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    scene.add_mesh(Mesh(floor, paint, scene.add(ground^), receive_shadow=True))
    var lift = Object3D()
    lift.set_position(0, 0.5, 0)
    scene.add_mesh(Mesh(block, paint, scene.add(lift^), cast_shadow=True))
    var sun = SunLight(
        scene,
        intensity=3.0,
        direction=Vector3(1, -1, 0),
        shadow=SunLightShadow(map_size=256),
    )
    var camera = PerspectiveCamera(
        Angle(60.0, DEGREE), 1.0, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 6, 0.001), Vector3(0, 0, 0))
    scene.lights[sun.light].shadow.bias = -0.002
    sun.update(scene, camera)
    var image = Renderer(32, 32).render(scene, assets, camera)
    # The light travels toward +x, so the shadow falls on the +x side.
    var shaded = image.get_pixel(21, 16).r
    var lit = image.get_pixel(9, 16).r
    assert_true(lit > shaded + 30, "the sun cast no shadow")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
