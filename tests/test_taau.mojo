# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `TAAUNode`: its resolve against three.js's rules,
its settings, and a scene drawn at half size and resolved at full."""

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
from postprocessing.composer import (
    TAAU,
    EffectComposer,
    reads_frame_as_light,
    taau_pass,
)
from postprocessing.sampling import LightView
from postprocessing.taau import (
    TaauFrame,
    TaauSettings,
    check_taau,
    taau_input_size,
    taau_pixel,
)
from postprocessing.traa import FloatPlane
from render.framebuffer import Color, FloatColor
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


comptime IN = 4
comptime OUT = 8


def test_the_settings_are_checked() raises:
    check_taau(TaauSettings())
    var bad = TaauSettings()
    bad.depth_threshold = -1
    with assert_raises(contains="thresholds"):
        check_taau(bad)
    bad = TaauSettings()
    bad.edge_depth_diff = Float32.MAX * 2
    with assert_raises(contains="thresholds"):
        check_taau(bad)
    bad = TaauSettings()
    bad.depth_threshold = Float32.MAX * 2
    with assert_raises(contains="thresholds"):
        check_taau(bad)
    bad = TaauSettings()
    bad.edge_depth_diff = -1
    with assert_raises(contains="thresholds"):
        check_taau(bad)
    bad = TaauSettings()
    bad.max_velocity_length = Float32.MAX * 2
    with assert_raises(contains="velocity"):
        check_taau(bad)
    bad = TaauSettings()
    bad.max_velocity_length = 0
    with assert_raises(contains="velocity"):
        check_taau(bad)
    bad = TaauSettings()
    bad.current_frame_weight = 2
    with assert_raises(contains="frame weight"):
        check_taau(bad)
    bad = TaauSettings()
    bad.current_frame_weight = -1
    with assert_raises(contains="frame weight"):
        check_taau(bad)
    bad = TaauSettings()
    bad.resolution_scale = 0
    with assert_raises(contains="resolution scale"):
        check_taau(bad)
    bad = TaauSettings()
    bad.resolution_scale = 1.5
    with assert_raises(contains="resolution scale"):
        check_taau(bad)
    with assert_raises(contains="resolution scale"):
        _ = taau_pass(resolution_scale=0)
    assert_true(taau_pass().kind == TAAU)
    assert_false(reads_frame_as_light(TAAU))
    assert_equal(taau_input_size(9, 0.5), 5)


def resolved(
    beauty: List[FloatColor],
    history_color: FloatColor,
    velocity_x: Float32,
    depth: Float32 = 0.5,
    x: Int = 3,
    y: Int = 3,
    velocity_y: Float32 = 0,
    edge: Bool = False,
) raises -> FloatColor:
    """Return one output pixel of the resolve over a 4 by 4 input and an
    8 by 8 history of one color, every pixel moving by the velocity, with a
    last depth of zero seen through identity matrices."""
    var history = List[FloatColor](length=OUT * OUT, fill=history_color)
    var depths = List[Float32](length=IN * IN, fill=depth)
    if edge:
        # A near texel among the others: the neighbors' depths part.
        depths[1 * IN + 1] = 0.95
    var previous = List[Float32](length=IN * IN, fill=0)
    var moved = List[Float32]()
    for _ in range(IN * IN):
        moved.append(velocity_x)
        moved.append(velocity_y)
    var settings = TaauSettings()
    var frame = TaauFrame(
        IN, IN, OUT, OUT, 0.1, -0.2, 0.1, 10, True, Matrix4(), settings
    )
    var result = taau_pixel(
        LightView(beauty, IN, IN),
        LightView(history, OUT, OUT),
        FloatPlane(depths, IN, IN, 1),
        FloatPlane(previous, IN, IN, 1),
        FloatPlane(moved, IN, IN, 2),
        x,
        y,
        frame,
    )
    _ = history^
    _ = depths^
    _ = previous^
    _ = moved^
    return result


def test_the_resolve_clips_a_kept_history() raises:
    # Still, the history is kept but clipped onto the red frame's box.
    var red = List[FloatColor](length=IN * IN, fill=FloatColor(1, 0, 0, 1))
    var kept = resolved(red, FloatColor(0, 0, 1, 1), 0)
    assert_almost_equal(kept.r, 1, atol=1e-3)
    assert_almost_equal(kept.b, 0, atol=1e-3)
    # A history read past each edge of the image is dropped: the new
    # frame alone.
    var across: List[Float32] = [4, -4, 0, 0]
    var down: List[Float32] = [0, 0, 4, -4]
    for at in range(4):
        var dropped = resolved(
            red, FloatColor(0, 0, 1, 1), across[at], velocity_y=down[at]
        )
        assert_almost_equal(dropped.r, 1, atol=1e-5)
        assert_almost_equal(dropped.b, 0, atol=1e-5)
    # An edge keeps the history of an uncovered pixel.
    var kept_edge = resolved(
        red, FloatColor(0, 0, 1, 1), 0, depth=1, x=2, y=2, edge=True
    )
    assert_almost_equal(kept_edge.b, 0, atol=1e-3)
    # So is an uncovered surface.
    var fresh = resolved(red, FloatColor(0, 0, 1, 1), 0, depth=1)
    assert_almost_equal(fresh.r, 1, atol=1e-5)


def test_a_thin_feature_locks_the_history() raises:
    # One bright input texel among dark ones: its luminance is far from the
    # mean, so the lock keeps the history against the clip.
    var dots = List[FloatColor](
        length=IN * IN, fill=FloatColor(0.1, 0.1, 0.1, 1)
    )
    dots[1 * IN + 1] = FloatColor(1, 1, 1, 1)
    var history = FloatColor(0, 0, 0.9, 1)
    # The last depth, moved into this view, is this one: 0.9090909.
    var locked = resolved(dots, history, 0, depth=0.9090909, x=2, y=2)
    assert_true(locked.b > 0.5)
    # A black frame has no luminance to compare: nothing locks.
    var black = List[FloatColor](length=IN * IN, fill=FloatColor(0, 0, 0, 1))
    var plain = resolved(black, history, 0)
    assert_true(plain.b < 0.1)


def a_scene(mut assets: Assets) raises -> Scene:
    """Return a white square, turned, on black."""
    var scene = Scene()
    var node = Object3D()
    node.set_euler(Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(20.0, DEGREE))
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                plane(Length(1.0, METER), Length(1.0, METER))
            ),
            assets.materials.add(Material(Color(255, 255, 255), kind=BASIC)),
            scene.add(node^),
        )
    )
    scene.update()
    return scene^


def test_the_pass_resolves_a_small_scene_at_full_size() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 0, 2), Vector3(0, 0, 0))
    var renderer = Renderer(16, 16)
    renderer.set_background(Color(0, 0, 0))
    var composer = EffectComposer()
    composer.add_pass(taau_pass())
    var image = composer.render(renderer, scene, assets, camera)
    for _ in range(3):
        image = composer.render(renderer, scene, assets, camera)
    assert_equal(composer.passes[0].taau.jitter_index, 4)
    assert_equal(composer.passes[0].taau.history_width, 16)
    assert_equal(composer.passes[0].taau.previous_width, 8)
    assert_true(image.get_pixel(8, 8).r > 200)
    assert_true(image.get_pixel(0, 0).r < 30)
    # A renderer of another size starts over.
    _ = composer.render(Renderer(8, 8), scene, assets, camera)
    assert_equal(composer.passes[0].taau.history_width, 8)
    _ = composer.render(Renderer(8, 4), scene, assets, camera)
    assert_equal(composer.passes[0].taau.history_height, 4)


def test_the_pass_runs_through_an_orthographic_camera() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var camera = centered(
        Length(2.0, METER), 1.0, Length(0.1, METER), Length(10.0, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    var composer = EffectComposer()
    composer.add_pass(taau_pass(resolution_scale=1))
    var renderer = Renderer(8, 8)
    _ = composer.render(renderer, scene, assets, camera)
    var image = composer.render(renderer, scene, assets, camera)
    assert_true(image.get_pixel(4, 4).r > 200)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
