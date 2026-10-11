# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Wide lines build the same triangles on one worker and on many."""

from cameras.orthographic_camera import OrthographicCamera, centered
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from materials.material import LineWidth, OPAQUE, line_material
from math.vector3 import Vector3
from objects.line_segments2 import (
    LineCoverage,
    LineSegments2,
    SOLID_LINE_COVERAGE,
    STRAND_LINE_COVERAGE,
    line_segments_geometry,
)
from render.framebuffer import Color, Framebuffer
from render.rasterizer import RasterVertex
from renderers.renderer import Frame, Renderer, WIDE_RUN_SEGMENTS
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Length, METER

comptime SIZE = 48
# Enough segments for three runs of `WIDE_RUN_SEGMENTS`.
comptime SEGMENTS = 3 * WIDE_RUN_SEGMENTS + 17
comptime WORKERS = 8
# The renderer cuts a line into `min(workers, segments // WIDE_RUN_SEGMENTS)`
# runs, and run `i` holds segments `i * segments // runs` up to the next.
comptime RUNS = min(WORKERS, SEGMENTS // WIDE_RUN_SEGMENTS)
comptime FIRST_RUN = SEGMENTS // RUNS


def _camera() raises -> OrthographicCamera:
    var camera = centered(
        Length(2, METER), 1, Length(0.1, METER), Length(10, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def _points(
    long_last: Bool = False, hidden_first: Bool = False
) -> List[Vector3]:
    # Short zig-zag segments over the view, some off its edges.
    var points = List[Vector3]()
    for s in range(SEGMENTS):
        var x = Float32(s % 97) / 40.0 - 1.2
        var y = Float32((s * 37) % 89) / 40.0 - 1.1
        points.append(Vector3(x, y, Float32(s % 5) * 0.1))
        points.append(Vector3(x + 0.05, y - 0.03, Float32(s % 3) * 0.1))
    if long_last:
        # The last run ends with one long segment.
        points[2 * SEGMENTS - 1] = Vector3(100.0, 100.0, 0)
    if hidden_first:
        # Every segment of the first run is behind the camera, so that run
        # holds no surface and a later run makes the line's surface.
        for s in range(2 * FIRST_RUN):
            points[s] = Vector3(points[s].x, points[s].y, 10.0)
    return points^


def _scene(
    coverage: LineCoverage,
    dash: Float32,
    long_last: Bool = False,
    hidden_first: Bool = False,
) raises -> Tuple[Scene, Assets]:
    var scene = Scene()
    var assets = Assets()
    var node = scene.add(Object3D())
    # A short dashed line of its own material comes first, so the long
    # line's surfaces do not start at zero and each run's are renumbered.
    var lead = assets.geometries.add(
        line_segments_geometry([Vector3(-0.9, 0.8, 0), Vector3(0.9, 0.7, 0.2)])
    )
    var lead_style = line_material(
        Color(40, 200, 120),
        LineWidth(pixels=5),
        dash_size=Length(0.07, METER),
        gap_size=Length(0.05, METER),
        blending=OPAQUE,
    )
    # A surface field the long line does not share.
    lead_style.alpha_test = 0.25
    var lead_material = assets.materials.add(lead_style^)
    scene.add_wide_line(LineSegments2(lead, lead_material, node))
    var geometry = assets.geometries.add(
        line_segments_geometry(_points(long_last, hidden_first))
    )
    var opacity = Float32(0.65) if coverage == STRAND_LINE_COVERAGE else 1.0
    var material = assets.materials.add(
        line_material(
            Color(220, 140, 60),
            LineWidth(pixels=3),
            dash_size=Length(dash, METER),
            gap_size=Length(dash, METER),
            opacity=opacity,
            blending=OPAQUE,
        )
    )
    scene.add_wide_line(
        LineSegments2(geometry, material, node, coverage=coverage)
    )
    scene.update()
    return (scene^, assets^)


def _render(scene: Scene, assets: Assets, workers: Int) raises -> Framebuffer:
    var renderer = Renderer(SIZE, SIZE, workers=workers)
    renderer.set_background(Color(0, 0, 0))
    return renderer.render(scene, assets, _camera())


def _frame(scene: Scene, assets: Assets, workers: Int) raises -> Frame:
    var renderer = Renderer(SIZE, SIZE, workers=workers)
    return renderer.prepare_frame(scene, assets, _camera())


def _same_surfaces(one: Frame, many: Frame) raises:
    # The slim lists themselves: each corner names the same surface, and
    # each surface holds the same draw state.
    assert_equal(len(one.corners), len(many.corners))
    for i in range(len(one.corners)):
        assert_equal(one.corners[i].surface, many.corners[i].surface)
    assert_equal(len(one.surfaces), len(many.surfaces))
    var tests = List[Float32]()
    for i in range(len(one.surfaces)):
        ref a = one.surfaces[i]
        ref b = many.surfaces[i]
        assert_true(a.blend == b.blend)
        assert_true(a.kind == b.kind)
        assert_true(a.texture == b.texture)
        assert_equal(a.alpha_test, b.alpha_test)
        assert_equal(a.dash_size, b.dash_size)
        assert_equal(a.gap_size, b.gap_size)
        assert_equal(a.fog, b.fog)
        assert_equal(a.flip_sided, b.flip_sided)
        assert_equal(a.receives_shadow, b.receives_shadow)
        if a.alpha_test not in tests:
            tests.append(a.alpha_test)
    # The lead line's surface and the long line's are both there.
    assert_equal(len(tests), 2)


def _same_corners(one: List[RasterVertex], many: List[RasterVertex]) raises:
    # Every corner, in order: place, depth, color, texture coordinates and
    # world point.
    assert_equal(len(one), len(many))
    for i in range(len(one)):
        ref a = one[i]
        ref b = many[i]
        assert_equal(a.x, b.x)
        assert_equal(a.y, b.y)
        assert_equal(a.z, b.z)
        assert_equal(a.inv_w, b.inv_w)
        assert_equal(a.color.r, b.color.r)
        assert_equal(a.color.g, b.color.g)
        assert_equal(a.color.b, b.color.b)
        assert_equal(a.color.a, b.color.a)
        assert_equal(a.u, b.u)
        assert_equal(a.v, b.v)
        assert_true(a.world == b.world)
        assert_true(a.normal == b.normal)
        assert_equal(a.emissive.r, b.emissive.r)
        assert_equal(a.emissive.g, b.emissive.g)
        assert_equal(a.emissive.b, b.emissive.b)
        assert_equal(a.view_depth, b.view_depth)
        assert_equal(a.line_distance, b.line_distance)
        # Joined from the surface: the draw state each corner reads.
        assert_true(a.blend == b.blend)
        assert_true(a.kind == b.kind)
        assert_equal(a.dash_size, b.dash_size)
        assert_equal(a.gap_size, b.gap_size)


def test_many_workers_draw_what_one_draws() raises:
    # Solid, dashed and strand coverage, each with three runs and a tail,
    # after a line with a surface of its own.
    # The last case cuts away every segment of the first run.
    var cases: List[Tuple[LineCoverage, Float32, Bool]] = [
        (SOLID_LINE_COVERAGE, Float32(0), False),
        (SOLID_LINE_COVERAGE, Float32(0.02), False),
        (STRAND_LINE_COVERAGE, Float32(0), False),
        (SOLID_LINE_COVERAGE, Float32(0), True),
    ]
    for choice in cases:
        var parts = _scene(choice[0], choice[1], hidden_first=choice[2])
        var serial = _frame(parts[0], parts[1], 1)
        var parallel = _frame(parts[0], parts[1], WORKERS)
        assert_true(len(serial.corners) > 0)
        _same_surfaces(serial, parallel)
        _same_corners(serial.whole_corners(), parallel.whole_corners())
        var one = _render(parts[0], parts[1], 1)
        var many = _render(parts[0], parts[1], WORKERS)
        var drawn = 0
        for y in range(SIZE):
            for x in range(SIZE):
                var a = one.get_pixel(x, y)
                var b = many.get_pixel(x, y)
                assert_equal(a.r, b.r)
                assert_equal(a.g, b.g)
                assert_equal(a.b, b.b)
                assert_equal(one.depth_at(x, y), many.depth_at(x, y))
                if a.r != 0:
                    drawn += 1
        assert_true(drawn > 0)


def test_a_refused_dash_pattern_refuses_on_many_workers() raises:
    # A dash 1 cm long cuts the last segment, about 140 m long, into
    # far more than 4096 dashes. The last run raises; the earlier ones pass.
    var parts = _scene(SOLID_LINE_COVERAGE, 0.01, long_last=True)
    for workers in [1, WORKERS]:
        with assert_raises(contains="dash pattern is too fine"):
            _ = _render(parts[0], parts[1], workers)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
