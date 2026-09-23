# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `math.curve3` and the tube it feeds.

The expected numbers come from three.js 0.180 itself, run under Node on the
same points. three.js works in double precision and measures its tangents
across a short step; the tolerances allow for both.
"""

from core.buffer_geometry import NORMAL, POSITION, UV
from geometries.tube import tube
from math.curve3 import (
    CATMULL_ROM3,
    CATMULLROM,
    CENTRIPETAL,
    CHORDAL,
    CUBIC3,
    LINE3,
    QUADRATIC3,
    STRAIGHT,
    CatmullRomType,
    Curve3,
    Curve3Kind,
    CurvePath3,
    FrenetFrames,
    catmull_rom3,
    cubic_bezier3,
    first_normal,
    line3,
    quadratic_bezier3,
    transport_frames,
)
from math.vector3 import Vector3
from std.math import cos, pi, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import Length, METER

comptime CLOSE = Float64(1e-4)
# three.js measures a tangent across a step of 1e-4 in `t`; this curve's
# tangent is the exact derivative, so the two differ in the fourth place.
comptime TURNING = Float64(2e-3)


def assert_xyz(
    got: Vector3, x: Float32, y: Float32, z: Float32, tolerance: Float64
) raises:
    """Assert a vector is (x, y, z), within `tolerance`."""
    assert_almost_equal(got.x, x, atol=tolerance)
    assert_almost_equal(got.y, y, atol=tolerance)
    assert_almost_equal(got.z, z, atol=tolerance)


def four() -> List[Vector3]:
    """Return the four points the three.js reference ran on."""
    return [
        Vector3(0, 0, 0),
        Vector3(1, 2, 0),
        Vector3(3, 2, 1),
        Vector3(4, 0, 2),
    ]


# --- kinds and types ----------------------------------------------------------


def test_curve3_kind_is_valid() raises:
    assert_true(LINE3.is_valid())
    assert_true(QUADRATIC3.is_valid())
    assert_true(CUBIC3.is_valid())
    assert_true(CATMULL_ROM3.is_valid())
    assert_false(Curve3Kind(9).is_valid())
    assert_equal(LINE3.control_count(), 2)
    assert_equal(QUADRATIC3.control_count(), 3)
    assert_equal(CUBIC3.control_count(), 4)
    assert_equal(CATMULL_ROM3.control_count(), 0)


def test_catmull_rom_type_is_valid() raises:
    assert_true(CENTRIPETAL.is_valid())
    assert_true(CHORDAL.is_valid())
    assert_true(CATMULLROM.is_valid())
    assert_false(CatmullRomType(7).is_valid())


def test_curve3_refuses_what_is_not_a_curve() raises:
    with assert_raises():
        _ = Curve3(Curve3Kind(9), [Vector3(0, 0, 0), Vector3(1, 0, 0)])
    with assert_raises():
        _ = catmull_rom3(four(), curve_type=CatmullRomType(7))
    with assert_raises():
        _ = Curve3(CATMULL_ROM3, [Vector3(0, 0, 0)])
    with assert_raises():
        _ = Curve3(QUADRATIC3, [Vector3(0, 0, 0), Vector3(1, 0, 0)])
    with assert_raises():
        _ = Curve3(LINE3, [Vector3(0, 0, 0), Vector3(1, 0, 0)], closed=True)
    with assert_raises():
        _ = catmull_rom3([Vector3(1, 1, 1), Vector3(1, 1, 1)])
    # A closed Catmull-Rom is allowed, and a curve that moves only in z
    # still moves.
    _ = catmull_rom3(four(), closed=True)
    _ = line3(Vector3(0, 0, 0), Vector3(0, 0, 1))


def test_curve3_copies() raises:
    var original = catmull_rom3(four(), True, CHORDAL, 0.25)
    var copied = Curve3(copy=original)
    assert_true(copied.closed)
    assert_true(copied.curve_type == CHORDAL)
    assert_equal(copied.tension, Float32(0.25))
    assert_equal(len(copied.points), 4)
    assert_equal(copied.segments(), 4)
    assert_equal(original.segments(), 4)
    assert_equal(catmull_rom3(four()).segments(), 3)


# --- points against three.js ------------------------------------------------


def test_bezier_and_line_points_match_three_js() raises:
    var run = line3(Vector3(1, 2, 3), Vector3(4, 6, 3))
    assert_xyz(run.point(0.5), 2.5, 4, 3, CLOSE)
    assert_xyz(run.point(1), 4, 6, 3, 0)
    assert_xyz(run.tangent(0.5), 0.6, 0.8, 0, CLOSE)
    assert_almost_equal(run.length().to(METER), Float32(5), atol=CLOSE)
    var arc = quadratic_bezier3(
        Vector3(0, 0, 0), Vector3(1, 2, 1), Vector3(2, 0, 2)
    )
    assert_xyz(arc.point(0.25), 0.5, 0.75, 0.5, CLOSE)
    var bend = cubic_bezier3(
        Vector3(0, 0, 0), Vector3(0, 1, 1), Vector3(1, 1, 2), Vector3(1, 0, 3)
    )
    assert_xyz(bend.point(0.25), 0.15625, 0.5625, 0.75, CLOSE)
    assert_almost_equal(bend.length().to(METER), Float32(3.623989), atol=CLOSE)
    # At the ends a Bezier leaves along its own control arms.
    assert_xyz(bend.tangent(0), 0, 0.707107, 0.707107, CLOSE)
    assert_xyz(arc.tangent(1), 0.408248, -0.816497, 0.408248, CLOSE)


def test_centripetal_points_match_three_js() raises:
    var open = catmull_rom3(four())
    assert_xyz(open.point(0), 0, 0, 0, CLOSE)
    assert_xyz(open.point(0.3), 0.8595, 1.881, -0.0405, CLOSE)
    assert_xyz(open.point(0.5), 2.001297, 2.241709, 0.440221, CLOSE)
    assert_xyz(open.point(1), 4, 0, 2, CLOSE)
    var shut = catmull_rom3(four(), closed=True)
    assert_xyz(shut.point(0.3), 1.352332, 2.157877, 0.136697, CLOSE)
    assert_xyz(shut.point(0.9), 1.438518, -0.387678, 0.816179, CLOSE)
    assert_almost_equal(shut.length().to(METER), Float32(11.858855), atol=1e-3)


def test_chordal_points_match_three_js() raises:
    var open = catmull_rom3(four(), curve_type=CHORDAL)
    assert_xyz(open.point(0.3), 0.8595, 1.881, -0.0405, CLOSE)
    assert_xyz(open.point(0.5), 2.002351, 2.233911, 0.442698, CLOSE)
    var shut = catmull_rom3(four(), True, CHORDAL)
    assert_xyz(shut.point(0.3), 1.352602, 2.155881, 0.137331, CLOSE)
    assert_xyz(shut.point(0.9), 1.385351, -0.610489, 0.845298, CLOSE)
    assert_almost_equal(shut.length().to(METER), Float32(12.017255), atol=1e-3)


def test_uniform_points_match_three_js() raises:
    var open = catmull_rom3(four(), False, CATMULLROM, 0.3)
    assert_xyz(open.point(0.3), 0.9045, 1.9062, -0.0243, CLOSE)
    assert_xyz(open.point(0.5), 2, 2.15, 0.4625, CLOSE)
    assert_xyz(open.point(1), 4, 0, 2, CLOSE)
    var shut = catmull_rom3(four(), True, CATMULLROM, 0.3)
    assert_xyz(shut.point(0.3), 1.2944, 2.096, 0.1232, CLOSE)
    assert_xyz(shut.point(0.9), 1.4512, -0.144, 0.7616, CLOSE)
    assert_almost_equal(shut.length().to(METER), Float32(11.666906), atol=1e-3)


def test_repeated_points_are_spaced_as_three_js_spaces_them() raises:
    var doubled = catmull_rom3(
        [
            Vector3(0, 0, 0),
            Vector3(0, 0, 0),
            Vector3(1, 0, 0),
            Vector3(1, 0, 0),
            Vector3(2, 1, 0),
        ]
    )
    assert_xyz(doubled.point(0.1), -0.048, 0, 0, CLOSE)
    assert_xyz(doubled.point(0.3), 0.152, 0, 0, CLOSE)
    assert_xyz(doubled.point(0.6), 1.035125, -0.036875, 0, CLOSE)
    # Where two points repeat the curve stands still, and has no direction.
    with assert_raises():
        _ = doubled.tangent(0)


def test_a_spline_of_two_points_is_the_run_between_them() raises:
    # three.js keeps both made-up end points in one scratch vector, and
    # here each end has its own.
    var run = catmull_rom3([Vector3(0, 0, 0), Vector3(2, 0, 0)])
    assert_xyz(run.point(0.5), 1, 0, 0, CLOSE)
    assert_xyz(run.tangent(0.5), 1, 0, 0, CLOSE)


def test_arc_length_matches_three_js() raises:
    var open = catmull_rom3(four())
    assert_almost_equal(open.length().to(METER), Float32(7.066615), atol=1e-3)
    assert_xyz(open.point_at(0.25), 0.672797, 1.629116, -0.07088, 1e-3)
    assert_xyz(open.tangent_at(0.25), 0.510269, 0.859067, 0.040368, TURNING)
    var spaced = open.spaced_points(4)
    assert_equal(len(spaced), 5)
    assert_xyz(spaced[1], 0.672797, 1.629116, -0.07088, 1e-3)
    assert_equal(len(open.sample(6)), 7)
    assert_equal(len(open.lengths(6)), 7)


def test_arc_divisions_grow_with_a_long_spline() raises:
    assert_equal(catmull_rom3(four()).arc_divisions(), 200)
    assert_equal(line3(Vector3(0, 0, 0), Vector3(1, 0, 0)).arc_divisions(), 200)
    var points = List[Vector3]()
    for index in range(41):
        points.append(Vector3(Float32(index % 2), Float32(index), 0))
    assert_equal(catmull_rom3(points^).arc_divisions(), 320)


def test_curve3_refuses_a_parameter_off_the_curve() raises:
    var run = line3(Vector3(0, 0, 0), Vector3(1, 0, 0))
    for bad in [Float32(-0.001), Float32(1.001)]:
        with assert_raises():
            _ = run.point(bad)
        with assert_raises():
            _ = run.tangent(bad)
        with assert_raises():
            _ = run.point_at(bad)
        with assert_raises():
            _ = run.tangent_at(bad)
    with assert_raises():
        _ = run.sample(0)
    with assert_raises():
        _ = run.spaced_points(0)
    with assert_raises():
        _ = run.frenet_frames(0, False)


def test_a_folded_quadratic_has_no_direction_at_its_turn() raises:
    var folded = quadratic_bezier3(
        Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 0)
    )
    with assert_raises():
        _ = folded.tangent(0.5)


# --- frames -----------------------------------------------------------------


def test_frenet_frames_match_three_js() raises:
    var frames = catmull_rom3(four()).frenet_frames(8, False)
    assert_equal(frames.count(), 9)
    assert_xyz(frames.tangents[0], 0.447106, 0.894481, -0.000067, TURNING)
    assert_xyz(frames.normals[0], -0.00003, -0.00006, -1, TURNING)
    assert_xyz(frames.binormals[0], -0.894481, 0.447106, 0, TURNING)
    assert_xyz(frames.tangents[4], 0.888986, -0.044929, 0.455725, TURNING)
    assert_xyz(frames.normals[4], 0.448614, 0.285209, -0.846995, TURNING)
    assert_xyz(frames.binormals[4], -0.091922, 0.957412, 0.273703, TURNING)
    assert_xyz(frames.normals[8], 0.772207, 0.070295, -0.63147, TURNING)
    assert_xyz(frames.binormals[8], 0.486939, 0.572962, 0.659246, TURNING)
    var copied = FrenetFrames(copy=frames)
    frames.normals.append(Vector3(0, 0, 1))
    assert_equal(copied.count(), 9)
    assert_equal(len(frames.normals), 10)


def loop() raises -> Curve3:
    """Return the closed wavy ring the three.js reference ran on."""
    var points = List[Vector3]()
    for index in range(8):
        var a = Float32(index) / 8 * 2 * Float32(pi)
        points.append(Vector3(cos(a) * 2, sin(a) * 2, sin(2 * a) * 0.5))
    return catmull_rom3(points^, closed=True)


def test_closed_frenet_frames_match_three_js() raises:
    var frames = loop().frenet_frames(12, True)
    assert_xyz(frames.normals[0], -1, -0.000381, -0.000135, TURNING)
    assert_xyz(frames.normals[6], 1, -0.000134, -0.000379, TURNING)
    assert_xyz(frames.binormals[6], 0.000402, 0.333501, 0.94275, TURNING)
    assert_xyz(frames.normals[12], -1, 0.000649, -0.000624, TURNING)


def test_first_normal_picks_the_axis_the_tangent_leans_least_along() raises:
    # Least along z: the normal lies in the plane of the tangent and z.
    assert_xyz(first_normal(Vector3(0.6, 0.8, 0)), 0, 0, -1, CLOSE)
    # Least along y.
    assert_xyz(first_normal(Vector3(0.6, 0, 0.8)), 0, -1, 0, CLOSE)
    # Least along x.
    assert_xyz(first_normal(Vector3(0, 0.6, 0.8)), -1, 0, 0, CLOSE)


def test_transport_frames_refuse_what_has_no_frame() raises:
    with assert_raises():
        _ = transport_frames([Vector3(1, 0, 0)], False)
    with assert_raises():
        _ = transport_frames([Vector3(1, 0, 0), Vector3(-1, 0, 0)], False)
    # Two tangents the same way carry the frame across unturned.
    var straight = transport_frames([Vector3(1, 0, 0), Vector3(1, 0, 0)], False)
    assert_xyz(straight.normals[1], 0, 0, -1, CLOSE)
    assert_true(STRAIGHT > 0)


def test_closed_frames_spread_their_twist_either_way() raises:
    # A square loop tilted up at one corner builds up a twist; seen from
    # either direction round, the spread brings the last normal back to
    # the first.
    var ways = List[List[Vector3]]()
    ways.append(
        [
            Vector3(1, 0, 0),
            Vector3(0, 1, 0),
            Vector3(0, 0, 1),
            Vector3(1, 0, 0),
        ]
    )
    ways.append(
        [
            Vector3(1, 0, 0),
            Vector3(0, 0, 1),
            Vector3(0, 1, 0),
            Vector3(1, 0, 0),
        ]
    )
    for way in range(2):
        var frames = transport_frames(ways[way], True)
        assert_xyz(
            frames.normals[3],
            frames.normals[0].x,
            frames.normals[0].y,
            frames.normals[0].z,
            CLOSE,
        )


# --- the tube ---------------------------------------------------------------


def test_a_tube_along_a_curve_matches_three_js() raises:
    var pipe = tube(catmull_rom3(four()), Length(0.25, METER), 8, 6)
    assert_equal(pipe.vertex_count(), 63)
    assert_equal(pipe.triangle_count(), 96)
    ref positions = pipe.attribute_view(String(POSITION))
    ref uvs = pipe.attribute_view(String(UV))
    assert_xyz(positions.vector3(0), 0, 0, 0.25, 1e-3)
    assert_xyz(positions.vector3(3), 0, 0, -0.25, 1e-3)
    assert_xyz(positions.vector3(30), 2.150741, 2.481369, 0.451059, 1e-3)
    assert_xyz(positions.vector3(61), 3.798049, -0.132837, 1.936203, 1e-3)
    assert_almost_equal(uvs.component(30, 0), Float32(0.5), atol=CLOSE)
    assert_almost_equal(uvs.component(30, 1), Float32(1.0 / 3), atol=CLOSE)
    assert_almost_equal(uvs.component(61, 0), Float32(1), atol=CLOSE)


def test_a_closed_tube_along_a_curve_ends_on_its_first_ring() raises:
    var pipe = tube(loop(), Length(0.1, METER), 12, 4, closed=True)
    ref positions = pipe.attribute_view(String(POSITION))
    ref normals = pipe.attribute_view(String(NORMAL))
    for step in range(5):
        var first = positions.vector3(step)
        var last = positions.vector3(12 * 5 + step)
        assert_xyz(last, first.x, first.y, first.z, 0)
        var n = normals.vector3(12 * 5 + step)
        assert_almost_equal(n.length(), Float32(1), atol=CLOSE)


def test_a_tube_along_a_curve_refuses_what_it_cannot_build() raises:
    var curve = catmull_rom3(four())
    with assert_raises():
        _ = tube(curve, Length(0.1, METER), 0)
    with assert_raises():
        _ = tube(curve, Length(0, METER))
    with assert_raises():
        _ = tube(curve, Length(0.1, METER), 8, 2)
    # The default is three.js's: 64 along and 8 around.
    assert_equal(tube(curve, Length(0.1, METER)).vertex_count(), 65 * 9)


# --- CurvePath3 -------------------------------------------------------------


def corner() raises -> CurvePath3:
    """Return a straight run then a quadratic, as the three.js reference
    drew them."""
    var path = CurvePath3()
    path.add(line3(Vector3(0, 0, 0), Vector3(3, 0, 0)))
    path.add(
        quadratic_bezier3(Vector3(3, 0, 0), Vector3(4, 0, 0), Vector3(4, 1, 0))
    )
    return path^


def test_curve_path_matches_three_js() raises:
    var path = corner()
    assert_equal(path.curve_count(), 2)
    var lengths = path.curve_lengths()
    assert_almost_equal(lengths[0], Float32(3), atol=CLOSE)
    assert_almost_equal(lengths[1], Float32(4.623221), atol=1e-3)
    assert_almost_equal(path.length().to(METER), Float32(4.623221), atol=1e-3)
    assert_xyz(path.point(0), 0, 0, 0, CLOSE)
    assert_xyz(path.point(0.5), 2.311611, 0, 0, 1e-3)
    assert_xyz(path.point(0.9), 3.931488, 0.545015, 0, 1e-3)
    assert_xyz(path.tangent(0.5), 1, 0, 0, CLOSE)
    assert_xyz(path.tangent(1), 0, 1, 0, CLOSE)
    # One run for the line and four for the quadratic, the join once.
    assert_equal(len(path.sample(4)), 6)
    var spaced = path.spaced_points(4)
    assert_equal(len(spaced), 5)
    assert_xyz(spaced[3], 3.459778, 0.070226, 0, 1e-3)
    assert_xyz(spaced[4], 4, 1, 0, 1e-3)
    var frames = path.frenet_frames(4, False)
    assert_equal(frames.count(), 5)
    var copied = CurvePath3(copy=path)
    path.close_path()
    assert_equal(copied.curve_count(), 2)
    assert_equal(path.curve_count(), 3)


def test_curve_path_sample_keeps_a_gap() raises:
    # Nothing joins two curves that do not meet: both ends are kept.
    var path = CurvePath3()
    path.add(line3(Vector3(0, 0, 0), Vector3(1, 0, 0)))
    path.add(line3(Vector3(2, 0, 0), Vector3(3, 0, 0)))
    assert_equal(len(path.sample(4)), 4)


def test_curve_path_closes() raises:
    var path = corner()
    path.close_path()
    assert_equal(path.curve_count(), 3)
    with assert_raises():
        path.close_path()


def test_an_empty_curve_path_is_refused() raises:
    var path = CurvePath3()
    with assert_raises():
        path.close_path()
    with assert_raises():
        _ = path.length()
    with assert_raises():
        _ = path.point(0.5)
    with assert_raises():
        _ = path.sample(4)
    with assert_raises():
        _ = path.spaced_points(4)
    var full = corner()
    with assert_raises():
        _ = full.point(1.5)
    with assert_raises():
        _ = full.point(-0.5)
    with assert_raises():
        _ = full.sample(0)
    with assert_raises():
        _ = full.spaced_points(0)
    with assert_raises():
        _ = full.frenet_frames(0, False)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
