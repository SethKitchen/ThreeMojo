# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a box of light probes: `lights.light_probe_grid`, three.js
r186's `LightProbeGrid` and `LightProbeGridNode`; its bake,
`renderers.light_probe_grid_utils`, three.js's `bake` and
`LightProbeGridUtils`; its place in `Lighting` and the renderer; its
helper, `helpers.light_probe_grid`; and the environment of one color it
is baked in here, `environments.color_environment`.

A surface moves half a probe spacing along its normal, then takes the
eight probes around it, blended trilinearly as three.js's linear filter
blends the texels of its probe textures. A probe baked in a uniform
environment of radiance `L` holds an irradiance of `pi * L` in every
direction.
"""

from cameras.orthographic_camera import OrthographicCamera
from core.assets import Assets
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from environments.color_environment import color_environment
from geometries.box import cube
from geometries.plane import plane
from helpers.light_probe_grid import (
    DEFAULT_GRID_HELPER_SIZE,
    LightProbeGridHelper,
)
from lights.light_probe_grid import (
    AUTO_PROBES,
    GRID_HEADER,
    LightProbeGrid,
    grid_falloff,
    grid_taps,
)
from lights.lighting import Lighting
from lights.shadow import SUN_BLEND
from lights.sun_light import SunLight
from materials.material import Material
from math.smoothstep import smoothstep
from math.spherical_harmonics3 import SphericalHarmonics3
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color, FloatColor, Framebuffer
from render.srgb import srgb_to_linear
from renderers.environment import scene_cube
from renderers.light_probe_grid_utils import (
    DEFAULT_CUBEMAP_SIZE,
    DEFAULT_SAMPLE_COUNT,
    bake_light_probe_grid,
    caster_sphere,
    fibonacci_direction,
    project_sh,
    replace_sun_lights,
    restore_sun_lights,
)
from renderers.renderer import Renderer
from std.math import inf, nan, pi, sqrt
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
comptime NO_NORMAL = Vector3(0, 0, 0)
comptime UP = Vector3(0, 1, 0)


def meters(value: Float32) -> Length:
    """Return a length in meters."""
    return Length(value, METER)


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
    var grid = LightProbeGrid(
        meters(2), meters(1), meters(1), 3, 2, 2, Vector3(1, 0.5, 0.5)
    )
    for index in range(grid.count()):
        grid.probes[index] = uniform_sh(Float32(index), 0, 0)
    return grid^


def a_line() raises -> LightProbeGrid:
    """Return two probes, at x = -1 and x = 1, in a box two meters wide."""
    return LightProbeGrid(meters(2), meters(1), meters(1), 2, 1, 1)


# --- the grid ---------------------------------------------------------------


def test_a_grid_holds_one_dark_probe_a_point() raises:
    var grid = a_grid()
    assert_equal(grid.count(), 12)
    assert_equal(len(grid.probes), 12)
    assert_false(grid.is_empty())
    assert_equal(grid.intensity, 1)
    assert_equal(grid.falloff.to(METER), 0)
    assert_at(grid.low(), 0, 0, 0)
    assert_at(grid.high(), 2, 1, 1)
    var empty = LightProbeGrid.none()
    assert_true(empty.is_empty())
    assert_equal(empty.count(), 0)


def test_a_grid_takes_three_js_default_counts() raises:
    # `max( 2, round( size ) + 1 )` a side: a meter gives two, 4.4 gives
    # five, 2.5 rounds up to three and gives four.
    var unit = LightProbeGrid()
    assert_equal(unit.resolution_x, 2)
    assert_equal(unit.count(), 8)
    var sized = LightProbeGrid(meters(4.4), meters(2.5), meters(0.2))
    assert_equal(sized.resolution_x, 5)
    assert_equal(sized.resolution_y, 4)
    assert_equal(sized.resolution_z, 2)
    var mixed = LightProbeGrid(meters(4.4), meters(1), meters(1), 3)
    assert_equal(mixed.resolution_x, 3)
    assert_equal(mixed.resolution_y, AUTO_PROBES + 2)


def test_a_grid_refuses_what_cannot_be_looked_up() raises:
    var one = meters(1)
    with assert_raises(contains="one probe or more"):
        _ = LightProbeGrid(one, one, one, -1, 1, 1)
    with assert_raises(contains="one probe or more"):
        _ = LightProbeGrid(one, one, one, 1, -1, 1)
    with assert_raises(contains="one probe or more"):
        _ = LightProbeGrid(one, one, one, 1, 1, -1)
    var far = inf[DType.float32]()
    with assert_raises(contains="positive lengths"):
        _ = LightProbeGrid(meters(far), one, one, 2, 2, 2)
    with assert_raises(contains="positive lengths"):
        _ = LightProbeGrid(one, meters(far), one, 2, 2, 2)
    with assert_raises(contains="positive lengths"):
        _ = LightProbeGrid(one, one, meters(far), 2, 2, 2)
    with assert_raises(contains="positive lengths"):
        _ = LightProbeGrid(meters(0), one, one, 2, 2, 2)
    with assert_raises(contains="positive lengths"):
        _ = LightProbeGrid(one, meters(-1), one, 2, 2, 2)
    with assert_raises(contains="positive lengths"):
        _ = LightProbeGrid(one, one, meters(0), 2, 2, 2)
    with assert_raises(contains="position"):
        _ = LightProbeGrid(one, one, one, 2, 2, 2, Vector3(far, 0, 0))
    with assert_raises(contains="position"):
        _ = LightProbeGrid(one, one, one, 2, 2, 2, Vector3(0, far, 0))
    with assert_raises(contains="position"):
        _ = LightProbeGrid(
            one, one, one, 2, 2, 2, Vector3(0, 0, nan[DType.float32]())
        )
    var grid = LightProbeGrid()
    grid.intensity = -1
    with assert_raises(contains="intensity"):
        grid.validate()
    grid.intensity = nan[DType.float32]()
    with assert_raises(contains="intensity"):
        grid.validate()
    grid.intensity = 1
    grid.falloff = meters(-1)
    with assert_raises(contains="falloff"):
        grid.validate()
    grid.falloff = meters(far)
    with assert_raises(contains="falloff"):
        grid.validate()
    grid.falloff = meters(0)
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


def test_the_probes_stand_where_three_js_puts_them() raises:
    # three.js's `getProbePosition`: `position - size / 2 + i * size /
    # ( res - 1 )`, or `position` on an axis of one probe.
    var grid = a_grid()
    assert_at(grid.get_probe_position(0, 0, 0), 0, 0, 0)
    assert_at(grid.get_probe_position(1, 0, 0), 1, 0, 0)
    assert_at(grid.get_probe_position(2, 1, 1), 2, 1, 1)
    assert_at(grid.position_of(grid.index(1, 1, 0)), 1, 1, 0)
    var line = LightProbeGrid(
        meters(2), meters(1), meters(1), 2, 1, 1, Vector3(0, 3, 4)
    )
    assert_at(line.position_of(1), 1, 3, 4)
    with assert_raises(contains="no probe there"):
        _ = grid.position_of(-1)
    with assert_raises(contains="no probe there"):
        _ = grid.position_of(12)
    with assert_raises(contains="no probe there"):
        _ = grid.get_probe_position(3, 0, 0)


def test_the_taps_are_a_trilinear_read() raises:
    # (0.5, 0.25, 0.75) in the first cell, with no normal: a half along
    # x, a quarter along y and three quarters along z.
    var taps = grid_taps(
        Vector3(0.5, 0.25, 0.75),
        NO_NORMAL,
        Vector3(0, 0, 0),
        Vector3(2, 1, 1),
        3,
        2,
        2,
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


def test_the_normal_moves_the_read_half_a_spacing() raises:
    # three.js's `positionWorld.add( normalWorld.mul( spacing ).mul( 0.5 )
    # )`: the probes are a meter apart along x, so a normal along +x moves
    # the read from 0.25 to 0.75.
    var taps = grid_taps(
        Vector3(0.25, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 0, 0),
        Vector3(2, 1, 1),
        3,
        2,
        2,
    )
    assert_almost_equal(taps.weights[1], 0.75, atol=1e-6)
    # Along an axis of one probe there is no spacing and no move.
    var flat = grid_taps(
        Vector3(0.3, 0.9, 0), UP, Vector3(-1, -0.5, -0.5), Vector3(1, 0.5, 0.5), 2, 1, 1
    )
    assert_equal(Int(flat.probes[1]), 1)
    assert_equal(Int(flat.probes[3]), 1)
    assert_almost_equal(flat.weights[1], 0.65, atol=1e-6)


def test_a_position_outside_the_box_takes_its_nearest_face() raises:
    var past = grid_taps(
        Vector3(5, 5, 5), NO_NORMAL, Vector3(0, 0, 0), Vector3(2, 1, 1), 3, 2, 2
    )
    for corner in range(8):
        assert_equal(Int(past.probes[corner]), 11)
    assert_almost_equal(past.weights[0], 1, atol=1e-6)
    var before = grid_taps(
        Vector3(-5, -5, -5),
        NO_NORMAL,
        Vector3(0, 0, 0),
        Vector3(2, 1, 1),
        3,
        2,
        2,
    )
    assert_equal(Int(before.probes[0]), 0)
    assert_almost_equal(before.weights[0], 1, atol=1e-6)


def test_the_blend_is_the_lerp_of_the_eight_probes() raises:
    var grid = a_grid()
    # Probe i holds i: the blend along x at a quarter of the first cell is
    # a quarter; one probe up in y adds three, and in z six.
    var blend = grid.sh_at(Vector3(0.25, 0, 0), NO_NORMAL)
    assert_almost_equal(blend.lanes[0], 0.25, atol=1e-6)
    blend = grid.sh_at(Vector3(0.25, 0.5, 0.5), NO_NORMAL)
    assert_almost_equal(blend.lanes[0], 0.25 + 1.5 + 3, atol=1e-5)
    assert_equal(blend.lanes[1], 0)
    assert_equal(
        LightProbeGrid.none().sh_at(Vector3(0, 0, 0), UP),
        SphericalHarmonics3(),
    )


def test_the_irradiance_carries_the_intensity_and_is_not_negative() raises:
    var grid = a_line()
    grid.intensity = 2
    grid.probes[0] = uniform_sh(1, -1, 0)
    grid.probes[1] = uniform_sh(1, -1, 0)
    var lift = grid.irradiance_at(Vector3(0, 0, 0), UP)
    assert_almost_equal(lift.x, 2 * 0.886227, atol=1e-5)
    # three.js holds the irradiance at zero: `.max( vec3( 0.0 ) )`.
    assert_equal(lift.y, 0)
    assert_equal(lift.z, 0)
    var scaled = grid.scaled()
    assert_equal(scaled.intensity, 1)
    assert_almost_equal(scaled.probes[0].lanes[0], 2, atol=1e-6)
    assert_equal(grid.probes[0].lanes[0], 1)


def test_the_falloff_fades_the_grid_outside_its_box() raises:
    # three.js: `1 - smoothstep( 0, falloff, distance )` outside the box.
    var low = Vector3(-1, -0.5, -0.5)
    var high = Vector3(1, 0.5, 0.5)
    assert_equal(grid_falloff(Vector3(5, 0, 0), low, high, 0), 1)
    assert_equal(grid_falloff(Vector3(0, 0, 0), low, high, 2), 1)
    assert_almost_equal(
        grid_falloff(Vector3(1.5, 0, 0), low, high, 1),
        1 - smoothstep(0, 1, 0.5),
        atol=1e-6,
    )
    assert_almost_equal(
        grid_falloff(Vector3(0, -1.1, 1.3), low, high, 2),
        1 - smoothstep(0, 2, Float32(sqrt(0.36 + 0.64))),
        atol=1e-6,
    )
    assert_equal(grid_falloff(Vector3(-4, 0, 0), low, high, 1), 0)
    var grid = a_line()
    grid.probes[0] = uniform_sh(1, 0, 0)
    grid.probes[1] = uniform_sh(1, 0, 0)
    grid.falloff = meters(1)
    var inside = grid.irradiance_at(Vector3(0, 0, 0), UP).x
    var outside = grid.irradiance_at(Vector3(0, 1, 0), UP).x
    assert_almost_equal(outside, inside * 0.5, atol=1e-5)


def test_a_grid_is_flattened_for_the_kernel() raises:
    var grid = a_grid()
    grid.falloff = meters(0.5)
    var flat = grid.flatten()
    assert_equal(len(flat), GRID_HEADER + 27 * 12)
    assert_equal(flat[3], 2)
    assert_equal(flat[6], 3)
    assert_equal(flat[7], 2)
    assert_equal(flat[8], 2)
    assert_equal(flat[9], 0.5)
    assert_equal(flat[GRID_HEADER + 27 * 5], 5)
    assert_equal(len(LightProbeGrid.none().flatten()), 0)
    var copied = LightProbeGrid(copy=grid)
    assert_equal(copied.resolution_x, 3)
    assert_equal(copied.probes[7], grid.probes[7])


# --- in the lighting --------------------------------------------------------


def test_the_grid_adds_to_the_ambient_term() raises:
    var scene = Scene()
    var grid = a_line()
    grid.intensity = 2
    grid.probes[0] = uniform_sh(1, 0, 0)
    grid.probes[1] = uniform_sh(0, 0, 1)
    var lighting = Lighting(scene, probe_grid=grid)
    # At the left probe, red at twice its irradiance; at the right, blue.
    var left = lighting.ambient_at(UP, Vector3(-1, 0, 0))
    assert_almost_equal(left.r, 2 * 0.886227, atol=1e-5)
    assert_almost_equal(left.b, 0, atol=1e-6)
    var right = lighting.ambient_at(UP, Vector3(1, 0, 0))
    assert_almost_equal(right.b, 2 * 0.886227, atol=1e-5)
    # Halfway, half of each; the indirect light is the same, over pi.
    var middle = lighting.indirect_at(UP, Vector3(0, 0, 0))
    assert_almost_equal(middle.r, 0.886227 / Float32(pi), atol=1e-5)
    assert_almost_equal(middle.b, 0.886227 / Float32(pi), atol=1e-5)
    assert_equal(Lighting(scene).ambient_at(UP, Vector3(0, 0, 0)).r, 0)


def test_the_lighting_refuses_a_wrong_grid() raises:
    var grid = LightProbeGrid()
    grid.probes[0].lanes[0] = nan[DType.float32]()
    with assert_raises(contains="coefficients"):
        _ = Lighting(Scene(), probe_grid=grid)
    var renderer = Renderer(8, 8)
    with assert_raises(contains="coefficients"):
        renderer.set_light_probe_grid(grid^)
    renderer.set_light_probe_grid(LightProbeGrid.none())
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
    var grid = LightProbeGrid(meters(4), meters(2), meters(4), 2, 1, 1)
    grid.intensity = 3
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
    # White by default, on three.js's sphere of sixteen segments.
    var white = color_environment(assets)
    var bright = scene_cube(Renderer(4, 4), white, assets, size=2)
    assert_almost_equal(bright.faces[2].wrapped_texel(0, 0, 0).g, 1, atol=1e-5)
    assert_equal(
        assets.geometries.get(white.meshes[0].geometry).vertex_count(),
        17 * 17,
    )


def test_the_directions_are_an_equal_area_fibonacci_sphere() raises:
    # three.js: `z = 1 - ( 2i + 1 ) / n`, `r = sqrt( 1 - z * z )`, and a
    # golden angle of turn each step, with z along y.
    var first = fibonacci_direction(0, 2)
    assert_almost_equal(first.x, Float32(sqrt(0.75)), atol=1e-6)
    assert_almost_equal(first.y, 0.5, atol=1e-6)
    assert_almost_equal(first.z, 0, atol=1e-6)
    var second = fibonacci_direction(1, 2)
    assert_almost_equal(second.y, -0.5, atol=1e-6)
    assert_almost_equal(second.length(), 1, atol=1e-6)
    assert_equal(DEFAULT_SAMPLE_COUNT, 512)
    assert_equal(DEFAULT_CUBEMAP_SIZE, 8)


def test_a_grid_baked_in_one_color_holds_pi_times_it() raises:
    # A uniform environment of radiance L gives an irradiance of pi L in
    # every direction, at every probe: 4 pi / n times n samples of L
    # times the band-zero basis, 0.282095, times 0.886227.
    var assets = Assets()
    var room = color_environment(assets, Color(255, 128, 0))
    var grid = LightProbeGrid(meters(1), meters(1), meters(1), 2, 1, 1)
    bake_light_probe_grid(grid, Renderer(4, 4), room, assets, cubemap_size=4)
    var green = srgb_to_linear(128.0 / 255)
    for index in range(2):
        var lift = grid.probes[index].get_irradiance_at(UP)
        assert_almost_equal(lift.x, Float32(pi), atol=2e-2)
        assert_almost_equal(lift.y, Float32(pi) * green, atol=1e-2)
        assert_almost_equal(lift.z, 0, atol=1e-4)
        var side = grid.probes[index].get_irradiance_at(Vector3(1, 0, 0))
        assert_almost_equal(side.x, Float32(pi), atol=2e-2)


def test_a_bake_can_bounce_and_bake_a_range() raises:
    var assets = Assets()
    var room = color_environment(assets, Color(255, 255, 255))
    var grid = LightProbeGrid(meters(1), meters(1), meters(1), 2, 1, 1)
    bake_light_probe_grid(
        grid,
        Renderer(4, 4),
        room,
        assets,
        cubemap_size=2,
        bounces=1,
        sample_count=64,
    )
    assert_true(grid.probes[1].lanes[0] > 3)
    var ranged = LightProbeGrid(meters(1), meters(1), meters(1), 2, 1, 1)
    bake_light_probe_grid(
        ranged, Renderer(4, 4), room, assets, 2, sample_count=64, start=1
    )
    assert_equal(ranged.probes[0], SphericalHarmonics3())
    assert_true(ranged.probes[1].lanes[0] > 3)
    # Nothing to bake is no bake.
    var none = LightProbeGrid(meters(1), meters(1), meters(1), 2, 1, 1)
    bake_light_probe_grid(none, Renderer(4, 4), room, assets, count=0)
    assert_equal(none.probes[1], SphericalHarmonics3())


def test_a_bake_refuses_what_three_js_refuses() raises:
    var assets = Assets()
    var room = color_environment(assets)
    var renderer = Renderer(4, 4)
    var grid = LightProbeGrid(meters(1), meters(1), meters(1), 2, 1, 1)
    with assert_raises(contains="lacks"):
        bake_light_probe_grid(grid, renderer, room, assets, start=-1)
    with assert_raises(contains="lacks"):
        bake_light_probe_grid(grid, renderer, room, assets, count=3)
    with assert_raises(contains="lacks"):
        bake_light_probe_grid(grid, renderer, room, assets, count=-2)
    with assert_raises(contains="negative"):
        bake_light_probe_grid(grid, renderer, room, assets, bounces=-1)
    with assert_raises(contains="every probe"):
        bake_light_probe_grid(
            grid, renderer, room, assets, bounces=1, count=1
        )
    with assert_raises(contains="one direction"):
        bake_light_probe_grid(grid, renderer, room, assets, sample_count=0)
    var cube = scene_cube(renderer, room, assets, size=2)
    with assert_raises(contains="one direction"):
        _ = project_sh(cube, 0)
    var wrong = LightProbeGrid.none()
    with assert_raises(contains="one probe or more"):
        bake_light_probe_grid(wrong, renderer, room, assets)


def a_sunny_room(mut assets: Assets) raises -> Scene:
    """Return a box a meter wide that casts, under a sun that casts."""
    var scene = Scene()
    var block = assets.geometries.add(cube(Length(1.0, METER)))
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    scene.add_mesh(Mesh(block, paint, scene.add(Object3D()), cast_shadow=True))
    var sun = SunLight(scene)
    for index in range(len(sun.lights)):
        scene.lights[sun.lights[index]].cast_shadow = True
    scene.update()
    return scene^


def test_a_sun_is_one_light_fit_to_the_casters_for_the_bake() raises:
    # three.js's `replaceSunLights`: the casters' sphere is the unit box's,
    # half its diagonal, held at one. The last cascade stands two radii
    # back toward the sun, a square of one to each side, from a half to
    # three and a half; the other lights nothing.
    var assets = Assets()
    var scene = a_sunny_room(assets)
    var sphere = caster_sphere(scene, assets)
    assert_at(sphere[0], 0, 0, 0)
    assert_equal(sphere[1], 1)
    var saved = replace_sun_lights(scene, assets)
    assert_equal(scene.lights[0].intensity, 0)
    ref bake = scene.lights[1]
    assert_false(bake.cascade.is_cascade())
    assert_equal(bake.shadow.right.to(METER), 1)
    assert_equal(bake.shadow.near.to(METER), 0.5)
    assert_equal(bake.shadow.far.to(METER), 3.5)
    assert_at(scene.world_position(bake.node), 0, 2, 0)
    assert_at(scene.world_position(bake.target), 0, 0, 0)
    restore_sun_lights(scene, saved)
    assert_equal(scene.lights[0].intensity, 1)
    assert_equal(scene.lights[1].cascade.blend, SUN_BLEND)
    assert_at(scene.world_position(scene.lights[1].node), 0, 1, 0)


def test_a_sun_that_does_not_cast_is_kept_and_no_caster_is_one_meter() raises:
    var assets = Assets()
    var scene = Scene()
    var sun = SunLight(scene)
    var sphere = caster_sphere(scene, assets)
    assert_at(sphere[0], 0, 0, 0)
    assert_equal(sphere[1], 1)
    var saved = replace_sun_lights(scene, assets)
    assert_equal(scene.lights[sun.lights[0]].intensity, 1)
    assert_true(scene.lights[sun.lights[1]].cascade.is_cascade())
    restore_sun_lights(scene, saved)
    # A mesh that does not cast is not a caster.
    var block = assets.geometries.add(cube(Length(4.0, METER)))
    var paint = assets.materials.add(Material(Color(200, 200, 200)))
    scene.add_mesh(Mesh(block, paint, scene.add(Object3D())))
    scene.update()
    assert_equal(caster_sphere(scene, assets)[1], 1)


def test_a_bake_puts_the_sun_back() raises:
    var assets = Assets()
    var scene = a_sunny_room(assets)
    var grid = LightProbeGrid(meters(4), meters(4), meters(4), 2, 1, 1)
    bake_light_probe_grid(
        grid, Renderer(4, 4), scene, assets, cubemap_size=2, sample_count=16
    )
    assert_equal(scene.lights[0].intensity, 1)
    assert_true(scene.lights[1].cascade.is_cascade())


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


def helper_color(red: Float32, green: Float32, blue: Float32) -> Color:
    """Return what a helper's sphere shows for band zero alone: three.js's
    `getShIrradianceAt( normalWorld, sh )`, encoded, with no division by
    pi and no intensity."""
    var scale = Float32(0.886227)
    return FloatColor(red * scale, green * scale, blue * scale).encode()


def assert_near(got: Color, expected: Color) raises:
    """Assert three color bytes, each to within one."""
    assert_true(abs(Int(got.r) - Int(expected.r)) <= 1, "red")
    assert_true(abs(Int(got.g) - Int(expected.g)) <= 1, "green")
    assert_true(abs(Int(got.b) - Int(expected.b)) <= 1, "blue")


def test_the_helper_shows_each_probe_at_its_place() raises:
    var assets = Assets()
    var scene = Scene()
    var grid = a_line()
    grid.intensity = 2
    grid.probes[0] = uniform_sh(0.6, 0.1, 0.1)
    grid.probes[1] = uniform_sh(0.1, 0.1, 0.6)
    var helper = LightProbeGridHelper(grid, scene, assets, Length(0.4, METER))
    assert_equal(len(helper.nodes), 2)
    assert_equal(len(helper.programs), 2)
    assert_equal(len(helper.materials), 2)
    scene.update()
    var image = draw_helper(scene, assets)
    # The left probe at x = -1 is pixel 8, the right at x = 1 pixel 24.
    # The intensity is not shown, as three.js's helper does not show it.
    assert_near(image.get_pixel(8, SIDE // 2), helper_color(0.6, 0.1, 0.1))
    assert_near(image.get_pixel(24, SIDE // 2), helper_color(0.1, 0.1, 0.6))
    assert_near(image.get_pixel(16, SIDE // 2), Color(16, 18, 26))
    # A new bake is shown once `update` writes it; a negative irradiance
    # shows black.
    grid.probes[0] = uniform_sh(0.1, 0.6, -0.5)
    helper.update(grid, assets)
    image = draw_helper(scene, assets)
    assert_near(image.get_pixel(8, SIDE // 2), helper_color(0.1, 0.6, 0))


def test_the_helper_has_three_js_default_size() raises:
    assert_equal(DEFAULT_GRID_HELPER_SIZE.to(METER), 0.12)
    var assets = Assets()
    var scene = Scene()
    var helper = LightProbeGridHelper(a_line(), scene, assets)
    var bounds = assets.geometries.get(helper.geometry).bounding_box()
    assert_almost_equal(bounds.max.x, 0.12, atol=1e-6)


def test_the_helper_hangs_from_its_parent() raises:
    var assets = Assets()
    var scene = Scene()
    var lift = Object3D()
    lift.set_position(0, 1, 0)
    var parent = scene.add(lift^)
    var helper = LightProbeGridHelper(
        a_line(), scene, assets, Length(0.4, METER), parent
    )
    scene.update()
    assert_at(scene.world_position(helper.nodes[1]), 1, 1, 0)


def test_the_helper_refuses_what_it_cannot_show() raises:
    var assets = Assets()
    var scene = Scene()
    with assert_raises(contains="one probe or more"):
        _ = LightProbeGridHelper(LightProbeGrid.none(), scene, assets)
    with assert_raises(contains="positive size"):
        _ = LightProbeGridHelper(a_line(), scene, assets, Length(0.0, METER))
    var helper = LightProbeGridHelper(a_line(), scene, assets)
    with assert_raises(contains="of its own size"):
        helper.update(
            LightProbeGrid(meters(2), meters(1), meters(1), 3, 1, 1), assets
        )
    with assert_raises(contains="one probe or more"):
        helper.update(LightProbeGrid.none(), assets)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
