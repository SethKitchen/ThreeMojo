# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `TRAANode`: its jitter, its helpers, each way the
resolve keeps or drops the history, and the composer pass."""

from cameras.orthographic_camera import centered
from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from materials.material import BASIC, Material
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.composer import TRAA, EffectComposer, render_pass, traa_pass
from postprocessing.sampling import LightView
from postprocessing.traa import (
    TRAA_JITTERS,
    FloatPlane,
    TraaFrame,
    TraaSettings,
    check_traa,
    clip_aabb,
    flicker_reduction,
    halton,
    subpixel_correction,
    traa_jitter,
    traa_pixel,
)
from render.framebuffer import Color, FloatColor
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


def test_the_jitter_walks_the_halton_sequence() raises:
    assert_equal(halton(1, 2), 0.5)
    assert_equal(halton(2, 2), 0.25)
    assert_equal(halton(3, 2), 0.75)
    assert_almost_equal(halton(1, 3), 1.0 / 3.0)
    assert_almost_equal(halton(2, 3), 2.0 / 3.0)
    assert_almost_equal(halton(3, 3), 1.0 / 9.0)
    assert_equal(halton(0, 2), 0)
    assert_equal(traa_jitter(0).x, 0.5)
    assert_almost_equal(traa_jitter(0).y, 1.0 / 3.0)
    assert_equal(TRAA_JITTERS, 32)


def test_the_settings_are_checked() raises:
    check_traa(TraaSettings())
    var bad = TraaSettings()
    bad.depth_threshold = -1
    with assert_raises(contains="depth thresholds"):
        check_traa(bad)
    bad = TraaSettings()
    bad.edge_depth_diff = Float32.MAX * 2
    with assert_raises(contains="depth thresholds"):
        check_traa(bad)
    bad = TraaSettings()
    bad.edge_depth_diff = -1
    with assert_raises(contains="depth thresholds"):
        check_traa(bad)
    bad = TraaSettings()
    bad.depth_threshold = Float32.MAX * 2
    with assert_raises(contains="depth thresholds"):
        check_traa(bad)
    bad = TraaSettings()
    bad.max_velocity_length = 0
    with assert_raises(contains="velocity length"):
        check_traa(bad)
    bad = TraaSettings()
    bad.max_velocity_length = Float32.MAX * 2
    with assert_raises(contains="velocity length"):
        check_traa(bad)
    with assert_raises(contains="velocity length"):
        _ = traa_pass(max_velocity_length=-1)
    assert_true(traa_pass().kind == TRAA)


def test_the_helpers_are_three_js_s() raises:
    var low = FloatColor(0, 0, 0, 0)
    var high = FloatColor(1, 1, 1, 1)
    var middle = FloatColor(0.5, 0.5, 0.5, 1)
    # Inside the box, the history is kept.
    var inside = clip_aabb(middle, FloatColor(0.2, 0.7, 0.4, 1), low, high)
    assert_almost_equal(inside.g, 0.7)
    # Outside, it is pulled back to the box's face along the line to it.
    var outside = clip_aabb(middle, FloatColor(2.5, 0.5, 0.5, 1), low, high)
    assert_almost_equal(outside.r, 1, atol=1e-5)
    assert_almost_equal(outside.g, 0.5, atol=1e-5)
    # A weight of one is the new frame; of zero, the history.
    var red = FloatColor(1, 0, 0, 1)
    var blue = FloatColor(0, 0, 1, 1)
    assert_almost_equal(flicker_reduction(red, blue, 1).r, 1)
    assert_almost_equal(flicker_reduction(red, blue, 0).b, 1)
    # A whole pixel of velocity is no fraction; half a pixel is all one.
    assert_almost_equal(subpixel_correction(0.25, 0.5, 4, 4), 0)
    assert_almost_equal(subpixel_correction(0.125, 0.125, 4, 4), 1)


comptime SIDE = 4


def colors(color: FloatColor) -> List[FloatColor]:
    """Return a 4 by 4 image of one color."""
    return List[FloatColor](length=SIDE * SIDE, fill=color)


def floats(value: Float32, lanes: Int) -> List[Float32]:
    """Return a 4 by 4 plane of one number."""
    return List[Float32](length=SIDE * SIDE * lanes, fill=value)


def resolved(
    velocity_x: Float32,
    velocity_y: Float32,
    depth: Float32 = 0.5,
    x: Int = 1,
    y: Int = 1,
    subpixel: Bool = True,
) raises -> FloatColor:
    """Return one pixel of the resolve over a red frame and a blue history,
    every pixel moving by the velocity, at one depth, and a last depth of
    zero seen through identity matrices."""
    var beauty = colors(FloatColor(1, 0, 0, 1))
    var history = colors(FloatColor(0, 0, 1, 1))
    var depths = floats(depth, 1)
    var previous = floats(0, 1)
    var moved = List[Float32]()
    for _ in range(SIDE * SIDE):
        moved.append(velocity_x)
        moved.append(velocity_y)
    var settings = TraaSettings()
    settings.use_subpixel_correction = subpixel
    var frame = TraaFrame(SIDE, SIDE, 0.1, 10, True, Matrix4(), settings)
    var result = traa_pixel(
        LightView(beauty, SIDE, SIDE),
        LightView(history, SIDE, SIDE),
        FloatPlane(depths, SIDE, SIDE, 1),
        FloatPlane(previous, SIDE, SIDE, 1),
        FloatPlane(moved, SIDE, SIDE, 2),
        x,
        y,
        frame,
    )
    # The views read the lists: they must live past the read.
    _ = beauty^
    _ = history^
    _ = depths^
    _ = previous^
    _ = moved^
    return result


def test_the_resolve_keeps_the_history_it_can_trust() raises:
    # Still, and the last depth further than this one: the history is
    # kept. The box of an even red frame is red alone, so the blue history
    # is clipped onto it.
    var kept = resolved(0, 0)
    assert_almost_equal(kept.r, 1, atol=1e-3)
    assert_almost_equal(kept.b, 0, atol=1e-3)
    # Without the subpixel correction too.
    kept = resolved(0, 0, subpixel=False)
    assert_almost_equal(kept.r, 1, atol=1e-3)
    # An uncovered surface drops the history: the new frame alone.
    var fresh = resolved(0, 0, depth=1)
    assert_almost_equal(fresh.r, 1, atol=1e-5)
    # So does a history read past each edge of the image.
    var across: List[Float32] = [4, -4, 0, 0]
    var down: List[Float32] = [0, 0, 4, -4]
    for at in range(4):
        var dropped = resolved(across[at], down[at])
        assert_almost_equal(dropped.r, 1, atol=1e-5)
        assert_almost_equal(dropped.b, 0, atol=1e-5)


def test_an_edge_keeps_the_history_of_an_uncovered_pixel() raises:
    var beauty = colors(FloatColor(1, 0, 0, 1))
    var history = colors(FloatColor(1, 0, 0, 1))
    # A near pixel beside far ones: an edge, uncovered, still kept.
    var depths = floats(1, 1)
    depths[1 * SIDE + 2] = 0.2
    var previous = floats(0, 1)
    var still = floats(0, 2)
    var settings = TraaSettings()
    var frame = TraaFrame(SIDE, SIDE, 0.1, 10, False, Matrix4(), settings)
    var edge = traa_pixel(
        LightView(beauty, SIDE, SIDE),
        LightView(history, SIDE, SIDE),
        FloatPlane(depths, SIDE, SIDE, 1),
        FloatPlane(previous, SIDE, SIDE, 1),
        FloatPlane(still, SIDE, SIDE, 2),
        1,
        1,
        frame,
    )
    _ = beauty^
    _ = history^
    _ = depths^
    _ = previous^
    _ = still^
    assert_almost_equal(edge.r, 1, atol=1e-5)


def a_scene(mut assets: Assets) raises -> Scene:
    """Return a white square on black."""
    var scene = Scene()
    var stand = Object3D()
    stand.set_euler(Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(20.0, DEGREE))
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                plane(Length(1.0, METER), Length(1.0, METER))
            ),
            assets.materials.add(Material(Color(255, 255, 255), kind=BASIC)),
            scene.add(stand^),
        )
    )
    scene.update()
    return scene^


def test_the_pass_softens_the_edges_over_frames() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 0, 2), Vector3(0, 0, 0))
    var renderer = Renderer(16, 16)
    renderer.set_background(Color(0, 0, 0))
    var composer = EffectComposer()
    composer.add_pass(traa_pass())
    var image = composer.render(renderer, scene, assets, camera)
    for _ in range(4):
        image = composer.render(renderer, scene, assets, camera)
    assert_equal(composer.passes[0].traa.jitter_index, 5)
    assert_equal(composer.passes[0].traa.history_width, 16)
    # The square's middle stays white, the corners black, and the edges
    # take the shades between.
    assert_equal(image.get_pixel(8, 8).r, 255)
    assert_equal(image.get_pixel(0, 0).r, 0)
    var between = 0
    for y in range(16):
        for x in range(16):
            var red = image.get_pixel(x, y).r
            if red > 10 and red < 245:
                between += 1
    assert_true(between > 4)
    # A renderer of another size starts the history over.
    _ = composer.render(Renderer(8, 8), scene, assets, camera)
    assert_equal(composer.passes[0].traa.history_width, 8)
    # So does one of another height alone.
    _ = composer.render(Renderer(8, 4), scene, assets, camera)
    assert_equal(composer.passes[0].traa.history_height, 4)


def test_the_pass_runs_through_an_orthographic_camera() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var camera = centered(
        Length(2.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var composer = EffectComposer()
    composer.add_pass(traa_pass(use_subpixel_correction=False))
    var renderer = Renderer(8, 8)
    _ = composer.render(renderer, scene, assets, camera)
    var image = composer.render(renderer, scene, assets, camera)
    assert_equal(image.get_pixel(4, 4).r, 255)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
