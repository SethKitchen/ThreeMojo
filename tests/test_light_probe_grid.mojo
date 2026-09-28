# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a box of light probes: `lights.light_probe_grid`, three.js's
`LightProbeGrid`; its bake, `renderers.light_probe_grid_utils`; its place
in `Lighting` and the renderer; its helper,
`helpers.light_probe_grid`; and the environment of one color it is baked
in here, `environments.color_environment`.

A surface takes the eight probes around it, blended trilinearly as
three.js's linear filter blends the texels of its probe textures, with
the corner probes at the box's corners. A probe baked in a uniform
environment of radiance `L` holds an irradiance of `pi * L` in every
direction.
"""

from cameras.orthographic_camera import OrthographicCamera
from core.assets import Assets
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from environments.color_environment import color_environment
from geometries.plane import plane
from helpers.light_probe_grid import LightProbeGridHelper
from lights.light_probe_grid import GRID_HEADER, LightProbeGrid, grid_taps
from lights.lighting import Lighting
from materials.material import Material
from math.spherical_harmonics3 import SphericalHarmonics3
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor, Framebuffer
from render.srgb import srgb_to_linear
from renderers.environment import scene_cube
from renderers.light_probe_grid_utils import bake_light_probe_grid
from renderers.renderer import Renderer
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

comptime SIDE = 32
comptime LOW = Vector3(-1, -0.5, -0.5)
comptime HIGH = Vector3(1, 0.5, 0.5)


def assert_at(point: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a point's three coordinates, to within a millionth."""
    assert_almost_equal(point.x, x, atol=1e-6)
    assert_almost_equal(point.y, y, atol=1e-6)
    assert_almost_equal(point.z, z, atol=1e-6)


def uniform_sh(
    red: Float32, green: Float32, blue: Float32
) raises -> SphericalHarmonics3:
    """Return coefficients of band zero alone."""
    var sh = SphericalHarmonics3()
    sh.set_coefficient(0, Vector3(red, green, blue))
    return sh


def a_grid() raises -> LightProbeGrid:
    """Return a grid of three by two by two probes over a box from
    (0, 0, 0) to (2, 1, 1), probe `i` holding band zero of `i` in red."""
    var grid = LightProbeGrid(Vector3(0, 0, 0), Vector3(2, 1, 1), 3, 2, 2)
    for index in range(grid.count()):
        grid.probes[index] = uniform_sh(Float32(index), 0, 0)
    return grid^


# --- the grid ---------------------------------------------------------------


def test_a_grid_holds_one_dark_probe_a_point() raises:
    var grid = LightProbeGrid(Vector3(0, 0, 0), Vector3(2, 1, 1), 3, 2, 2)
    assert_equal(grid.count(), 12)
    assert_equal(len(grid.probes), 12)
    assert_false(grid.is_empty())
    assert_equal(grid.intensity, 1)
    assert_equal(grid.probes[11], SphericalHarmonics3())
    var empty = LightProbeGrid()
    assert_true(empty.is_empty())
    assert_equal(empty.count(), 0)


def test_a_grid_refuses_what_cannot_be_looked_up() raises:
    var low = Vector3(0, 0, 0)
    var high = Vector3(1, 1, 1)
    with assert_raises(contains="one probe or more"):
        _ = LightProbeGrid(low, high, 0, 1, 1)
    with assert_raises(contains="one probe or more"):
        _ = LightProbeGrid(low, high, 1, 0, 1)
    with assert_raises(contains="one probe or more"):
        _ = LightProbeGrid(low, high, 1, 1, 0)
    var far = inf[DType.float32]()
    with assert_raises(contains="finite"):
        _ = LightProbeGrid(Vector3(far, 0, 0), high, 1, 1, 1)
    with assert_raises(contains="finite"):
        _ = LightProbeGrid(Vector3(0, far, 0), high, 1, 1, 1)
    with assert_raises(contains="finite"):
        _ = LightProbeGrid(Vector3(0, 0, far), high, 1, 1, 1)
    with assert_raises(contains="finite"):
        _ = LightProbeGrid(low, Vector3(1, 1, nan[DType.float32]()), 1, 1, 1)
    with assert_raises(contains="wider than zero"):
        _ = LightProbeGrid(low, Vector3(0, 1, 1), 1, 1, 1)
    with assert_raises(contains="wider than zero"):
        _ = LightProbeGrid(low, Vector3(1, -1, 1), 1, 1, 1)
    with assert_raises(contains="wider than zero"):
        _ = LightProbeGrid(low, Vector3(1, 1, 0), 1, 1, 1)
    with assert_raises(contains="intensity"):
        _ = LightProbeGrid(low, high, 1, 1, 1, intensity=-1)
    with assert_raises(contains="intensity"):
        _ = LightProbeGrid(low, high, 1, 1, 1, intensity=nan[DType.float32]())
    var grid = LightProbeGrid(low, high, 1, 1, 1)
    grid.probes[0].lanes[4] = far
    with assert_raises(contains="coefficients"):
        grid.validate()


def test_a_probes_place_counts_x_fastest() raises:
    var grid = a_grid()
    assert_equal(grid.index(0, 0, 0), 0)
    assert_equal(grid.index(2, 0, 0), 2)
    assert_equal(grid.index(0, 1, 0), 3)
    assert_equal(grid.index(1, 1, 1), 10)
    with assert_raises(contains="no probe there"):
        _ = grid.index(-1, 0, 0)
    with assert_raises(contains="no probe there"):
        _ = grid.index(0, -1, 0)
    with assert_raises(contains="no probe there"):
        _ = grid.index(0, 0, -1)
    with assert_raises(contains="no probe there"):
        _ = grid.index(3, 0, 0)
    with assert_raises(contains="no probe there"):
        _ = grid.index(0, 2, 0)
    with assert_raises(contains="no probe there"):
        _ = grid.index(0, 0, 2)


def test_the_corner_probes_stand_at_the_boxs_corners() raises:
    var grid = a_grid()
    assert_at(grid.position(0), 0, 0, 0)
    assert_at(grid.position(1), 1, 0, 0)
    assert_at(grid.position(11), 2, 1, 1)
    assert_at(grid.position(grid.index(1, 1, 0)), 1, 1, 0)
    # A single probe on an axis stands in the middle of it.
    var line = LightProbeGrid(LOW, HIGH, 2, 1, 1)
    assert_at(line.position(1), 1, 0, 0)
    with assert_raises(contains="no probe there"):
        _ = grid.position(-1)
    with assert_raises(contains="no probe there"):
        _ = grid.position(12)


def test_the_taps_are_a_trilinear_read() raises:
    # (0.5, 0.25, 0.75) in the first cell: a half along x, a quarter along
    # y and three quarters along z.
    var taps = grid_taps(
        Vector3(0.5, 0.25, 0.75), Vector3(0, 0, 0), Vector3(2, 1, 1), 3, 2, 2
    )
    assert_equal(Int(taps.probes[0]), 0)
    assert_equal(Int(taps.probes[1]), 1)
    assert_equal(Int(taps.probes[2]), 3)
    assert_equal(Int(taps.probes[4]), 6)
    assert_equal(Int(taps.probes[7]), 10)
    assert_almost_equal(taps.weights[0], 0.5 * 0.75 * 0.25, atol=1e-6)
    assert_almost_equal(taps.weights[7], 0.5 * 0.25 * 0.75, atol=1e-6)
    var total = Float32(0)
    for corner in range(8):
        total += taps.weights[corner]
    assert_almost_equal(total, 1, atol=1e-6)


def test_a_position_outside_the_box_takes_its_nearest_face() raises:
    # Past the high corner: the last probe alone, with no step.
    var past = grid_taps(
        Vector3(5, 5, 5), Vector3(0, 0, 0), Vector3(2, 1, 1), 3, 2, 2
    )
    for corner in range(8):
        assert_equal(Int(past.probes[corner]), 11)
    assert_almost_equal(past.weights[0], 1, atol=1e-6)
    # Before the low corner: the first.
    var before = grid_taps(
        Vector3(-5, -5, -5), Vector3(0, 0, 0), Vector3(2, 1, 1), 3, 2, 2
    )
    assert_equal(Int(before.probes[0]), 0)
    assert_almost_equal(before.weights[0], 1, atol=1e-6)
    # One probe along an axis: that probe, whatever the position.
    var flat = grid_taps(Vector3(0.3, 0.9, 0), LOW, HIGH, 2, 1, 1)
    assert_equal(Int(flat.probes[1]), 1)
    assert_equal(Int(flat.probes[3]), 1)
    assert_almost_equal(flat.weights[1], 0.65, atol=1e-6)


def test_the_blend_is_the_lerp_of_the_eight_probes() raises:
    var grid = a_grid()
    # Probe i holds i: the blend along x at a quarter of the first cell is
    # a quarter; one probe up in y adds three, and in z six.
    var blend = grid.sh_at(Vector3(0.25, 0, 0))
    assert_almost_equal(blend.lanes[0], 0.25, atol=1e-6)
    blend = grid.sh_at(Vector3(0.25, 0.5, 0.5))
    assert_almost_equal(blend.lanes[0], 0.25 + 1.5 + 3, atol=1e-5)
    assert_equal(blend.lanes[1], 0)
    assert_equal(
        LightProbeGrid().sh_at(Vector3(0, 0, 0)), SphericalHarmonics3()
    )


def test_the_irradiance_carries_the_intensity() raises:
    var grid = LightProbeGrid(LOW, HIGH, 2, 1, 1, intensity=2)
    grid.probes[0] = uniform_sh(1, 0, 0)
    grid.probes[1] = uniform_sh(1, 0, 0)
    var lift = grid.irradiance_at(Vector3(0, 0, 0), Vector3(0, 1, 0))
    assert_almost_equal(lift.x, 2 * 0.886227, atol=1e-5)
    assert_equal(lift.y, 0)
    var scaled = grid.scaled()
    assert_equal(scaled.intensity, 1)
    assert_almost_equal(scaled.probes[0].lanes[0], 2, atol=1e-6)
    # The original is left as it was.
    assert_equal(grid.probes[0].lanes[0], 1)


def test_a_grid_is_flattened_for_the_kernel() raises:
    var grid = a_grid()
    var flat = grid.flatten()
    assert_equal(len(flat), GRID_HEADER + 27 * 12)
    assert_equal(flat[3], 2)
    assert_equal(flat[6], 3)
    assert_equal(flat[7], 2)
    assert_equal(flat[8], 2)
    assert_equal(flat[GRID_HEADER + 27 * 5], 5)
    assert_equal(len(LightProbeGrid().flatten()), 0)
    var copied = LightProbeGrid(copy=grid)
    assert_equal(copied.count_x, 3)
    assert_equal(copied.probes[7], grid.probes[7])


# --- in the lighting --------------------------------------------------------


def test_the_grid_adds_to_the_ambient_term() raises:
    var scene = Scene()
    var grid = LightProbeGrid(LOW, HIGH, 2, 1, 1, intensity=2)
    grid.probes[0] = uniform_sh(1, 0, 0)
    grid.probes[1] = uniform_sh(0, 0, 1)
    var lighting = Lighting(scene, probe_grid=grid)
    var up = Vector3(0, 1, 0)
    # At the left probe, red at twice its irradiance; at the right, blue.
    var left = lighting.ambient_at(up, Vector3(-1, 0, 0))
    assert_almost_equal(left.r, 2 * 0.886227, atol=1e-5)
    assert_almost_equal(left.b, 0, atol=1e-6)
    var right = lighting.ambient_at(up, Vector3(1, 0, 0))
    assert_almost_equal(right.b, 2 * 0.886227, atol=1e-5)
    # Halfway, half of each; the indirect light is the same, over pi.
    var middle = lighting.indirect_at(up, Vector3(0, 0, 0))
    assert_almost_equal(middle.r, 0.886227 / Float32(pi), atol=1e-5)
    assert_almost_equal(middle.b, 0.886227 / Float32(pi), atol=1e-5)
    # Without a grid, nothing.
    assert_equal(Lighting(scene).ambient_at(up, Vector3(0, 0, 0)).r, 0)


def test_the_lighting_refuses_a_wrong_grid() raises:
    var grid = LightProbeGrid(LOW, HIGH, 1, 1, 1)
    grid.probes[0].lanes[0] = nan[DType.float32]()
    with assert_raises(contains="coefficients"):
        _ = Lighting(Scene(), probe_grid=grid)
    var renderer = Renderer(8, 8)
    with assert_raises(contains="coefficients"):
        renderer.set_light_probe_grid(grid^)
    renderer.set_light_probe_grid(LightProbeGrid())
    assert_true(renderer.probe_grid.is_empty())


def a_lit_floor(mut assets: Assets) raises -> Scene:
    """Return a gray floor at y = 0, four meters wide, with no light."""
    var scene = Scene()
    var ground = Object3D()
    ground.set_euler(
        Angle(-90.0, DEGREE), Angle(0.0, DEGREE), Angle(0.0, DEGREE)
    )
    var floor = assets.geometries.add(
        plane(Length(4.0, METER), Length(4.0, METER), 2, 2)
    )
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    scene.add_mesh(Mesh(floor, paint, scene.add(ground^)))
    scene.update()
    return scene^


def top_camera() raises -> OrthographicCamera:
    """Return a camera four meters up looking down, two meters each way."""
    var camera = OrthographicCamera(
        Length(-2.0, METER),
        Length(2.0, METER),
        Length(2.0, METER),
        Length(-2.0, METER),
        Length(0.1, METER),
        Length(10.0, METER),
    )
    camera.place(Vector3(0, 4, 0.001), Vector3(0, 0, 0))
    return camera^


def test_the_renderer_lights_a_floor_with_its_grid() raises:
    # A floor with no light is black; with a grid that is red on the left
    # and blue on the right, it is red on the left and blue on the right.
    var assets = Assets()
    var scene = a_lit_floor(assets)
    var renderer = Renderer(SIDE, SIDE)
    var dark = renderer.render(scene, assets, top_camera())
    assert_equal(dark.get_pixel(4, SIDE // 2).r, 0)
    var grid = LightProbeGrid(
        Vector3(-2, -1, -2), Vector3(2, 1, 2), 2, 1, 1, intensity=3
    )
    grid.probes[0] = uniform_sh(1, 0, 0)
    grid.probes[1] = uniform_sh(0, 0, 1)
    renderer.set_light_probe_grid(grid^)
    var lit = renderer.render(scene, assets, top_camera())
    var left = lit.get_pixel(1, SIDE // 2)
    var right = lit.get_pixel(SIDE - 2, SIDE // 2)
    assert_true(Int(left.r) > Int(left.b) + 60, "the left is not red")
    assert_true(Int(right.b) > Int(right.r) + 60, "the right is not blue")


# --- baked ------------------------------------------------------------------


def test_a_color_environment_is_its_color_in_every_direction() raises:
    var assets = Assets()
    var gray = color_environment(assets, Color(128, 64, 32))
    var cube = scene_cube(Renderer(4, 4), gray, assets, size=4)
    for face in range(6):
        for y in range(4):
            for x in range(4):
                var seen = cube.faces[face].wrapped_texel(x, y, 0)
                assert_almost_equal(
                    seen.r, srgb_to_linear(128.0 / 255), atol=1e-5
                )
                assert_almost_equal(
                    seen.g, srgb_to_linear(64.0 / 255), atol=1e-5
                )
                assert_almost_equal(
                    seen.b, srgb_to_linear(32.0 / 255), atol=1e-5
                )
    # White by default.
    var white = color_environment(assets)
    var bright = scene_cube(Renderer(4, 4), white, assets, size=2)
    assert_almost_equal(bright.faces[2].wrapped_texel(0, 0, 0).g, 1, atol=1e-5)


def test_a_grid_baked_in_one_color_holds_pi_times_it() raises:
    # A uniform environment of radiance L gives an irradiance of pi L in
    # every direction, at every probe.
    var assets = Assets()
    var room = color_environment(assets, Color(255, 128, 0))
    var grid = LightProbeGrid(
        Vector3(-0.5, -0.5, -0.5), Vector3(0.5, 0.5, 0.5), 2, 1, 1
    )
    bake_light_probe_grid(grid, Renderer(4, 4), room, assets, size=4)
    var green = srgb_to_linear(128.0 / 255)
    for index in range(2):
        var lift = grid.probes[index].get_irradiance_at(Vector3(0, 1, 0))
        assert_almost_equal(lift.x, Float32(pi), atol=1e-3)
        assert_almost_equal(lift.y, Float32(pi) * green, atol=1e-3)
        assert_almost_equal(lift.z, 0, atol=1e-4)
        var side = grid.probes[index].get_irradiance_at(Vector3(1, 0, 0))
        assert_almost_equal(side.x, Float32(pi), atol=1e-3)
    var wrong = LightProbeGrid()
    with assert_raises(contains="one probe or more"):
        bake_light_probe_grid(wrong, Renderer(4, 4), room, assets)


# --- the helper -------------------------------------------------------------


def draw_helper(scene: Scene, assets: Assets) raises -> Framebuffer:
    """Draw a scene from +z, two meters each way."""
    var camera = OrthographicCamera(
        Length(-2.0, METER),
        Length(2.0, METER),
        Length(2.0, METER),
        Length(-2.0, METER),
        Length(0.1, METER),
        Length(10.0, METER),
    )
    camera.place(Vector3(0, 0, 5), Vector3(0, 0, 0))
    return Renderer(SIDE, SIDE).render(scene, assets, camera)


def helper_color(
    red: Float32, green: Float32, blue: Float32, intensity: Float32
) -> Color:
    """Return what a helper's sphere shows for band zero alone: three.js's
    shader, `RECIPROCAL_PI * irradiance * intensity`, encoded."""
    var scale = Float32(0.886227) * Float32(0.318309886) * intensity
    return FloatColor(red * scale, green * scale, blue * scale).encode()


def assert_near(got: Color, expected: Color) raises:
    """Assert three color bytes, each to within one."""
    assert_true(abs(Int(got.r) - Int(expected.r)) <= 1, "red")
    assert_true(abs(Int(got.g) - Int(expected.g)) <= 1, "green")
    assert_true(abs(Int(got.b) - Int(expected.b)) <= 1, "blue")


def test_the_helper_shows_each_probe_at_its_place() raises:
    var assets = Assets()
    var scene = Scene()
    var grid = LightProbeGrid(LOW, HIGH, 2, 1, 1, intensity=2)
    grid.probes[0] = uniform_sh(0.6, 0.1, 0.1)
    grid.probes[1] = uniform_sh(0.1, 0.1, 0.6)
    var helper = LightProbeGridHelper(grid, scene, assets, Length(0.4, METER))
    assert_equal(len(helper.nodes), 2)
    assert_equal(len(helper.programs), 2)
    assert_equal(len(helper.materials), 2)
    scene.update()
    var image = draw_helper(scene, assets)
    # The left probe at x = -1 is pixel 8, the right at x = 1 pixel 24.
    assert_near(image.get_pixel(8, SIDE // 2), helper_color(0.6, 0.1, 0.1, 2))
    assert_near(image.get_pixel(24, SIDE // 2), helper_color(0.1, 0.1, 0.6, 2))
    # Between them, nothing is drawn: the renderer's clear color.
    assert_near(image.get_pixel(16, SIDE // 2), Color(16, 18, 26))
    # A new bake is shown once `update` writes it.
    grid.probes[0] = uniform_sh(0.1, 0.6, 0.1)
    helper.update(grid, assets)
    image = draw_helper(scene, assets)
    assert_near(image.get_pixel(8, SIDE // 2), helper_color(0.1, 0.6, 0.1, 2))


def test_the_helper_hangs_from_its_parent() raises:
    var assets = Assets()
    var scene = Scene()
    var lift = Object3D()
    lift.set_position(0, 1, 0)
    var parent = scene.add(lift^)
    var grid = LightProbeGrid(LOW, HIGH, 2, 1, 1)
    var helper = LightProbeGridHelper(
        grid, scene, assets, Length(0.4, METER), parent
    )
    scene.update()
    assert_at(scene.world_position(helper.nodes[1]), 1, 1, 0)


def test_the_helper_refuses_what_it_cannot_show() raises:
    var assets = Assets()
    var scene = Scene()
    with assert_raises(contains="one probe or more"):
        _ = LightProbeGridHelper(LightProbeGrid(), scene, assets)
    var grid = LightProbeGrid(LOW, HIGH, 2, 1, 1)
    with assert_raises(contains="positive size"):
        _ = LightProbeGridHelper(grid, scene, assets, Length(0.0, METER))
    var helper = LightProbeGridHelper(grid, scene, assets)
    with assert_raises(contains="of its own size"):
        helper.update(LightProbeGrid(LOW, HIGH, 3, 1, 1), assets)
    with assert_raises(contains="one probe or more"):
        helper.update(LightProbeGrid(), assets)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
