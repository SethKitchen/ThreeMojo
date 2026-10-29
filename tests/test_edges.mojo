# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `geometries.edges`."""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import BufferGeometry, MaterialIndex, POSITION
from geometries.box import cube
from geometries.edges import (
    DEFAULT_THRESHOLD,
    WELD,
    edges_geometry,
    triangle_edges,
    welded_points,
    wireframe_geometry,
)
from geometries.plane import plane
from geometries.sphere import sphere
from std.math import nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_raises,
    assert_true,
)
from math.vector3 import Vector3
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


def test_a_weld_compares_every_axis() raises:
    """A point in the next cell that is too far on y, or on z, stays
    apart."""
    var step = WELD * 1.5
    var spread = welded_points(
        points([0.0, 0.0, 0.0, 0.0, step, 0.0, 0.0, 0.0, step])
    )
    assert_true(spread[0] != spread[1])
    assert_true(spread[0] != spread[2])
    assert_true(spread[1] != spread[2])


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


def test_a_face_with_no_area_lends_no_crease() raises:
    """A face whose corners coincide is skipped, as three.js's
    `EdgesGeometry` skips it. Its normal is zero, which dots to zero with
    any neighbor, and that read as a right-angle turn: a flat square with
    such a face on its diagonal kept the diagonal as a crease. Each way two
    of three corners can be the same point is tried."""
    var flat = points(
        [
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            1.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            1.0,
            0.0,
            0.0,
            1.0,
            0.0,
            # Degenerate: first two corners, last two, and first and last.
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            1.0,
            0.0,
            1.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
        ]
    )
    assert_equal(segments_of(edges_geometry(flat)), 4)
    # three.js's `WireframeGeometry` does not skip them. Their edge of no
    # length, from the origin to the origin, is kept once: six edges.
    assert_equal(segments_of(wireframe_geometry(flat)), 6)


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
    assert_equal(len(triangle_edges(nothing)[0]), 0)


def test_faces_that_run_an_edge_the_same_way_do_not_pair() raises:
    """An edge pairs only with itself run the other way, as in three.js."""
    # Three triangles hinged on the segment from the origin to (1, 0, 0):
    # one flat, one turned a quarter, one turned back on the first. Each
    # runs the hinge from the origin out, so none pairs with another.
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
    # three.js's `EdgesGeometry` keeps the hinge of the first face and
    # skips it in the other two, so it is an edge with one face. Every
    # threshold keeps all seven. The port paired the first two faces and
    # dropped the hinge at a half turn.
    assert_equal(segments_of(edges_geometry(fan, Angle(180.0, DEGREE))), 7)


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


def test_edges_paired_by_index_do_not_weld() raises:
    """`triangle_edges` is three.js's wireframe rule: index, not position."""
    # A cube builds each face from its own four vertices, so the twelve
    # edges of the shape are twenty-four vertex pairs. Pairing by index
    # keeps them apart; `wireframe_geometry` welds them into eighteen.
    var box = cube(Length(1, METER))
    var ends = triangle_edges(box)
    assert_equal(len(ends[0]), 30)
    assert_equal(segments_of(wireframe_geometry(box)), 18)
    # A sphere is large enough that the buckets really collide, which is
    # the case where a key is compared and found to be another edge's.
    var ball = sphere(Length(1, METER), 24, 16)
    var many = triangle_edges(ball)
    assert_true(len(many[0]) > 1000)
    # Every edge once: three per triangle, less the ones shared.
    assert_true(len(many[0]) < ball.triangle_count() * 3)


def segment(drawn: BufferGeometry, index: Int) raises -> List[Vector3]:
    """Return the two ends of one segment of a geometry of point pairs.

    Args:
        drawn: The drawn edges.
        index: Which segment, from zero.

    Returns:
        Its first end and its second.

    Raises:
        Error: If it has no positions or no such segment.
    """
    ref positions = drawn.attribute_view(String(POSITION))
    return [positions.vector3(index * 2), positions.vector3(index * 2 + 1)]


def test_a_wireframe_keeps_points_that_are_near_but_not_equal() raises:
    """The `WireframeGeometry` of three.js keys an edge by the exact
    positions of its ends. Two triangles 5e-5 apart are six edges there.
    The port welded points within a tenth of a millimeter and drew three.
    Minus zero is zero, as JavaScript prints it, and every NaN is one
    number."""
    var near = points(
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
            5e-5,
            0.0,
            0.0,
            1.00005,
            0.0,
            0.0,
            5e-5,
            1.0,
            0.0,
        ]
    )
    assert_equal(segments_of(wireframe_geometry(near)), 6)
    var signed = points(
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
            1.0,
            0.0,
            0.0,
            -0.0,
            -0.0,
            -0.0,
            0.0,
            0.0,
            1.0,
        ]
    )
    assert_equal(segments_of(wireframe_geometry(signed)), 5)
    var unknown = nan[DType.float32]()
    var missing = points(
        [
            unknown,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            1.0,
            0.0,
            0.0,
            -unknown,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
        ]
    )
    assert_equal(segments_of(wireframe_geometry(missing)), 5)


def test_a_small_sphere_keeps_every_wireframe_edge() raises:
    """A wireframe does not depend on the scale, as in three.js. A sphere
    of a millimeter has points closer than a tenth of a millimeter near its
    poles, and the port welded them."""
    var large = wireframe_geometry(sphere(Length(1, METER), 32, 16))
    var small = wireframe_geometry(sphere(Length(0.001, METER), 32, 16))
    assert_equal(segments_of(small), segments_of(large))


def test_a_wireframe_reads_an_indexed_geometry_group_by_group() raises:
    """The `WireframeGeometry` of three.js reads the groups of an indexed
    geometry. A triangle in no group gives no edge."""
    var quad = plane(Length(2, METER), Length(2, METER))
    quad.add_group(0, 3, MaterialIndex(0))
    assert_equal(segments_of(wireframe_geometry(quad)), 3)
    # A second group adds the edges of its own triangle that are new.
    quad.add_group(3, 3, MaterialIndex(1))
    assert_equal(segments_of(wireframe_geometry(quad)), 5)


def test_an_edge_geometry_is_in_three_js_s_order() raises:
    """A pair is drawn when three.js meets the second face, in that face's
    direction, and the edges with one face after the pairs. The port drew
    every edge in the order and direction of its first face."""
    # Two faces hinged a quarter turn on the segment from the origin to
    # (1, 0, 0). The second runs the hinge from (1, 0, 0) back.
    var folded = points(
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
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
        ]
    )
    var drawn = edges_geometry(folded)
    assert_equal(segments_of(drawn), 5)
    var hinge = segment(drawn, 0)
    assert_true(hinge[0] == Vector3(1, 0, 0))
    assert_true(hinge[1] == Vector3(0, 0, 0))
    var expected: List[Vector3] = [
        Vector3(1, 0, 0),
        Vector3(0, 1, 0),
        Vector3(0, 1, 0),
        Vector3(0, 0, 0),
        Vector3(0, 0, 0),
        Vector3(0, 0, 1),
        Vector3(0, 0, 1),
        Vector3(1, 0, 0),
    ]
    for index in range(4):
        var ends = segment(drawn, index + 1)
        assert_true(ends[0] == expected[index * 2])
        assert_true(ends[1] == expected[index * 2 + 1])


def test_an_edge_key_is_three_js_s_rounded_coordinate() raises:
    """A point is keyed by `Math.round` of each coordinate times ten
    thousand, as in three.js. Points at 4e-5 and 6e-5 round apart, so the
    hinge between two faces does not pair, and it is drawn twice. The port
    welded the two points and dropped the hinge at a half turn."""
    var straddle = points(
        [
            4e-5,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            1.0,
            0.0,
            0.0,
            6e-5,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
        ]
    )
    var drawn = edges_geometry(straddle, Angle(180.0, DEGREE))
    assert_equal(segments_of(drawn), 6)


def test_a_third_face_after_a_pair_is_an_edge_with_one_face() raises:
    """In three.js a pair closes its edge. A third face that runs the edge
    the way the second did starts a new edge, which has one face."""
    var hinged = points(
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
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            -1.0,
            0.0,
        ]
    )
    # Seven edges with one face. The paired hinge turns a quarter, which a
    # half turn threshold drops. The port kept that pair for the third
    # face too, and drew six.
    var drawn = edges_geometry(hinged, Angle(180.0, DEGREE))
    assert_equal(segments_of(drawn), 7)
    var hinge = segment(drawn, 4)
    assert_true(hinge[0] == Vector3(1, 0, 0))
    assert_true(hinge[1] == Vector3(0, 0, 0))


def test_a_face_in_a_line_has_no_normal() raises:
    """Three corners on one line, on three keys, give three.js's zero
    normal. It dots to zero, so a right angle threshold keeps the edge it
    shares with a flat face."""
    var thin = points(
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
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
            2.0,
            0.0,
            0.0,
        ]
    )
    # The hinge, then the four edges with one face.
    var drawn = edges_geometry(thin, Angle(90.0, DEGREE))
    assert_equal(segments_of(drawn), 5)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
