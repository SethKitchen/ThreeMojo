# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `environments.room_environment`, `render.pmrem.pmrem_from_faces`
and `renderers.environment.pmrem_from_scene`: a scene drawn into a cube and
prefiltered, three.js's `PMREMGenerator.fromScene`."""

from core.assets import Assets
from core.background import color_background
from core.object3d import Object3D
from core.scene import Scene
from environments.room_environment import (
    debug_environment,
    glowing_panel,
    room_environment,
)
from geometries.box import cube
from lights.light import POINT
from materials.material import BACK_SIDE, LAMBERT, STANDARD, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.cube_texture import CubeTexture
from render.framebuffer import Color
from render.pmrem import pmrem_from_cube, pmrem_from_faces
from render.texture import BILINEAR, CLAMP, IGNORED, Texture, float_texture
from renderers.environment import pmrem_from_scene
from renderers.renderer import Renderer
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER, RADIAN


def a_lit_cube(size: Int) raises -> CubeTexture:
    """Return a float cube whose +y face alone holds ten."""
    var faces = List[Texture]()
    for face in range(6):
        var data = List[Float32]()
        for _ in range(size * size):
            var level = Float32(10) if face == 2 else Float32(0)
            data.append(level)
            data.append(level)
            data.append(level)
            data.append(1)
        faces.append(
            float_texture(size, size, data^, CLAMP, BILINEAR, False, IGNORED)
        )
    return CubeTexture(faces^)


# --- the scenes -------------------------------------------------------------


def test_a_room_holds_three_js_room() raises:
    var assets = Assets()
    var room = room_environment(assets)
    assert_equal(len(room.lights), 1)
    ref bulb = room.lights[0]
    assert_equal(bulb.kind, POINT)
    assert_equal(bulb.intensity, 900)
    assert_equal(bulb.distance, 28)
    assert_equal(bulb.decay, 2)
    var at = room.world_position(bulb.node)
    assert_almost_equal(at.y, 16.199, atol=1e-4)
    # The room, then six panels; the six boxes are one instanced mesh.
    assert_equal(len(room.meshes), 7)
    assert_equal(len(room.instanced_meshes), 1)
    assert_equal(room.instanced_meshes[0].count(), 6)
    var walls = assets.materials.get(room.meshes[0].material)
    assert_equal(walls.kind, STANDARD)
    assert_equal(walls.side, BACK_SIDE)
    assert_equal(walls.roughness, 1)
    var scale = room.world_scale(room.meshes[0].node)
    assert_almost_equal(scale.x, 31.713, atol=1e-3)
    var ceiling = assets.materials.get(room.meshes[6].material)
    assert_equal(ceiling.kind, LAMBERT)
    assert_equal(ceiling.emissive_intensity, 100)
    assert_equal(ceiling.color.hex(), 0)
    assert_equal(ceiling.emissive.hex(), 0xFFFFFF)
    var intensities: List[Float32] = [50, 50, 17, 43, 20, 100]
    for index in range(6):
        var panel = assets.materials.get(room.meshes[index + 1].material)
        assert_equal(panel.emissive_intensity, intensities[index])


def test_a_debug_room_holds_three_colored_panels() raises:
    var assets = Assets()
    var room = debug_environment(assets)
    assert_equal(len(room.lights), 1)
    assert_equal(room.lights[0].intensity, 50)
    assert_equal(room.lights[0].distance, 0)
    assert_equal(len(room.meshes), 4)
    var walls = assets.materials.get(room.meshes[0].material)
    assert_equal(walls.metalness, 0)
    assert_equal(walls.side, BACK_SIDE)
    var colors: List[Int] = [0xFF0000, 0x00FF00, 0x0000FF]
    for index in range(3):
        var panel = assets.materials.get(room.meshes[index + 1].material)
        assert_equal(panel.color.hex(), colors[index])
        assert_equal(panel.emissive_intensity, 10)
    var red = room.world_position(room.meshes[1].node)
    assert_equal(red.x, -5)


def test_a_panel_refuses_a_negative_glow() raises:
    var panel = glowing_panel(Color(0, 0, 0), 5)
    assert_equal(panel.emissive_intensity, 5)
    with assert_raises():
        _ = glowing_panel(Color(0, 0, 0), -1)


# --- prefiltering drawn faces -----------------------------------------------


def test_a_blur_spreads_the_sharpest_copy() raises:
    var cube = a_lit_cube(16)
    var plain = pmrem_from_faces(cube, Angle(0.0, RADIAN))
    var same = pmrem_from_cube(cube)
    var horizon = Vector3(1, 0.1, 0)
    assert_equal(
        plain.sample_rough(horizon, 0).r, same.sample_rough(horizon, 0).r
    )
    var blurred = pmrem_from_faces(cube, Angle(20.0, DEGREE))
    assert_true(
        blurred.sample_rough(horizon, 0).r > plain.sample_rough(horizon, 0).r,
        "the blur did not spread the light",
    )
    # A blur narrower than a texel takes one sample and changes little.
    var faint = pmrem_from_faces(cube, Angle(0.0001, RADIAN))
    assert_almost_equal(
        faint.sample_rough(Vector3(0, 1, 0), 0).r,
        plain.sample_rough(Vector3(0, 1, 0), 0).r,
        atol=1e-3,
    )
    for wrong in [Float32(-0.1), nan[DType.float32](), inf[DType.float32]()]:
        with assert_raises():
            _ = pmrem_from_faces(cube, Angle(wrong, RADIAN))


# --- prefiltering a scene ---------------------------------------------------


def test_a_scene_is_drawn_in_linear_light_and_prefiltered() raises:
    # One panel glowing at forty above the origin, in a gray void.
    var assets = Assets()
    var scene = Scene()
    var block = assets.geometries.add(cube(Length(1.0, METER)))
    var glow = assets.materials.add(glowing_panel(Color(0, 0, 0), 40))
    var above = Object3D()
    above.set_position(0, 3, 0)
    above.set_scale(6, 0.1, 6)
    scene.add_mesh(Mesh(block, glow, scene.add(above^)))
    scene.update()
    var renderer = Renderer(8, 8)
    renderer.set_background(Color(0, 0, 0))
    var cube_map = pmrem_from_scene(renderer, scene, assets, size=16)
    assert_true(cube_map.is_prefiltered())
    assert_equal(cube_map.size, 16)
    # Straight up sees the panel at its full forty, which a byte face
    # would have clipped to one.
    var up = cube_map.sample_rough(Vector3(0, 1, 0), 0)
    assert_almost_equal(up.r, 40, atol=0.5)
    var down = cube_map.sample_rough(Vector3(0, -1, 0), 0)
    assert_almost_equal(down.r, 0, atol=1e-4)
    # The scene's color background fills where nothing is drawn.
    scene.background = color_background(Color(255, 255, 255))
    var white = pmrem_from_scene(renderer, scene, assets, size=16)
    assert_almost_equal(
        white.sample_rough(Vector3(0, -1, 0), 0).r, 1, atol=1e-3
    )
    # Standing above the panel, down sees it and up does not.
    var over = pmrem_from_scene(
        renderer,
        scene,
        assets,
        sigma=Angle(0.05, RADIAN),
        size=16,
        position=Vector3(0, 6, 0),
        near=Length(0.5, METER),
        far=Length(20.0, METER),
    )
    assert_true(over.sample_rough(Vector3(0, -1, 0), 0).r > 10)
    with assert_raises():
        _ = pmrem_from_scene(renderer, scene, assets, size=0)
    with assert_raises():
        _ = pmrem_from_scene(
            renderer, scene, assets, size=16, sigma=Angle(-1.0, RADIAN)
        )


def test_a_room_lights_a_cube_from_every_side() raises:
    var assets = Assets()
    var room = room_environment(assets)
    var renderer = Renderer(8, 8)
    var lit = pmrem_from_scene(renderer, room, assets, size=16)
    for direction in [
        Vector3(1, 0, 0),
        Vector3(-1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 1),
        Vector3(0, 0, -1),
    ]:
        assert_true(lit.sample_rough(direction, 1).r > 0.1, "a side was dark")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
