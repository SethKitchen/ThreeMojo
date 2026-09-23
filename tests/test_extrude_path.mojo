# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.extrude` along a path: three.js's `extrudePath`.

The expected triangles come from three.js 0.180 itself, run under Node on
the same shape and curves, rounded to five places. three.js measures a
Bezier curve's tangent across a short step, and this port takes the exact
derivative, so the frames differ in the fourth place; the tolerance allows
for it.
"""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.extrude import extrude
from math.curve3 import CurvePath3, Curve3, cubic_bezier3, line3
from math.path import Path, Shape
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Length, METER

comptime TOLERANCE = Float32(2e-3)
# Five numbers a corner: a position and a texture coordinate.
comptime CORNER = 5


def polygon(corners: List[Vector2]) raises -> Path:
    """Return the closed path through `corners`, corner after corner."""
    var pen = Path(corners[0])
    for index in range(1, len(corners)):
        pen.line_to(corners[index])
    pen.close_path()
    return pen^


def wedge() raises -> Shape:
    """Return the triangle the three.js reference swept. A triangle fills
    in with one triangle whatever cuts it, so every face can be matched."""
    return Shape(polygon([Vector2(0, 0), Vector2(1, 0), Vector2(0.25, 0.5)]))


def bezier() raises -> Curve3:
    """Return the Bezier curve the three.js reference swept along."""
    return cubic_bezier3(
        Vector3(0, 0, 0), Vector3(1, 0, 1), Vector3(2, 1, 1), Vector3(3, 1, 0)
    )


def two_lines() raises -> CurvePath3:
    """Return the two straight runs the three.js reference swept along."""
    var path = CurvePath3()
    path.add(line3(Vector3(0, 0, 0), Vector3(2, 0, 0)))
    path.add(line3(Vector3(2, 0, 0), Vector3(2, 2, 1)))
    return path^


def triangles(geometry: BufferGeometry) raises -> List[Float32]:
    """Return every triangle as fifteen numbers: each corner's position and
    texture coordinate, in the order the geometry holds them."""
    ref positions = geometry.attribute_view(String(POSITION))
    ref uvs = geometry.attribute_view(String(UV))
    var out = List[Float32]()
    for vertex in range(geometry.vertex_count()):
        for axis in range(3):
            out.append(positions.component(vertex, axis))
        for axis in range(2):
            out.append(uvs.component(vertex, axis))
    return out^


def same_triangle(
    ours: List[Float32], mine: Int, theirs: List[Float32], other: Int
) -> Bool:
    """Return True when triangle `mine` of `ours` is triangle `other` of
    `theirs`, starting at any corner but running the same way round."""
    for turn in range(3):
        var all_close = True
        for corner in range(3):
            var at = mine * 15 + ((corner + turn) % 3) * CORNER
            var there = other * 15 + corner * CORNER
            for number in range(CORNER):
                if abs(ours[at + number] - theirs[there + number]) > TOLERANCE:
                    all_close = False
        if all_close:
            return True
    return False


def assert_same_faces(geometry: BufferGeometry, theirs: List[Float32]) raises:
    """Assert the geometry holds three.js's triangles and no others, each
    wound the same way, in whatever order."""
    var ours = triangles(geometry)
    assert_equal(len(ours), len(theirs))
    var count = len(theirs) // 15
    var used = List[Bool](length=count, fill=False)
    for other in range(count):
        var found = False
        for mine in range(count):
            if not used[mine] and same_triangle(ours, mine, theirs, other):
                used[mine] = True
                found = True
                break
        assert_true(found, String("three.js triangle ", other, " is missing"))


def closed_volume(geometry: BufferGeometry) raises -> Float32:
    """Return the volume a closed, outward-wound surface encloses, from the
    divergence theorem."""
    var total = Float32(0)
    for triangle in range(geometry.triangle_count()):
        var first = geometry.corner(triangle, 0)
        var second = geometry.corner(triangle, 1)
        var third = geometry.corner(triangle, 2)
        var crossed = second
        crossed.cross(third)
        total += first.dot(crossed)
    return total / 6


def three_bezier_sweep() -> List[Float32]:
    """Return three.js's triangles for the cubic Bezier sweep, fifteen numbers
    each: three corners of a position and a texture coordinate."""
    return [
        0,
        0,
        0,
        0,
        0,
        0.35355,
        -0.25,
        -0.35356,
        0.35355,
        -0.25,
        0.00005,
        -1,
        0.00005,
        0.00005,
        -1,
        3.26881,
        0.07506,
        0.26875,
        3.26881,
        0.07506,
        2.74021,
        0.57871,
        -0.25985,
        2.74021,
        0.57871,
        3,
        1,
        0,
        3,
        1,
        0,
        0,
        0,
        0,
        1,
        0.00005,
        -1,
        0.00005,
        -1,
        0.99995,
        1.5,
        0.5,
        0.75,
        0.5,
        0.25,
        0.00005,
        -1,
        0.00005,
        -1,
        0.99995,
        1.93874,
        -0.37748,
        0.94373,
        -0.37748,
        0.05627,
        1.5,
        0.5,
        0.75,
        0.5,
        0.25,
        1.5,
        0.5,
        0.75,
        0.5,
        0.25,
        1.93874,
        -0.37748,
        0.94373,
        -0.37748,
        0.05627,
        3,
        1,
        0,
        1,
        1,
        1.93874,
        -0.37748,
        0.94373,
        -0.37748,
        0.05627,
        3.26881,
        0.07506,
        0.26875,
        0.07506,
        0.73125,
        3,
        1,
        0,
        1,
        1,
        0.00005,
        -1,
        0.00005,
        -1,
        0.99995,
        0.35355,
        -0.25,
        -0.35356,
        -0.25,
        1.35356,
        1.93874,
        -0.37748,
        0.94373,
        -0.37748,
        0.05627,
        0.35355,
        -0.25,
        -0.35356,
        -0.25,
        1.35356,
        1.653,
        0.19399,
        0.3079,
        0.19399,
        0.6921,
        1.93874,
        -0.37748,
        0.94373,
        -0.37748,
        0.05627,
        1.93874,
        -0.37748,
        0.94373,
        -0.37748,
        0.05627,
        1.653,
        0.19399,
        0.3079,
        0.19399,
        0.6921,
        3.26881,
        0.07506,
        0.26875,
        0.07506,
        0.73125,
        1.653,
        0.19399,
        0.3079,
        0.19399,
        0.6921,
        2.74021,
        0.57871,
        -0.25985,
        0.57871,
        1.25985,
        3.26881,
        0.07506,
        0.26875,
        0.07506,
        0.73125,
        0.35355,
        -0.25,
        -0.35356,
        0.35355,
        1.35356,
        0,
        0,
        0,
        0,
        1,
        1.653,
        0.19399,
        0.3079,
        1.653,
        0.6921,
        0,
        0,
        0,
        0,
        1,
        1.5,
        0.5,
        0.75,
        1.5,
        0.25,
        1.653,
        0.19399,
        0.3079,
        1.653,
        0.6921,
        1.653,
        0.19399,
        0.3079,
        0.19399,
        0.6921,
        1.5,
        0.5,
        0.75,
        0.5,
        0.25,
        2.74021,
        0.57871,
        -0.25985,
        0.57871,
        1.25985,
        1.5,
        0.5,
        0.75,
        0.5,
        0.25,
        3,
        1,
        0,
        1,
        1,
        2.74021,
        0.57871,
        -0.25985,
        0.57871,
        1.25985,
    ]


def three_path_sweep() -> List[Float32]:
    """Return three.js's triangles for the sweep along two lines, fifteen
    numbers each."""
    return [
        0,
        0,
        0,
        0,
        0,
        0,
        0.5,
        -0.25,
        0,
        0.5,
        0,
        0,
        -1,
        0,
        0,
        2.44721,
        2.4,
        0.2,
        2.44721,
        2.4,
        1.66459,
        2.2,
        0.6,
        1.66459,
        2.2,
        2,
        2,
        1,
        2,
        2,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        -1,
        0,
        2,
        2,
        0.10557,
        0.05279,
        0.10557,
        0.94721,
        0,
        0,
        -1,
        0,
        2,
        2.44721,
        0.50557,
        -0.74721,
        0.50557,
        1.74721,
        2,
        0.10557,
        0.05279,
        0.10557,
        0.94721,
        2,
        0.10557,
        0.05279,
        2,
        0.94721,
        2.44721,
        0.50557,
        -0.74721,
        2.44721,
        1.74721,
        2,
        2,
        1,
        2,
        0,
        2.44721,
        0.50557,
        -0.74721,
        2.44721,
        1.74721,
        2.44721,
        2.4,
        0.2,
        2.44721,
        0.8,
        2,
        2,
        1,
        2,
        0,
        0,
        0,
        -1,
        0,
        2,
        0,
        0.5,
        -0.25,
        0.5,
        1.25,
        2.44721,
        0.50557,
        -0.74721,
        0.50557,
        1.74721,
        0,
        0.5,
        -0.25,
        0.5,
        1.25,
        1.66459,
        0.30557,
        -0.34721,
        0.30557,
        1.34721,
        2.44721,
        0.50557,
        -0.74721,
        0.50557,
        1.74721,
        2.44721,
        0.50557,
        -0.74721,
        2.44721,
        1.74721,
        1.66459,
        0.30557,
        -0.34721,
        1.66459,
        1.34721,
        2.44721,
        2.4,
        0.2,
        2.44721,
        0.8,
        1.66459,
        0.30557,
        -0.34721,
        1.66459,
        1.34721,
        1.66459,
        2.2,
        0.6,
        1.66459,
        0.4,
        2.44721,
        2.4,
        0.2,
        2.44721,
        0.8,
        0,
        0.5,
        -0.25,
        0.5,
        1.25,
        0,
        0,
        0,
        0,
        1,
        1.66459,
        0.30557,
        -0.34721,
        0.30557,
        1.34721,
        0,
        0,
        0,
        0,
        1,
        2,
        0.10557,
        0.05279,
        0.10557,
        0.94721,
        1.66459,
        0.30557,
        -0.34721,
        0.30557,
        1.34721,
        1.66459,
        0.30557,
        -0.34721,
        1.66459,
        1.34721,
        2,
        0.10557,
        0.05279,
        2,
        0.94721,
        1.66459,
        2.2,
        0.6,
        1.66459,
        0.4,
        2,
        0.10557,
        0.05279,
        2,
        0.94721,
        2,
        2,
        1,
        2,
        0,
        1.66459,
        2.2,
        0.6,
        1.66459,
        0.4,
    ]


# --- against three.js -------------------------------------------------------


def test_a_bezier_sweep_matches_three_js() raises:
    var solid = extrude(wedge(), bezier(), steps=2)
    # One triangle a cap, two caps, three walls of two steps of two each.
    assert_equal(solid.triangle_count(), 2 + 3 * 2 * 2)
    assert_same_faces(solid, three_bezier_sweep())


def test_a_sweep_along_a_curve_path_matches_three_js() raises:
    var solid = extrude(wedge(), two_lines(), steps=2)
    assert_same_faces(solid, three_path_sweep())


# --- the solid --------------------------------------------------------------


def test_a_straight_sweep_is_the_prism() raises:
    # Along a straight line the sweep is the plain extrusion turned round,
    # so a plate with a hole encloses its area times the length.
    var plate = Shape(
        polygon([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
    )
    plate.add_hole(
        polygon([Vector2(1, 1), Vector2(3, 1), Vector2(3, 3), Vector2(1, 3)])
    )
    var along = line3(Vector3(0, 0, 0), Vector3(0, 0, 2))
    var solid = extrude(plate, along, steps=3)
    var flat = extrude(plate, Length(2, METER), steps=3)
    assert_equal(solid.triangle_count(), flat.triangle_count())
    assert_almost_equal(closed_volume(solid), Float32(24), atol=1e-3)
    var box = solid.bounding_box()
    assert_almost_equal(box.min.z, Float32(0), atol=1e-4)
    assert_almost_equal(box.max.z, Float32(2), atol=1e-4)


def test_the_front_cap_faces_on_along_the_curve() raises:
    var solid = extrude(wedge(), bezier(), steps=4)
    ref normals = solid.attribute_view(String(NORMAL))
    var curve = bezier()
    var start = curve.tangent(0)
    var end = curve.tangent(1)
    # The back cap is written first and the front cap next, three corners
    # each.
    var back = Vector3(
        normals.component(0, 0),
        normals.component(0, 1),
        normals.component(0, 2),
    )
    var front = Vector3(
        normals.component(3, 0),
        normals.component(3, 1),
        normals.component(3, 2),
    )
    assert_almost_equal(back.dot(start), Float32(-1), atol=1e-3)
    assert_almost_equal(front.dot(end), Float32(1), atol=1e-3)


def test_one_step_is_the_default() raises:
    var solid = extrude(wedge(), bezier())
    assert_equal(solid.triangle_count(), 2 + 3 * 2)


# --- what is refused --------------------------------------------------------


def test_a_sweep_refuses_what_it_cannot_build() raises:
    with assert_raises(contains="at least one step"):
        _ = extrude(wedge(), bezier(), steps=0)
    with assert_raises(contains="at least one step"):
        _ = extrude(wedge(), two_lines(), steps=0)
    with assert_raises():
        _ = extrude(wedge(), bezier(), curve_segments=0)
    with assert_raises():
        _ = extrude(wedge(), CurvePath3())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
