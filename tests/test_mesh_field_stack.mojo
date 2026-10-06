# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact traversal controls for the scalar-indexed mesh search stack."""

from extensions.humanoid.skeleton.mesh_field import (
    MeshTree,
    STACK_SIZE,
    _box_gap,
    closest_on_triangle,
)
from math.vector3 import Vector3
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true


def _reference_nearest(
    tree: MeshTree, p: Vector3, start: Int
) -> Tuple[Int, Vector3, Float32, Float32, Int, Int]:
    """Return the nearest triangle to `p`, the nearest point on it, the
    point's weights on the triangle's second and third corners, and
    the part of the triangle it lies on.

    The search starts from triangle `start`: a triangle near `p`
    bounds the search at once, and the walk leaves out every box
    farther than it.

    Args:
        tree: The original tree data.
        p: The point.
        start: A triangle to start from, any one.

    Returns:
        The triangle's index, the point, two weights and the part; see
        `closest_on_triangle`. The last result is peak pending-node count.
    """
    var first = closest_on_triangle(
        p,
        tree.points[tree.triangles[start * 3]],
        tree.points[tree.triangles[start * 3 + 1]],
        tree.points[tree.triangles[start * 3 + 2]],
    )
    var gap = first[0] - p
    var best = gap.dot(gap)
    var found = start
    # The walk holds at most two nodes a level of the tree.
    var stack = SIMD[DType.int32, STACK_SIZE](0)
    var top = 1
    var peak = top
    while top > 0:
        top -= 1
        var node = Int(stack[top])
        if _box_gap(tree.low[node], tree.high[node], p) >= best:
            continue
        if tree.left[node] < 0:
            var hit = tree.leaves[tree.leaf[node]].nearest(p)
            if hit[0] < best:
                best = hit[0]
                found = Int(tree.leaves[tree.leaf[node]].ids[hit[1]])
            continue
        # The nearer child last, so it is walked first.
        var l = tree.left[node]
        var r = tree.right[node]
        if _box_gap(tree.low[l], tree.high[l], p) < _box_gap(
            tree.low[r], tree.high[r], p
        ):
            stack[top] = Int32(r)
            stack[top + 1] = Int32(l)
        else:
            stack[top] = Int32(l)
            stack[top + 1] = Int32(r)
        top += 2
        peak = max(peak, top)
    var hit = closest_on_triangle(
        p,
        tree.points[tree.triangles[found * 3]],
        tree.points[tree.triangles[found * 3 + 1]],
        tree.points[tree.triangles[found * 3 + 2]],
    )
    return (found, hit[0], hit[1], hit[2], hit[3], peak)


def _compare(tree: MeshTree, p: Vector3, start: Int) raises:
    """Compare the triangle, feature, weights and point bit for bit."""
    var actual = tree.nearest(p, start)
    var expected = _reference_nearest(tree, p, start)
    assert_equal(actual[0], expected[0])
    assert_equal(actual[4], expected[4])
    var a: List[Float32] = [
        actual[1].x,
        actual[1].y,
        actual[1].z,
        actual[2],
        actual[3],
    ]
    var b: List[Float32] = [
        expected[1].x,
        expected[1].y,
        expected[1].z,
        expected[2],
        expected[3],
    ]
    for i in range(len(a)):
        assert_equal(bitcast[DType.uint32](a[i]), bitcast[DType.uint32](b[i]))


def test_stack_keeps_triangle_features_and_seeded_ties() raises:
    var points: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 2),
        Vector3(1, 0, 2),
        Vector3(0, 1, 2),
    ]
    var indices: List[Int] = [0, 1, 2, 3, 4, 5]
    var tree = MeshTree(points^, indices^)
    for z in [-1, 0, 1, 2, 3]:
        for p in [
            Vector3(-1, -1, Float32(z)),
            Vector3(2, -0.5, Float32(z)),
            Vector3(-0.5, 2, Float32(z)),
            Vector3(0.5, -1, Float32(z)),
            Vector3(-1, 0.5, Float32(z)),
            Vector3(1, 1, Float32(z)),
            Vector3(0.2, 0.3, Float32(z)),
        ]:
            _compare(tree, p, 0)
            _compare(tree, p, 1)
    var tie = Vector3(0.25, 0.25, 1)
    assert_equal(tree.nearest(tie, 0)[0], 0)
    assert_equal(tree.nearest(tie, 1)[0], 1)


def test_stack_keeps_large_mesh_query_order() raises:
    var points = List[Vector3]()
    var indices = List[Int]()
    for y in range(65):
        for x in range(65):
            points.append(
                Vector3(Float32(x), Float32(y), Float32((x * y) % 7) * 0.02)
            )
    for y in range(64):
        for x in range(64):
            var a = y * 65 + x
            indices.extend([a, a + 1, a + 65, a + 1, a + 66, a + 65])
    var tree = MeshTree(points^, indices^)
    assert_true(len(tree.low) > 500)
    for y in range(-1, 10):
        for x in range(-1, 10):
            var p = Vector3(
                Float32(x) * 7 + 0.3,
                Float32(y) * 7 + 0.7,
                Float32((x + y) % 3) - 1,
            )
            for start in [0, 17, 4095, 8191]:
                _compare(tree, p, start)


def test_stack_retains_its_full_capacity() raises:
    var points: List[Vector3] = [
        Vector3(0, 0, 0),
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
    ]
    var indices: List[Int] = [0, 1, 2]
    var tree = MeshTree(points^, indices^)
    # A deliberately unbalanced hierarchy with valid loose bounds. Each
    # equal-bound right continuation is visited before a pending left leaf.
    # The reference counts the peak to verify that this fills
    # the stack to its original capacity without changing any triangle.
    var depth = STACK_SIZE - 1
    var nodes = 2 * depth + 1
    tree.low = List[Vector3](length=nodes, fill=Vector3(-2, -2, -2))
    tree.high = List[Vector3](length=nodes, fill=Vector3(2, 2, 2))
    tree.left = List[Int](length=nodes, fill=-1)
    tree.right = List[Int](length=nodes, fill=-1)
    tree.leaf = List[Int](length=nodes, fill=0)
    for i in range(depth):
        tree.left[i] = depth + 1 + i
        tree.right[i] = i + 1
        tree.leaf[i] = -1
    var point = Vector3(0.25, 0.25, 1)
    assert_equal(_reference_nearest(tree, point, 0)[5], STACK_SIZE)
    _compare(tree, point, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
