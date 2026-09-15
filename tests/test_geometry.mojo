# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `core.buffer_attribute`, `core.buffer_geometry` and the builders
in `geometries`.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from geometries.box import box, cube
from geometries.circle import circle, ring
from geometries.plane import plane
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
from units.si import Angle, DEGREE, FOOT, Length, METER, TURN

comptime TOLERANCE = Float64(1e-6)


def floats(values: List[Float32]) -> List[Float32]:
    """Return a copy of `values`, for building attributes inline."""
    return values.copy()


def assert_xy(got: Vector3, x: Float32, y: Float32) raises:
    """Assert a flat vertex lies at (x, y, 0), within tolerance."""
    assert_almost_equal(got.x, x, atol=Float64(1e-5))
    assert_almost_equal(got.y, y, atol=Float64(1e-5))
    assert_equal(got.z, Float32(0))


def assert_flat_and_facing_plus_z(geometry: BufferGeometry) raises:
    """Assert every vertex has z zero and the normal (0, 0, 1)."""
    ref positions = geometry.attribute_view(String(POSITION))
    ref normals = geometry.attribute_view(String(NORMAL))
    for vertex in range(geometry.vertex_count()):
        assert_equal(positions.vector3(vertex).z, Float32(0))
        var normal = normals.vector3(vertex)
        assert_equal(normal.x, Float32(0))
        assert_equal(normal.y, Float32(0))
        assert_equal(normal.z, Float32(1))


def assert_winds_counter_clockwise(geometry: BufferGeometry) raises:
    """Assert every triangle has positive signed area seen from +z."""
    for triangle in range(geometry.triangle_count()):
        var a = geometry.corner(triangle, 0)
        var b = geometry.corner(triangle, 1)
        var c = geometry.corner(triangle, 2)
        var area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        assert_true(area > 0, "a triangle winds clockwise")


def assert_texture_coordinates_in_range(geometry: BufferGeometry) raises:
    """Assert every texture coordinate lies between zero and one."""
    ref uvs = geometry.attribute_view(String(UV))
    for vertex in range(geometry.vertex_count()):
        for axis in range(2):
            var value = uvs.component(vertex, axis)
            assert_true(value >= Float32(-1e-6) and value <= Float32(1 + 1e-6))


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
        _ = geometry.clone_attribute(String("uv"))
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
    var geometry = cube(Length(1.0, METER))
    assert_equal(geometry.vertex_count(), 24)
    assert_equal(geometry.triangle_count(), 12)


def test_every_cube_corner_sits_on_the_box() raises:
    var geometry = cube(Length(2.0, METER))
    for triangle in range(geometry.triangle_count()):
        for corner in range(3):
            var point = geometry.corner(triangle, corner)
            assert_almost_equal(abs(point.x), Float32(1), atol=TOLERANCE)
            assert_almost_equal(abs(point.y), Float32(1), atol=TOLERANCE)
            assert_almost_equal(abs(point.z), Float32(1), atol=TOLERANCE)


def test_a_box_can_have_three_different_extents() raises:
    var geometry = box(
        Length(2.0, METER), Length(4.0, METER), Length(6.0, METER)
    )
    var widest = Float32(0)
    var tallest = Float32(0)
    var deepest = Float32(0)
    for vertex in range(geometry.vertex_count()):
        var point = geometry.attribute_view(String(POSITION)).vector3(vertex)
        widest = max(widest, abs(point.x))
        tallest = max(tallest, abs(point.y))
        deepest = max(deepest, abs(point.z))
    assert_almost_equal(widest, Float32(1), atol=TOLERANCE)
    assert_almost_equal(tallest, Float32(2), atol=TOLERANCE)
    assert_almost_equal(deepest, Float32(3), atol=TOLERANCE)


def test_a_box_is_centered_on_the_origin() raises:
    var geometry = cube(Length(3.0, METER))
    var total = Vector3(0, 0, 0)
    for vertex in range(geometry.vertex_count()):
        total.add(geometry.attribute_view(String(POSITION)).vector3(vertex))
    assert_almost_equal(total.length(), Float32(0), atol=Float64(1e-4))


def test_a_box_can_be_specified_in_feet() raises:
    # World units are meters, so a one-foot cube is 0.3048 m across.
    var geometry = cube(Length(1.0, FOOT))
    assert_almost_equal(
        abs(geometry.corner(0, 0).x), Float32(0.1524), atol=TOLERANCE
    )


def test_each_face_is_two_consecutive_triangles() raises:
    # examples/cubes.mojo shades by triangle // 2, which relies on this.
    var geometry = cube(Length(1.0, METER))
    for face in range(6):
        var first = geometry.corner(face * 2, 0)
        var second = geometry.corner(face * 2 + 1, 0)
        assert_equal(first.x, second.x)
        assert_equal(first.y, second.y)
        assert_equal(first.z, second.z)


def test_a_box_with_no_extent_is_rejected() raises:
    with assert_raises():
        _ = box(Length(0.0, METER), Length(1.0, METER), Length(1.0, METER))
    with assert_raises():
        _ = box(Length(1.0, METER), Length(-1.0, METER), Length(1.0, METER))
    with assert_raises():
        _ = box(Length(1.0, METER), Length(1.0, METER), Length(0.0, METER))


def test_a_box_carries_a_normal_per_vertex() raises:
    var geometry = cube(Length(1.0, METER))
    assert_true(geometry.has_attribute(String(NORMAL)))
    assert_equal(geometry.attribute_view(String(NORMAL)).count(), 24)


def test_a_face_four_vertices_share_one_normal() raises:
    # What keeps a cube's edges crisp when normals are interpolated.
    var geometry = cube(Length(1.0, METER))
    ref normals = geometry.attribute_view(String(NORMAL))
    for corner in range(4):
        var direction = normals.vector3(corner)
        assert_almost_equal(direction.z, Float32(1), atol=TOLERANCE)


def test_box_normals_point_outwards_and_are_unit_length() raises:
    var geometry = cube(Length(2.0, METER))
    ref normals = geometry.attribute_view(String(NORMAL))
    for vertex in range(normals.count()):
        assert_almost_equal(
            normals.vector3(vertex).length(), Float32(1), atol=TOLERANCE
        )


def test_the_six_faces_point_six_different_ways() raises:
    var geometry = cube(Length(1.0, METER))
    ref normals = geometry.attribute_view(String(NORMAL))
    var seen = List[Float32]()
    for face in range(6):
        var direction = normals.vector3(face * 4)
        seen.append(direction.x * 100 + direction.y * 10 + direction.z)
    for first in range(6):
        for second in range(first + 1, 6):
            assert_true(seen[first] != seen[second])


# --- sphere -----------------------------------------------------------------


def test_every_sphere_vertex_lies_on_the_surface() raises:
    var geometry = sphere(Length(3.0, METER), 12, 8)
    ref positions = geometry.attribute_view(String(POSITION))
    for vertex in range(positions.count()):
        assert_almost_equal(
            positions.vector3(vertex).length(), Float32(3), atol=Float64(1e-5)
        )


def test_a_sphere_normal_is_the_direction_from_the_center() raises:
    # Which is what makes neighboring triangles agree and the facets vanish.
    var geometry = sphere(Length(2.0, METER), 12, 8)
    ref positions = geometry.attribute_view(String(POSITION))
    ref normals = geometry.attribute_view(String(NORMAL))
    for vertex in range(positions.count()):
        var point = positions.vector3(vertex)
        var direction = normals.vector3(vertex)
        assert_almost_equal(direction.length(), Float32(1), atol=TOLERANCE)
        assert_almost_equal(point.x / 2, direction.x, atol=Float64(1e-5))


def test_the_seam_has_a_vertex_on_each_side() raises:
    # One extra column per ring, so longitude can wrap.
    var geometry = sphere(Length(1.0, METER), 8, 4)
    assert_equal(geometry.vertex_count(), (8 + 1) * (4 + 1))


def test_the_poles_contribute_only_one_triangle_per_quad() raises:
    # A quad at a pole is degenerate on one side, so it is not emitted.
    var segments = 8
    var rings = 4
    var geometry = sphere(Length(1.0, METER), segments, rings)
    # Two triangles per quad everywhere except the two polar rings.
    assert_equal(geometry.triangle_count(), segments * (2 * rings - 2))


def test_no_sphere_triangle_is_degenerate() raises:
    var geometry = sphere(Length(1.0, METER), 10, 6)
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
        geometry.attribute_view(String(POSITION)).vector3(0).length(),
        Float32(0.3048),
        atol=Float64(1e-5),
    )


def test_a_sphere_with_no_radius_is_rejected() raises:
    with assert_raises():
        _ = sphere(Length(0.0, METER), 8, 4)
    with assert_raises():
        _ = sphere(Length(-1.0, METER), 8, 4)


def test_a_sphere_needs_enough_segments_to_close() raises:
    with assert_raises():
        _ = sphere(Length(1.0, METER), 2, 4)
    with assert_raises():
        _ = sphere(Length(1.0, METER), 8, 1)


def test_cloning_an_attribute_gives_an_independent_copy() raises:
    # The deliberate-copy half of the pair. Replacing the geometry's attribute
    # afterwards must not reach through into the clone, which is the whole
    # difference between this and `attribute_view`.
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), triangle_attribute())
    var taken = geometry.clone_attribute(String(POSITION))
    assert_equal(taken.count(), 3)

    var replacement = List[Float32]()
    for _ in range(9):
        replacement.append(99.0)
    geometry.set_attribute(String(POSITION), BufferAttribute(replacement^, 3))

    assert_equal(geometry.attribute_view(String(POSITION)).vector3(0).x, 99.0)
    # The clone still holds what it held when it was taken.
    assert_equal(taken.vector3(0).x, Float32(0))


def test_a_geometry_counts_the_attributes_it_holds() raises:
    var geometry = BufferGeometry()
    assert_equal(geometry.attribute_count(), 0)
    geometry.set_attribute(String(POSITION), triangle_attribute())
    assert_equal(geometry.attribute_count(), 1)
    geometry.set_attribute(String(NORMAL), triangle_attribute())
    assert_equal(geometry.attribute_count(), 2)
    # Replacing a name that is already there does not add a second entry.
    geometry.set_attribute(String(POSITION), triangle_attribute())
    assert_equal(geometry.attribute_count(), 2)


# --- texture coordinates ----------------------------------------------------


def test_a_box_gives_every_face_the_whole_image() raises:
    var geometry = cube(Length(1.0, METER))
    assert_true(geometry.has_attribute(String(UV)))
    ref uvs = geometry.attribute_view(String(UV))
    assert_equal(uvs.count(), 24)
    # Each face's four corners run (0,0) (1,0) (1,1) (0,1) counter-clockwise
    # from its bottom-left seen from outside.
    for face in range(6):
        var base = face * 4
        assert_equal(uvs.component(base, 0), Float32(0))
        assert_equal(uvs.component(base, 1), Float32(0))
        assert_equal(uvs.component(base + 1, 0), Float32(1))
        assert_equal(uvs.component(base + 1, 1), Float32(0))
        assert_equal(uvs.component(base + 2, 0), Float32(1))
        assert_equal(uvs.component(base + 2, 1), Float32(1))
        assert_equal(uvs.component(base + 3, 0), Float32(0))
        assert_equal(uvs.component(base + 3, 1), Float32(1))


def test_every_box_texture_coordinate_is_in_range() raises:
    var geometry = cube(Length(2.0, METER))
    ref uvs = geometry.attribute_view(String(UV))
    for vertex in range(uvs.count()):
        assert_true(uvs.component(vertex, 0) >= 0)
        assert_true(uvs.component(vertex, 0) <= 1)
        assert_true(uvs.component(vertex, 1) >= 0)
        assert_true(uvs.component(vertex, 1) <= 1)


def test_a_sphere_wraps_u_once_around_the_equator() raises:
    var geometry = sphere(Length(1.0, METER), 8, 4)
    assert_true(geometry.has_attribute(String(UV)))
    ref uvs = geometry.attribute_view(String(UV))
    # One row is width_segments + 1 vertices, the last repeating the first in
    # space but not in u -- which is the whole reason the seam is duplicated.
    assert_equal(uvs.component(0, 0), Float32(0))
    assert_equal(uvs.component(8, 0), Float32(1))
    ref positions = geometry.attribute_view(String(POSITION))
    var start = positions.vector3(0)
    var wrapped = positions.vector3(8)
    assert_almost_equal(start.x, wrapped.x, atol=Float64(1e-5))
    assert_almost_equal(start.z, wrapped.z, atol=Float64(1e-5))


def test_a_sphere_runs_v_from_one_at_the_north_pole_to_zero_at_the_south() raises:
    # Texture space has its origin at the bottom while `ring` counts down from
    # the top, so v is the complement of the ring fraction.
    var geometry = sphere(Length(1.0, METER), 8, 4)
    ref uvs = geometry.attribute_view(String(UV))
    assert_equal(uvs.component(0, 1), Float32(1))
    # Last row: ring == height_segments, so the final vertex.
    assert_equal(uvs.component(uvs.count() - 1, 1), Float32(0))


def test_sphere_texture_coordinates_cover_the_whole_range() raises:
    var geometry = sphere(Length(1.0, METER), 12, 6)
    ref uvs = geometry.attribute_view(String(UV))
    var widest = Float32(0)
    var tallest = Float32(0)
    for vertex in range(uvs.count()):
        widest = max(widest, uvs.component(vertex, 0))
        tallest = max(tallest, uvs.component(vertex, 1))
    assert_equal(widest, Float32(1))
    assert_equal(tallest, Float32(1))


# --- plane -------------------------------------------------------------------


def test_a_plane_has_a_vertex_per_grid_point() raises:
    var sheet = plane(Length(2.0, METER), Length(1.0, METER), 3, 2)
    assert_equal(sheet.vertex_count(), 12)
    assert_equal(sheet.triangle_count(), 12)
    assert_equal(
        plane(Length(1.0, METER), Length(1.0, METER)).triangle_count(), 2
    )


def test_a_plane_is_flat_and_faces_plus_z() raises:
    var sheet = plane(Length(2.0, METER), Length(1.0, METER), 3, 2)
    ref normals = sheet.attribute_view(String(NORMAL))
    for vertex in range(sheet.vertex_count()):
        assert_equal(
            sheet.attribute_view(String(POSITION)).vector3(vertex).z, Float32(0)
        )
        var normal = normals.vector3(vertex)
        assert_equal(normal.x, Float32(0))
        assert_equal(normal.y, Float32(0))
        assert_equal(normal.z, Float32(1))


def test_a_plane_is_centered_and_spans_its_extents() raises:
    var sheet = plane(Length(2.0, METER), Length(1.0, METER), 4, 3)
    ref positions = sheet.attribute_view(String(POSITION))
    var left = Float32(0)
    var right = Float32(0)
    var top = Float32(0)
    var bottom = Float32(0)
    for vertex in range(sheet.vertex_count()):
        var p = positions.vector3(vertex)
        left = min(left, p.x)
        right = max(right, p.x)
        bottom = min(bottom, p.y)
        top = max(top, p.y)
    assert_almost_equal(left, Float32(-1), atol=TOLERANCE)
    assert_almost_equal(right, Float32(1), atol=TOLERANCE)
    assert_almost_equal(bottom, Float32(-0.5), atol=TOLERANCE)
    assert_almost_equal(top, Float32(0.5), atol=TOLERANCE)


def test_a_plane_covers_the_whole_image_once_from_the_top_left() raises:
    var sheet = plane(Length(2.0, METER), Length(1.0, METER), 2, 2)
    ref uvs = sheet.attribute_view(String(UV))
    ref positions = sheet.attribute_view(String(POSITION))
    # The first vertex is the top-left corner: u is zero, v is one.
    assert_equal(uvs.component(0, 0), Float32(0))
    assert_equal(uvs.component(0, 1), Float32(1))
    assert_almost_equal(positions.vector3(0).y, Float32(0.5), atol=TOLERANCE)
    # The last is the bottom-right: u is one, v is zero.
    var last = sheet.vertex_count() - 1
    assert_equal(uvs.component(last, 0), Float32(1))
    assert_equal(uvs.component(last, 1), Float32(0))


def test_plane_triangles_wind_counter_clockwise_from_the_front() raises:
    var sheet = plane(Length(2.0, METER), Length(1.0, METER), 3, 2)
    for triangle in range(sheet.triangle_count()):
        var a = sheet.corner(triangle, 0)
        var b = sheet.corner(triangle, 1)
        var c = sheet.corner(triangle, 2)
        var area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        assert_true(area > 0, "a plane triangle winds clockwise")


def test_a_plane_can_be_measured_in_feet() raises:
    var sheet = plane(Length(2.0, FOOT), Length(2.0, FOOT))
    var corner = sheet.attribute_view(String(POSITION)).vector3(0)
    assert_almost_equal(corner.x, Float32(-0.3048), atol=TOLERANCE)


def test_a_plane_needs_positive_extents_and_segments() raises:
    with assert_raises():
        _ = plane(Length(0.0, METER), Length(1.0, METER))
    with assert_raises():
        _ = plane(Length(1.0, METER), Length(-1.0, METER))
    with assert_raises():
        _ = plane(Length(1.0, METER), Length(1.0, METER), 0, 1)
    with assert_raises():
        _ = plane(Length(1.0, METER), Length(1.0, METER), 1, 0)


# --- circle -----------------------------------------------------------------


def test_a_circle_is_a_fan_around_a_center_vertex() raises:
    var disk = circle(Length(1.0, METER), 8)
    # The center, then a rim of nine: one per segment and one to close.
    assert_equal(disk.vertex_count(), 8 + 2)
    assert_equal(disk.triangle_count(), 8)
    assert_xy(disk.attribute_view(String(POSITION)).vector3(0), 0, 0)
    for triangle in range(disk.triangle_count()):
        assert_equal(disk.corner_index(triangle, 2), 0)


def test_a_circle_is_flat_and_faces_plus_z() raises:
    assert_flat_and_facing_plus_z(circle(Length(1.0, METER), 8))


def test_every_circle_rim_vertex_lies_on_the_rim() raises:
    var disk = circle(Length(3.0, METER), 12)
    ref positions = disk.attribute_view(String(POSITION))
    for vertex in range(1, disk.vertex_count()):
        assert_almost_equal(
            positions.vector3(vertex).length(), Float32(3), atol=Float64(1e-5)
        )


def test_a_circle_starts_at_plus_x_and_runs_counter_clockwise() raises:
    var disk = circle(Length(2.0, METER), 4)
    ref positions = disk.attribute_view(String(POSITION))
    # Rim vertices at 0, 90, 180 and 270 degrees, then the seam.
    assert_xy(positions.vector3(1), 2, 0)
    assert_xy(positions.vector3(2), 0, 2)
    assert_xy(positions.vector3(3), -2, 0)
    assert_xy(positions.vector3(4), 0, -2)
    # The last rim vertex sits on the first, as the sphere's seam does.
    assert_xy(positions.vector3(5), 2, 0)


def test_circle_triangles_wind_counter_clockwise_from_the_front() raises:
    assert_winds_counter_clockwise(circle(Length(1.0, METER), 7))


def test_a_circle_maps_its_bounding_square_onto_the_image() raises:
    var disk = circle(Length(2.0, METER), 4)
    ref uvs = disk.attribute_view(String(UV))
    # The center is the middle of the image.
    assert_equal(uvs.component(0, 0), Float32(0.5))
    assert_equal(uvs.component(0, 1), Float32(0.5))
    # The +x rim vertex touches the right edge, halfway up.
    assert_almost_equal(uvs.component(1, 0), Float32(1), atol=TOLERANCE)
    assert_almost_equal(uvs.component(1, 1), Float32(0.5), atol=TOLERANCE)
    # The +y rim vertex touches the top edge, halfway across.
    assert_almost_equal(uvs.component(2, 0), Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(uvs.component(2, 1), Float32(1), atol=TOLERANCE)
    assert_texture_coordinates_in_range(disk)


def test_a_circle_with_a_partial_sweep_is_a_pie_slice() raises:
    var slice = circle(
        Length(1.0, METER), 4, Angle(90.0, DEGREE), Angle(180.0, DEGREE)
    )
    assert_equal(slice.triangle_count(), 4)
    ref positions = slice.attribute_view(String(POSITION))
    # Four segments from +y round through -x to -y.
    assert_xy(positions.vector3(1), 0, 1)
    assert_xy(positions.vector3(3), -1, 0)
    assert_xy(positions.vector3(5), 0, -1)
    assert_winds_counter_clockwise(slice)


def test_a_full_turn_in_degrees_closes_a_circle() raises:
    var disk = circle(
        Length(1.0, METER), 8, Angle(0.0, DEGREE), Angle(360.0, DEGREE)
    )
    assert_xy(disk.attribute_view(String(POSITION)).vector3(9), 1, 0)


def test_a_circle_can_be_measured_in_feet() raises:
    var disk = circle(Length(1.0, FOOT), 8)
    assert_almost_equal(
        disk.attribute_view(String(POSITION)).vector3(1).x,
        Float32(0.3048),
        atol=Float64(1e-5),
    )


def test_a_circle_with_no_radius_is_rejected() raises:
    with assert_raises():
        _ = circle(Length(0.0, METER))
    with assert_raises():
        _ = circle(Length(-1.0, METER))


def test_a_circle_needs_three_segments() raises:
    with assert_raises():
        _ = circle(Length(1.0, METER), 2)


def test_a_sweep_must_be_positive_and_at_most_a_turn() raises:
    var radius = Length(1.0, METER)
    var start = Angle(0.0, DEGREE)
    with assert_raises():
        _ = circle(radius, 8, start, Angle(0.0, DEGREE))
    with assert_raises():
        _ = circle(radius, 8, start, Angle(-90.0, DEGREE))
    with assert_raises():
        _ = circle(radius, 8, start, Angle(361.0, DEGREE))
    with assert_raises():
        _ = ring(radius, Length(2.0, METER), 8, 1, start, Angle(2.0, TURN))
    with assert_raises():
        _ = ring(radius, Length(2.0, METER), 8, 1, start, Angle(0.0, TURN))


# --- ring -------------------------------------------------------------------


def test_a_ring_has_a_row_of_vertices_per_radius() raises:
    var washer = ring(Length(1.0, METER), Length(2.0, METER), 8, 3)
    assert_equal(washer.vertex_count(), (8 + 1) * (3 + 1))
    assert_equal(washer.triangle_count(), 2 * 8 * 3)
    assert_equal(
        ring(Length(1.0, METER), Length(2.0, METER)).triangle_count(), 64
    )


def test_a_ring_is_flat_and_faces_plus_z() raises:
    assert_flat_and_facing_plus_z(
        ring(Length(1.0, METER), Length(2.0, METER), 8, 2)
    )


def test_ring_rows_step_from_the_inner_radius_to_the_outer() raises:
    var washer = ring(Length(1.0, METER), Length(3.0, METER), 6, 4)
    ref positions = washer.attribute_view(String(POSITION))
    for row in range(5):
        var expected = Float32(1) + Float32(row) * Float32(0.5)
        for column in range(7):
            assert_almost_equal(
                positions.vector3(row * 7 + column).length(),
                expected,
                atol=Float64(1e-5),
            )


def test_a_ring_starts_at_plus_x_and_closes_at_the_seam() raises:
    var washer = ring(Length(1.0, METER), Length(2.0, METER), 4, 1)
    ref positions = washer.attribute_view(String(POSITION))
    # The inner row first: 0, 90, 180 and 270 degrees, then the seam.
    assert_xy(positions.vector3(0), 1, 0)
    assert_xy(positions.vector3(1), 0, 1)
    assert_xy(positions.vector3(4), 1, 0)
    # Then the outer row.
    assert_xy(positions.vector3(5), 2, 0)
    assert_xy(positions.vector3(7), -2, 0)


def test_ring_triangles_wind_counter_clockwise_from_the_front() raises:
    assert_winds_counter_clockwise(
        ring(Length(1.0, METER), Length(2.0, METER), 5, 2)
    )


def test_no_ring_triangle_is_degenerate() raises:
    var washer = ring(Length(1.0, METER), Length(2.0, METER), 6, 2)
    for triangle in range(washer.triangle_count()):
        var a = washer.corner(triangle, 0)
        var first = washer.corner(triangle, 1)
        first.sub(a)
        var second = washer.corner(triangle, 2)
        second.sub(a)
        first.cross(second)
        assert_true(first.length() > Float32(1e-6))


def test_a_ring_maps_the_outer_bounding_square_onto_the_image() raises:
    var washer = ring(Length(1.0, METER), Length(2.0, METER), 4, 1)
    ref uvs = washer.attribute_view(String(UV))
    # The inner vertex at +x is three quarters of the way across, halfway up.
    assert_almost_equal(uvs.component(0, 0), Float32(0.75), atol=TOLERANCE)
    assert_almost_equal(uvs.component(0, 1), Float32(0.5), atol=TOLERANCE)
    # The outer vertex at +x touches the right edge.
    assert_almost_equal(uvs.component(5, 0), Float32(1), atol=TOLERANCE)
    assert_texture_coordinates_in_range(washer)


def test_a_ring_with_a_partial_sweep_is_an_arc() raises:
    var arc = ring(
        Length(1.0, METER),
        Length(2.0, METER),
        4,
        1,
        Angle(0.0, DEGREE),
        Angle(90.0, DEGREE),
    )
    ref positions = arc.attribute_view(String(POSITION))
    assert_xy(positions.vector3(0), 1, 0)
    # Each row ends at +y: the inner row at its radius, the outer at its.
    assert_xy(positions.vector3(4), 0, 1)
    assert_xy(positions.vector3(9), 0, 2)
    assert_winds_counter_clockwise(arc)


def test_a_ring_can_be_measured_in_feet() raises:
    var washer = ring(Length(1.0, FOOT), Length(2.0, FOOT), 8)
    assert_almost_equal(
        washer.attribute_view(String(POSITION)).vector3(0).x,
        Float32(0.3048),
        atol=Float64(1e-5),
    )


def test_a_ring_needs_a_hole_inside_its_rim() raises:
    with assert_raises():
        _ = ring(Length(0.0, METER), Length(1.0, METER))
    with assert_raises():
        _ = ring(Length(-1.0, METER), Length(1.0, METER))
    with assert_raises():
        _ = ring(Length(1.0, METER), Length(1.0, METER))
    with assert_raises():
        _ = ring(Length(2.0, METER), Length(1.0, METER))


def test_a_ring_needs_enough_segments() raises:
    with assert_raises():
        _ = ring(Length(1.0, METER), Length(2.0, METER), 2, 1)
    with assert_raises():
        _ = ring(Length(1.0, METER), Length(2.0, METER), 8, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
