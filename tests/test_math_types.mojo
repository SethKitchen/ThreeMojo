# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.triangle`, `math.spherical`, `math.matrix2` and
`math.utils`."""

from math.matrix2 import Box2, Matrix2
from math.matrix4 import translation
from math.spherical import Cylindrical, Spherical
from math.triangle import Line3, Triangle
from math.utils import (
    SeededRandom,
    ceil_power_of_two,
    clamp,
    damp,
    euclidean_modulo,
    floor_power_of_two,
    inverse_lerp,
    is_power_of_two,
    lerp,
    map_linear,
    pingpong,
    smooth_step,
    smootherstep,
)
from math.vector2 import Vector2
from math.vector3 import Vector3
from std.math import pi, sqrt
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, Duration, RADIAN, SECOND

comptime TOLERANCE = Float64(1e-5)


def _near(a: Vector3, b: Vector3) raises:
    """Assert two vectors are close.

    Args:
        a: One.
        b: The other.

    Raises:
        Error: If they differ.
    """
    assert_almost_equal(a.x, b.x, atol=TOLERANCE)
    assert_almost_equal(a.y, b.y, atol=TOLERANCE)
    assert_almost_equal(a.z, b.z, atol=TOLERANCE)


def _right() -> Triangle:
    """Return the right triangle (0,0,0), (1,0,0), (0,1,0) in z = 0."""
    return Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0))


def _flat() -> Triangle:
    """Return a triangle whose corners lie on the x axis."""
    return Triangle(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0))


def test_a_triangle_has_a_normal_an_area_and_a_plane() raises:
    var t = _right()
    _near(t.normal(), Vector3(0, 0, 1))
    assert_almost_equal(t.area(), Float32(0.5), atol=TOLERANCE)
    _near(t.midpoint(), Vector3(Float32(1) / 3, Float32(1) / 3, 0))
    assert_almost_equal(
        t.plane().distance_to_point(Vector3(0, 0, 2)), Float32(2)
    )
    assert_false(t.is_degenerate())
    assert_true(t.is_front_facing(Vector3(0, 0, -1)))
    assert_false(t.is_front_facing(Vector3(0, 0, 1)))


def test_a_degenerate_triangle_is_refused_what_it_cannot_answer() raises:
    var t = _flat()
    assert_true(t.is_degenerate())
    with assert_raises(contains="no normal"):
        _ = t.normal()
    with assert_raises(contains="no normal"):
        _ = t.plane()
    with assert_raises(contains="barycentric"):
        _ = t.barycoord(Vector3(0, 0, 0))
    # The nearest point is still on the segment the corners make.
    _near(t.closest_point_to_point(Vector3(1.5, 3, 0)), Vector3(1.5, 0, 0))


def test_barycentric_coordinates_and_interpolation() raises:
    var t = _right()
    _near(t.barycoord(Vector3(0.25, 0.25, 7)), Vector3(0.5, 0.25, 0.25))
    assert_true(t.contains_point(Vector3(0.2, 0.2, 3)))
    assert_false(t.contains_point(Vector3(1, 1, 0)))
    _near(
        t.interpolate(
            Vector3(0.5, 0.5, 0),
            Vector3(1, 0, 0),
            Vector3(0, 1, 0),
            Vector3(0, 0, 1),
        ),
        Vector3(0, 0.5, 0.5),
    )


def test_the_closest_point_on_a_triangle() raises:
    var t = _right()
    # Above the face.
    _near(t.closest_point_to_point(Vector3(0.2, 0.3, 5)), Vector3(0.2, 0.3, 0))
    # Past each edge: below y = 0, left of x = 0, past the hypotenuse.
    _near(t.closest_point_to_point(Vector3(0.5, -1, 0)), Vector3(0.5, 0, 0))
    _near(t.closest_point_to_point(Vector3(-1, 0.5, 0)), Vector3(0, 0.5, 0))
    _near(t.closest_point_to_point(Vector3(1, 1, 0)), Vector3(0.5, 0.5, 0))
    # Past a corner.
    _near(t.closest_point_to_point(Vector3(-1, -1, 0)), Vector3(0, 0, 0))
    # A triangle of one point.
    var dot = Triangle(Vector3(1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 1))
    _near(dot.closest_point_to_point(Vector3(0, 0, 0)), Vector3(1, 1, 1))


def test_a_segment() raises:
    var line = Line3(Vector3(0, 0, 0), Vector3(2, 0, 0))
    _near(line.center(), Vector3(1, 0, 0))
    assert_almost_equal(line.distance(), Float32(2))
    _near(line.at(1.5), Vector3(3, 0, 0))
    assert_almost_equal(
        line.closest_point_parameter(Vector3(3, 1, 0), False), Float32(1.5)
    )
    _near(line.closest_point(Vector3(3, 1, 0), True), Vector3(2, 0, 0))
    _near(line.closest_point(Vector3(-3, 1, 0), True), Vector3(0, 0, 0))
    var moved = line
    moved.apply_matrix4(translation(0, 1, 0))
    _near(moved.start, Vector3(0, 1, 0))
    var point = Line3(Vector3(1, 1, 1), Vector3(1, 1, 1))
    with assert_raises(contains="no length"):
        _ = point.closest_point_parameter(Vector3(0, 0, 0), True)


def test_the_distance_between_two_segments() raises:
    var x = Line3(Vector3(0, 0, 0), Vector3(2, 0, 0))
    # Crossing above: one apart.
    assert_almost_equal(
        x.distance_to_line(Line3(Vector3(1, -1, 1), Vector3(1, 1, 1))),
        Float32(1),
        atol=TOLERANCE,
    )
    # Parallel.
    assert_almost_equal(
        x.distance_to_line(Line3(Vector3(0, 2, 0), Vector3(2, 2, 0))),
        Float32(2),
        atol=TOLERANCE,
    )
    # The other ends before this starts, and after this ends.
    assert_almost_equal(
        x.distance_to_line(Line3(Vector3(-1, -1, 0), Vector3(-1, -3, 0))),
        Float32(sqrt(Float32(2))),
        atol=TOLERANCE,
    )
    assert_almost_equal(
        x.distance_to_line(Line3(Vector3(3, 1, 0), Vector3(3, 3, 0))),
        Float32(sqrt(Float32(2))),
        atol=TOLERANCE,
    )
    # The same segment reversed: its nearest point is its end.
    assert_almost_equal(
        x.distance_to_line(Line3(Vector3(3, 3, 0), Vector3(3, 1, 0))),
        Float32(sqrt(Float32(2))),
        atol=TOLERANCE,
    )
    # Points on either side, and both.
    var p = Line3(Vector3(1, 3, 0), Vector3(1, 3, 0))
    assert_almost_equal(x.distance_to_line(p), Float32(3), atol=TOLERANCE)
    assert_almost_equal(p.distance_to_line(x), Float32(3), atol=TOLERANCE)
    var q = Line3(Vector3(1, 0, 4), Vector3(1, 0, 4))
    assert_almost_equal(p.distance_to_line(q), Float32(5), atol=TOLERANCE)


def test_spherical_coordinates() raises:
    var s = Spherical.from_vector3(Vector3(0, 0, 5))
    assert_almost_equal(s.radius, Float32(5))
    assert_almost_equal(s.phi.to(DEGREE), Float32(90), atol=1e-3)
    assert_almost_equal(s.theta.to(DEGREE), Float32(0), atol=1e-3)
    var t = Spherical(2, Angle(90.0, DEGREE), Angle(90.0, DEGREE))
    _near(t.to_vector3(), Vector3(2, 0, 0))
    var origin = Spherical.from_vector3(Vector3(0, 0, 0))
    assert_equal(origin.radius, Float32(0))
    var pole = Spherical(1, Angle(0.0, RADIAN), Angle(0.0, RADIAN))
    pole.make_safe()
    assert_true(pole.phi.to(RADIAN) > 0)
    var round_trip = Spherical.from_vector3(Vector3(1, 2, 3)).to_vector3()
    _near(round_trip, Vector3(1, 2, 3))


def test_cylindrical_coordinates() raises:
    var c = Cylindrical.from_vector3(Vector3(3, 7, 4))
    assert_almost_equal(c.radius, Float32(5))
    assert_almost_equal(c.y, Float32(7))
    _near(c.to_vector3(), Vector3(3, 7, 4))


def test_matrix2() raises:
    var r = Matrix2.rotation(Angle(90.0, DEGREE))
    var v = r.transform(Vector2(1, 0))
    assert_almost_equal(v.x, Float32(0), atol=TOLERANCE)
    assert_almost_equal(v.y, Float32(1), atol=TOLERANCE)
    var s = Matrix2.scaling(2, 3)
    assert_almost_equal(s.determinant(), Float32(6))
    var product = s * s.inverse()
    assert_true(product == Matrix2.identity())
    assert_false(product != Matrix2.identity())
    assert_true(Matrix2(1, 2, 3, 4).transposed() == Matrix2(1, 3, 2, 4))
    assert_true(Matrix2(1, 2, 3, 4) != Matrix2(1, 2, 3, 5))
    assert_true(Matrix2(1, 2, 3, 4) != Matrix2(1, 2, 0, 4))
    assert_true(Matrix2(1, 2, 3, 4) != Matrix2(1, 0, 3, 4))
    assert_true(Matrix2(1, 2, 3, 4) != Matrix2(0, 2, 3, 4))
    with assert_raises(contains="singular"):
        _ = Matrix2(1, 2, 2, 4).inverse()


def test_box2() raises:
    var box = Box2.from_points([Vector2(1, 2), Vector2(-1, 4)])
    assert_almost_equal(box.center().x, Float32(0))
    assert_almost_equal(box.size().y, Float32(2))
    assert_true(box.contains_point(Vector2(0, 3)))
    assert_false(box.contains_point(Vector2(0, 5)))
    assert_true(Box2.from_points(List[Vector2]()).is_empty())
    assert_equal(Box2.empty().size().x, Float32(0))
    assert_true(box.intersects_box(Box2(Vector2(0, 0), Vector2(5, 2))))
    assert_false(box.intersects_box(Box2(Vector2(2, 0), Vector2(5, 9))))
    assert_almost_equal(box.distance_to_point(Vector2(4, 3)), Float32(3))
    with assert_raises(contains="empty"):
        _ = Box2.empty().clamp_point(Vector2(0, 0))
    var grown = box
    grown.union(Box2(Vector2(5, 5), Vector2(6, 6)))
    assert_almost_equal(grown.max.x, Float32(6))
    grown.union(Box2.empty())
    assert_almost_equal(grown.max.x, Float32(6))
    var both = box
    both.intersect(Box2(Vector2(0, 0), Vector2(5, 3)))
    assert_almost_equal(both.min.x, Float32(0))
    assert_almost_equal(both.max.y, Float32(3))
    var neither = box
    neither.intersect(Box2(Vector2(9, 9), Vector2(10, 10)))
    assert_true(neither.is_empty())


def test_scalar_helpers() raises:
    assert_equal(clamp(5, 0, 1), Float32(1))
    assert_equal(lerp(2, 4, 0.5), Float32(3))
    assert_equal(inverse_lerp(2, 4, 3), Float32(0.5))
    assert_equal(inverse_lerp(2, 2, 3), Float32(0))
    assert_equal(map_linear(5, 0, 10, 100, 200), Float32(150))
    assert_almost_equal(
        damp(0, 1, 1, Duration(1.0, SECOND)), Float32(0.6321206), atol=1e-6
    )
    assert_equal(euclidean_modulo(-1, 3), Float32(2))
    assert_equal(pingpong(1.5), Float32(0.5))
    assert_equal(smootherstep(-1, 0, 1), Float32(0))
    assert_equal(smootherstep(2, 0, 1), Float32(1))
    assert_equal(smootherstep(0.5, 0, 1), Float32(0.5))
    assert_equal(smooth_step(0.5, 0, 1), Float32(0.5))
    assert_true(is_power_of_two(8))
    assert_false(is_power_of_two(6))
    assert_false(is_power_of_two(0))
    assert_equal(ceil_power_of_two(1), 1)
    assert_equal(ceil_power_of_two(5), 8)
    assert_equal(floor_power_of_two(1), 1)
    assert_equal(floor_power_of_two(5), 4)
    with assert_raises(contains="positive"):
        _ = ceil_power_of_two(0)
    with assert_raises(contains="positive"):
        _ = floor_power_of_two(-2)


def test_the_seeded_generator_matches_three_js() raises:
    # The first three numbers three.js's seededRandom(42) returns.
    var random = SeededRandom(42)
    assert_almost_equal(random.next(), 0.6011037519201636, atol=1e-12)
    assert_almost_equal(random.next(), 0.44829055899754167, atol=1e-12)
    assert_almost_equal(random.next(), 0.8524657934904099, atol=1e-12)
    var other = SeededRandom(7)
    var x = other.float_in(2, 3)
    assert_true(x >= 2 and x < 3)
    var y = other.float_spread(4)
    assert_true(y >= -2 and y <= 2)
    for _ in range(50):
        var n = other.int_in(1, 3)
        assert_true(n >= 1 and n <= 3)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
