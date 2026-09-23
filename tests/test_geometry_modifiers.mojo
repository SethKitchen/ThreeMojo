# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.tessellate`, `geometries.simplify` and
`geometries.edge_split`.

The expected numbers are what three.js 0.180's `TessellateModifier`,
`SimplifyModifier` and `EdgeSplitModifier` give under node, for the same
input built the same way."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    COLOR,
    NORMAL,
    POSITION,
    TANGENT,
    UV,
    UV1,
)
from geometries.edge_split import edge_split
from geometries.simplify import simplify
from geometries.tessellate import tessellate
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, Length, METER, RADIAN


def near(actual: Float64, expected: Float64, tolerance: Float64) raises:
    """Check `actual` is within `tolerance` of `expected`."""
    if not (abs(actual - expected) <= tolerance):
        raise Error(
            "expected " + String(expected) + " but got " + String(actual)
        )


def check_numbers(
    geometry: BufferGeometry,
    name: String,
    expected: List[Float64],
    start: Int = 0,
    tolerance: Float64 = 1e-7,
) raises:
    """Check a run of an attribute's numbers, from number `start` on."""
    var numbers = geometry.attribute_view(name).packed()
    for index in range(len(expected)):
        near(Float64(numbers[start + index]), expected[index], tolerance)


def check_index(geometry: BufferGeometry, expected: List[Int]) raises:
    """Check a geometry's index entry for entry."""
    assert_equal(len(geometry.index), len(expected))
    for entry in range(len(expected)):
        assert_equal(geometry.index[entry], expected[entry])


def total(geometry: BufferGeometry, name: String) raises -> Float64:
    """Return the sum of every number of an attribute."""
    var sum = 0.0
    var numbers = geometry.attribute_view(name).packed()
    for index in range(len(numbers)):
        sum += Float64(numbers[index])
    return sum


def grid(n: Int) raises -> BufferGeometry:
    """Return the bumpy indexed grid the three.js reference builds, with
    every attribute the simplifier keeps."""
    var pos = List[Float32]()
    var nor = List[Float32]()
    var uv = List[Float32]()
    var col = List[Float32]()
    var tan = List[Float32]()
    var index = List[Int]()
    for j in range(n + 1):
        for i in range(n + 1):
            pos.append(Float32(Float64(i) * 0.25))
            pos.append(Float32(Float64(j) * 0.25))
            pos.append(Float32(Float64((i * 7 + j * 3) % 5) * 0.1))
            nor.extend([Float32(0), 0, 1])
            uv.append(Float32(Float64(i) / Float64(n)))
            uv.append(Float32(Float64(j) / Float64(n)))
            col.append(Float32(Float64(i) / Float64(n)))
            col.append(0.5)
            col.append(Float32(Float64(j) / Float64(n)))
            tan.extend([Float32(1), 0, 0, 1])
    for j in range(n):
        for i in range(n):
            var a = j * (n + 1) + i
            var b = a + 1
            var c = a + n + 1
            var d = c + 1
            index.extend([a, b, d, a, d, c])
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(pos^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(nor^, 3))
    geometry.set_attribute(String(UV), BufferAttribute(uv^, 2))
    geometry.set_attribute(String(COLOR), BufferAttribute(col^, 3))
    geometry.set_attribute(String(TANGENT), BufferAttribute(tan^, 4))
    geometry.set_index(index^)
    return geometry^


def triangles() raises -> BufferGeometry:
    """Return the three triangles the tessellation reference cuts."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute(
            [
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                0.5,
                0,
                0,
                0,
                0,
                0.2,
                0.1,
                0,
                0,
                0.9,
                0.1,
                0,
                0,
                0,
                0.3,
                0,
                0,
                0.25,
                0.6,
                0,
            ],
            3,
        ),
    )
    geometry.set_attribute(
        String(NORMAL),
        BufferAttribute(
            [
                0,
                0,
                1,
                0,
                1,
                0,
                1,
                0,
                0,
                0,
                0,
                1,
                0,
                0,
                1,
                0,
                0,
                1,
                0,
                0,
                1,
                0,
                0,
                1,
                0,
                0,
                1,
            ],
            3,
        ),
    )
    geometry.set_attribute(
        String(COLOR),
        BufferAttribute(
            [
                1,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                1,
                1,
                1,
                1,
                1,
                1,
                1,
                1,
                1,
                1,
                0.5,
                0.5,
                0.5,
                0,
                0,
                0,
                1,
                1,
                1,
            ],
            3,
        ),
    )
    geometry.set_attribute(
        String(UV),
        BufferAttribute(
            [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1], 2
        ),
    )
    geometry.set_attribute(
        String(UV1),
        BufferAttribute(
            [0, 0, 2, 0, 0, 2, 0, 0, 2, 0, 0, 2, 0, 0, 2, 0, 0, 2], 2
        ),
    )
    geometry.set_attribute(
        "extra", BufferAttribute([1, 2, 3, 4, 5, 6, 7, 8, 9], 1)
    )
    return geometry^


def meters(value: Float32) -> Length:
    """Return `value` meters."""
    return Length(value, METER)


def test_tessellation_matches_three() raises:
    var cut = tessellate(triangles(), meters(0.4), 6)
    assert_equal(cut.vertex_count(), 72)
    assert_equal(cut.attribute_count(), 5)
    assert_equal(cut.names[4], String(UV1))
    assert_false(cut.has_attribute("extra"))
    check_numbers(
        cut,
        String(POSITION),
        [
            0,
            0,
            0,
            0.25,
            0,
            0,
            0.25,
            0.125,
            0,
            0.25,
            0,
            0,
            0.5,
            0,
            0,
            0.25,
            0.125,
            0,
        ],
    )
    check_numbers(
        cut,
        String(POSITION),
        [
            0.2750000059604645,
            0.30000001192092896,
            0,
            0.25,
            0.6000000238418579,
            0,
            0.125,
            0.30000001192092896,
            0,
        ],
        72 * 3 - 9,
    )
    check_numbers(
        cut, String(NORMAL), [0, 0, 1, 0, 0.25, 0.75, 0.25, 0.25, 0.5]
    )
    check_numbers(cut, String(COLOR), [1, 0, 0, 0.75, 0.25, 0, 0.5, 0.25, 0.25])
    check_numbers(cut, String(UV), [0, 0, 0.25, 0, 0.25, 0.25])
    check_numbers(cut, String(UV1), [0, 0, 0.5, 0, 0.5, 0.5])
    near(total(cut, String(POSITION)), 34.524999901652336, 1e-5)


def test_tessellation_stops_when_the_passes_run_out() raises:
    var once = tessellate(triangles(), meters(0.4), 1)
    assert_equal(once.vertex_count(), 18)
    check_numbers(
        once,
        String(POSITION),
        [0, 0, 0, 1, 0, 0, 0.5, 0.25, 0, 0.5, 0.25, 0, 0, 0.5, 0, 0, 0, 0],
    )
    check_numbers(once, String(NORMAL), [0, 0, 1, 0, 1, 0, 0.5, 0.5, 0])
    near(total(once, String(POSITION)), 7.900000035762787, 1e-5)
    var fine = tessellate(triangles(), meters(0.1), 3)
    assert_equal(fine.vertex_count(), 72)
    check_numbers(
        fine,
        String(POSITION),
        [
            0.1875,
            0.45000001788139343,
            0,
            0.125,
            0.30000001192092896,
            0,
            0.2750000059604645,
            0.30000001192092896,
            0,
        ],
        72 * 3 - 9,
    )
    near(total(fine, String(POSITION)), 31.600000116974115, 1e-5)
    for passes_and_limit in [(0, Float32(0.4)), (6, Float32(2))]:
        var same = tessellate(
            triangles(), meters(passes_and_limit[1]), passes_and_limit[0]
        )
        assert_equal(same.vertex_count(), 9)
        near(total(same, String(POSITION)), 3.9500000178813934, 1e-6)


def test_tessellation_makes_an_indexed_surface_flat_first() raises:
    var cut = tessellate(grid(2), meters(0.2), 3)
    assert_equal(cut.vertex_count(), 144)
    assert_false(cut.is_indexed())
    assert_equal(cut.attribute_count(), 4)
    assert_false(cut.has_attribute(String(TANGENT)))
    near(total(cut, String(POSITION)), 92.67500060796738, 1e-4)


def test_tessellation_refuses_what_it_cannot_cut() raises:
    with assert_raises():
        _ = tessellate(triangles(), meters(-1))
    with assert_raises():
        _ = tessellate(triangles(), Length(inf[DType.float32](), METER))
    with assert_raises():
        _ = tessellate(triangles(), meters(1), -1)
    var partial = BufferGeometry()
    partial.set_attribute(
        String(POSITION), BufferAttribute([0, 0, 0, 1, 0, 0], 3)
    )
    with assert_raises():
        _ = tessellate(partial)
    var odd = triangles()
    odd.set_attribute(
        String(UV), BufferAttribute(List[Float32](length=27, fill=0), 3)
    )
    with assert_raises():
        _ = tessellate(odd)
    with assert_raises():
        _ = tessellate(BufferGeometry())


def test_simplification_matches_three() raises:
    var fewer = simplify(grid(4), 6)
    assert_equal(fewer.vertex_count(), 19)
    assert_equal(fewer.names[1], String(UV))
    assert_equal(fewer.names[4], String(COLOR))
    check_index(
        fewer,
        [
            1,
            3,
            0,
            3,
            4,
            5,
            4,
            6,
            7,
            4,
            7,
            5,
            0,
            3,
            9,
            0,
            9,
            2,
            3,
            5,
            9,
            5,
            7,
            10,
            2,
            9,
            12,
            2,
            12,
            8,
            9,
            5,
            13,
            9,
            13,
            12,
            5,
            10,
            13,
            11,
            8,
            14,
            11,
            14,
            15,
            8,
            12,
            16,
            8,
            16,
            14,
            12,
            13,
            17,
            12,
            17,
            16,
            13,
            18,
            17,
        ],
    )
    check_numbers(
        fewer,
        String(POSITION),
        [
            0,
            0,
            0,
            0.25,
            0,
            0.20000000298023224,
            0,
            0.25,
            0.30000001192092896,
            0.5,
            0,
            0.4000000059604645,
            0.75,
            0,
            0.10000000149011612,
            0.75,
            0.25,
            0.4000000059604645,
            1,
            0,
            0.30000001192092896,
            1,
            0.25,
            0.10000000149011612,
            0,
            0.5,
            0.10000000149011612,
            0.5,
            0.5,
            0,
            1,
            0.5,
            0.4000000059604645,
            0,
            0.75,
            0.4000000059604645,
            0.5,
            0.75,
            0.30000001192092896,
            0.75,
            0.75,
            0,
            0.25,
            1,
            0.4000000059604645,
            0,
            1,
            0.20000000298023224,
            0.5,
            1,
            0.10000000149011612,
            0.75,
            1,
            0.30000001192092896,
            1,
            1,
            0,
        ],
    )
    check_numbers(fewer, String(NORMAL), [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1])
    check_numbers(
        fewer,
        String(TANGENT),
        [0.7071067690849304, 0, 0, 0.7071067690849304, 1, 0, 0, 1],
    )
    check_numbers(fewer, String(UV), [0, 0, 0.25, 0, 0, 0.25, 0.5, 0])
    check_numbers(fewer, String(COLOR), [0, 0.5, 0, 0.25, 0.5, 0])


def test_simplification_can_go_a_long_way() raises:
    var few = simplify(grid(4), 20)
    assert_equal(few.vertex_count(), 5)
    check_index(few, [0, 1, 2, 0, 2, 3, 2, 4, 3])
    check_numbers(
        few,
        String(POSITION),
        [
            0,
            0,
            0,
            0.5,
            0,
            0.4000000059604645,
            0.75,
            0.75,
            0,
            0.75,
            1,
            0.30000001192092896,
            1,
            1,
            0,
        ],
    )
    check_numbers(
        few,
        String(TANGENT),
        [
            0.7071067690849304,
            0,
            0,
            0.7071067690849304,
            0.7071067690849304,
            0,
            0,
            0.7071067690849304,
        ],
    )
    check_numbers(few, String(UV), [0, 0, 0.5, 0, 0.75, 0.75, 0.75, 1])
    var none = simplify(grid(3), 100)
    assert_equal(none.vertex_count(), 0)
    assert_equal(none.attribute_count(), 1)
    assert_equal(len(none.index), 0)


def test_simplifying_a_lone_triangle_removes_its_corners_one_by_one() raises:
    var triangle = BufferGeometry()
    triangle.set_attribute(
        String(POSITION), BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3)
    )
    triangle.set_attribute("skin", BufferAttribute([1, 2, 3], 1))
    var gone = simplify(triangle, 5)
    assert_equal(gone.vertex_count(), 0)
    var one = simplify(triangle, 1)
    assert_equal(one.attribute_count(), 1)
    check_numbers(one, String(POSITION), [1, 0, 0, 0, 1, 0])
    assert_equal(len(one.index), 0)
    var same = simplify(triangle, 0)
    assert_equal(same.vertex_count(), 3)
    check_index(same, [0, 1, 2])


def test_simplifying_a_sliver_matches_three() raises:
    # The first triangle welds into one with a vertex at two corners.
    var sliver = BufferGeometry()
    sliver.set_attribute(
        String(POSITION),
        BufferAttribute(
            [
                0,
                0,
                0,
                1,
                0,
                0,
                1,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                1,
                0,
                1,
                0,
                0,
                2,
                1,
                0.5,
                0,
                1,
                0,
            ],
            3,
        ),
    )
    var expected: List[List[Float64]] = [
        [0, 0, 0, 0, 1, 0, 2, 1, 0.5],
        [0, 1, 0, 2, 1, 0.5],
        [2, 1, 0.5],
        [],
    ]
    for steps in range(1, 5):
        var fewer = simplify(sliver, steps)
        assert_equal(fewer.vertex_count() * 3, len(expected[steps - 1]))
        check_numbers(fewer, String(POSITION), expected[steps - 1])
        assert_equal(len(fewer.index), 0)


def test_the_modifiers_pass_an_empty_surface_through() raises:
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    assert_equal(tessellate(empty).vertex_count(), 0)
    assert_equal(simplify(empty, 1).vertex_count(), 0)
    assert_equal(
        edge_split(empty, Angle(Float32(0.5), RADIAN)).vertex_count(), 0
    )


def test_simplification_refuses_what_it_cannot_reduce() raises:
    with assert_raises():
        _ = simplify(grid(2), -1)
    with assert_raises():
        _ = simplify(BufferGeometry(), 1)
    var flat = BufferGeometry()
    flat.set_attribute(String(POSITION), BufferAttribute([0, 0, 0, 1], 2))
    with assert_raises():
        _ = simplify(flat, 1)
    for name_and_size in [
        (String(UV), 3),
        (String(NORMAL), 2),
        (String(TANGENT), 3),
        (String(COLOR), 2),
    ]:
        var odd = grid(1)
        var size = name_and_size[1]
        odd.set_attribute(
            name_and_size[0],
            BufferAttribute(List[Float32](length=4 * size, fill=0), size),
        )
        with assert_raises():
            _ = simplify(odd, 1)
    var rgba = grid(1)
    rgba.set_attribute(
        String(COLOR), BufferAttribute(List[Float32](length=16, fill=0.5), 4)
    )
    var kept = simplify(rgba, 0)
    assert_equal(kept.attribute_view(String(COLOR)).item_size, 3)
    var instanced = grid(1)
    instanced.instanced = True
    with assert_raises():
        _ = simplify(instanced, 1)


def tent(with_normals: Bool = True) raises -> BufferGeometry:
    """Return the tent the edge split reference cuts: two slopes meeting at
    a ridge, indexed, with normals worked out by three.js's rule."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute(
            [
                0,
                0,
                0,
                1,
                0,
                0,
                2,
                0,
                0,
                0,
                1,
                0.5,
                1,
                1,
                0.5,
                2,
                1,
                0.5,
                0,
                2,
                0,
                1,
                2,
                0,
                2,
                2,
                0,
            ],
            3,
        ),
    )
    geometry.set_attribute(
        String(UV),
        BufferAttribute(
            [0, 0, 0.5, 0, 1, 0, 0, 0.5, 0.5, 0.5, 1, 0.5, 0, 1, 0.5, 1, 1, 1],
            2,
        ),
    )
    geometry.set_index(
        [0, 1, 4, 0, 4, 3, 1, 2, 5, 1, 5, 4, 3, 4, 7, 3, 7, 6, 4, 5, 8, 4, 8, 7]
    )
    if with_normals:
        geometry.compute_vertex_normals()
    return geometry^


comptime SLOPE = 0.4472135901451111
comptime RISE = 0.8944271802902222


def split_normals(kept: Bool) -> List[Float64]:
    """Return the normals three.js gives the split tent: 27 vertices."""
    var out: List[Float64] = [0, -SLOPE, RISE, 0, -SLOPE, RISE, 0, -SLOPE, RISE]
    if kept:
        out.extend(
            [
                0,
                0.16439898312091827,
                0.986393928527832,
                0,
                0,
                1,
                0,
                -0.16439898312091827,
                0.986393928527832,
            ]
        )
    else:
        out.extend([0, SLOPE, RISE, 0, -SLOPE, RISE, 0, -SLOPE, RISE])
    out.extend([0, SLOPE, RISE, 0, SLOPE, RISE, 0, SLOPE, RISE])
    out.extend(List[Float64](length=15 * 3, fill=0))
    out.extend([0, -SLOPE, RISE, 0, SLOPE, RISE, 0, SLOPE, RISE])
    return out^


def test_an_edge_split_matches_three() raises:
    var angle = Angle(Float32(0.5235987901687622), RADIAN)
    for keep in [True, False]:
        var split = edge_split(tent(), angle, keep)
        assert_equal(split.vertex_count(), 27)
        assert_equal(split.names[2], String(NORMAL))
        check_index(
            split,
            [
                0,
                1,
                4,
                0,
                4,
                24,
                1,
                2,
                5,
                1,
                5,
                4,
                3,
                25,
                7,
                3,
                7,
                6,
                25,
                26,
                8,
                25,
                8,
                7,
            ],
        )
        check_numbers(
            split, String(POSITION), [0, 1, 0.5, 1, 1, 0.5, 2, 1, 0.5], 72
        )
        check_numbers(
            split, String(POSITION), List[Float64](length=45, fill=0), 27
        )
        check_numbers(split, String(UV), [0, 0.5, 0.5, 0.5, 1, 0.5], 48)
        check_numbers(split, String(NORMAL), split_normals(keep), 0, 1e-6)


def test_a_wide_angle_splits_nothing() raises:
    var split = edge_split(tent(), Angle(Float32(1.5707963705062866), RADIAN))
    assert_equal(split.vertex_count(), 24)
    check_index(
        split,
        [
            0,
            1,
            4,
            0,
            4,
            3,
            1,
            2,
            5,
            1,
            5,
            4,
            3,
            4,
            7,
            3,
            7,
            6,
            4,
            5,
            8,
            4,
            8,
            7,
        ],
    )
    var expected = split_normals(True)
    expected.resize(72, 0)
    check_numbers(split, String(NORMAL), expected, 0, 1e-6)


def test_an_edge_split_welds_a_surface_without_an_index() raises:
    var flat = tent(False).to_non_indexed()
    var split = edge_split(flat, Angle(Float32(0.5235987901687622), RADIAN))
    assert_equal(split.vertex_count(), 27)
    assert_equal(split.attribute_count(), 2)
    assert_false(split.has_attribute(String(NORMAL)))
    check_index(
        split,
        [
            0,
            1,
            2,
            0,
            2,
            25,
            1,
            4,
            5,
            1,
            5,
            2,
            3,
            24,
            6,
            3,
            6,
            7,
            24,
            26,
            8,
            24,
            8,
            6,
        ],
    )
    check_numbers(
        split,
        String(POSITION),
        [
            0,
            0,
            0,
            1,
            0,
            0,
            1,
            1,
            0.5,
            0,
            1,
            0.5,
            2,
            0,
            0,
            2,
            1,
            0.5,
            1,
            2,
            0,
            0,
            2,
            0,
            2,
            2,
            0,
        ],
    )
    check_numbers(
        split, String(POSITION), [1, 1, 0.5, 0, 1, 0.5, 2, 1, 0.5], 72
    )
    var with_normals = tent(False).to_non_indexed()
    with_normals.compute_vertex_normals()
    var worked = edge_split(
        with_normals, Angle(Float32(0.5235987901687622), RADIAN)
    )
    assert_equal(worked.vertex_count(), 27)
    check_numbers(
        worked,
        String(NORMAL),
        [0, -SLOPE, RISE, 0, -SLOPE, RISE, 0, -SLOPE, RISE, 0, SLOPE, RISE],
        0,
        1e-6,
    )
    check_numbers(
        worked,
        String(NORMAL),
        [0, SLOPE, RISE, 0, -SLOPE, RISE, 0, SLOPE, RISE],
        72,
        1e-6,
    )


def test_an_edge_split_parts_three_faces_at_a_corner() raises:
    var corners = BufferGeometry()
    corners.set_attribute(
        String(POSITION),
        BufferAttribute(
            [
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                1,
                3,
                0,
                0,
                4,
                0,
                0,
                3,
                1,
                0,
                3,
                0,
                1,
            ],
            3,
        ),
    )
    corners.set_index([0, 1, 2, 0, 2, 3, 0, 3, 1, 5, 6, 4, 6, 7, 4, 7, 5, 4])
    corners.compute_vertex_normals()
    var split = edge_split(corners, Angle(Float32(0.7853981852531433), RADIAN))
    assert_equal(split.vertex_count(), 28)
    check_index(
        split,
        [0, 1, 2, 18, 21, 3, 19, 22, 20, 5, 6, 4, 26, 7, 23, 27, 25, 24],
    )
    check_numbers(
        split,
        String(POSITION),
        [
            0,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            1,
            3,
            0,
            0,
            3,
            0,
            0,
            4,
            0,
            0,
            3,
            1,
            0,
            3,
            0,
            1,
        ],
        54,
    )
    var third = 0.5773502588272095
    var half = 0.7071067690849304
    var normals: List[Float64] = [
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        1,
        0,
        0,
        third,
        third,
        third,
        0,
        0,
        1,
        half,
        0,
        half,
        half,
        half,
        0,
    ]
    normals.extend(List[Float64](length=30, fill=0))
    normals.extend(
        [
            1,
            0,
            0,
            0,
            1,
            0,
            0,
            1,
            0,
            1,
            0,
            0,
            0,
            1,
            0,
            1,
            0,
            0,
            0,
            1,
            0,
            0,
            1,
            0,
            1,
            0,
            0,
            0,
            1,
            0,
        ]
    )
    check_numbers(split, String(NORMAL), normals, 0, 1e-6)


def test_an_edge_split_refuses_what_it_cannot_split() raises:
    var angle = Angle(Float32(0.5), RADIAN)
    with assert_raises():
        _ = edge_split(BufferGeometry(), angle)
    with assert_raises():
        _ = edge_split(tent(), Angle(nan[DType.float32](), RADIAN))
    var instanced = tent()
    instanced.instanced = True
    with assert_raises():
        _ = edge_split(instanced, angle)
    var flat = BufferGeometry()
    flat.set_attribute(String(POSITION), BufferAttribute([0, 0, 1, 0, 0, 1], 2))
    flat.set_index([0, 1, 2])
    with assert_raises():
        _ = edge_split(flat, angle)
    var past = tent()
    past.index[3] = 40
    with assert_raises():
        _ = edge_split(past, angle)
    var lonely = tent()
    lonely.set_attribute(
        String(POSITION), BufferAttribute(List[Float32](length=30, fill=0), 3)
    )
    with assert_raises():
        _ = edge_split(lonely, angle)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
