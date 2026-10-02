# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Cube captures retain the renderer's scene resources and clipping, #397."""

from cameras.cube_camera import CubeCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from lights.light import rect_area_light
from lights.light_probe_grid import LightProbeGrid
from lights.ltc import LTC_FLOATS, LtcTables
from lights.shadow import VSM_SHADOW_MAP
from materials.material import MaterialId
from math.bounds import Plane
from math.vector3 import Vector3
from render.cube_texture import FACE_COUNT, face_forward
from render.framebuffer import Color
from render.layered_target import cube_render_target
from render.rect import Rect
from render.target import FLOAT_TARGET
from render.tonemap import NO_TONE_MAPPING, REINHARD_TONE_MAPPING
from renderers.environment import scene_cube
from renderers.renderer import Renderer
from std.testing import TestSuite, assert_equal, assert_true
from tests.test_environment import a_room
from units.si import Duration, Length, METER, SECOND


def _camera() raises -> CubeCamera:
    """Return six small face cameras around the origin."""
    return CubeCamera(Length(0.1, METER), Length(20, METER), 8)


def _tables() raises -> LtcTables:
    """Return valid identity transforms and constant Fresnel terms."""
    var first = List[Float32](length=LTC_FLOATS, fill=0)
    for at in range(0, LTC_FLOATS, 4):
        first[at] = 1
        first[at + 3] = 1
    return LtcTables(first^, List[Float32](length=LTC_FLOATS, fill=1))


def test_all_cube_capture_paths_apply_global_clipping() raises:
    var assets = Assets()
    var scene = Scene()
    _ = a_room(scene, assets)
    var renderer = Renderer(8, 8)
    renderer.background = Color(0, 0, 0)
    renderer.clipping_planes = [Plane(Vector3(1, 0, 0), -100)]
    var captured = renderer.render_cube(scene, assets, _camera())
    var target = cube_render_target(8, Color(0, 0, 0), FLOAT_TARGET)
    renderer.render_cube_into(target, scene, assets, _camera())
    var environment = scene_cube(renderer, scene, assets, size=8)
    for face in range(FACE_COUNT):
        var direction = face_forward(face)
        assert_equal(captured.sample(direction).r, Float32(0))
        assert_equal(captured.sample(direction).g, Float32(0))
        assert_equal(captured.sample(direction).b, Float32(0))
        assert_equal(target.image(face).color_at(4, 4).r, Float32(0))
        assert_equal(target.image(face).color_at(4, 4).g, Float32(0))
        assert_equal(target.image(face).color_at(4, 4).b, Float32(0))
        assert_equal(environment.sample(direction).r, Float32(0))
        assert_equal(environment.sample(direction).g, Float32(0))
        assert_equal(environment.sample(direction).b, Float32(0))


def test_cube_rendering_keeps_ltc_tables_for_area_lights() raises:
    var scene = Scene()
    var node = scene.add(Object3D())
    scene.add_light(rect_area_light(Color(255, 255, 255), node))
    scene.update()
    var renderer = Renderer(8, 8)
    renderer.set_ltc_tables(_tables())
    var cube = renderer.render_cube(scene, Assets(), _camera())
    assert_equal(cube.size, 8)
    var target = cube_render_target(8, Color(0, 0, 0), FLOAT_TARGET)
    renderer.render_cube_into(target, scene, Assets(), _camera())
    assert_equal(target.width, 8)


def test_cube_face_settings_keep_scene_state_and_reset_capture_state() raises:
    var renderer = Renderer(20, 10)
    renderer.shadow_map_type = VSM_SHADOW_MAP
    renderer.shadow_map_transmitted = True
    renderer.local_clipping_enabled = True
    renderer.time = Duration(3, SECOND)
    renderer.override_material = MaterialId(4)
    renderer.tone_mapping = REINHARD_TONE_MAPPING
    renderer.tone_mapping_exposure = 7
    renderer.scissor_test = True
    renderer.set_light_probe_grid(
        LightProbeGrid(Length(1, METER), Length(1, METER), Length(1, METER))
    )
    var side = renderer._cube_renderer(8)
    assert_equal(side.shadow_map_type, VSM_SHADOW_MAP)
    assert_equal(side.shadow_map_transmitted, True)
    assert_equal(side.local_clipping_enabled, True)
    assert_equal(side.time.to(SECOND), Float32(3))
    assert_equal(side.override_material.value(), MaterialId(4))
    assert_equal(side.probe_grid.count(), 8)
    assert_equal(side.tone_mapping, NO_TONE_MAPPING)
    assert_equal(side.tone_mapping_exposure, Float32(1))
    assert_equal(side.viewport, Rect.whole(8, 8))
    assert_equal(side.scissor_test, False)
    var bake = renderer._cube_renderer(8, copy_probe_grid=False)
    assert_equal(bake.probe_grid.count(), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
