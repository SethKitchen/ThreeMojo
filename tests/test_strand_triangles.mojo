# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A strand keeps out the triangles that have no area on the image.

A one-pixel strand has a zero inner feather radius, so its middle strip
and two of the three triangles in each cap step collapse onto the center
line. Neither rasterizer draws a triangle of zero area, so the renderer
does not emit them (#298).
"""

from cameras.orthographic_camera import OrthographicCamera, centered
from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from materials.material import LineWidth, OPAQUE, line_material
from math.vector3 import Vector3
from objects.line_segments2 import (
    LineSegments2,
    STRAND_LINE_COVERAGE,
    cap_steps,
    line_segments_geometry,
)
from render.framebuffer import Color
from renderers.renderer import Frame, Renderer
from std.testing import TestSuite, assert_equal, assert_true
from units.si import Length, METER

comptime SIZE = 64


def _camera() raises -> OrthographicCamera:
    var camera = centered(
        Length(2, METER), 1, Length(0.1, METER), Length(10, METER)
    )
    camera.place(Vector3(0, 0, 4), Vector3(0, 0, 0))
    return camera^


def _scene(
    pixels: Float32,
    start: Vector3,
    units: Float32 = 0,
    factor: Float32 = 0,
) raises -> Tuple[Scene, Assets]:
    var scene = Scene()
    var assets = Assets()
    var node = scene.add(Object3D())
    var geometry = assets.geometries.add(
        line_segments_geometry([start, Vector3(0.5, 0.2, 0)])
    )
    var style = line_material(
        Color(220, 140, 60),
        LineWidth(pixels=pixels),
        opacity=0.65,
        blending=OPAQUE,
    )
    if units != 0 or factor != 0:
        style.polygon_offset = True
        style.polygon_offset_units = units
        style.polygon_offset_factor = factor
    var material = assets.materials.add(style^)
    scene.add_wide_line(
        LineSegments2(geometry, material, node, coverage=STRAND_LINE_COVERAGE)
    )
    scene.update()
    return (scene^, assets^)


def _frame(parts: Tuple[Scene, Assets]) raises -> Frame:
    var renderer = Renderer(SIZE, SIZE, workers=1)
    return renderer.prepare_frame(parts[0], parts[1], _camera())


def _no_two_corners_meet(frame: Frame) raises:
    for triangle in range(len(frame.corners) // 3):
        for side in range(3):
            ref a = frame.corners[triangle * 3 + side]
            ref b = frame.corners[triangle * 3 + (side + 1) % 3]
            assert_true(a.x != b.x or a.y != b.y)


def test_a_one_pixel_strand_drops_its_zero_area_triangles() raises:
    var frame = _frame(_scene(1, Vector3(-0.5, 0.1, 0)))
    # Four of the six ribbon triangles, and one of the three in each step
    # of both caps.
    var steps = cap_steps(Float32(1))
    assert_equal(len(frame.corners), 3 * (4 + 2 * steps))
    _no_two_corners_meet(frame)


def test_a_wider_strand_keeps_every_triangle() raises:
    # A three-pixel strand has an inner radius, so no triangle collapses.
    var frame = _frame(_scene(3, Vector3(-0.5, 0.1, 0)))
    var steps = cap_steps(Float32(2))
    assert_equal(len(frame.corners), 3 * (6 + 2 * 3 * steps))
    _no_two_corners_meet(frame)


def test_an_offset_strand_moves_its_depths_only() raises:
    var plain = _frame(_scene(1, Vector3(-0.5, 0.1, 0)))
    var pushed = _frame(_scene(1, Vector3(-0.5, 0.1, 0), units=4))
    assert_equal(len(plain.corners), len(pushed.corners))
    for i in range(len(plain.corners)):
        assert_equal(plain.corners[i].x, pushed.corners[i].x)
        assert_equal(plain.corners[i].y, pushed.corners[i].y)
        assert_true(pushed.corners[i].z > plain.corners[i].z)


def test_a_sloped_offset_strand_keeps_its_places() raises:
    # A factor alone scales the depth slope, which is zero for a strand
    # square to an orthographic view. The strand takes the offset path
    # and keeps the same corners.
    var plain = _frame(_scene(1, Vector3(-0.5, 0.1, 0)))
    var sloped = _frame(_scene(1, Vector3(-0.5, 0.1, 0), factor=2))
    assert_equal(len(plain.corners), len(sloped.corners))
    for i in range(len(plain.corners)):
        assert_equal(plain.corners[i].x, sloped.corners[i].x)
        assert_equal(plain.corners[i].y, sloped.corners[i].y)
        assert_true(sloped.corners[i].z >= plain.corners[i].z)


def test_a_strand_cut_by_the_image_edge_is_still_drawn() raises:
    # The start is past the left edge, so its cap goes through the clipper.
    var parts = _scene(1, Vector3(-1.5, 0.1, 0))
    var frame = _frame(parts)
    assert_true(len(frame.corners) > 0)
    for i in range(len(frame.corners)):
        assert_true(frame.corners[i].x >= -0.001)
    var renderer = Renderer(SIZE, SIZE, workers=1)
    renderer.set_background(Color(0, 0, 0))
    var image = renderer.render(parts[0], parts[1], _camera())
    var drawn = 0
    for x in range(SIZE):
        for y in range(SIZE):
            drawn += Int(image.get_pixel(x, y).r > 0)
    assert_true(drawn > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
