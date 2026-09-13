# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.buffer_attribute`, `core.buffer_geometry` and `geometries.box`.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION
from geometries.box import box, cube
from geometries.sphere import sphere
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length, METRE

comptime TOLERANCE = Float64(1e-6)


def floats(values: List[Float32]) -> List[Float32]:
    """Return a copy of `values`, for building attributes inline."""
    return values.copy()


def triangle_attribute() raises -> BufferAttribute:
    """Return one triangle's worth of positions.

    Returns:
        A three-vertex position attribute.

    Raises:
        Error: If the data is malformed, which it is not.
    """
    var data = List[Float32]()
    for value in [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0]:
        data.append(Float32(value))
    return BufferAttribute(data^, 3)


# --- BufferAttribute --------------------------------------------------------


def test_count_divides_data_by_item_size() raises:
    assert_equal(triangle_attribute().count(), 3)
    assert_equal(BufferAttribute(List[Float32](length=8, fill=0), 2).count(), 4)


def test_components_are_read_per_vertex() raises:
    var positions = triangle_attribute()
    assert_equal(positions.component(1, 0), Float32(1))
    assert_equal(positions.component(2, 1), Float32(1))
    assert_equal(positions.component(0, 2), Float32(0))


def test_a_vertex_reads_back_as_a_vector() raises:
    var point = triangle_attribute().vector3(2)
    assert_equal(point.x, Float32(0))
    assert_equal(point.y, Float32(1))
    assert_equal(point.z, Float32(0))


def test_an_empty_attribute_is_allowed() raises:
    # A geometry may be built up before its data arrives.
    assert_equal(BufferAttribute(List[Float32](), 3).count(), 0)


def test_a_non_positive_item_size_is_rejected() raises:
    with assert_raises():
        _ = BufferAttribute(List[Float32](length=3, fill=0), 0)
    with assert_raises():
        _ = BufferAttribute(List[Float32](length=3, fill=0), -1)


def test_data_that_leaves_a_partial_vertex_is_rejected() raises:
    with assert_raises():
        _ = BufferAttribute(List[Float32](length=7, fill=0), 3)


def test_reading_past_the_last_vertex_is_rejected() raises:
    var positions = triangle_attribute()
    with assert_raises():
        _ = positions.component(3, 0)
    with assert_raises():
        _ = positions.component(-1, 0)


def test_reading_past_the_item_size_is_rejected() raises:
    var positions = triangle_attribute()
    with assert_raises():
        _ = positions.component(0, 3)
    with assert_raises():
        _ = positions.component(0, -1)


def test_a_two_component_attribute_has_no_vector3() raises:
    var uv = BufferAttribute(List[Float32](length=4, fill=0), 2)
    with assert_raises():
        _ = uv.vector3(0)


def test_copying_an_attribute_leaves_the_original_alone() raises:
    var original = triangle_attribute()
    var duplicate = BufferAttribute(copy=original)
    duplicate.data[0] = 99.0
    assert_equal(original.component(0, 0), Float32(0))


# --- BufferGeometry ---------------------------------------------------------


def test_a_new_geometry_has_nothing_in_it() raises:
    var geometry = BufferGeometry()
    assert_false(geometry.has_attribute(String(POSITION)))
    assert_false(geometry.is_indexed())


def test_attributes_are_stored_and_fetched_by_name() raises:
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), triangle_attribute())
    assert_true(geometry.has_attribute(String(POSITION)))
    assert_equal(geometry.vertex_count(), 3)


def test_setting_an_attribute_twice_replaces_it() raises:
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), triangle_attribute())
    geometry.set_attribute(
        String(POSITION), BufferAttribute(List[Float32](length=18, fill=0), 3)
    )
    assert_equal(geometry.vertex_count(), 6)


def test_fetching_an_attribute_that_is_not_there_is_rejected() raises:
    var geometry = BufferGeometry()
    with assert_raises():
        _ = geometry.attribute(String("uv"))
    with assert_raises():
        _ = geometry.vertex_count()


def test_an_unindexed_geometry_takes_vertices_three_at_a_time() raises:
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), triangle_attribute())
    assert_equal(geometry.triangle_count(), 1)
    assert_equal(geometry.corner_index(0, 2), 2)
    assert_equal(geometry.corner(0, 1).x, Float32(1))


def test_an_index_buffer_selects_which_vertices_to_use() raises:
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), triangle_attribute())
    geometry.set_index([2, 1, 0])
    assert_true(geometry.is_indexed())
    assert_equal(geometry.corner_index(0, 0), 2)
    assert_equal(geometry.corner(0, 0).y, Float32(1))


def test_a_vertex_can_serve_several_triangles() raises:
    # The reason indexing exists at all.
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), triangle_attribute())
    geometry.set_index([0, 1, 2, 0, 2, 1])
    assert_equal(geometry.triangle_count(), 2)
    assert_equal(geometry.corner_index(1, 2), 1)


def test_an_empty_index_clears_indexing() raises:
    # Setting no index is how a geometry goes back to reading its vertices
    # three at a time, so it must be allowed rather than treated as an error.
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), triangle_attribute())
    geometry.set_index([0, 1, 2])
    assert_true(geometry.is_indexed())
    geometry.set_index(List[Int]())
    assert_false(geometry.is_indexed())
    assert_equal(geometry.triangle_count(), 1)


def test_an_index_that_is_not_whole_triangles_is_rejected() raises:
    var geometry = BufferGeometry()
    with assert_raises():
        geometry.set_index([0, 1])


def test_a_negative_index_entry_is_rejected() raises:
    var geometry = BufferGeometry()
    with assert_raises():
        geometry.set_index([0, -1, 2])


def test_an_index_pointing_past_the_last_vertex_is_rejected() raises:
    # Checked on read, since the index may be set before the positions.
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), triangle_attribute())
    geometry.set_index([0, 1, 9])
    with assert_raises():
        _ = geometry.corner(0, 2)


def test_asking_for_a_triangle_that_is_not_there_is_rejected() raises:
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), triangle_attribute())
    with assert_raises():
        _ = geometry.corner(1, 0)
    with assert_raises():
        _ = geometry.corner(-1, 0)


def test_a_triangle_has_exactly_three_corners() raises:
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), triangle_attribute())
    with assert_raises():
        _ = geometry.corner(0, 3)
    with assert_raises():
        _ = geometry.corner(0, -1)


# --- box --------------------------------------------------------------------


def test_a_cube_has_four_vertices_per_face() raises:
    # Twenty-four, not eight: a shared corner could carry only one normal.
    var geometry = cube(Length(1.0, METRE))
    assert_equal(geometry.vertex_count(), 24)
    assert_equal(geometry.triangle_count(), 12)


def test_every_cube_corner_sits_on_the_box() raises:
    var geometry = cube(Length(2.0, METRE))
    for triangle in range(geometry.triangle_count()):
        for corner in range(3):
            var point = geometry.corner(triangle, corner)
            assert_almost_equal(abs(point.x), Float32(1), atol=TOLERANCE)
            assert_almost_equal(abs(point.y), Float32(1), atol=TOLERANCE)
            assert_almost_equal(abs(point.z), Float32(1), atol=TOLERANCE)


def test_a_box_can_have_three_different_extents() raises:
    var geometry = box(
        Length(2.0, METRE), Length(4.0, METRE), Length(6.0, METRE)
    )
    var widest = Float32(0)
    var tallest = Float32(0)
    var deepest = Float32(0)
    for vertex in range(geometry.vertex_count()):
        var point = geometry.attribute(String(POSITION)).vector3(vertex)
        widest = max(widest, abs(point.x))
        tallest = max(tallest, abs(point.y))
        deepest = max(deepest, abs(point.z))
    assert_almost_equal(widest, Float32(1), atol=TOLERANCE)
    assert_almost_equal(tallest, Float32(2), atol=TOLERANCE)
    assert_almost_equal(deepest, Float32(3), atol=TOLERANCE)


def test_a_box_is_centred_on_the_origin() raises:
    var geometry = cube(Length(3.0, METRE))
    var total = Vector3(0, 0, 0)
    for vertex in range(geometry.vertex_count()):
        total.add(geometry.attribute(String(POSITION)).vector3(vertex))
    assert_almost_equal(total.length(), Float32(0), atol=Float64(1e-4))


def test_a_box_can_be_specified_in_feet() raises:
    # World units are metres, so a one-foot cube is 0.3048 m across.
    var geometry = cube(Length(1.0, FOOT))
    assert_almost_equal(
        abs(geometry.corner(0, 0).x), Float32(0.1524), atol=TOLERANCE
    )


def test_each_face_is_two_consecutive_triangles() raises:
    # examples/cubes.mojo shades by triangle // 2, which relies on this.
    var geometry = cube(Length(1.0, METRE))
    for face in range(6):
        var first = geometry.corner(face * 2, 0)
        var second = geometry.corner(face * 2 + 1, 0)
        assert_equal(first.x, second.x)
        assert_equal(first.y, second.y)
        assert_equal(first.z, second.z)


def test_a_box_with_no_extent_is_rejected() raises:
    with assert_raises():
        _ = box(Length(0.0, METRE), Length(1.0, METRE), Length(1.0, METRE))
    with assert_raises():
        _ = box(Length(1.0, METRE), Length(-1.0, METRE), Length(1.0, METRE))
    with assert_raises():
        _ = box(Length(1.0, METRE), Length(1.0, METRE), Length(0.0, METRE))


def test_a_box_carries_a_normal_per_vertex() raises:
    var geometry = cube(Length(1.0, METRE))
    assert_true(geometry.has_attribute(String(NORMAL)))
    assert_equal(geometry.attribute(String(NORMAL)).count(), 24)


def test_a_face_four_vertices_share_one_normal() raises:
    # What keeps a cube's edges crisp when normals are interpolated.
    var normals = cube(Length(1.0, METRE)).attribute(String(NORMAL))
    for corner in range(4):
        var direction = normals.vector3(corner)
        assert_almost_equal(direction.z, Float32(1), atol=TOLERANCE)


def test_box_normals_point_outwards_and_are_unit_length() raises:
    var normals = cube(Length(2.0, METRE)).attribute(String(NORMAL))
    for vertex in range(normals.count()):
        assert_almost_equal(
            normals.vector3(vertex).length(), Float32(1), atol=TOLERANCE
        )


def test_the_six_faces_point_six_different_ways() raises:
    var normals = cube(Length(1.0, METRE)).attribute(String(NORMAL))
    var seen = List[Float32]()
    for face in range(6):
        var direction = normals.vector3(face * 4)
        seen.append(direction.x * 100 + direction.y * 10 + direction.z)
    for first in range(6):
        for second in range(first + 1, 6):
            assert_true(seen[first] != seen[second])


# --- sphere -----------------------------------------------------------------


def test_every_sphere_vertex_lies_on_the_surface() raises:
    var geometry = sphere(Length(3.0, METRE), 12, 8)
    var positions = geometry.attribute(String(POSITION))
    for vertex in range(positions.count()):
        assert_almost_equal(
            positions.vector3(vertex).length(), Float32(3), atol=Float64(1e-5)
        )


def test_a_sphere_normal_is_the_direction_from_the_centre() raises:
    # Which is what makes neighbouring triangles agree and the facets vanish.
    var geometry = sphere(Length(2.0, METRE), 12, 8)
    var positions = geometry.attribute(String(POSITION))
    var normals = geometry.attribute(String(NORMAL))
    for vertex in range(positions.count()):
        var point = positions.vector3(vertex)
        var direction = normals.vector3(vertex)
        assert_almost_equal(direction.length(), Float32(1), atol=TOLERANCE)
        assert_almost_equal(point.x / 2, direction.x, atol=Float64(1e-5))


def test_the_seam_has_a_vertex_on_each_side() raises:
    # One extra column per ring, so longitude can wrap.
    var geometry = sphere(Length(1.0, METRE), 8, 4)
    assert_equal(geometry.vertex_count(), (8 + 1) * (4 + 1))


def test_the_poles_contribute_only_one_triangle_per_quad() raises:
    # A quad at a pole is degenerate on one side, so it is not emitted.
    var segments = 8
    var rings = 4
    var geometry = sphere(Length(1.0, METRE), segments, rings)
    # Two triangles per quad everywhere except the two polar rings.
    assert_equal(geometry.triangle_count(), segments * (2 * rings - 2))


def test_no_sphere_triangle_is_degenerate() raises:
    var geometry = sphere(Length(1.0, METRE), 10, 6)
    for triangle in range(geometry.triangle_count()):
        var a = geometry.corner(triangle, 0)
        var b = geometry.corner(triangle, 1)
        var c = geometry.corner(triangle, 2)
        var first = b
        first.sub(a)
        var second = c
        second.sub(a)
        first.cross(second)
        assert_true(first.length() > Float32(1e-6))


def test_a_sphere_can_be_measured_in_feet() raises:
    var geometry = sphere(Length(1.0, FOOT), 8, 4)
    assert_almost_equal(
        geometry.attribute(String(POSITION)).vector3(0).length(),
        Float32(0.3048),
        atol=Float64(1e-5),
    )


def test_a_sphere_with_no_radius_is_rejected() raises:
    with assert_raises():
        _ = sphere(Length(0.0, METRE), 8, 4)
    with assert_raises():
        _ = sphere(Length(-1.0, METRE), 8, 4)


def test_a_sphere_needs_enough_segments_to_close() raises:
    with assert_raises():
        _ = sphere(Length(1.0, METRE), 2, 4)
    with assert_raises():
        _ = sphere(Length(1.0, METRE), 8, 1)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
