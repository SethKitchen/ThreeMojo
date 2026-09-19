# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.edges`."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, POSITION
from geometries.box import cube
from geometries.edges import (
    DEFAULT_THRESHOLD,
    WELD,
    edges_geometry,
    welded_points,
    wireframe_geometry,
)
from geometries.plane import plane
from geometries.sphere import sphere
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Length, METER


def points(var numbers: List[Float32]) raises -> BufferGeometry:
    """Return a geometry holding `numbers` as positions and nothing else.

    Args:
        numbers: Three per point.

    Returns:
        The geometry.

    Raises:
        Error: If the numbers do not divide into points.
    """
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(numbers^, 3))
    return geometry^


def segments_of(geometry: BufferGeometry) raises -> Int:
    """Return how many segments a geometry of point pairs holds.

    Args:
        geometry: The drawn edges.

    Returns:
        Half its point count.

    Raises:
        Error: If it has no positions.
    """
    return geometry.attribute_view(String(POSITION)).count() // 2


def test_two_points_at_one_place_are_one_welded_point() raises:
    """Welding is by position, not by index."""
    var shared = welded_points(
        points([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0])
    )
    assert_equal(len(shared), 3)
    assert_equal(shared[0], shared[2])
    assert_true(shared[0] != shared[1])


def test_two_points_a_weld_apart_are_still_one_point() raises:
    """The tolerance is a distance, and a point just inside it welds."""
    var near = welded_points(points([0.0, 0.0, 0.0, WELD * 0.5, 0.0, 0.0]))
    assert_equal(near[0], near[1])
    var apart = welded_points(points([0.0, 0.0, 0.0, 1.0, 0.0, 0.0]))
    assert_true(apart[0] != apart[1])


def test_a_triangle_has_three_edges() raises:
    """The simplest surface there is, wireframed."""
    var drawn = wireframe_geometry(
        points([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0])
    )
    assert_equal(segments_of(drawn), 3)


def test_a_wireframe_keeps_the_diagonal_a_quad_is_split_on() raises:
    """Two triangles share one edge, so five edges and not six."""
    var quad = plane(Length(2, METER), Length(2, METER))
    assert_equal(segments_of(wireframe_geometry(quad)), 5)


def test_an_edge_geometry_drops_an_edge_its_faces_do_not_turn_at() raises:
    """The diagonal of a flat quad is a mesh edge, not a shape edge."""
    var quad = plane(Length(2, METER), Length(2, METER))
    assert_equal(segments_of(edges_geometry(quad)), 4)


def test_a_cube_keeps_its_twelve_edges() raises:
    """Its faces turn a quarter turn, and its face diagonals do not turn."""
    var box = cube(Length(1, METER))
    assert_equal(segments_of(edges_geometry(box)), 12)
    # And a wireframe keeps those twelve and the diagonal each face is
    # split on: eighteen, not thirty-six, because welding lets the two
    # faces meeting at an edge be seen to share it.
    assert_equal(segments_of(wireframe_geometry(box)), 18)


def test_a_threshold_past_every_turn_keeps_nothing_of_a_closed_shape() raises:
    """A cube has no boundary edge, so a half turn threshold drops all
    twelve."""
    var box = cube(Length(1, METER))
    assert_equal(segments_of(edges_geometry(box, Angle(180.0, DEGREE))), 0)


def test_a_threshold_under_every_turn_keeps_every_edge() raises:
    """At no threshold at all an edge geometry is a wireframe."""
    var box = cube(Length(1, METER))
    var all_of_it = edges_geometry(box, Angle(0.0, DEGREE))
    assert_equal(segments_of(all_of_it), segments_of(wireframe_geometry(box)))


def test_a_sphere_is_smooth_only_beside_its_threshold() raises:
    """A facet of a sphere turns by degrees, so the default keeps almost
    every edge and a quarter turn keeps almost none."""
    var ball = sphere(Length(1, METER), 24, 16)
    var fine = segments_of(edges_geometry(ball))
    assert_true(fine > segments_of(wireframe_geometry(ball)) // 2)
    # No two facets of a sphere turn a quarter turn, and it is closed, so
    # a quarter turn keeps nothing at all.
    assert_equal(segments_of(edges_geometry(ball, Angle(90.0, DEGREE))), 0)


def test_a_boundary_edge_is_kept_however_flat_it_is() raises:
    """One triangle has no neighbor anywhere, so all three edges stay."""
    var lone = points([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0])
    assert_equal(segments_of(edges_geometry(lone, Angle(180.0, DEGREE))), 3)


def test_the_default_threshold_is_the_one_three_js_uses() raises:
    """One degree, as `thresholdAngle` defaults."""
    assert_true(DEFAULT_THRESHOLD == Angle(1.0, DEGREE))


def test_a_surface_that_cannot_be_read_is_refused() raises:
    """No positions, a negative threshold and a bad index each raise."""
    with assert_raises():
        _ = wireframe_geometry(BufferGeometry())
    with assert_raises():
        _ = edges_geometry(
            points([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0]),
            Angle(-1.0, DEGREE),
        )
    var broken = points([0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0])
    broken.set_index([0, 1, 9])
    with assert_raises():
        _ = wireframe_geometry(broken)


def test_a_surface_with_no_points_has_no_edges() raises:
    """Nothing in gives nothing out, at every step of the way."""
    var nothing = points(List[Float32]())
    assert_equal(len(welded_points(nothing)), 0)
    assert_equal(segments_of(wireframe_geometry(nothing)), 0)
    assert_equal(segments_of(edges_geometry(nothing)), 0)


def test_a_third_face_on_one_edge_does_not_change_its_angle() raises:
    """A non-manifold edge keeps the turn its first two faces make."""
    # Three triangles hinged on the segment from the origin to (1, 0, 0):
    # one flat, one turned a quarter, one turned back on the first.
    var fan = points(
        [
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            -1.0,
            0.0,
        ]
    )
    # The hinge is shared by all three, and the other six edges have one
    # face each: seven unique edges in all.
    assert_equal(segments_of(wireframe_geometry(fan)), 7)
    # The first two faces turn a quarter, which a half turn threshold
    # drops. The six boundary edges stay whatever the threshold.
    assert_equal(segments_of(edges_geometry(fan, Angle(180.0, DEGREE))), 6)


def test_a_cube_keeps_its_right_angles_at_an_inclusive_ninety() raises:
    """The rule is inclusive, and a float32 cosine must not make it
    exclusive."""
    # An `Angle` holds radians as a Float32, so ninety degrees is
    # 1.5707964 and its cosine is -4.37e-8 rather than zero, while two
    # perpendicular faces give a dot product of exactly zero. Without the
    # slack the comparison rejected every right angle a cube has.
    var box = cube(Length(1, METER))
    assert_equal(segments_of(edges_geometry(box, Angle(90.0, DEGREE))), 12)
    assert_equal(segments_of(edges_geometry(box, Angle(89.99, DEGREE))), 12)
    # And just past the right angle nothing survives, so the slack is a
    # tolerance rather than a widening of the threshold.
    assert_equal(segments_of(edges_geometry(box, Angle(90.01, DEGREE))), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
