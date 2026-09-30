# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the signed distance to a triangle mesh."""

from extensions.humanoid.skeleton.mesh_field import (
    MeshField,
    closest_on_triangle,
)
from math.vector3 import Vector3
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def _near(a: Vector3, b: Vector3) -> Bool:
    """Return True if `a` and `b` are within a micrometer."""
    return (a - b).length() < 1e-6


def _box(cells: Int) -> Tuple[List[Vector3], List[Int]]:
    """Return a unit cube centered on the origin, each face split into
    `cells` by `cells` squares, wound outward, and one stray vertex no
    triangle uses."""
    var points = List[Vector3]()
    var triangles = List[Int]()
    var axes: List[Vector3] = [
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 1),
    ]
    for a in range(3):  # pragma: no branch
        var n = axes[a]
        var u = axes[(a + 1) % 3]
        var v = axes[(a + 2) % 3]
        for s in range(2):  # pragma: no branch
            var sign = Float32(1) - Float32(2 * s)
            var base = len(points)
            for j in range(cells + 1):  # pragma: no branch
                for i in range(cells + 1):  # pragma: no branch
                    var x = Float32(i) / Float32(cells) - 0.5
                    var y = Float32(j) / Float32(cells) - 0.5
                    points.append(n * (0.5 * sign) + u * x + v * y)
            for j in range(cells):  # pragma: no branch
                for i in range(cells):  # pragma: no branch
                    var c = base + j * (cells + 1) + i
                    var d = c + cells + 1
                    if sign > 0:
                        triangles.append(c)
                        triangles.append(c + 1)
                        triangles.append(d + 1)
                        triangles.append(c)
                        triangles.append(d + 1)
                        triangles.append(d)
                    else:
                        triangles.append(c)
                        triangles.append(d + 1)
                        triangles.append(c + 1)
                        triangles.append(c)
                        triangles.append(d)
                        triangles.append(d + 1)
    points.append(Vector3(5, 5, 5))
    return (points^, triangles^)


def test_the_nearest_point_of_a_triangle() raises:
    var a = Vector3(0, 0, 0)
    var b = Vector3(1, 0, 0)
    var c = Vector3(0, 1, 0)
    # The three corners' regions.
    assert_true(_near(closest_on_triangle(Vector3(-1, -1, 0), a, b, c)[0], a))
    assert_true(_near(closest_on_triangle(Vector3(2, -0.5, 0), a, b, c)[0], b))
    assert_true(_near(closest_on_triangle(Vector3(-0.5, 2, 0), a, b, c)[0], c))
    # The three edges' regions.
    var ab = closest_on_triangle(Vector3(0.5, -1, 0), a, b, c)
    assert_true(_near(ab[0], Vector3(0.5, 0, 0)))
    assert_true(abs(ab[1] - 0.5) < 1e-6)
    var ac = closest_on_triangle(Vector3(-1, 0.5, 0), a, b, c)
    assert_true(_near(ac[0], Vector3(0, 0.5, 0)))
    assert_true(abs(ac[2] - 0.5) < 1e-6)
    var bc = closest_on_triangle(Vector3(1, 1, 0), a, b, c)
    assert_true(_near(bc[0], Vector3(0.5, 0.5, 0)))
    # Round the whole plane, the point found is on the triangle and no
    # farther than any corner or edge's middle.
    var probes: List[Vector3] = [
        a,
        b,
        c,
        Vector3(0.5, 0, 0),
        Vector3(0, 0.5, 0),
        Vector3(0.5, 0.5, 0),
    ]
    for j in range(-12, 13):  # pragma: no branch
        for i in range(-12, 13):  # pragma: no branch
            var p = Vector3(Float32(i) * 0.2 + 0.3, Float32(j) * 0.2 + 0.3, 0.1)
            var hit = closest_on_triangle(p, a, b, c)
            var q = hit[0]
            assert_true(q.x >= -1e-6 and q.y >= -1e-6 and q.x + q.y <= 1 + 1e-5)
            for probe in probes:  # pragma: no branch
                assert_true((q - p).length() <= (probe - p).length() + 1e-5)
    # Triangles blunt at each corner in turn: the edges' regions reach
    # round behind the blunt corner.
    var blunt: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(-0.6, 0.4, 0),
        Vector3(1.6, 0.4, 0),
        Vector3(0.5, -0.1, 0),
        Vector3(0.5, 1, 0),
    ]
    for k in range(3):  # pragma: no branch
        var ta = blunt[0]
        var tb = blunt[1]
        var tc = blunt[2]
        if k == 1:
            tc = blunt[3]
        elif k == 2:
            ta = blunt[4]
            tb = blunt[5]
            tc = Vector3(0.3, 0.45, 0)
        for j in range(-10, 11):  # pragma: no branch
            for i in range(-10, 11):  # pragma: no branch
                var p = Vector3(Float32(i) * 0.2, Float32(j) * 0.2, 0.2)
                var q = closest_on_triangle(p, ta, tb, tc)[0]
                var corners: List[Vector3] = [ta, tb, tc]
                for probe in corners:  # pragma: no branch
                    assert_true((q - p).length() <= (probe - p).length() + 1e-5)
    # The face.
    var face = closest_on_triangle(Vector3(0.2, 0.3, 4), a, b, c)
    assert_true(_near(face[0], Vector3(0.2, 0.3, 0)))
    assert_true(abs(face[1] - 0.2) < 1e-6 and abs(face[2] - 0.3) < 1e-6)


def test_a_mesh_field_is_signed() raises:
    var box = _box(6)
    var field = MeshField(box[0].copy(), box[1].copy())
    assert_equal(field.count(), len(box[0]))
    assert_true(_near(field.point(0), box[0][0]))
    assert_true(abs(field.box_high.x - 0.5) < 1e-6)
    # Inside, outside, and past an edge and a corner.
    assert_true(abs(field.distance(Vector3(0, 0, 0)) + 0.5) < 1e-5)
    assert_true(abs(field.distance(Vector3(0.1, 0.2, 0.3)) + 0.2) < 1e-5)
    assert_true(abs(field.distance(Vector3(0, 0, 2)) - 1.5) < 1e-5)
    assert_true(abs(field.distance(Vector3(1.5, 0, 1.5)) - 1.4142) < 1e-3)
    assert_true(abs(field.distance(Vector3(-1, -1, -1)) - 0.866) < 1e-3)
    var hit = field.nearest(Vector3(0.1, 0.9, 0.1))
    assert_true(_near(hit[1], Vector3(0.1, 0.5, 0.1)))
    # A single triangle, and a flat one: no box to split.
    var flat: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
    ]
    var one: List[Int] = [0, 1, 2]
    var single = MeshField(flat^, one^)
    assert_true(abs(single.distance(Vector3(0.2, 0.2, 1)) - 1) < 1e-6)
    assert_true(abs(single.distance(Vector3(0.2, 0.2, -1)) + 1) < 1e-6)


def test_a_mesh_field_refuses_a_bad_mesh() raises:
    var points: List[Vector3] = [Vector3(0, 0, 0), Vector3(1, 0, 0)]
    with assert_raises(contains="whole triangles"):
        _ = MeshField(points.copy(), List[Int]())
    var two: List[Int] = [0, 1]
    with assert_raises(contains="whole triangles"):
        _ = MeshField(points.copy(), two^)
    var far: List[Int] = [0, 1, 2]
    with assert_raises(contains="names no vertex"):
        _ = MeshField(points.copy(), far^)
    var negative: List[Int] = [0, 1, -1]
    with assert_raises(contains="names no vertex"):
        _ = MeshField(points.copy(), negative^)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
