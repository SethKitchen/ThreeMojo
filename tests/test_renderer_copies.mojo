# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Renderer copies retain draw selection, lighting and clear state, #397."""

from core.assets import Assets
from core.scene import Scene
from lights.light_probe_grid import LightProbeGrid
from render.framebuffer import Color
from render.rect import Rect
from render.target import FLOAT_TARGET, RenderTarget
from renderers.draw_filter import NO_OIT_DRAWS, ONE_OIT_DRAW
from renderers.renderer import Renderer
from std.testing import TestSuite, assert_equal, assert_true
from tests.test_light_probe_grid import a_lit_floor, top_camera, uniform_sh
from tests.test_oit import a_camera, a_scene
from units.si import Length, METER


def test_scaled_copies_keep_draw_selection_and_own_their_lists() raises:
    var renderer = Renderer(8, 6)
    renderer.draw_filter = ONE_OIT_DRAW
    renderer.oit_draw = 2
    renderer.snap_vertices = True
    renderer.uv_space_meshes = [1, 3]
    renderer.antialias = True
    renderer.viewport = Rect(1, 1, 4, 3)
    renderer.scissor = Rect(2, 1, 3, 2)
    renderer.scissor_test = True
    var big = renderer.scaled(2)
    assert_equal(big.draw_filter, ONE_OIT_DRAW)
    assert_equal(big.oit_draw, 2)
    assert_equal(big.snap_vertices, True)
    assert_equal(big.uv_space_meshes[1], 3)
    assert_equal(big.viewport, Rect(2, 2, 8, 6))
    assert_equal(big.scissor, Rect(4, 2, 6, 4))
    assert_equal(big.scissor_test, True)
    assert_equal(big.render_scale, 2)
    assert_equal(big.antialias, False)
    big.uv_space_meshes[0] = 9
    assert_equal(renderer.uv_space_meshes[0], 1)


def test_resized_copies_keep_resources_flags_and_whole_target_bounds() raises:
    var renderer = Renderer(8, 6)
    renderer.draw_filter = ONE_OIT_DRAW
    renderer.oit_draw = 2
    renderer.snap_vertices = True
    renderer.uv_space_meshes = [1]
    renderer.auto_clear = False
    renderer.auto_clear_color = False
    renderer.auto_clear_depth = False
    renderer.auto_clear_stencil = False
    renderer.info_auto_reset = False
    renderer.antialias = True
    renderer.scissor_test = True
    renderer.viewport = Rect(1, 1, 2, 2)
    var grid = LightProbeGrid(
        Length(1, METER), Length(1, METER), Length(1, METER)
    )
    grid.probes[0] = uniform_sh(1, 0, 0)
    renderer.set_light_probe_grid(grid^)
    var small = renderer.resized(4, 3)
    assert_equal(small.draw_filter, ONE_OIT_DRAW)
    assert_equal(small.oit_draw, 2)
    assert_equal(small.snap_vertices, True)
    assert_equal(small.uv_space_meshes[0], 1)
    assert_equal(small.auto_clear, False)
    assert_equal(small.auto_clear_color, False)
    assert_equal(small.auto_clear_depth, False)
    assert_equal(small.auto_clear_stencil, False)
    assert_equal(small.info_auto_reset, False)
    assert_equal(small.antialias, True)
    assert_equal(small.viewport, Rect.whole(4, 3))
    assert_equal(small.scissor, Rect.whole(4, 3))
    assert_equal(small.scissor_test, False)
    assert_equal(small.probe_grid.count(), 8)
    assert_equal(small.probe_grid.probes[0].lanes[0], Float32(1))
    small.probe_grid.probes[0].lanes[0] = 2
    assert_equal(renderer.probe_grid.probes[0].lanes[0], Float32(1))


def test_multisampling_keeps_only_the_selected_oit_draw() raises:
    var assets = Assets()
    var scene = a_scene(assets)
    var renderer = Renderer(16, 16)
    renderer.draw_filter = ONE_OIT_DRAW
    # Select one pane from the stable depth order; the result has one color.
    renderer.oit_draw = 2
    var plain = RenderTarget(16, 16, Color(0, 0, 0, 0), FLOAT_TARGET)
    renderer.render_into(plain, scene, assets, a_camera())
    var sampled = RenderTarget(
        16, 16, Color(0, 0, 0, 0), FLOAT_TARGET, samples=4
    )
    renderer.render_into(sampled, scene, assets, a_camera())
    var plain_channels = [Float32(0), Float32(0), Float32(0)]
    var sample_channels = [Float32(0), Float32(0), Float32(0)]
    for at in range(16 * 16):
        plain_channels[0] += plain.colors[at].r
        plain_channels[1] += plain.colors[at].g
        plain_channels[2] += plain.colors[at].b
        sample_channels[0] += sampled.colors[at].r
        sample_channels[1] += sampled.colors[at].g
        sample_channels[2] += sampled.colors[at].b
    var lit = 0
    for channel in range(3):
        if plain_channels[channel] == 0:
            assert_equal(sample_channels[channel], Float32(0))
        else:
            lit += 1
            assert_true(sample_channels[channel] > 0)
    assert_equal(lit, 1)


def test_resized_lighting_matches_a_same_size_renderer_with_the_grid() raises:
    var assets = Assets()
    var scene = a_lit_floor(assets)
    var renderer = Renderer(32, 32)
    var grid = LightProbeGrid(
        Length(4, METER), Length(2, METER), Length(4, METER), 2, 1, 1
    )
    grid.probes[0] = uniform_sh(1, 0, 0)
    grid.probes[1] = uniform_sh(1, 0, 0)
    renderer.set_light_probe_grid(grid^)
    var resized = renderer.resized(16, 16)
    var direct = Renderer(16, 16)
    direct.set_light_probe_grid(renderer.probe_grid.copy())
    var copied = resized.render(scene, assets, top_camera())
    var expected = direct.render(scene, assets, top_camera())
    assert_true(copied.get_pixel(8, 8).r > 40)
    for y in range(16):
        for x in range(16):
            var got = copied.get_pixel(x, y)
            var want = expected.get_pixel(x, y)
            assert_equal(got.r, want.r)
            assert_equal(got.g, want.g)
            assert_equal(got.b, want.b)
            assert_equal(got.a, want.a)


def test_resized_draws_keep_a_target_when_auto_clear_is_off() raises:
    var renderer = Renderer(8, 8)
    renderer.auto_clear = False
    var small = renderer.resized(4, 4)
    var target = RenderTarget(4, 4, Color(255, 0, 0), FLOAT_TARGET)
    small.render_into(target, Scene(), Assets(), a_camera())
    assert_equal(target.color_at(0, 0).r, Float32(1))
    assert_equal(target.color_at(0, 0).b, Float32(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
