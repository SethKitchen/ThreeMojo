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
from renderers.renderer import Renderer, WIDE_RUN_SEGMENTS
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Length, METER

comptime SIZE = 48
# Enough segments for three runs of `WIDE_RUN_SEGMENTS`.
comptime SEGMENTS = 3 * WIDE_RUN_SEGMENTS + 17


def _camera() raises -> OrthographicCamera:
    var camera = centered(
        Length(2, METER), 1, Length(0.1, METER), Length(10, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def _points(long_last: Bool = False) -> List[Vector3]:
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
    return points^


def _scene(
    coverage: LineCoverage, dash: Float32, long_last: Bool = False
) raises -> Tuple[Scene, Assets]:
    var scene = Scene()
    var assets = Assets()
    var node = scene.add(Object3D())
    var geometry = assets.geometries.add(
        line_segments_geometry(_points(long_last))
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


def _corners(
    scene: Scene, assets: Assets, workers: Int
) raises -> List[RasterVertex]:
    var renderer = Renderer(SIZE, SIZE, workers=workers)
    return renderer.prepare_frame(scene, assets, _camera()).whole_corners()


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


def test_many_workers_draw_what_one_draws() raises:
    # Solid, dashed and strand coverage, each with three runs and a tail.
    var cases: List[Tuple[LineCoverage, Float32]] = [
        (SOLID_LINE_COVERAGE, Float32(0)),
        (SOLID_LINE_COVERAGE, Float32(0.02)),
        (STRAND_LINE_COVERAGE, Float32(0)),
    ]
    for choice in cases:
        var parts = _scene(choice[0], choice[1])
        var serial = _corners(parts[0], parts[1], 1)
        assert_true(len(serial) > 0)
        _same_corners(serial, _corners(parts[0], parts[1], 8))
        var one = _render(parts[0], parts[1], 1)
        var many = _render(parts[0], parts[1], 8)
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
    for workers in [1, 8]:
        with assert_raises(contains="dash pattern is too fine"):
            _ = _render(parts[0], parts[1], workers)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
