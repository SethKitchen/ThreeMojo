# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Finite input contracts checked before generated shape allocation."""

from core.buffer_geometry import BufferGeometry, POSITION
from geometries.box import box
from geometries.box_line import box_line
from geometries.capsule import capsule
from geometries.circle import FULL_TURN, check_sweep, circle, ring
from geometries.cylinder import cylinder
from geometries.decal import decal
from geometries.extrude import check_extrusion
from geometries.plane import plane
from geometries.sphere import sphere
from geometries.surface import require_positive_radius
from geometries.torus import torus, torus_knot
from geometries.tube import tube
from math.euler import Euler, XYZ
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from geometries.rounded_box import rounded_box
from std.math import inf, isfinite, nan
from std.testing import TestSuite, assert_equal, assert_raises, assert_true
from units.si import Angle, Length, METER, RADIAN


def test_box_line_refuses_every_nonfinite_extent() raises:
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        for axis in range(3):
            var extents = [Float32(1), Float32(1), Float32(1)]
            extents[axis] = bad
            with assert_raises(contains="finite"):
                _ = box_line(
                    Length(extents[0], METER),
                    Length(extents[1], METER),
                    Length(extents[2], METER),
                )


def test_rounded_box_refuses_nonfinite_extents_and_radius() raises:
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        for field in range(4):
            var values = [Float32(1), Float32(1), Float32(1), Float32(0.1)]
            values[field] = bad
            with assert_raises(contains="finite"):
                _ = rounded_box(
                    Length(values[0], METER),
                    Length(values[1], METER),
                    Length(values[2], METER),
                    1,
                    Length(values[3], METER),
                )


def test_sweep_validation_itself_refuses_nonfinite_angles() raises:
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        with assert_raises(contains="finite"):
            check_sweep(Angle(bad, RADIAN))
    check_sweep(FULL_TURN)
    with assert_raises(contains="positive"):
        check_sweep(Angle(0, RADIAN))
    with assert_raises(contains="full turn"):
        check_sweep(Angle(Float32(FULL_TURN.value * 2), RADIAN))


def test_finite_box_boundaries_keep_their_geometry() raises:
    var lines = box_line(Length(2, METER), Length(4, METER), Length(6, METER))
    var bounds = lines.bounding_box()
    assert_equal(bounds.min.x, Float32(-1))
    assert_equal(bounds.max.y, Float32(2))
    assert_equal(bounds.max.z, Float32(3))
    for radius in [Float32(0), Float32(10)]:
        var rounded = rounded_box(
            Length(2, METER),
            Length(2, METER),
            Length(2, METER),
            1,
            Length(radius, METER),
        )
        assert_equal(rounded.vertex_count(), 324)
        for component in rounded.attribute_view(String(POSITION)).packed():
            assert_true(isfinite(component))
            assert_true(abs(component) <= 1.000001)


def test_shapes_refuse_each_nonfinite_dimension_before_generation() raises:
    var geometry = box(Length(1, METER), Length(1, METER), Length(1, METER))
    for bad in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        with assert_raises(contains="finite"):
            require_positive_radius(bad, "test")
        with assert_raises(contains="finite"):
            _ = circle(Length(bad, METER))
        with assert_raises(contains="finite"):
            _ = sphere(Length(bad, METER))
        for axis in range(3):
            var values = [Float32(1), Float32(1), Float32(1)]
            values[axis] = bad
            with assert_raises(contains="finite"):
                _ = box(
                    Length(values[0], METER),
                    Length(values[1], METER),
                    Length(values[2], METER),
                )
            with assert_raises(contains="finite"):
                _ = cylinder(
                    Length(values[0], METER),
                    Length(values[1], METER),
                    Length(values[2], METER),
                )
            with assert_raises(contains="finite"):
                _ = decal(
                    geometry,
                    Matrix4(),
                    Vector3(0, 0, 0),
                    Euler(
                        Angle(0, RADIAN),
                        Angle(0, RADIAN),
                        Angle(0, RADIAN),
                        XYZ,
                    ),
                    Length(values[0], METER),
                    Length(values[1], METER),
                    Length(values[2], METER),
                )
        for axis in range(2):
            var values = [Float32(1), Float32(2)]
            values[axis] = bad
            with assert_raises(contains="finite"):
                _ = plane(Length(values[0], METER), Length(values[1], METER))
            with assert_raises(contains="finite"):
                _ = ring(Length(values[0], METER), Length(values[1], METER))
            with assert_raises(contains="finite"):
                _ = torus(Length(values[0], METER), Length(values[1], METER))
            with assert_raises(contains="finite"):
                _ = torus_knot(
                    Length(values[0], METER), Length(values[1], METER)
                )


def test_finite_shared_radius_validation_keeps_zero_and_negative_errors() raises:
    require_positive_radius(Float32(1), "test")
    for value in [Float32(0), Float32(-1)]:
        with assert_raises(contains="positive"):
            require_positive_radius(value, "test")


def test_nonfinite_dimensions_fail_before_topology_or_source_reads() raises:
    var bad = Length(inf[DType.float32](), METER)
    var one = Length(1, METER)
    with assert_raises(contains="finite"):
        _ = box(bad, one, one, 0)
    with assert_raises(contains="finite"):
        _ = plane(bad, one, 0)
    with assert_raises(contains="finite"):
        _ = circle(bad, 0)
    with assert_raises(contains="finite"):
        _ = ring(one, bad, 0)
    with assert_raises(contains="finite"):
        _ = cylinder(one, bad, one, 0)
    with assert_raises(contains="finite"):
        _ = torus(one, bad, 0)
    with assert_raises(contains="finite"):
        _ = torus_knot(one, bad, 0)
    with assert_raises(contains="finite"):
        _ = decal(
            BufferGeometry(),
            Matrix4(),
            Vector3(0, 0, 0),
            Euler(Angle(0, RADIAN), Angle(0, RADIAN), Angle(0, RADIAN), XYZ),
            one,
            one,
            bad,
        )


def _bad_lengths() -> List[Float32]:
    return [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]


def test_capsule_length_refuses_nonfinite_values_before_generation() raises:
    var one = Length(1, METER)
    for bad in _bad_lengths():
        with assert_raises(contains="finite"):
            _ = capsule(one, Length(bad, METER), 1, 3, 1)
    var built = capsule(one, Length(0, METER), 1, 3, 1)
    assert_true(built.vertex_count() > 0)


def test_tube_path_points_refuse_nonfinite_values_before_frames() raises:
    var radius = Length(0.2, METER)
    var origin = Vector3(0, 0, 0)
    var ahead = Vector3(1, 0, 0)
    for bad in _bad_lengths():
        for axis in range(3):
            var point = Vector3(1, 0, 0)
            if axis == 0:
                point.x = bad
            elif axis == 1:
                point.y = bad
            else:
                point.z = bad
            with assert_raises(contains="finite"):
                _ = tube([origin, point], radius, 3)
            with assert_raises(contains="finite"):
                _ = tube([point, ahead, origin], radius, 3, closed=True)
    var built = tube([origin, ahead], radius, 3)
    assert_true(built.vertex_count() > 0)


def test_extrusion_refuses_nonfinite_depth_and_bevel_amounts() raises:
    var one = Length(1, METER)
    var zero = Length(0, METER)
    for bad in _bad_lengths():
        var bad_length = Length(bad, METER)
        with assert_raises(contains="finite depth"):
            check_extrusion(bad_length, 1, 1, False, one, one, 1, zero)
        with assert_raises(contains="finite thickness"):
            check_extrusion(one, 1, 1, True, bad_length, one, 1, zero)
        with assert_raises(contains="finite size"):
            check_extrusion(one, 1, 1, True, one, bad_length, 1, zero)
        with assert_raises(contains="finite offset"):
            check_extrusion(one, 1, 1, True, one, zero, 1, bad_length)
        # A bevel that is off does not read those amounts.
        check_extrusion(one, 1, 1, False, bad_length, bad_length, 1, bad_length)
    with assert_raises(contains="positive depth"):
        check_extrusion(zero, 1, 1, False, one, one, 1, zero)
    with assert_raises(contains="positive thickness"):
        check_extrusion(one, 1, 1, True, zero, one, 1, zero)
    with assert_raises(contains="negative distance"):
        check_extrusion(one, 1, 1, True, one, Length(-1, METER), 1, zero)
    with assert_raises(contains="one band"):
        check_extrusion(
            one, 1, 1, True, Length(nan[DType.float32](), METER), one, 0, zero
        )
    # A negative offset is a lip inward, and a size of zero is square.
    check_extrusion(one, 1, 1, True, one, zero, 1, Length(-0.25, METER))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
