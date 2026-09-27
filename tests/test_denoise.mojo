# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `DenoiseNode`: its settings, the pixels it leaves
alone, and a checkered surface smoothed toward its mean."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from geometries.plane import plane
from materials.material import BASIC, Material
from math.vector3 import Vector3
from objects.mesh import Mesh
from postprocessing.composer import (
    DENOISE,
    EffectComposer,
    Pass,
    denoise_pass,
    frame_outputs,
    render_pass,
)
from postprocessing.denoise import DenoiseSettings, check_denoise, denoise_light
from postprocessing.screen_space import DepthView
from render.framebuffer import Color, FloatColor
from render.target import (
    FLOAT_TARGET,
    OUTPUT_COLOR,
    OUTPUT_NORMAL,
    RenderTarget,
    TargetOutput,
)
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


comptime SIZE = 24


def test_the_settings_are_checked() raises:
    check_denoise(DenoiseSettings())
    var bad = DenoiseSettings()
    bad.luma_phi = 0
    with assert_raises(contains="phis"):
        check_denoise(bad)
    bad = DenoiseSettings()
    bad.depth_phi = -1
    with assert_raises(contains="phis"):
        check_denoise(bad)
    bad = DenoiseSettings()
    bad.normal_phi = 0
    with assert_raises(contains="phis"):
        check_denoise(bad)
    for index in range(3):
        bad = DenoiseSettings()
        if index == 0:
            bad.luma_phi = Float32.MAX * 2
        elif index == 1:
            bad.depth_phi = Float32.MAX * 2
        else:
            bad.normal_phi = Float32.MAX * 2
        with assert_raises(contains="phis"):
            check_denoise(bad)
    bad = DenoiseSettings()
    bad.radius = Float32.MAX * 2
    with assert_raises(contains="radius"):
        check_denoise(bad)
    with assert_raises(contains="phis"):
        _ = denoise_pass(luma_phi=0)
    assert_true(denoise_pass().kind == DENOISE)
    var steps: List[Pass] = [render_pass(), denoise_pass()]
    var outputs = frame_outputs(steps)
    assert_equal(len(outputs), 2)
    assert_true(outputs[1] == OUTPUT_NORMAL)


def a_camera() raises -> PerspectiveCamera:
    """Return a camera two meters in front of the square."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(20.0, METER)
    )
    camera.place(Vector3(0, 0, 2), Vector3(0, 0, 0))
    return camera^


def a_checkered_square() raises -> RenderTarget:
    """Return a square drawn with its normals, a pixel checker of two
    grays laid over it, and the background black."""
    var assets = Assets()
    var scene = Scene()
    scene.add_mesh(
        Mesh(
            assets.geometries.add(
                plane(Length(1.0, METER), Length(1.0, METER))
            ),
            assets.materials.add(Material(Color(255, 255, 255), kind=BASIC)),
            scene.add(Object3D()),
        )
    )
    scene.update()
    var renderer = Renderer(SIZE, SIZE)
    renderer.set_background(Color(0, 0, 0))
    var outputs: List[TargetOutput] = [OUTPUT_COLOR, OUTPUT_NORMAL]
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET, outputs)
    renderer.render_into(target, scene, assets, a_camera())
    for y in range(SIZE):
        for x in range(SIZE):
            var slot = y * SIZE + x
            if target.colors[slot].r > 0.5:
                var gray = Float32(0.4) if (x + y) % 2 == 0 else Float32(0.6)
                target.colors[slot] = FloatColor(gray, gray, gray, 1)
    return target^


def view_of(target: RenderTarget) raises -> DepthView:
    """Return the target's depth seen through the camera."""
    var camera = a_camera()
    return DepthView(
        target.depth,
        SIZE,
        SIZE,
        camera.projection_matrix(),
        Length(0.1, METER),
        Length(20.0, METER),
        target.depth_mode,
        target.normals,
    )


def test_a_checkered_surface_is_smoothed_and_the_rest_kept() raises:
    var target = a_checkered_square()
    var view = view_of(target)
    var middle = target.colors[12 * SIZE + 12].r
    assert_almost_equal(middle, 0.4)
    # A pixel with no normal is kept, even over a surface.
    target.normals[12 * SIZE + 13] = Vector3(0, 0, 0)
    denoise_light(target, view, DenoiseSettings())
    var smoothed = target.colors[12 * SIZE + 12].r
    assert_true(smoothed > 0.42 and smoothed < 0.58)
    assert_almost_equal(target.colors[12 * SIZE + 13].r, 0.6)
    # The background has no surface and stays black.
    assert_equal(target.colors[0].r, 0)


def test_a_frame_without_normals_is_refused() raises:
    var target = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET)
    var camera = a_camera()
    var view = DepthView(
        target.depth,
        SIZE,
        SIZE,
        camera.projection_matrix(),
        Length(0.1, METER),
        Length(20.0, METER),
    )
    with assert_raises(contains="normal attachment"):
        denoise_light(target, view, DenoiseSettings())


def test_the_composer_runs_a_denoise_pass() raises:
    var assets = Assets()
    var scene = Scene()
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(denoise_pass(radius=3))
    var image = composer.render(Renderer(8, 8), scene, assets, a_camera())
    assert_equal(image.width, 8)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
