# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Draco traversal returns only the points visited in the current call."""

from loaders.draco_mesh import (
    NONE,
    DracoCornerTable,
    DracoEncodingData,
    traverse_depth_first,
    traverse_prediction_degree,
)
from loaders.draco_buffer import draco_require
from std.testing import TestSuite, assert_equal


# These reference bodies retain main 0ad03120 per-call points ownership.
struct _OriginalEncodingData(Copyable, Movable):
    """The order in which the values of an attribute are stored.

    Draco's `MeshAttributeIndicesEncodingData`, filled by a traversal.
    """

    var value_corners: List[Int]
    """For each stored value, the corner it was reached at."""
    var vertex_values: List[Int]
    """For each vertex, its value; zero for a vertex not reached."""

    def __init__(out self, vertices: Int):
        """Make the data for a table of `vertices` vertices.

        Args:
            vertices: The vertices.
        """
        self.value_corners = List[Int]()
        self.vertex_values = List[Int](length=vertices, fill=0)

    def visit(
        mut self,
        vertex: Int,
        corner: Int,
        faces: List[Int],
        mut points: List[Int],
    ):
        """Store the next value, reached at a corner.

        Draco's `MeshAttributeIndicesEncodingObserver::OnNewVertexVisited`.

        Args:
            vertex: The vertex of the attribute's table.
            corner: The corner it was reached at.
            faces: The points of the mesh's corners.
            points: The points in the order their values are stored.
        """
        points.append(faces[corner])
        self.vertex_values[vertex] = len(self.value_corners)
        self.value_corners.append(corner)


def _original_depth_first(
    table: DracoCornerTable,
    faces: List[Int],
    mut data: _OriginalEncodingData,
) raises -> List[Int]:
    """Visit the vertices of a table depth first.

    Draco's `DepthFirstTraverser`, run from each face in turn by
    `MeshTraversalSequencer`.

    Args:
        table: The table to walk: the mesh's or an attribute's.
        faces: The point of each corner.
        data: The order of the values, filled as vertices are reached.

    Returns:
        The point of each stored value, in order.

    Raises:
        Error: If the table has a corner with no vertex.
    """
    var points = List[Int]()
    var face_done = List[Bool](length=table.faces(), fill=False)
    var vertex_done = List[Bool](length=table.vertices(), fill=False)
    var stack = List[Int]()
    for face in range(table.faces()):
        var start = 3 * face
        if face_done[face]:
            continue
        stack.clear()
        stack.append(start)
        var ends: List[Int] = [table.next(start), table.previous(start)]
        for corner in ends:  # pragma: no branch
            var vertex = table.vertex(corner)
            draco_require(vertex != NONE, "a corner has no vertex")
            if not vertex_done[vertex]:
                vertex_done[vertex] = True
                data.visit(vertex, corner, faces, points)
        while len(stack) > 0:
            # Draco also pops an invalid corner here, but only corners of
            # faces not yet visited are pushed.
            var corner = stack[len(stack) - 1]
            if face_done[corner // 3]:
                _ = stack.pop()
                continue
            while True:
                face_done[corner // 3] = True
                var vertex = table.vertex(corner)
                draco_require(vertex != NONE, "a corner has no vertex")
                if not vertex_done[vertex]:
                    var on_boundary = table.is_on_boundary(vertex)
                    vertex_done[vertex] = True
                    data.visit(vertex, corner, faces, points)
                    if not on_boundary:
                        corner = table.right_corner(corner)
                        continue
                var right = table.right_corner(corner)
                var left = table.left_corner(corner)
                var right_done = right == NONE or face_done[right // 3]
                var left_done = left == NONE or face_done[left // 3]
                if right_done:
                    if left_done:
                        _ = stack.pop()
                        break
                    corner = left
                elif left_done:
                    corner = right
                else:
                    stack[len(stack) - 1] = left
                    stack.append(right)
                    break
    return points^


def _original_prediction_degree(
    table: DracoCornerTable,
    faces: List[Int],
    mut data: _OriginalEncodingData,
) raises -> List[Int]:
    """Visit the vertices of a table, best predicted first.

    Draco's `MaxPredictionDegreeTraverser`: a face whose tip vertex is
    already predicted from more neighbors is visited first.

    Args:
        table: The mesh's table.
        faces: The point of each corner.
        data: The order of the values, filled as vertices are reached.

    Returns:
        The point of each stored value, in order.

    Raises:
        Error: If the table has a corner with no vertex.
    """
    var points = List[Int]()
    var face_done = List[Bool](length=table.faces(), fill=False)
    var vertex_done = List[Bool](length=table.vertices(), fill=False)
    var degree = List[Int](length=table.vertices(), fill=0)
    var stacks: List[List[Int]] = [List[Int](), List[Int](), List[Int]()]
    if table.vertices() == 0:
        return points^
    for face in range(table.faces()):  # pragma: no branch
        var start = 3 * face
        stacks[0].append(start)
        var best = 0
        var ends: List[Int] = [table.next(start), table.previous(start), start]
        for corner in ends:  # pragma: no branch
            var vertex = table.vertex(corner)
            draco_require(vertex != NONE, "a corner has no vertex")
            if not vertex_done[vertex]:
                vertex_done[vertex] = True
                data.visit(vertex, corner, faces, points)
        while True:
            var corner = NONE
            # The best priority is 0, 1 or 2. The loop always runs.
            for priority in range(best, 3):  # pragma: no branch
                if len(stacks[priority]) > 0:
                    corner = stacks[priority].pop()
                    best = priority
                    break
            if corner == NONE:
                break
            if face_done[corner // 3]:
                continue
            while True:
                face_done[corner // 3] = True
                var vertex = table.vertex(corner)
                if not vertex_done[vertex]:
                    vertex_done[vertex] = True
                    data.visit(vertex, corner, faces, points)
                var right = table.right_corner(corner)
                var left = table.left_corner(corner)
                var right_done = right == NONE or face_done[right // 3]
                var left_done = left == NONE or face_done[left // 3]
                if not left_done:
                    var priority = _original_priority(
                        table, left, vertex_done, degree
                    )
                    if right_done and priority <= best:
                        corner = left
                        continue
                    stacks[priority].append(left)
                    best = min(best, priority)
                if not right_done:
                    var priority = _original_priority(
                        table, right, vertex_done, degree
                    )
                    if priority <= best:
                        corner = right
                        continue
                    stacks[priority].append(right)
                    best = min(best, priority)
                break
    return points^


def _original_priority(
    table: DracoCornerTable,
    corner: Int,
    vertex_done: List[Bool],
    mut degree: List[Int],
) -> Int:
    """Draco's `ComputePriority`: 0 for a reached tip, 1 for a tip that
    two faces predict, 2 otherwise."""
    var tip = table.vertex(corner)
    if vertex_done[tip]:
        return 0
    degree[tip] += 1
    if degree[tip] > 1:
        return 1
    return 2


def _triangle_table() -> DracoCornerTable:
    var table = DracoCornerTable(1)
    table.corner_to_vertex = [0, 1, 2]
    table.vertex_corners = [0, 1, 2]
    return table^


def test_depth_first_reuse_and_empty_table_match_main() raises:
    var table = _triangle_table()
    var faces: List[Int] = [10, 20, 30]
    var actual = DracoEncodingData(3)
    var original = _OriginalEncodingData(3)
    for _ in range(2):
        assert_equal(
            traverse_depth_first(table, faces, actual),
            _original_depth_first(table, faces, original),
        )
        assert_equal(actual.value_corners, original.value_corners)
        assert_equal(actual.vertex_values, original.vertex_values)
    var empty = DracoCornerTable(0)
    assert_equal(
        traverse_depth_first(empty, List[Int](), actual),
        _original_depth_first(empty, List[Int](), original),
    )
    assert_equal(len(actual.points), 0)
    assert_equal(actual.value_corners, original.value_corners)
    assert_equal(actual.vertex_values, original.vertex_values)


def test_prediction_reuse_and_empty_table_match_main() raises:
    var table = _triangle_table()
    var faces: List[Int] = [10, 20, 30]
    var actual = DracoEncodingData(3)
    var original = _OriginalEncodingData(3)
    for _ in range(2):
        assert_equal(
            traverse_prediction_degree(table, faces, actual),
            _original_prediction_degree(table, faces, original),
        )
        assert_equal(actual.value_corners, original.value_corners)
        assert_equal(actual.vertex_values, original.vertex_values)
    var empty = DracoCornerTable(0)
    assert_equal(
        traverse_prediction_degree(empty, List[Int](), actual),
        _original_prediction_degree(empty, List[Int](), original),
    )
    assert_equal(len(actual.points), 0)
    assert_equal(actual.value_corners, original.value_corners)
    assert_equal(actual.vertex_values, original.vertex_values)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()


def test_original_external_points_visit_overload() raises:
    var current = DracoEncodingData(3)
    var original = _OriginalEncodingData(3)
    var current_points: List[Int] = [99]
    var original_points: List[Int] = [99]
    var faces: List[Int] = [10, 20, 30]
    current.points.append(77)
    current.visit(2, 1, faces, current_points)
    original.visit(2, 1, faces, original_points)
    current.visit(0, 2, faces, current_points)
    original.visit(0, 2, faces, original_points)
    assert_equal(current_points, original_points)
    assert_equal(current.value_corners, original.value_corners)
    assert_equal(current.vertex_values, original.vertex_values)
    assert_equal(len(current.points), 1)
    assert_equal(current.points[0], 77)
