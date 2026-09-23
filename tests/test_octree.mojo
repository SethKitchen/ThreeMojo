# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.capsule` and `math.octree`, three.js's `Capsule` and
`Octree`.

The level is a six by six grid of quads with stepped heights, and a wall.
Both this file and the reference script build it the same way. The
expected values were calculated by three.js 0.180, by node on
`examples/jsm/math/Octree.js`: which triangles each query gathers, in
three.js's order, and each push and hit.
"""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from core.layers import Layers
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from geometries.box import cube
from materials.material import Material
from math.bounds import Box3, Sphere
from math.capsule import Capsule
from math.octree import (
    Octree,
    box_intersects_triangle,
    line_to_line_closest_points,
    triangle_capsule_intersect,
    triangle_sphere_intersect,
)
from math.ray import Ray
from math.triangle import Triangle
from math.vector3 import Vector3
from objects.mesh import Mesh
from render.framebuffer import Color
from std.math import nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER

comptime TOLERANCE = Float64(2e-6)


def assert_vector(v: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a vector's components, within the tolerance."""
    assert_almost_equal(v.x, x, atol=TOLERANCE)
    assert_almost_equal(v.y, y, atol=TOLERANCE)
    assert_almost_equal(v.z, z, atol=TOLERANCE)


def assert_indices(found: List[Int], expected: List[Int]) raises:
    """Assert a list of triangle indices, in order."""
    assert_equal(len(found), len(expected))
    for index in range(len(expected)):
        assert_equal(found[index], expected[index])


def height(i: Int, j: Int) -> Float32:
    """Return the height of the level's grid at a corner."""
    return Float32((i * 7 + j * 3) % 5) * 0.25


def level() -> List[Triangle]:
    """Return the level's triangles, in the reference script's order."""
    var triangles = List[Triangle]()
    for i in range(6):
        for j in range(6):
            var x0 = Float32(i - 3)
            var z0 = Float32(j - 3)
            var a = Vector3(x0, height(i, j), z0)
            var b = Vector3(x0, height(i, j + 1), z0 + 1)
            var c = Vector3(x0 + 1, height(i + 1, j + 1), z0 + 1)
            var d = Vector3(x0 + 1, height(i + 1, j), z0)
            triangles.append(Triangle(a, b, c))
            triangles.append(Triangle(a, c, d))
    triangles.append(
        Triangle(Vector3(2, 0, -2), Vector3(2, 3, -2), Vector3(2, 3, 2))
    )
    triangles.append(
        Triangle(Vector3(2, 0, -2), Vector3(2, 3, 2), Vector3(2, 0, 2))
    )
    return triangles^


def built() -> Octree:
    """Return the octree of the level, with three.js's defaults."""
    var tree = Octree()
    for triangle in level():
        tree.add_triangle(triangle)
    tree.build()
    return tree^


def ray(
    ox: Float32, oy: Float32, oz: Float32, dx: Float32, dy: Float32, dz: Float32
) raises -> Ray:
    """Return a ray."""
    return Ray(Vector3(ox, oy, oz), Vector3(dx, dy, dz))


def ground() -> Triangle:
    """Return the triangle of the single-triangle tests, flat at y = 0 and
    facing up."""
    return Triangle(Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))


# --- Capsule ----------------------------------------------------------------


def test_capsule_default_and_parts() raises:
    """The default is three.js's: a meter up y, a meter in radius."""
    var capsule = Capsule()
    assert_vector(capsule.start, 0, 0, 0)
    assert_vector(capsule.end, 0, 1, 0)
    assert_equal(capsule.radius, 1)
    assert_vector(capsule.center(), 0, 0.5, 0)
    capsule.translate(Vector3(1, 2, 3))
    assert_vector(capsule.start, 1, 2, 3)
    assert_vector(capsule.end, 1, 3, 3)
    assert_vector(capsule.center(), 1, 2.5, 3)


def test_capsule_refuses_a_bad_radius() raises:
    """A negative radius, or one that is not a number, is refused."""
    with assert_raises(contains="radius"):
        _ = Capsule(Vector3(0, 0, 0), Vector3(0, 1, 0), -0.5)
    with assert_raises(contains="radius"):
        _ = Capsule(Vector3(0, 0, 0), Vector3(0, 1, 0), nan[DType.float32]())
    var line = Capsule(Vector3(0, 0, 0), Vector3(0, 1, 0), 0)
    assert_equal(line.radius, 0)


def test_capsule_intersects_box() raises:
    """Each side of each plane can keep a capsule from a box."""
    var box = Box3(Vector3(0, 0, 0), Vector3(1, 1, 1))
    var up = Vector3(0, 1, 0)
    var inside = Capsule(Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.8, 0.5), 0.1)
    assert_true(inside.intersects_box(box))
    var near = Capsule(Vector3(-0.2, 0.5, 0.5), Vector3(-0.2, 0.8, 0.5), 0.3)
    assert_true(near.intersects_box(box))
    # Past each face in turn.
    var offsets: List[Vector3] = [
        Vector3(-2, 0, 0),
        Vector3(2, 0, 0),
        Vector3(0, -2, 0),
        Vector3(0, 2, 0),
        Vector3(0, 0, -2),
        Vector3(0, 0, 2),
    ]
    for offset in offsets:
        var start = Vector3(0.5, 0.2, 0.5) + offset
        var away = Capsule(start, start + up * 0.5, 0.25)
        assert_false(away.intersects_box(box))
    # Crossing a face: one end in, one out.
    var through = Capsule(Vector3(0.5, -1, 0.5), Vector3(0.5, 2, 0.5), 0.1)
    assert_true(through.intersects_box(box))
    var across = Capsule(Vector3(-1, 0.5, 0.5), Vector3(2, 0.5, 0.5), 0.1)
    assert_true(across.intersects_box(box))
    var deep = Capsule(Vector3(0.5, 0.5, -1), Vector3(0.5, 0.5, 2), 0.1)
    assert_true(deep.intersects_box(box))
    var back = Capsule(Vector3(2, 0.5, 0.5), Vector3(-1, 0.5, 0.5), 0.1)
    assert_true(back.intersects_box(box))


# --- Box3.intersectsTriangle ----------------------------------------------


def test_box_intersects_triangle() raises:
    """Each family of axes can separate a triangle from a box."""
    var box = Box3(Vector3(0, 0, 0), Vector3(1, 1, 1))
    assert_true(
        box_intersects_triangle(
            box,
            Triangle(
                Vector3(0.5, 0.5, 0.5),
                Vector3(2, 0.5, 0.5),
                Vector3(0.5, 2, 0.5),
            ),
        )
    )
    # A box axis separates it.
    assert_false(
        box_intersects_triangle(
            box,
            Triangle(Vector3(2, 0, 0), Vector3(3, 0, 0), Vector3(2, 1, 0)),
        )
    )
    # An edge cross product separates it: a triangle across a corner.
    assert_false(
        box_intersects_triangle(
            box,
            Triangle(
                Vector3(1.6, 1.6, -1),
                Vector3(1.6, 1.6, 2),
                Vector3(3, 0.9, 0.5),
            ),
        )
    )
    # Only the normal separates it: a plane past the corner.
    assert_false(
        box_intersects_triangle(
            box,
            Triangle(
                Vector3(1.4, 1.4, 1.4) + Vector3(-3, 1.5, 1.5),
                Vector3(1.4, 1.4, 1.4) + Vector3(1.5, -3, 1.5),
                Vector3(1.4, 1.4, 1.4) + Vector3(1.5, 1.5, -3),
            ),
        )
    )
    assert_false(
        box_intersects_triangle(
            Box3.empty(),
            Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)),
        )
    )


# --- building ---------------------------------------------------------------


def test_build_matches_three() raises:
    """The bounds, the margin and the number of boxes are three.js's."""
    var tree = built()
    assert_equal(tree.node_count(), 118)
    assert_equal(len(tree.triangles), 74)
    assert_vector(tree.bounds.min, -3, 0, -3)
    assert_vector(tree.bounds.max, 3, 3, 3)
    assert_true(Bool(tree.box))
    assert_vector(
        tree.box.value().min, -3.00999999, -0.00999999978, -3.00999999
    )
    assert_vector(tree.box.value().max, 3, 3, 3)


def test_a_shallow_tree_stops_at_its_last_level() raises:
    """A leaf at the last level keeps more than its share.

    The settings hold at every level here. three.js reads them only on the
    root, so the reference is three.js's `Octree.js` with its defaults
    changed to these.
    """
    var tree = Octree()
    tree.triangles_per_leaf = 2
    tree.max_level = 3
    for triangle in level():
        tree.add_triangle(triangle)
    tree.build()
    assert_equal(tree.node_count(), 846)
    assert_indices(
        tree.sphere_triangles(Sphere(Vector3(0.3, 0.3, 0.2), 0.5)),
        [29, 28, 31, 30, 40, 41, 52, 42, 43, 54, 55],
    )
    var hit = tree.ray_intersect(ray(0.3, 5, 0.2, 0, -1, 0))
    assert_true(Bool(hit))
    assert_almost_equal(hit.value().distance, 4.94999981, atol=TOLERANCE)
    assert_equal(hit.value().index, 43)
    var push = tree.sphere_intersect(Sphere(Vector3(0.3, 0.3, 0.2), 0.5))
    assert_true(Bool(push))
    assert_vector(push.value().normal, 0.361426413, 0.861296713, 0.357125878)
    assert_almost_equal(push.value().depth, 0.421781927, atol=TOLERANCE)


def test_an_empty_tree_meets_nothing() raises:
    """A tree with no triangles builds and answers every query with
    nothing."""
    var tree = Octree()
    assert_false(Bool(tree.box))
    tree.build()
    assert_equal(tree.node_count(), 1)
    assert_false(Bool(tree.ray_intersect(ray(0, 5, 0, 0, -1, 0))))
    assert_false(Bool(tree.sphere_intersect(Sphere(Vector3(0, 0, 0), 1))))
    assert_false(Bool(tree.capsule_intersect(Capsule())))


def test_clear() raises:
    """A cleared tree is an empty one."""
    var tree = built()
    tree.clear()
    assert_false(Bool(tree.box))
    assert_true(tree.bounds.is_empty())
    assert_equal(len(tree.triangles), 0)
    assert_equal(tree.node_count(), 1)


# --- queries ----------------------------------------------------------------


def test_ray_triangles_match_three() raises:
    """A ray gathers three.js's triangles, in three.js's order."""
    var tree = built()
    assert_indices(
        tree.ray_triangles(ray(0.3, 5, 0.2, 0, -1, 0)),
        [43, 42, 40, 31, 29, 28, 30, 33, 44, 45, 52, 55, 73, 72],
    )
    assert_indices(
        tree.ray_triangles(ray(-2.5, 1, 0.5, 1, 0, 0)),
        [
            4,
            6,
            7,
            9,
            18,
            20,
            21,
            31,
            30,
            28,
            19,
            17,
            16,
            33,
            42,
            44,
            45,
            52,
            55,
            53,
            64,
            66,
            67,
            69,
            73,
        ],
    )
    assert_indices(
        tree.ray_triangles(ray(-2.7, 4, -2.6, 1, -1, 1)),
        [16, 17, 27, 28, 43, 42, 40, 31, 45, 44, 33, 57, 56, 54, 30, 52, 55],
    )
    assert_equal(len(tree.ray_triangles(ray(0, 10, 0, 0, 1, 0))), 0)


def test_ray_intersect_matches_three() raises:
    """The nearest triangle met from its front."""
    var tree = built()
    var down = tree.ray_intersect(ray(0.3, 5, 0.2, 0, -1, 0))
    assert_true(Bool(down))
    assert_almost_equal(down.value().distance, 4.94999981, atol=TOLERANCE)
    assert_equal(down.value().index, 43)
    assert_vector(down.value().position, 0.3, 0.05, 0.2)
    var level_triangles = level()
    assert_vector(
        down.value().triangle.a,
        level_triangles[43].a.x,
        level_triangles[43].a.y,
        level_triangles[43].a.z,
    )
    var along = tree.ray_intersect(ray(-2.5, 1, 0.5, 1, 0, 0))
    assert_true(Bool(along))
    assert_almost_equal(along.value().distance, 0, atol=TOLERANCE)
    assert_equal(along.value().index, 6)
    assert_vector(along.value().position, -2.5, 1, 0.5)
    var slant = tree.ray_intersect(ray(-2.7, 4, -2.6, 1, -1, 1))
    assert_true(Bool(slant))
    assert_almost_equal(slant.value().distance, 6.79829931, atol=1e-5)
    assert_equal(slant.value().index, 56)
    assert_vector(slant.value().position, 1.22500002, 0.0750000030, 1.32500005)
    assert_false(Bool(tree.ray_intersect(ray(0, 10, 0, 0, 1, 0))))


def test_sphere_triangles_match_three() raises:
    """A sphere gathers three.js's triangles, in three.js's order."""
    var tree = built()
    assert_indices(
        tree.sphere_triangles(Sphere(Vector3(0.3, 0.9, 0.2), 0.5)),
        [
            14,
            15,
            16,
            17,
            26,
            27,
            28,
            29,
            31,
            30,
            41,
            40,
            38,
            39,
            50,
            52,
            53,
            43,
            42,
            55,
            54,
            33,
            44,
            45,
        ],
    )
    assert_indices(
        tree.sphere_triangles(Sphere(Vector3(1.7, 1, 0), 0.5)),
        [
            52,
            41,
            40,
            27,
            38,
            39,
            50,
            53,
            73,
            64,
            62,
            63,
            65,
            72,
            55,
            54,
            43,
            30,
            31,
            33,
            42,
            44,
            45,
            66,
            67,
            69,
        ],
    )
    assert_indices(
        tree.sphere_triangles(Sphere(Vector3(-1.5, 0.2, 1.5), 0.4)),
        [21, 18, 9, 8, 10, 11, 20, 22, 23, 33, 32, 30, 19, 34, 35],
    )
    assert_equal(len(tree.sphere_triangles(Sphere(Vector3(0, 5, 0), 0.5))), 0)


def test_sphere_intersect_matches_three() raises:
    """The push out of the level, as three.js gives it."""
    var tree = built()
    assert_false(
        Bool(tree.sphere_intersect(Sphere(Vector3(0.3, 0.9, 0.2), 0.5)))
    )
    var ground_push = tree.sphere_intersect(Sphere(Vector3(0.3, 0.3, 0.2), 0.5))
    assert_true(Bool(ground_push))
    assert_vector(
        ground_push.value().normal, 0.317669362, 0.867351234, 0.383129239
    )
    assert_almost_equal(ground_push.value().depth, 0.432467163, atol=TOLERANCE)
    var wall_push = tree.sphere_intersect(Sphere(Vector3(1.7, 1, 0), 0.5))
    assert_true(Bool(wall_push))
    assert_vector(
        wall_push.value().normal, 0.901667476, 0.417060792, 0.114263050
    )
    assert_almost_equal(wall_push.value().depth, 0.939162791, atol=TOLERANCE)
    assert_false(Bool(tree.sphere_intersect(Sphere(Vector3(0, 5, 0), 0.5))))
    assert_false(
        Bool(tree.sphere_intersect(Sphere(Vector3(-1.5, 0.2, 1.5), 0.4)))
    )


def test_capsule_triangles_match_three() raises:
    """A capsule gathers three.js's triangles, in three.js's order."""
    var tree = built()
    assert_indices(
        tree.capsule_triangles(
            Capsule(Vector3(0.3, 0.6, 0.2), Vector3(0.3, 1.6, 0.2), 0.35)
        ),
        [
            14,
            15,
            16,
            17,
            26,
            27,
            28,
            29,
            31,
            30,
            40,
            41,
            38,
            39,
            50,
            52,
            53,
            43,
            42,
            33,
            44,
            45,
            55,
            73,
            72,
        ],
    )
    assert_indices(
        tree.capsule_triangles(
            Capsule(Vector3(1.8, 0.8, 0.1), Vector3(1.8, 1.8, 0.1), 0.3)
        ),
        [73, 64, 53, 52, 62, 63, 65, 72, 66, 55, 54, 67, 69],
    )
    assert_indices(
        tree.capsule_triangles(
            Capsule(Vector3(-1.2, 0.3, -1.4), Vector3(-0.4, 0.5, -1.0), 0.3)
        ),
        [12, 13, 14, 15, 24, 25, 26, 27, 16, 17, 28, 29],
    )
    assert_equal(
        len(
            tree.capsule_triangles(
                Capsule(Vector3(0, 5, 0), Vector3(0, 6, 0), 0.35)
            )
        ),
        0,
    )


def test_capsule_intersect_matches_three() raises:
    """The push out of the level, as three.js gives it."""
    var tree = built()
    assert_false(
        Bool(
            tree.capsule_intersect(
                Capsule(Vector3(0.3, 0.6, 0.2), Vector3(0.3, 1.6, 0.2), 0.35)
            )
        )
    )
    var ground_push = tree.capsule_intersect(
        Capsule(Vector3(0.3, 0.2, 0.2), Vector3(0.3, 1.2, 0.2), 0.35)
    )
    assert_true(Bool(ground_push))
    assert_vector(
        ground_push.value().normal, 0.0492065363, 0.971848309, 0.230411634
    )
    assert_almost_equal(ground_push.value().depth, 0.281368315, atol=TOLERANCE)
    var wall_push = tree.capsule_intersect(
        Capsule(Vector3(1.8, 0.8, 0.1), Vector3(1.8, 1.8, 0.1), 0.3)
    )
    assert_true(Bool(wall_push))
    assert_vector(
        wall_push.value().normal, -0.540581882, 0.703015268, 0.462104648
    )
    assert_almost_equal(wall_push.value().depth, 0.346594006, atol=TOLERANCE)
    var slope_push = tree.capsule_intersect(
        Capsule(Vector3(-1.2, 0.3, -1.4), Vector3(-0.4, 0.5, -1.0), 0.3)
    )
    assert_true(Bool(slope_push))
    assert_vector(
        slope_push.value().normal, -0.408248305, 0.816496611, 0.408248305
    )
    assert_almost_equal(slope_push.value().depth, 0.136700690, atol=TOLERANCE)
    assert_false(
        Bool(
            tree.capsule_intersect(
                Capsule(Vector3(0, 5, 0), Vector3(0, 6, 0), 0.35)
            )
        )
    )


# --- one triangle ------------------------------------------------------------


def test_triangle_capsule_intersect_matches_three() raises:
    """Through the face, past an edge, above, below and beside."""
    var face = triangle_capsule_intersect(
        Capsule(Vector3(0.2, 0.1, 0.2), Vector3(0.2, 1.1, 0.2), 0.3), ground()
    )
    assert_true(Bool(face))
    assert_vector(face.value().normal, 0, 1, 0)
    assert_vector(face.value().point, 0.2, 0.3, 0.2)
    assert_almost_equal(face.value().depth, 0.2, atol=TOLERANCE)
    var misses: List[Capsule] = [
        Capsule(Vector3(1.1, 0.1, 0.5), Vector3(1.1, 1, 0.5), 0.3),
        Capsule(Vector3(0.2, 1, 0.2), Vector3(0.2, 2, 0.2), 0.3),
        Capsule(Vector3(0.2, -2, 0.2), Vector3(0.2, -1, 0.2), 0.3),
        Capsule(Vector3(3, 0.1, 3), Vector3(3, 1, 3), 0.3),
        Capsule(Vector3(-0.5, 0.1, -0.2), Vector3(-0.2, 0.1, -0.5), 0.4),
    ]
    for capsule in misses:
        assert_false(Bool(triangle_capsule_intersect(capsule, ground())))
    var edge = triangle_capsule_intersect(
        Capsule(Vector3(-0.3, 0.1, 0.2), Vector3(-0.3, 0.1, 0.9), 0.4), ground()
    )
    assert_true(Bool(edge))
    assert_vector(edge.value().normal, -0.948683321, 0.316227764, 0)
    assert_vector(edge.value().point, 0, 0, 0.2)
    assert_almost_equal(edge.value().depth, 0.0837722346, atol=TOLERANCE)


def test_triangle_sphere_intersect_matches_three() raises:
    """Over the face, and every way to miss."""
    var face = triangle_sphere_intersect(
        Sphere(Vector3(0.2, 0.1, 0.2), 0.3), ground()
    )
    assert_true(Bool(face))
    assert_vector(face.value().normal, 0, 1, 0)
    assert_vector(face.value().point, 0.2, 0, 0.2)
    assert_almost_equal(face.value().depth, 0.2, atol=TOLERANCE)
    var misses: List[Sphere] = [
        Sphere(Vector3(1.1, 0.1, 0.5), 0.3),
        Sphere(Vector3(0.2, 1, 0.2), 0.3),
        Sphere(Vector3(3, 0.1, 3), 0.3),
        Sphere(Vector3(-0.1, -0.1, -0.1), 0.3),
    ]
    for sphere in misses:
        assert_false(Bool(triangle_sphere_intersect(sphere, ground())))


def test_a_sphere_meets_an_edge() raises:
    """A sphere past an edge, and near it, is pushed away from the edge."""
    var met = triangle_sphere_intersect(
        Sphere(Vector3(-0.1, 0.1, 0.5), 0.3), ground()
    )
    assert_true(Bool(met))
    assert_vector(met.value().point, 0, 0, 0.5)
    assert_vector(met.value().normal, -0.707106769, 0.707106769, 0)
    assert_almost_equal(met.value().depth, 0.3 - 0.141421356, atol=TOLERANCE)


def test_a_degenerate_triangle_meets_by_its_edges() raises:
    """A triangle on one line has no plane, and three.js still meets its
    edges; an edge of no length meets nothing."""
    var flat = Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0))
    var met = triangle_capsule_intersect(
        Capsule(Vector3(0.5, 0.1, -0.5), Vector3(0.5, 0.1, 0.5), 0.3), flat
    )
    assert_true(Bool(met))
    assert_vector(met.value().normal, 0, 1, 0)
    assert_vector(met.value().point, 0.5, 0, 0)
    assert_almost_equal(met.value().depth, 0.2, atol=TOLERANCE)
    assert_false(
        Bool(triangle_sphere_intersect(Sphere(Vector3(0.5, 0.1, 0), 0.3), flat))
    )
    var point = Triangle(Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0))
    assert_false(
        Bool(
            triangle_capsule_intersect(
                Capsule(Vector3(0, 0.1, -1), Vector3(0, 0.1, 1), 0.3), point
            )
        )
    )
    assert_false(
        Bool(triangle_sphere_intersect(Sphere(Vector3(0, 0.1, 0), 0.3), point))
    )


def test_line_to_line_closest_points() raises:
    """Crossing, parallel from either end, and a segment of no length."""
    var crossing = line_to_line_closest_points(
        Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, -1), Vector3(0, 1, 1)
    )
    assert_true(Bool(crossing))
    assert_vector(crossing.value()[0], 0, 0, 0)
    assert_vector(crossing.value()[1], 0, 1, 0)
    # Parallel: the start of the first is nearer the middle of the second.
    var near_start = line_to_line_closest_points(
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(-0.5, 1, 0),
        Vector3(0.5, 1, 0),
    )
    assert_true(Bool(near_start))
    assert_vector(near_start.value()[0], 0, 0, 0)
    assert_vector(near_start.value()[1], 0, 1, 0)
    # Parallel: the end of the first is nearer.
    var near_end = line_to_line_closest_points(
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0.5, 1, 0),
        Vector3(1.5, 1, 0),
    )
    assert_true(Bool(near_end))
    assert_vector(near_end.value()[0], 1, 0, 0)
    assert_vector(near_end.value()[1], 1, 1, 0)
    assert_false(
        Bool(
            line_to_line_closest_points(
                Vector3(0, 0, 0),
                Vector3(1, 0, 0),
                Vector3(2, 2, 2),
                Vector3(2, 2, 2),
            )
        )
    )


# --- from a scene -----------------------------------------------------------


def test_from_graph_node() raises:
    """The meshes at and below a node, in world space, on shared layers."""
    var assets = Assets()
    var material = assets.materials.add(Material(Color(255, 255, 255)))
    var box = assets.geometries.add(cube(Length(1.0, METER)))
    var scene = Scene()
    var root = scene.add(Object3D())
    var moved = Object3D()
    moved.set_position(10, 0, 0)
    moved.parent = root
    var child = scene.add(moved^)
    var hidden = Object3D()
    hidden.parent = root
    hidden.layers.set(3)
    var off_layer = scene.add(hidden^)
    var outside = scene.add(Object3D())
    scene.add_mesh(Mesh(box, material, child))
    scene.add_mesh(Mesh(box, material, off_layer))
    scene.add_mesh(Mesh(box, material, outside))
    var tree = Octree()
    tree.from_graph_node(scene, assets, root)
    assert_equal(len(tree.triangles), 12)
    assert_vector(tree.bounds.min, 9.5, -0.5, -0.5)
    assert_vector(tree.bounds.max, 10.5, 0.5, 0.5)
    var hit = tree.ray_intersect(ray(10, 5, 0.1, 0, -1, 0))
    assert_true(Bool(hit))
    assert_almost_equal(hit.value().distance, 4.5, atol=TOLERANCE)
    # The layer can be widened to read the other mesh.
    var wide = Octree()
    wide.layers = Layers.all()
    wide.from_graph_node(scene, assets, root)
    assert_equal(len(wide.triangles), 24)
    var nowhere = Octree()
    with assert_raises():
        nowhere.from_graph_node(scene, assets, NodeId(99))


def test_from_graph_node_with_nothing_to_read() raises:
    """A scene with no meshes, and a mesh with no triangles, add none."""
    var assets = Assets()
    var bare = Scene()
    var root = bare.add(Object3D())
    var tree = Octree()
    tree.from_graph_node(bare, assets, root)
    assert_equal(len(tree.triangles), 0)
    var empty = BufferGeometry()
    empty.set_attribute(POSITION, BufferAttribute(List[Float32](), 3))
    bare.add_mesh(
        Mesh(
            assets.geometries.add(empty^),
            assets.materials.add(Material(Color(255, 255, 255))),
            root,
        )
    )
    var again = Octree()
    again.from_graph_node(bare, assets, root)
    assert_equal(len(again.triangles), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
