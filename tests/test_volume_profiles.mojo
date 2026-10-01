# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Volume ray steps use each spot light's beam profile, issue #358."""

from cameras.perspective_camera import PerspectiveCamera
from core.object3d import Object3D
from core.scene import Scene
from lights.ies_spot_light import ies_spot_light
from lights.light import IES_SPOT, PROJECTOR_SPOT
from lights.lighting import Lighting
from lights.projector_light import projector_light
from lights.spot_profile import SpotProfile
from math.vector3 import Vector3
from render.framebuffer import Color
from render.texture import Texture, float_texture
from render.texture_store import NO_TEXTURE, TextureId
from std.math import pi
from std.testing import TestSuite, assert_almost_equal, assert_equal
from units.si import Angle, DEGREE, Length, METER


def _ies(red: Float32) raises -> Lighting:
    """Return a lamp one meter above the origin with a constant IES beam."""
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    scene.add_light(
        ies_spot_light(Color(255, 255, 255), scene.add(lamp^), TextureId(0))
    )
    scene.update()
    var pixels: List[Float32] = [red, 0, 0, 1]
    var profiles = List[SpotProfile]()
    profiles.append(
        SpotProfile(
            0,
            IES_SPOT,
            TextureId(0),
            float_texture(1, 1, pixels^),
            SIMD[DType.float32, 16](0),
        )
    )
    return Lighting(scene, profiles=profiles^)


def _projector(aspect: Float32) raises -> Lighting:
    """Return a projector at the origin facing -z with constant falloff."""
    var scene = Scene()
    var lamp = scene.add(Object3D())
    var target = Object3D()
    target.set_position(0, 0, -1)
    var aim = scene.add(target^)
    scene.add_light(
        projector_light(
            Color(255, 255, 255),
            lamp,
            2,
            angle=Angle(45, DEGREE),
            decay=0,
            target=aim,
            aspect=aspect,
        )
    )
    scene.update()
    var camera = PerspectiveCamera(
        Angle(90, DEGREE), aspect, Length(0.5, METER), Length(10, METER)
    )
    var projection = camera.projection_matrix()
    var frame = SIMD[DType.float32, 16](0)
    for at in range(16):
        frame[at] = projection.elements[at]
    var profiles = List[SpotProfile]()
    profiles.append(
        SpotProfile(0, PROJECTOR_SPOT, NO_TEXTURE, Texture(), frame)
    )
    return Lighting(scene, profiles=profiles^)


def test_a_black_ies_profile_leaves_volume_steps_dark() raises:
    var lighting = _ies(0)
    var p = Vector3(0, 0, 0)
    var n = Vector3(0, 0, 1)
    assert_equal(lighting.intensity_at(n, p).r, Float32(0))
    var light = lighting.volume_light_at(p, n, False)
    assert_equal(light.x, Float32(0))
    assert_equal(light.y, Float32(0))
    assert_equal(light.z, Float32(0))


def test_an_ies_profile_scales_the_volume_before_distance_falloff() raises:
    var lighting = _ies(0.25)
    var n = Vector3(0, 0, 1)
    assert_almost_equal(
        lighting.volume_light_at(Vector3(0, 0, 0), n, False).x, Float32(0.25)
    )
    assert_almost_equal(
        lighting.volume_light_at(Vector3(0, 0, -1), n, False).x, Float32(0.0625)
    )


def test_a_projector_reaches_volume_steps_outside_a_circular_cone() raises:
    var lighting = _projector(2)
    # The 90-degree circular cone stops at x=1; this rectangle reaches x=2.
    var light = lighting.volume_light_at(
        Vector3(1.5, 0, -1), Vector3(0, 0, 1), False
    )
    assert_almost_equal(light.x, Float32(2 / pi), atol=1e-6)


def test_a_narrow_projector_excludes_steps_inside_the_circular_cone() raises:
    var lighting = _projector(0.25)
    var light = lighting.volume_light_at(
        Vector3(0.5, 0, -1), Vector3(0, 0, 1), False
    )
    assert_equal(light.x, Float32(0))
    assert_equal(
        lighting.volume_light_at(Vector3(0, 0, 1), Vector3(0, 0, 1), False).x,
        Float32(0),
    )


def test_an_ies_light_without_a_profile_retains_its_cone() raises:
    var scene = Scene()
    var lamp = Object3D()
    lamp.set_position(0, 0, 1)
    scene.add_light(
        ies_spot_light(
            Color(255, 255, 255),
            scene.add(lamp^),
            NO_TEXTURE,
            angle=Angle(30, DEGREE),
        )
    )
    scene.update()
    var lighting = Lighting(scene)
    var n = Vector3(0, 0, 1)
    assert_almost_equal(
        lighting.volume_light_at(Vector3(0, 0, 0), n, False).x, Float32(1)
    )
    assert_equal(
        lighting.volume_light_at(Vector3(2, 0, 0), n, False).x, Float32(0)
    )
    assert_equal(
        lighting.volume_light_at(Vector3(0, 0, 1), n, False).x, Float32(0)
    )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
