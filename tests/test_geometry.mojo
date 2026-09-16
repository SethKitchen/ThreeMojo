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
from geometries.cylinder import cone, cylinder
from geometries.plane import plane
from geometries.sphere import sphere
from geometries.torus import torus, torus_knot
from math.vector3 import Vector3
from std.math import cos, pi, sin, sqrt
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


def signed_area(geometry: BufferGeometry) raises -> Float32:
    """Return the summed signed area of every triangle, seen from +z."""
    var total = Float32(0)
    for triangle in range(geometry.triangle_count()):
        var a = geometry.corner(triangle, 0)
        var b = geometry.corner(triangle, 1)
        var c = geometry.corner(triangle, 2)
        total += ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) / 2
    return total


def surface_area(geometry: BufferGeometry) raises -> Float32:
    """Return the summed area of every triangle, in three dimensions."""
    var total = Float32(0)
    for triangle in range(geometry.triangle_count()):
        var a = geometry.corner(triangle, 0)
        var first = geometry.corner(triangle, 1)
        first.sub(a)
        var second = geometry.corner(triangle, 2)
        second.sub(a)
        first.cross(second)
        total += first.length() / 2
    return total


def assert_faces_wind_with_their_normals(geometry: BufferGeometry) raises:
    """Assert every triangle's winding faces the way its corners' normals
    point: the cross product of its edges has a positive dot with the sum
    of the three normals."""
    ref normals = geometry.attribute_view(String(NORMAL))
    for triangle in range(geometry.triangle_count()):
        var a = geometry.corner(triangle, 0)
        var first = geometry.corner(triangle, 1)
        first.sub(a)
        var second = geometry.corner(triangle, 2)
        second.sub(a)
        first.cross(second)
        var stated = normals.vector3(geometry.corner_index(triangle, 0))
        stated.add(normals.vector3(geometry.corner_index(triangle, 1)))
        stated.add(normals.vector3(geometry.corner_index(triangle, 2)))
        assert_true(first.dot(stated) > 0, "a face winds against its normals")


def assert_no_degenerate_triangle(geometry: BufferGeometry) raises:
    """Assert every triangle has some area."""
    for triangle in range(geometry.triangle_count()):
        var a = geometry.corner(triangle, 0)
        var first = geometry.corner(triangle, 1)
        first.sub(a)
        var second = geometry.corner(triangle, 2)
        second.sub(a)
        first.cross(second)
        assert_true(first.length() > Float32(1e-6), "a triangle has no area")


def assert_unit(normal: Vector3) raises:
    """Assert a normal has unit length."""
    assert_almost_equal(normal.length(), Float32(1), atol=Float64(1e-5))


def assert_xyz(got: Vector3, x: Float32, y: Float32, z: Float32) raises:
    """Assert a point lies at (x, y, z), within a hundred-thousandth."""
    assert_almost_equal(got.x, x, atol=Float64(1e-5))
    assert_almost_equal(got.y, y, atol=Float64(1e-5))
    assert_almost_equal(got.z, z, atol=Float64(1e-5))


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


def test_a_circles_area_is_its_fan_of_triangles() raises:
    # N triangles of radius r over a sweep cover N / 2 * r^2 * sin(sweep / N),
    # which tends to pi r^2 as N grows. Twelve segments at a radius of one
    # and a half: 6 * 2.25 * sin(30 degrees).
    var disk = circle(Length(1.5, METER), 12)
    assert_almost_equal(signed_area(disk), Float32(6.75), atol=Float64(1e-4))
    # Four segments over a half turn at a radius of two: 2 * 4 * sin(45).
    var half = circle(
        Length(2.0, METER), 4, Angle(0.0, DEGREE), Angle(180.0, DEGREE)
    )
    assert_almost_equal(
        signed_area(half), Float32(8 * 0.70710678), atol=Float64(1e-4)
    )


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
    assert_no_degenerate_triangle(
        ring(Length(1.0, METER), Length(2.0, METER), 6, 2)
    )


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


def test_a_rings_area_is_the_outer_fan_less_the_inner() raises:
    # N cells round cover N / 2 * (R^2 - r^2) * sin(sweep / N), however
    # many rows they are cut into. Eight cells from one to two:
    # 4 * 3 * sin(45 degrees).
    var expected = Float32(12 * 0.70710678)
    assert_almost_equal(
        signed_area(ring(Length(1.0, METER), Length(2.0, METER), 8, 1)),
        expected,
        atol=Float64(1e-4),
    )
    assert_almost_equal(
        signed_area(ring(Length(1.0, METER), Length(2.0, METER), 8, 3)),
        expected,
        atol=Float64(1e-4),
    )
    # Three cells over a quarter turn from one to three: 1.5 * 8 * sin(30).
    var arc = ring(
        Length(1.0, METER),
        Length(3.0, METER),
        3,
        2,
        Angle(30.0, DEGREE),
        Angle(90.0, DEGREE),
    )
    assert_almost_equal(signed_area(arc), Float32(6), atol=Float64(1e-4))


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


# --- cylinder ---------------------------------------------------------------


def a_can(radial: Int = 8, rows: Int = 2) raises -> BufferGeometry:
    """Return a cylinder of radius one and height two."""
    return cylinder(
        Length(1.0, METER), Length(1.0, METER), Length(2.0, METER), radial, rows
    )


def test_a_cylinder_is_a_bent_grid_with_a_cap_at_each_end() raises:
    var can = a_can(8, 2)
    # Three rows of nine down the side, then each cap: eight centers and a
    # rim of nine, as three.js emits them.
    assert_equal(can.vertex_count(), 9 * 3 + 2 * (8 + 9))
    assert_equal(can.triangle_count(), 2 * 8 * 2 + 8 + 8)
    assert_equal(
        cylinder(
            Length(1.0, METER), Length(1.0, METER), Length(1.0, METER)
        ).triangle_count(),
        2 * 32 + 64,
    )


def test_a_cylinders_side_lies_at_its_radius_between_its_ends() raises:
    var can = a_can(8, 2)
    ref positions = can.attribute_view(String(POSITION))
    for vertex in range(27):
        var p = positions.vector3(vertex)
        assert_almost_equal(
            sqrt(p.x * p.x + p.z * p.z), Float32(1), atol=Float64(1e-5)
        )
        assert_true(p.y >= -1 and p.y <= 1)
    # Rows run from the top down.
    assert_equal(positions.vector3(0).y, Float32(1))
    assert_equal(positions.vector3(9).y, Float32(0))
    assert_equal(positions.vector3(18).y, Float32(-1))


def test_a_cylinder_starts_at_plus_z_and_runs_toward_plus_x() raises:
    # three.js's convention, and not the circle's: x = r sin, z = r cos.
    var can = cylinder(
        Length(2.0, METER), Length(2.0, METER), Length(1.0, METER), 4, 1
    )
    ref positions = can.attribute_view(String(POSITION))
    var first = positions.vector3(0)
    assert_almost_equal(first.x, Float32(0), atol=Float64(1e-5))
    assert_almost_equal(first.z, Float32(2), atol=Float64(1e-5))
    var quarter = positions.vector3(1)
    assert_almost_equal(quarter.x, Float32(2), atol=Float64(1e-5))
    assert_almost_equal(quarter.z, Float32(0), atol=Float64(1e-5))
    var half = positions.vector3(2)
    assert_almost_equal(half.z, Float32(-2), atol=Float64(1e-5))
    # The seam: the last column sits on the first.
    var seam = positions.vector3(4)
    assert_almost_equal(seam.x, Float32(0), atol=Float64(1e-5))
    assert_almost_equal(seam.z, Float32(2), atol=Float64(1e-5))


def test_cylinder_normals_are_horizontal_on_the_side_and_axial_on_the_caps() raises:
    var can = a_can(8, 1)
    ref normals = can.attribute_view(String(NORMAL))
    for vertex in range(18):
        var n = normals.vector3(vertex)
        assert_unit(n)
        assert_equal(n.y, Float32(0))
    # The first side normal points along +z, where the sweep starts.
    assert_almost_equal(normals.vector3(0).z, Float32(1), atol=Float64(1e-6))
    # Top cap: eight centers and nine rim vertices, all facing +y.
    for vertex in range(18, 35):
        var n = normals.vector3(vertex)
        assert_equal(n.x, Float32(0))
        assert_equal(n.y, Float32(1))
    for vertex in range(35, 52):
        assert_equal(normals.vector3(vertex).y, Float32(-1))


def test_a_cylinder_maps_u_around_and_v_down_and_each_cap_to_a_square() raises:
    var can = cylinder(
        Length(2.0, METER), Length(2.0, METER), Length(1.0, METER), 4, 1
    )
    ref uvs = can.attribute_view(String(UV))
    ref positions = can.attribute_view(String(POSITION))
    # The side: u from zero at the first column to one at the seam, v from
    # one at the top row to zero at the bottom.
    assert_equal(uvs.component(0, 0), Float32(0))
    assert_equal(uvs.component(0, 1), Float32(1))
    assert_equal(uvs.component(4, 0), Float32(1))
    assert_equal(uvs.component(5, 1), Float32(0))
    # The top cap's centers are the middle of the image.
    assert_equal(uvs.component(10, 0), Float32(0.5))
    assert_equal(uvs.component(10, 1), Float32(0.5))
    assert_equal(positions.vector3(10).y, Float32(0.5))
    # Its rim starts at +z, which maps to the right edge halfway up.
    assert_almost_equal(uvs.component(14, 0), Float32(1), atol=TOLERANCE)
    assert_almost_equal(uvs.component(14, 1), Float32(0.5), atol=TOLERANCE)
    # The bottom cap is seen from below, so its v runs the other way: the
    # +x rim vertex maps to the bottom edge.
    assert_almost_equal(uvs.component(24, 0), Float32(0.5), atol=TOLERANCE)
    assert_almost_equal(uvs.component(24, 1), Float32(0), atol=TOLERANCE)
    assert_almost_equal(positions.vector3(24).x, Float32(2), atol=TOLERANCE)
    assert_texture_coordinates_in_range(can)


def test_every_cylinder_face_winds_outward() raises:
    assert_faces_wind_with_their_normals(a_can(8, 2))
    assert_no_degenerate_triangle(a_can(8, 2))


def test_a_cylinders_area_is_its_facets_and_its_caps() raises:
    # Eight flat facets of chord 2 r sin(pi / 8) by the height, and two fans
    # of eight triangles each.
    var can = a_can(8, 1)
    var chord = 2 * sin(Float32(pi) / 8)
    var side = 8 * chord * 2
    var caps = 2 * (Float32(8) / 2 * sin(Float32(pi) / 4))
    assert_almost_equal(surface_area(can), side + caps, atol=Float64(1e-4))


def test_a_frustum_leans_its_normals_with_its_side() raises:
    # Top radius one, bottom radius two, height one: the side leans out at
    # 45 degrees on its way down, and so does every normal, up.
    var bucket = cylinder(
        Length(1.0, METER), Length(2.0, METER), Length(1.0, METER), 8, 1
    )
    ref normals = bucket.attribute_view(String(NORMAL))
    var lean = Float32(0.70710678)
    for vertex in range(18):
        var n = normals.vector3(vertex)
        assert_unit(n)
        assert_almost_equal(n.y, lean, atol=Float64(1e-5))
    assert_almost_equal(normals.vector3(0).z, lean, atol=Float64(1e-5))
    ref positions = bucket.attribute_view(String(POSITION))
    assert_almost_equal(positions.vector3(0).z, Float32(1), atol=TOLERANCE)
    assert_almost_equal(positions.vector3(9).z, Float32(2), atol=TOLERANCE)
    assert_faces_wind_with_their_normals(bucket)


def test_an_open_cylinder_has_no_caps() raises:
    var pipe = cylinder(
        Length(1.0, METER),
        Length(1.0, METER),
        Length(2.0, METER),
        8,
        1,
        open_ended=True,
    )
    assert_equal(pipe.vertex_count(), 9 * 2)
    assert_equal(pipe.triangle_count(), 2 * 8)


def test_a_partial_sweep_makes_a_section() raises:
    var half = cylinder(
        Length(1.0, METER),
        Length(1.0, METER),
        Length(1.0, METER),
        4,
        1,
        False,
        Angle(0.0, DEGREE),
        Angle(180.0, DEGREE),
    )
    ref positions = half.attribute_view(String(POSITION))
    # The last column stops at -z, halfway round from +z.
    var end = positions.vector3(4)
    assert_almost_equal(end.x, Float32(0), atol=Float64(1e-5))
    assert_almost_equal(end.z, Float32(-1), atol=Float64(1e-5))
    # The caps are half disks, still one center per segment.
    assert_equal(half.vertex_count(), 5 * 2 + 2 * (4 + 5))
    assert_equal(half.triangle_count(), 2 * 4 + 4 + 4)
    assert_faces_wind_with_their_normals(half)


def test_a_cylinder_can_be_measured_in_feet() raises:
    var can = cylinder(
        Length(1.0, FOOT), Length(1.0, FOOT), Length(2.0, FOOT), 8
    )
    var top = can.attribute_view(String(POSITION)).vector3(0)
    assert_almost_equal(top.y, Float32(0.3048), atol=Float64(1e-5))
    assert_almost_equal(top.z, Float32(0.3048), atol=Float64(1e-5))


def test_a_cylinder_needs_a_radius_a_height_and_enough_segments() raises:
    var one = Length(1.0, METER)
    var none = Length(0.0, METER)
    with assert_raises():
        _ = cylinder(Length(-1.0, METER), one, one)
    with assert_raises():
        _ = cylinder(one, Length(-1.0, METER), one)
    with assert_raises():
        _ = cylinder(none, none, one)
    with assert_raises():
        _ = cylinder(one, one, none)
    with assert_raises():
        _ = cylinder(one, one, one, 2)
    with assert_raises():
        _ = cylinder(one, one, one, 8, 0)
    with assert_raises():
        _ = cylinder(
            one, one, one, 8, 1, False, Angle(0.0, DEGREE), Angle(0.0, TURN)
        )
    with assert_raises():
        _ = cylinder(
            one, one, one, 8, 1, False, Angle(0.0, DEGREE), Angle(2.0, TURN)
        )


# --- cone -------------------------------------------------------------------


def test_a_cone_is_a_cylinder_with_no_top() raises:
    var spike = cone(Length(1.0, METER), Length(2.0, METER), 8, 1)
    # Two rows of nine down the side and one cap: the top has no radius, so
    # it gets no cap, and each side cell is one triangle rather than two.
    assert_equal(spike.vertex_count(), 9 * 2 + (8 + 9))
    assert_equal(spike.triangle_count(), 8 + 8)
    ref positions = spike.attribute_view(String(POSITION))
    for vertex in range(9):
        assert_almost_equal(
            positions.vector3(vertex).x, Float32(0), atol=TOLERANCE
        )
        assert_equal(positions.vector3(vertex).y, Float32(1))
        assert_almost_equal(
            positions.vector3(vertex).z, Float32(0), atol=TOLERANCE
        )
    assert_no_degenerate_triangle(spike)
    assert_faces_wind_with_their_normals(spike)


def test_a_cones_point_has_one_normal_per_column() raises:
    # Radius one over height two: the side climbs at a slope of a half, and
    # every normal leans up by that much, at the point as on the side.
    var spike = cone(Length(1.0, METER), Length(2.0, METER), 8, 1)
    ref normals = spike.attribute_view(String(NORMAL))
    var up = Float32(0.5) / sqrt(Float32(1.25))
    for vertex in range(18):
        var n = normals.vector3(vertex)
        assert_unit(n)
        assert_almost_equal(n.y, up, atol=Float64(1e-5))
    # The point's first normal leans toward +z, its third toward +x.
    assert_true(normals.vector3(0).z > 0.8)
    assert_true(normals.vector3(2).x > 0.8)


def test_a_cone_with_rows_keeps_every_whole_cell() raises:
    # Only the cells against the point lose a triangle.
    var spike = cone(Length(1.0, METER), Length(2.0, METER), 8, 2)
    assert_equal(spike.vertex_count(), 9 * 3 + (8 + 9))
    assert_equal(spike.triangle_count(), 8 + 16 + 8)
    assert_no_degenerate_triangle(spike)
    assert_faces_wind_with_their_normals(spike)


def test_a_cylinder_with_no_bottom_radius_is_a_cone_the_other_way_up() raises:
    var funnel = cylinder(
        Length(1.0, METER), Length(0.0, METER), Length(2.0, METER), 8, 2
    )
    assert_equal(funnel.vertex_count(), 9 * 3 + (8 + 9))
    assert_equal(funnel.triangle_count(), 16 + 8 + 8)
    ref positions = funnel.attribute_view(String(POSITION))
    for vertex in range(18, 27):
        assert_equal(positions.vector3(vertex).y, Float32(-1))
    # The one cap is on top, facing +y.
    assert_equal(
        funnel.attribute_view(String(NORMAL)).vector3(27).y, Float32(1)
    )
    assert_no_degenerate_triangle(funnel)
    assert_faces_wind_with_their_normals(funnel)


def test_a_cones_area_is_its_facets_and_its_base() raises:
    # Eight triangles from the base chord up to the point, plus the base fan.
    var spike = cone(Length(1.0, METER), Length(2.0, METER), 8, 1)
    var chord = 2 * sin(Float32(pi) / 8)
    var apothem = cos(Float32(pi) / 8)
    var slant = sqrt(apothem * apothem + 4)
    var side = 8 * chord * slant / 2
    var base = Float32(8) / 2 * sin(Float32(pi) / 4)
    assert_almost_equal(surface_area(spike), side + base, atol=Float64(1e-4))


def test_a_cone_can_be_open_and_partial() raises:
    var shell = cone(
        Length(1.0, METER),
        Length(1.0, METER),
        6,
        1,
        True,
        Angle(90.0, DEGREE),
        Angle(90.0, DEGREE),
    )
    assert_equal(shell.vertex_count(), 7 * 2)
    assert_equal(shell.triangle_count(), 6)
    # The sweep starts a quarter turn on from +z: at +x.
    var start = shell.attribute_view(String(POSITION)).vector3(7)
    assert_almost_equal(start.x, Float32(1), atol=Float64(1e-5))
    assert_almost_equal(start.z, Float32(0), atol=Float64(1e-5))


def test_a_cone_needs_a_radius_and_a_height() raises:
    with assert_raises():
        _ = cone(Length(0.0, METER), Length(1.0, METER))
    with assert_raises():
        _ = cone(Length(1.0, METER), Length(0.0, METER))
    with assert_raises():
        _ = cone(Length(1.0, METER), Length(1.0, METER), 2)


# --- torus ------------------------------------------------------------------


def a_ring() raises -> BufferGeometry:
    """Return a torus of radius two with a tube of a half, eight by twelve."""
    return torus(Length(2.0, METER), Length(0.5, METER), 8, 12)


def test_a_torus_is_a_grid_of_rings() raises:
    var ring = a_ring()
    assert_equal(ring.vertex_count(), (8 + 1) * (12 + 1))
    assert_equal(ring.triangle_count(), 2 * 8 * 12)
    assert_equal(
        torus(Length(1.0, METER), Length(0.25, METER)).triangle_count(),
        2 * 12 * 48,
    )


def test_every_torus_vertex_lies_on_its_tube() raises:
    # A vertex is the tube's radius from the circle the tube follows, and its
    # normal points straight away from that circle.
    var ring = a_ring()
    ref positions = ring.attribute_view(String(POSITION))
    ref normals = ring.attribute_view(String(NORMAL))
    for vertex in range(ring.vertex_count()):
        var p = positions.vector3(vertex)
        var spoke = sqrt(p.x * p.x + p.y * p.y)
        var center = Vector3(p.x / spoke * 2, p.y / spoke * 2, 0)
        var out = p - center
        assert_almost_equal(out.length(), Float32(0.5), atol=Float64(1e-5))
        var n = normals.vector3(vertex)
        assert_unit(n)
        assert_almost_equal(n.dot(out), Float32(0.5), atol=Float64(1e-5))


def test_a_torus_starts_at_plus_x_and_closes_its_seams() raises:
    var ring = a_ring()
    ref positions = ring.attribute_view(String(POSITION))
    # Row zero is the outer equator, and its first vertex the far side of
    # the tube from the center: radius plus tube along +x.
    assert_xyz(positions.vector3(0), 2.5, 0, 0)
    # The last column of a row sits on its first, and the last row on row
    # zero.
    assert_xyz(positions.vector3(12), 2.5, 0, 0)
    assert_xyz(positions.vector3(8 * 13), 2.5, 0, 0)
    # A quarter of the way around the tube the vertex is on top of it.
    assert_xyz(positions.vector3(2 * 13), 2, 0, 0.5)


def test_a_torus_maps_u_along_and_v_around() raises:
    var ring = a_ring()
    ref uvs = ring.attribute_view(String(UV))
    assert_equal(uvs.component(0, 0), Float32(0))
    assert_equal(uvs.component(0, 1), Float32(0))
    assert_equal(uvs.component(12, 0), Float32(1))
    assert_equal(uvs.component(12, 1), Float32(0))
    assert_equal(uvs.component(8 * 13, 0), Float32(0))
    assert_equal(uvs.component(8 * 13, 1), Float32(1))
    assert_equal(uvs.component(ring.vertex_count() - 1, 0), Float32(1))
    assert_equal(uvs.component(ring.vertex_count() - 1, 1), Float32(1))
    assert_texture_coordinates_in_range(ring)


def test_every_torus_face_winds_outward() raises:
    assert_faces_wind_with_their_normals(a_ring())
    assert_no_degenerate_triangle(a_ring())


def test_a_torus_area_approaches_the_closed_form() raises:
    # Flat cells under a curved surface: within a few percent of the true
    # area at the default resolution, and closer with more cells.
    var exact = 4 * Float32(pi) * Float32(pi) * 2 * 0.5
    var coarse = surface_area(torus(Length(2.0, METER), Length(0.5, METER)))
    assert_true(abs(coarse - exact) / exact < 0.03)
    var fine = surface_area(
        torus(Length(2.0, METER), Length(0.5, METER), 48, 96)
    )
    assert_true(abs(fine - exact) < abs(coarse - exact))


def test_a_torus_arc_is_a_bent_pipe() raises:
    var bend = torus(
        Length(2.0, METER), Length(0.5, METER), 4, 4, Angle(90.0, DEGREE)
    )
    # The last column of the outer row is a quarter turn round, at +y.
    assert_xyz(bend.attribute_view(String(POSITION)).vector3(4), 0, 2.5, 0)
    assert_faces_wind_with_their_normals(bend)


def test_a_torus_can_be_measured_in_feet() raises:
    var ring = torus(Length(2.0, FOOT), Length(1.0, FOOT), 4, 4)
    assert_almost_equal(
        ring.attribute_view(String(POSITION)).vector3(0).x,
        Float32(3 * 0.3048),
        atol=Float64(1e-5),
    )


def test_a_torus_needs_radii_and_segments_and_an_arc() raises:
    var two = Length(2.0, METER)
    var half = Length(0.5, METER)
    with assert_raises():
        _ = torus(Length(0.0, METER), half)
    with assert_raises():
        _ = torus(two, Length(0.0, METER))
    with assert_raises():
        _ = torus(two, half, 2, 12)
    with assert_raises():
        _ = torus(two, half, 8, 2)
    with assert_raises():
        _ = torus(two, half, 8, 12, Angle(0.0, TURN))
    with assert_raises():
        _ = torus(two, half, 8, 12, Angle(2.0, TURN))


# --- torus knot -------------------------------------------------------------


def a_knot() raises -> BufferGeometry:
    """Return a trefoil of radius two and tube a tenth, 48 rings of 8."""
    return torus_knot(Length(2.0, METER), Length(0.1, METER), 48, 8)


def ring_center(knot: BufferGeometry, ring: Int, radial: Int) raises -> Vector3:
    """Return the mean of a ring's vertices, the seam duplicate left out: the
    point on the curve the ring was built around, since the vertices are
    spaced evenly on a circle about it."""
    ref positions = knot.attribute_view(String(POSITION))
    var total = Vector3(0, 0, 0)
    for step in range(radial):
        total.add(positions.vector3(ring * (radial + 1) + step))
    return total * (1 / Float32(radial))


def test_a_torus_knot_is_a_tube_of_rings() raises:
    var knot = a_knot()
    assert_equal(knot.vertex_count(), (48 + 1) * (8 + 1))
    assert_equal(knot.triangle_count(), 2 * 48 * 8)
    assert_equal(
        torus_knot(Length(1.0, METER), Length(0.1, METER)).triangle_count(),
        2 * 64 * 8,
    )


def test_every_knot_vertex_sits_on_its_ring() raises:
    # Each ring is a circle of the tube's radius around a point of the
    # curve, and each normal points straight out from that point.
    var knot = a_knot()
    ref positions = knot.attribute_view(String(POSITION))
    ref normals = knot.attribute_view(String(NORMAL))
    for ring in range(49):
        var center = ring_center(knot, ring, 8)
        for step in range(9):
            var vertex = ring * 9 + step
            var out = positions.vector3(vertex) - center
            assert_almost_equal(out.length(), Float32(0.1), atol=Float64(1e-5))
            var n = normals.vector3(vertex)
            assert_unit(n)
            assert_almost_equal(n.dot(out), Float32(0.1), atol=Float64(1e-5))


def test_a_trefoil_winds_twice_round_and_three_times_through() raises:
    # three.js's curve lies between half and one and a half of the radius
    # from the axis. Ring zero is at the outer reach on +x; with 48 rings,
    # ring 8 is a third of the way round the first loop, at the inner reach;
    # rings 4 and 12 are where the curve is highest and lowest.
    var knot = a_knot()
    assert_xyz(ring_center(knot, 0, 8), 3, 0, 0)
    var inner = ring_center(knot, 8, 8)
    assert_xyz(inner, -0.5, 0.8660254, 0)
    assert_almost_equal(
        ring_center(knot, 4, 8).z, Float32(1), atol=Float64(1e-4)
    )
    assert_almost_equal(
        ring_center(knot, 12, 8).z, Float32(-1), atol=Float64(1e-4)
    )
    # The last ring is the first: the knot closes.
    assert_xyz(ring_center(knot, 48, 8), 3, 0, 0)


def test_every_knot_face_winds_outward() raises:
    assert_faces_wind_with_their_normals(a_knot())
    assert_no_degenerate_triangle(a_knot())
    # And with the windings the other way round.
    var wound = torus_knot(Length(2.0, METER), Length(0.2, METER), 64, 6, 3, 2)
    assert_faces_wind_with_their_normals(wound)
    assert_no_degenerate_triangle(wound)


def test_a_knot_maps_u_along_and_v_around() raises:
    var knot = a_knot()
    ref uvs = knot.attribute_view(String(UV))
    assert_equal(uvs.component(0, 0), Float32(0))
    assert_equal(uvs.component(0, 1), Float32(0))
    assert_equal(uvs.component(8, 0), Float32(0))
    assert_equal(uvs.component(8, 1), Float32(1))
    assert_equal(uvs.component(48 * 9, 0), Float32(1))
    assert_equal(uvs.component(48 * 9, 1), Float32(0))
    assert_equal(uvs.component(knot.vertex_count() - 1, 1), Float32(1))
    assert_texture_coordinates_in_range(knot)


def test_a_torus_knot_can_be_measured_in_feet() raises:
    var knot = torus_knot(Length(2.0, FOOT), Length(0.1, FOOT), 12, 4)
    assert_almost_equal(
        ring_center(knot, 0, 4).x, Float32(3 * 0.3048), atol=Float64(1e-5)
    )


def test_a_torus_knot_needs_radii_segments_and_windings() raises:
    var two = Length(2.0, METER)
    var tenth = Length(0.1, METER)
    with assert_raises():
        _ = torus_knot(Length(0.0, METER), tenth)
    with assert_raises():
        _ = torus_knot(two, Length(0.0, METER))
    with assert_raises():
        _ = torus_knot(two, tenth, 2, 8)
    with assert_raises():
        _ = torus_knot(two, tenth, 48, 2)
    with assert_raises():
        _ = torus_knot(two, tenth, 48, 8, 0, 3)
    with assert_raises():
        _ = torus_knot(two, tenth, 48, 8, 2, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
