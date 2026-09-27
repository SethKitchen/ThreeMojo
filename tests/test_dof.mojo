# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for three.js's `DepthOfFieldNode`: its kernels, its settings, and
a frame whose focused half stays sharp while its far half blurs."""

from cameras.perspective_camera import PerspectiveCamera
from core.assets import Assets
from core.scene import Scene
from math.vector3 import Vector3
from postprocessing.composer import DOF, EffectComposer, dof_pass, render_pass
from postprocessing.display_nodes import (
    DisplaySettings,
    check_display,
    dof_kernel,
    dof_light,
)
from postprocessing.screen_space import DepthView
from render.framebuffer import Color, FloatColor
from render.target import FLOAT_TARGET, RenderTarget
from renderers.renderer import Renderer
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


comptime SIZE = 32


def test_the_kernels_are_three_js_s() raises:
    var wide = dof_kernel(False)
    var narrow = dof_kernel(True)
    assert_equal(len(wide), 64)
    assert_equal(len(narrow), 16)
    assert_equal(narrow[0].x, 0)
    assert_equal(narrow[0].y, 0)
    for i in range(64):
        assert_true(wide[i].length() < 1)
    # The second point of the spiral is the wide kernel's first.
    assert_almost_equal(wide[0].length(), Float32(1 / 80.0) ** 0.5, atol=1e-6)


def test_the_settings_are_checked() raises:
    var bad = DisplaySettings()
    bad.focal_length = Length(0, METER)
    with assert_raises(contains="focal length"):
        check_display(bad)
    bad = DisplaySettings()
    bad.bokeh_scale = Float32.MAX * 2
    with assert_raises(contains="finite"):
        check_display(bad)
    bad = DisplaySettings()
    bad.focus_distance = Length(Float32.MAX * 2, METER)
    with assert_raises(contains="finite"):
        check_display(bad)
    bad = DisplaySettings()
    bad.focal_length = Length(Float32.MAX * 2, METER)
    with assert_raises(contains="finite"):
        check_display(bad)
    with assert_raises(contains="focal length"):
        _ = dof_pass(focal_length=Length(-1, METER))
    assert_true(dof_pass().kind == DOF)


def a_camera() raises -> PerspectiveCamera:
    """Return a camera at the origin."""
    var camera = PerspectiveCamera(
        Angle(50.0, DEGREE), 1, Length(0.1, METER), Length(50.0, METER)
    )
    camera.place(Vector3(0, 0, 0), Vector3(0, 0, -1))
    return camera^


def test_the_focus_stays_sharp_and_the_far_field_blurs() raises:
    # A checker of dark and bright pixels. The left half is two meters
    # away, in focus; the right half is twenty.
    var camera = a_camera()
    var projection = camera.projection_matrix()
    var near_z = projection.transform_point(Vector3(0, 0, -2)).z
    var far_z = projection.transform_point(Vector3(0, 0, -20)).z
    var frame = RenderTarget(SIZE, SIZE, Color(0, 0, 0), FLOAT_TARGET)
    var depth = List[Float32]()
    for y in range(SIZE):
        for x in range(SIZE):
            var gray = Float32(0.9) if (x // 2 + y // 2) % 2 == 0 else Float32(
                0.1
            )
            frame.colors[y * SIZE + x] = FloatColor(gray, gray, gray, 1)
            depth.append(near_z if x < SIZE // 2 else far_z)
    var before = frame.colors.copy()
    var view = DepthView(
        depth,
        SIZE,
        SIZE,
        projection,
        Length(0.1, METER),
        Length(50.0, METER),
    )
    var settings = DisplaySettings()
    settings.focus_distance = Length(2, METER)
    settings.focal_length = Length(1, METER)
    settings.bokeh_scale = 4
    dof_light(frame, view, settings)
    # In focus, away from the edge: unchanged.
    assert_almost_equal(frame.colors[8 * SIZE + 4].r, before[8 * SIZE + 4].r)
    # Far and whole: the dark cells take the bright light spread over them.
    var dark = 0
    for y in range(SIZE):
        for x in range(SIZE // 2 + 4, SIZE):
            if frame.colors[y * SIZE + x].r < 0.3:
                dark += 1
    assert_equal(dark, 0)


def test_the_composer_runs_a_dof_pass() raises:
    var composer = EffectComposer()
    composer.add_pass(render_pass())
    composer.add_pass(dof_pass(Length(3, METER), Length(2, METER), 2))
    var image = composer.render(Renderer(9, 7), Scene(), Assets(), a_camera())
    assert_equal(image.width, 9)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
