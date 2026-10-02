# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Clipping storage reuse preserves every ordered vertex and varying."""

from math.bounds import Plane
from math.vector3 import Vector3
from render.framebuffer import FloatColor
from renderers.clip import (
    ClipVertex,
    _clip_plane,
    _clip_side,
    _cross_at,
    _cross_side,
    clip_ordered,
    flipped,
)
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_not_equal


def _vertex(x: Float32, y: Float32, z: Float32, value: Float32) -> ClipVertex:
    """Return a vertex with distinct values in every varying."""
    var out = ClipVertex(
        Vector3(x, y, z),
        FloatColor(value, value + 1, value + 2, value + 3),
        Vector3(value + 4, value + 5, value + 6),
        value + 7,
        value + 8,
        Vector3(value + 9, value + 10, value + 11),
        FloatColor(value + 12, value + 13, value + 14, value + 15),
        value + 16,
        value + 17,
        value + 18,
    )
    for index in range(8):
        out.custom[index] = value + Float32(index + 19)
    out.gouraud_direct = Vector3(value + 27, value + 28, value + 29)
    out.gouraud_indirect = Vector3(value + 30, value + 31, value + 32)
    out.gouraud_back_direct = Vector3(value + 33, value + 34, value + 35)
    out.gouraud_back_indirect = Vector3(value + 36, value + 37, value + 38)
    out.current = Vector3(value + 39, value + 40, value + 41)
    out.previous = Vector3(value + 42, value + 43, value + 44)
    return out


def _same_number(a: Float32, b: Float32) raises:
    assert_equal(bitcast[DType.uint32](a), bitcast[DType.uint32](b))


def _same_vector(a: Vector3, b: Vector3) raises:
    _same_number(a.x, b.x)
    _same_number(a.y, b.y)
    _same_number(a.z, b.z)


def _same_color(a: FloatColor, b: FloatColor) raises:
    _same_number(a.r, b.r)
    _same_number(a.g, b.g)
    _same_number(a.b, b.b)
    _same_number(a.a, b.a)


def _same(a: List[ClipVertex], b: List[ClipVertex]) raises:
    assert_equal(len(a), len(b))
    for index in range(len(a)):
        ref x = a[index]
        ref y = b[index]
        _same_vector(x.position, y.position)
        _same_color(x.color, y.color)
        _same_vector(x.normal, y.normal)
        _same_number(x.u, y.u)
        _same_number(x.v, y.v)
        _same_vector(x.world, y.world)
        _same_color(x.emissive, y.emissive)
        _same_number(x.line_distance, y.line_distance)
        _same_number(x.u1, y.u1)
        _same_number(x.v1, y.v1)
        for lane in range(8):
            _same_number(x.custom[lane], y.custom[lane])
        _same_vector(x.gouraud_direct, y.gouraud_direct)
        _same_vector(x.gouraud_indirect, y.gouraud_indirect)
        _same_vector(x.gouraud_back_direct, y.gouraud_back_direct)
        _same_vector(x.gouraud_back_indirect, y.gouraud_back_indirect)
        _same_vector(x.current, y.current)
        _same_vector(x.previous, y.previous)


def _old_depth(
    polygon: List[ClipVertex], plane: Float32, less: Bool
) -> List[ClipVertex]:
    """The original allocating edge walk, without whole-polygon shortcuts."""
    var kept = List[ClipVertex]()
    for index in range(len(polygon)):
        var a = polygon[index]
        var b = polygon[(index + 1) % len(polygon)]
        var a_in = a.position.z <= plane if less else a.position.z >= plane
        var b_in = b.position.z <= plane if less else b.position.z >= plane
        if a_in:
            kept.append(a)
        if a_in != b_in:
            kept.append(_cross_at(a, b, plane))
    return kept^


def _old_side(polygon: List[ClipVertex], plane: Plane) -> List[ClipVertex]:
    """The original side-plane walk, preserving its interpolation order."""
    var kept = List[ClipVertex]()
    for index in range(len(polygon)):
        var a = polygon[index]
        var b = polygon[(index + 1) % len(polygon)]
        var a_in = plane.distance_to_point(a.position) >= 0
        var b_in = plane.distance_to_point(b.position) >= 0
        if a_in:
            kept.append(a)
        if a_in != b_in:
            kept.append(_cross_side(a, b, plane))
    return kept^


def _fan(polygon: List[ClipVertex], mut out: List[ClipVertex]):
    for corner in range(1, len(polygon) - 1):
        out.append(polygon[0])
        out.append(polygon[corner])
        out.append(polygon[corner + 1])


def _old_clip(
    a: ClipVertex,
    b: ClipVertex,
    c: ClipVertex,
    sides: List[Plane],
    any_of: List[Plane],
) -> List[ClipVertex]:
    """The original ordered passes, including disjoint union pieces."""
    var polygon: List[ClipVertex] = [a, b, c]
    polygon = _old_depth(polygon, -1, True)
    polygon = _old_depth(polygon, -3, False)
    for side in sides:
        polygon = _old_side(polygon, side)
    var triangles = List[ClipVertex]()
    if len(any_of) == 0:
        _fan(polygon, triangles)
    else:
        for index in range(len(any_of)):
            var piece = _old_side(polygon, any_of[index])
            for earlier in range(index):
                piece = _old_side(piece, flipped(any_of[earlier]))
            _fan(piece, triangles)
    return triangles^


def test_clipping_reuses_whole_polygon_storage() raises:
    var source: List[ClipVertex] = [
        _vertex(-0.0, 0, -1, 1),
        _vertex(1, 0, -2, 2),
        _vertex(0, 1, -3, 3),
    ]
    var held = source.copy()
    var address = Int(held.unsafe_ptr())
    held = _clip_plane(held^, -1, True)
    assert_equal(Int(held.unsafe_ptr()), address)
    held = _clip_plane(held^, -3, False)
    assert_equal(Int(held.unsafe_ptr()), address)
    held = _clip_side(held^, Plane(Vector3(1, 0, 0), 0))
    assert_equal(Int(held.unsafe_ptr()), address)
    _same(held, source)
    # The transferred buffer is independent of the borrowed source.
    held[0].u = 99
    assert_not_equal(held[0].u, source[0].u)
    _same_number(source[0].u, 8)
    # Empty polygons still flow through all later planes.
    held = _clip_side(held^, Plane(Vector3(-1, 0, 0), -4))
    assert_equal(len(held), 0)
    held = _clip_plane(held^, -1, True)
    held = _clip_side(held^, Plane(Vector3(0, 1, 0), 0))
    assert_equal(len(held), 0)


def test_reused_clipping_matches_original_vertices_bit_for_bit() raises:
    var values: List[Float32] = [-4, -3, -1, -0.0, 0.25, 1, 3, 4]
    var box: List[Plane] = [
        Plane(Vector3(1, 0, 0), 1),
        Plane(Vector3(-1, 0, 0), 1),
        Plane(Vector3(0, 1, 0), 1),
        Plane(Vector3(0, -1, 0), 1),
    ]
    var union: List[Plane] = [
        Plane(Vector3(1, 0, 0), 0),
        Plane(Vector3(0, 1, 0), 0),
        Plane(Vector3(1, 1, 0), -0.25),
    ]
    for mode in range(4):
        var sides = List[Plane]()
        var any_of = List[Plane]()
        if mode % 2 == 1:
            sides = box.copy()
        if mode >= 2:
            any_of = union.copy()
        for i in range(len(values)):
            for j in range(len(values)):
                for k in range(len(values)):
                    var a = _vertex(values[i], -0.5, values[j], 0.25)
                    var b = _vertex(0.5, values[j], values[k], 1.5)
                    var c = _vertex(values[k], 0.5, values[i], -2.25)
                    var expected = _old_clip(a, b, c, sides, any_of)
                    var actual = clip_ordered(a, b, c, 1, 3, sides, any_of)
                    _same(actual, expected)
                    # Repeated calls cannot consume earlier output or inputs.
                    _same(
                        clip_ordered(c, b, a, 1, 3, sides, any_of),
                        _old_clip(c, b, a, sides, any_of),
                    )
                    _same(actual, expected)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
