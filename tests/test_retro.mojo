# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `RetroPassNode`: a scene drawn small, in eight
bits, with its corners snapped, and shown with nearest filtering."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.composer import (
    RETRO,
    EffectComposer,
    reads_frame_as_light,
    retro_pass,
)
from postprocessing.retro import (
    RetroSettings,
    byte_color,
    check_retro,
    retro_render,
)
from render.framebuffer import Color, FloatColor
from render.target import FLOAT_TARGET, RenderTarget
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


comptime SIZE = 16


def test_the_settings_are_checked() raises:
    check_retro(RetroSettings())
    var bad = RetroSettings()
    bad.resolution_scale = 0
    with assert_raises(contains="resolution scale"):
        check_retro(bad)
    bad.resolution_scale = 2
    with assert_raises(contains="resolution scale"):
        check_retro(bad)
    bad.resolution_scale = Float32.MAX * 2
    with assert_raises(contains="resolution scale"):
        check_retro(bad)
    with assert_raises(contains="resolution scale"):
        _ = retro_pass(0)
    assert_true(retro_pass().kind == RETRO)
    assert_almost_equal(retro_pass().retro.resolution_scale, 0.25)
    assert_false(reads_frame_as_light(RETRO))


def test_a_byte_target_rounds_and_clamps() raises:
    var held = byte_color(FloatColor(0.5, 2, -1, 1))
    assert_almost_equal(held.r, 128.0 / 255.0, atol=1e-6)
    assert_equal(held.g, 1)
    assert_equal(held.b, 0)


def a_scene(mut assets: Assets) raises -> Scene:
    """Return a white square, turned, on black."""
    var scene = Scene()
    var node = Object3D()
    node.set_euler(Angle(0.0, DEGREE), Angle(0.0, DEGREE), Angle(30.0, DEGREE))
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


def a_camera() raises -> PerspectiveCamera:
    """Return a camera two meters back."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 0, 2), Vector3(0, 0, 0))
    return camera^


def test_the_frame_is_blocks_of_small_pixels() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var frame = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET)
    retro_render(frame, renderer, scene, assets, a_camera(), RetroSettings())
    var lit = 0
    for y in range(SIZE):
        for x in range(SIZE):
            var here = frame.colors[y * SIZE + x]
            var block = frame.colors[(y // 4 * 4) * SIZE + x // 4 * 4]
            assert_equal(here.r, block.r)
            assert_equal(
                frame.depth[y * SIZE + x],
                frame.depth[(y // 4 * 4) * SIZE + x // 4 * 4],
            )
            if here.r > 0.5:
                lit += 1
    assert_true(lit > 0)
    assert_false(frame.data[0])
    with assert_raises(contains="resolution scale"):
        var bad = RetroSettings()
        bad.resolution_scale = -1
        retro_render(frame, renderer, scene, assets, a_camera(), bad)


def test_the_composer_runs_the_pass() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var composer = EffectComposer()
    composer.add_pass(retro_pass(0.5))
    var image = composer.render(Renderer(SIZE, SIZE), scene, assets, a_camera())
    assert_equal(image.get_pixel(0, 0).r, image.get_pixel(1, 1).r)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
