# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.attribute_utils`.

The expected numbers are what three.js 0.180's `BufferGeometryUtils` gives
under node, for the same input built the same way."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import (
    BufferGeometry,
    GeometryGroup,
    MAX_MORPH_TARGETS,
    MaterialIndex,
    NORMAL,
    POSITION,
)
from core.interleaved_buffer import InterleavedBuffer
from geometries.attribute_utils import (
    DrawMode,
    TRIANGLES_DRAW_MODE,
    TRIANGLE_FAN_DRAW_MODE,
    TRIANGLE_STRIP_DRAW_MODE,
    compute_morphed_attributes,
    deinterleave_attribute,
    deinterleave_geometry,
    estimate_bytes_used,
    interleave_attributes,
    merge_attributes,
    merge_groups,
    to_triangles_draw_mode,
)
from math.matrix4 import Matrix4, rotation_z, translation
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE


def check(actual: List[Float32], expected: List[Float64]) raises:
    """Check a list of numbers, each to a float's precision."""
    assert_equal(len(actual), len(expected))
    for index in range(len(expected)):
        if abs(Float64(actual[index]) - expected[index]) > 1e-6:
            raise Error(
                "entry "
                + String(index)
                + ": expected "
                + String(expected[index])
                + " but got "
                + String(actual[index])
            )


def check_ints(actual: List[Int], expected: List[Int]) raises:
    """Check a list of whole numbers, entry for entry."""
    assert_equal(len(actual), len(expected))
    for index in range(len(expected)):
        assert_equal(actual[index], expected[index])


def rep(item: List[Float32], times: Int) raises -> BufferAttribute:
    """Return an attribute of `times` copies of one item."""
    var data = List[Float32]()
    for _ in range(times):
        data.extend(item.copy())
    return BufferAttribute(data^, len(item))


def shared() raises -> BufferAttribute:
    """Return three.js's test attribute: three numbers of every five."""
    return BufferAttribute(
        InterleavedBuffer([1, 2, 3, 9, 9, 4, 5, 6, 9, 9], 5), 3, 0
    )


def test_merging_attributes_matches_three() raises:
    var merged = merge_attributes([shared(), shared()])
    assert_false(merged.is_interleaved())
    check(merged.data, [1, 2, 3, 4, 5, 6, 1, 2, 3, 4, 5, 6])
    var plain = merge_attributes([BufferAttribute([7, 8, 9], 3), shared()])
    check(plain.data, [7, 8, 9, 1, 2, 3, 4, 5, 6])
    with assert_raises():
        _ = merge_attributes([])
    with assert_raises():
        _ = merge_attributes([shared(), BufferAttribute([1, 2], 2)])


def test_interleaving_attributes_matches_three() raises:
    var laid = interleave_attributes(
        [
            BufferAttribute([0, 1, 2, 3, 4, 5, 6, 7, 8], 3),
            BufferAttribute([0.1, 0.2, 0.3, 0.4, 0.5, 0.6], 2),
            BufferAttribute([1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0.5], 4),
        ]
    )
    assert_equal(len(laid), 3)
    assert_equal(laid[0].stride(), 9)
    assert_equal(laid[1].offset(), 3)
    assert_equal(laid[2].offset(), 5)
    assert_true(
        laid[0].interleaved_buffer().shares_with(laid[2].interleaved_buffer())
    )
    check(laid[1].packed(), [0.1, 0.2, 0.3, 0.4, 0.5, 0.6])
    var array = List[Float32]()
    var buffer = laid[0].interleaved_buffer()
    for at in range(buffer.length()):
        array.append(buffer.value(at))
    check(
        array,
        [
            0,
            1,
            2,
            0.10000000149011612,
            0.20000000298023224,
            1,
            0,
            0,
            1,
            3,
            4,
            5,
            0.30000001192092896,
            0.4000000059604645,
            0,
            1,
            0,
            1,
            6,
            7,
            8,
            0.5,
            0.6000000238418579,
            0,
            0,
            1,
            0.5,
        ],
    )


def test_interleaving_refuses_attributes_that_do_not_fit() raises:
    with assert_raises():
        _ = interleave_attributes([])
    with assert_raises():
        _ = interleave_attributes(
            [BufferAttribute([1, 2, 3], 3), BufferAttribute([1, 2, 3, 4], 2)]
        )
    with assert_raises():
        _ = interleave_attributes([BufferAttribute([1, 2, 3, 4, 5], 5)])


def test_deinterleaving_matches_three() raises:
    var own = deinterleave_attribute(shared())
    assert_false(own.is_interleaved())
    assert_false(own.is_instanced())
    check(own.data, [1, 2, 3, 4, 5, 6])
    var instanced = BufferAttribute(
        InterleavedBuffer([1, 2, 3, 4, 5, 6, 7, 8], 4, mesh_per_attribute=2),
        2,
        1,
    )
    var copied = deinterleave_attribute(instanced)
    check(copied.data, [2, 3, 6, 7])
    # three.js loses the instancing here; see the function's docstring.
    assert_equal(copied.mesh_per_attribute(), 2)
    var wide = BufferAttribute(
        InterleavedBuffer([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], 6), 5, 1
    )
    check(deinterleave_attribute(wide).data, [2, 3, 4, 5, 0, 8, 9, 10, 11, 0])
    with assert_raises():
        _ = deinterleave_attribute(BufferAttribute([1, 2, 3], 3))


def test_deinterleaving_a_geometry_leaves_plain_attributes_alone() raises:
    var geometry = BufferGeometry()
    var laid = interleave_attributes(
        [
            BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0], 3),
            BufferAttribute([0, 0, 1, 0, 0, 1], 2),
        ]
    )
    geometry.set_attribute(String(POSITION), laid[0].copy())
    geometry.set_attribute("uv", laid[1].copy())
    geometry.set_attribute(String(NORMAL), rep([0, 0, 1], 3))
    geometry.add_morph_target(laid[0].copy(), rep([0, 1, 0], 3))
    geometry.add_morph_target(rep([1, 1, 1], 3), laid[0].copy())
    deinterleave_geometry(geometry)
    for slot in range(geometry.attribute_count()):
        assert_false(geometry.values[slot].is_interleaved())
    assert_false(geometry.morph_positions[0].is_interleaved())
    assert_false(geometry.morph_normals[1].is_interleaved())
    check(geometry.attribute_view("uv").data, [0, 0, 1, 0, 0, 1])
    check(geometry.morph_positions[0].data, [0, 0, 0, 1, 0, 0, 0, 1, 0])


def test_bytes_used_match_three() raises:
    var laid = interleave_attributes(
        [
            BufferAttribute([0, 1, 2, 3, 4, 5, 6, 7, 8], 3),
            BufferAttribute([0.1, 0.2, 0.3, 0.4, 0.5, 0.6], 2),
            BufferAttribute([1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0.5], 4),
        ]
    )
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), laid[0].copy())
    geometry.set_attribute("uv", laid[1].copy())
    geometry.set_attribute("color", laid[2].copy())
    geometry.set_index([0, 1, 2])
    assert_equal(estimate_bytes_used(geometry), 114)
    geometry.index[2] = 70000
    assert_equal(estimate_bytes_used(geometry), 120)
    var plain = BufferGeometry()
    plain.set_attribute(
        String(POSITION), BufferAttribute([0, 1, 2, 3, 4, 5, 6, 7, 8], 3)
    )
    assert_equal(estimate_bytes_used(plain), 36)


def strip_geometry() raises -> BufferGeometry:
    """Return six vertices and one group, as the three.js reference has."""
    var geometry = BufferGeometry()
    var numbers = List[Float32]()
    for n in range(18):
        numbers.append(Float32(n))
    geometry.set_attribute(String(POSITION), BufferAttribute(numbers^, 3))
    geometry.add_group(0, 3, MaterialIndex(1))
    return geometry^


def test_strips_and_fans_become_triangles_as_in_three() raises:
    var strip = to_triangles_draw_mode(
        strip_geometry(), TRIANGLE_STRIP_DRAW_MODE
    )
    check_ints(strip.index, [0, 1, 2, 3, 2, 1, 2, 3, 4, 5, 4, 3])
    assert_equal(len(strip.groups), 0)
    var fan = to_triangles_draw_mode(strip_geometry(), TRIANGLE_FAN_DRAW_MODE)
    check_ints(fan.index, [0, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 5])
    var given = to_triangles_draw_mode(
        strip_geometry(), TRIANGLE_STRIP_DRAW_MODE, [5, 3, 1, 0, 2]
    )
    check_ints(given.index, [5, 3, 1, 0, 1, 3, 1, 0, 2])
    var given_fan = to_triangles_draw_mode(
        strip_geometry(), TRIANGLE_FAN_DRAW_MODE, [5, 3, 1, 0, 2]
    )
    check_ints(given_fan.index, [5, 3, 1, 5, 1, 0, 5, 0, 2])
    var indexed = strip_geometry()
    indexed.set_index([5, 3, 1, 0, 2, 4])
    var from_index = to_triangles_draw_mode(indexed, TRIANGLE_FAN_DRAW_MODE)
    check_ints(from_index.index, [5, 3, 1, 5, 1, 0, 5, 0, 2, 5, 2, 4])
    var same = to_triangles_draw_mode(strip_geometry(), TRIANGLES_DRAW_MODE)
    assert_false(same.is_indexed())
    assert_equal(len(same.groups), 1)


def test_a_strip_must_be_a_strip_of_the_geometry() raises:
    with assert_raises():
        _ = to_triangles_draw_mode(strip_geometry(), DrawMode(3))
    with assert_raises():
        _ = to_triangles_draw_mode(strip_geometry(), DrawMode(-1))
    with assert_raises():
        _ = to_triangles_draw_mode(
            strip_geometry(), TRIANGLE_STRIP_DRAW_MODE, [0, 1]
        )
    with assert_raises():
        _ = to_triangles_draw_mode(
            strip_geometry(), TRIANGLE_STRIP_DRAW_MODE, [0, 1, 6]
        )
    with assert_raises():
        _ = to_triangles_draw_mode(
            strip_geometry(), TRIANGLE_FAN_DRAW_MODE, [0, -1, 2]
        )


def check_groups(geometry: BufferGeometry, expected: List[List[Int]]) raises:
    """Check a geometry's groups as `[start, count, material]` rows."""
    assert_equal(len(geometry.groups), len(expected))
    for index in range(len(expected)):
        assert_equal(geometry.groups[index].start, expected[index][0])
        assert_equal(geometry.groups[index].count, expected[index][1])
        assert_equal(
            geometry.groups[index].material_index.value, expected[index][2]
        )


def test_merging_groups_matches_three() raises:
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION), BufferAttribute(List[Float32](length=36, fill=0), 3)
    )
    geometry.set_index([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 2, 1, 0, 5, 4, 3])
    geometry.add_group(0, 3, MaterialIndex(2))
    geometry.add_group(3, 6, MaterialIndex(0))
    geometry.add_group(9, 3, MaterialIndex(2))
    geometry.add_group(12, 3, MaterialIndex(1))
    geometry.add_group(15, 3, MaterialIndex(0))
    merge_groups(geometry)
    check_ints(
        geometry.index,
        [3, 4, 5, 6, 7, 8, 5, 4, 3, 2, 1, 0, 0, 1, 2, 9, 10, 11],
    )
    check_groups(geometry, [[0, 9, 0], [9, 3, 1], [12, 6, 2]])


def test_merging_groups_indexes_a_geometry_first() raises:
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION), BufferAttribute(List[Float32](length=27, fill=0), 3)
    )
    geometry.add_group(6, 3, MaterialIndex(1))
    geometry.add_group(0, 6, MaterialIndex(1))
    geometry.add_group(3, 3, MaterialIndex(0))
    merge_groups(geometry)
    check_ints(geometry.index, [3, 4, 5, 0, 1, 2, 3, 4, 5, 6, 7, 8])
    check_groups(geometry, [[0, 3, 0], [3, 9, 1]])


def test_merging_groups_leaves_a_geometry_without_groups() raises:
    var geometry = strip_geometry()
    geometry.clear_groups()
    merge_groups(geometry)
    assert_false(geometry.is_indexed())
    var past = strip_geometry()
    past.add_group(3, 6, MaterialIndex(0))
    with assert_raises():
        merge_groups(past)


def morph_geometry(relative: Bool) raises -> BufferGeometry:
    """Return the morphed triangle of the three.js reference: four
    vertices, one unused, and three targets with normals."""
    var geometry = BufferGeometry()
    geometry.set_attribute(
        String(POSITION),
        BufferAttribute([0, 0, 0, 1, 0, 0, 0, 1, 0, 5, 5, 5], 3),
    )
    geometry.set_attribute(
        String(NORMAL), BufferAttribute([0, 0, 1, 0, 0, 1, 0, 0, 1, 1, 0, 0], 3)
    )
    geometry.add_morph_target(
        BufferAttribute([0, 0, 1, 1, 0, 1, 0, 1, 1, 9, 9, 9], 3),
        rep([0, 1, 0], 4),
    )
    geometry.add_morph_target(
        BufferAttribute([0.5, 0, 0, 1.5, 0.25, 0, 0, 1, -1, 7, 7, 7], 3),
        rep([1, 0, 0], 4),
    )
    geometry.add_morph_target(rep([3, 3, 3], 4), rep([0, 0, -1], 4))
    geometry.morph_relative = relative
    geometry.set_index([0, 1, 2])
    return geometry^


def weights() -> SIMD[DType.float32, MAX_MORPH_TARGETS]:
    """Return the weights of the three.js reference."""
    var out = SIMD[DType.float32, MAX_MORPH_TARGETS](0)
    out[0] = 0.25
    out[1] = 0.5
    return out


def test_morphed_attributes_match_three() raises:
    var absolute = compute_morphed_attributes(morph_geometry(False), weights())
    check(
        absolute.morphed_position.data,
        [0.25, 0, 0.25, 1.25, 0.125, 0.25, 0, 1, -0.25, 0, 0, 0],
    )
    check(
        absolute.morphed_normal.data,
        [0.5, 0.25, 0.25, 0.5, 0.25, 0.25, 0.5, 0.25, 0.25, 0, 0, 0],
    )
    check(absolute.position.data, [0, 0, 0, 1, 0, 0, 0, 1, 0, 5, 5, 5])
    check(absolute.normal.data, [0, 0, 1, 0, 0, 1, 0, 0, 1, 1, 0, 0])
    var relative = compute_morphed_attributes(morph_geometry(True), weights())
    check(
        relative.morphed_position.data,
        [0.25, 0, 0.25, 2, 0.125, 0.25, 0, 1.75, -0.25, 0, 0, 0],
    )
    check(
        relative.morphed_normal.data,
        [0.5, 0.25, 1, 0.5, 0.25, 1, 0.5, 0.25, 1, 0, 0, 0],
    )


def test_morphed_attributes_carry_a_skinned_mesh() raises:
    var carriers = List[Matrix4]()
    for vertex in range(4):
        var carry = translation(Float32(vertex), 0, 0)
        carry.multiply(rotation_z(Angle(90, DEGREE)))
        carriers.append(carry)
    var worn = compute_morphed_attributes(
        morph_geometry(False),
        SIMD[DType.float32, MAX_MORPH_TARGETS](0),
        carriers,
    )
    # Positions turn a quarter and then move; normals only turn.
    check(worn.morphed_position.data, [0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 0, 0])
    check(worn.morphed_normal.data, [0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0])
    with assert_raises():
        _ = compute_morphed_attributes(
            morph_geometry(False), weights(), List[Matrix4]()
        )


def test_morphed_attributes_need_normals_that_fit() raises:
    var bare = BufferGeometry()
    bare.set_attribute(String(POSITION), BufferAttribute([0, 0, 0], 3))
    with assert_raises():
        _ = compute_morphed_attributes(bare, weights())
    var flat = BufferGeometry()
    flat.set_attribute(String(POSITION), BufferAttribute([0, 0, 1, 1], 2))
    flat.set_attribute(String(NORMAL), BufferAttribute([0, 0, 1, 0, 0, 1], 3))
    with assert_raises():
        _ = compute_morphed_attributes(flat, weights())
    var short = BufferGeometry()
    short.set_attribute(
        String(POSITION), BufferAttribute([0, 0, 0, 1, 0, 0], 3)
    )
    short.set_attribute(String(NORMAL), BufferAttribute([0, 0, 1], 3))
    with assert_raises():
        _ = compute_morphed_attributes(short, weights())
    var sideways = BufferGeometry()
    sideways.set_attribute(String(POSITION), BufferAttribute([0, 0, 0], 3))
    sideways.set_attribute(String(NORMAL), BufferAttribute([0, 1], 2))
    with assert_raises():
        _ = compute_morphed_attributes(sideways, weights())


def test_empty_attributes_and_geometries_pass_through() raises:
    var none = List[Float32]()
    var laid = interleave_attributes([BufferAttribute(none.copy(), 3)])
    assert_equal(laid[0].count(), 0)
    assert_equal(deinterleave_attribute(laid[0]).count(), 0)
    var empty = BufferGeometry()
    deinterleave_geometry(empty)
    assert_equal(estimate_bytes_used(empty), 0)
    var hollow = BufferGeometry()
    hollow.set_attribute(String(POSITION), BufferAttribute(none.copy(), 3))
    hollow.set_attribute(String(NORMAL), BufferAttribute(none.copy(), 3))
    with assert_raises():
        _ = to_triangles_draw_mode(hollow, TRIANGLE_FAN_DRAW_MODE)
    var worn = compute_morphed_attributes(hollow, weights())
    assert_equal(worn.morphed_position.count(), 0)
    hollow.add_group(0, 0, MaterialIndex(3))
    merge_groups(hollow)
    check_groups(hollow, [[0, 0, 3]])
    var plain = morph_geometry(False)
    plain.morph_positions.clear()
    plain.morph_normals.clear()
    var same = compute_morphed_attributes(plain, weights())
    check(same.morphed_position.data, [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
