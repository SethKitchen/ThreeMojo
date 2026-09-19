# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the humanoid spec, osteometric femur and the femur mesh."""

from core.buffer_geometry import NORMAL, POSITION, UV
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.leg.femur.dimensions import (
    MAX_STATURE,
    MIN_STATURE,
    _sd_segment,
    femur_dimensions,
    femur_distance,
)
from extensions.humanoid.skeleton.leg.femur.geometry import (
    _direction,
    femur,
    femur_from_dimensions,
)
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import CENTIMETER, FOOT, Length, METER

comptime TOLERANCE = Float64(1e-5)


def test_male_and_female_are_valid() raises:
    assert_true(MALE.is_valid())
    assert_true(FEMALE.is_valid())
    assert_false(Sex(2).is_valid())
    assert_false(Sex(-1).is_valid())


def test_right_and_left_are_valid() raises:
    assert_true(RIGHT.is_valid())
    assert_true(LEFT.is_valid())
    assert_false(BodySide(2).is_valid())
    assert_false(BodySide(-1).is_valid())


def test_six_foot_male_femur_length_matches_trotter_gleser() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var stature_cm = Length(6.0, FOOT).to(CENTIMETER)
    var expected_cm = (stature_cm - Float32(61.41)) / Float32(2.38)
    assert_almost_equal(dims.length.to(CENTIMETER), expected_cm, atol=TOLERANCE)
    assert_true(dims.sex == MALE)
    assert_true(dims.side == RIGHT)


def test_six_foot_female_uses_the_female_line() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), FEMALE)
    var stature_cm = Length(6.0, FOOT).to(CENTIMETER)
    var expected_cm = (stature_cm - Float32(54.10)) / Float32(2.47)
    assert_almost_equal(dims.length.to(CENTIMETER), expected_cm, atol=TOLERANCE)
    assert_true(dims.sex == FEMALE)


def test_head_diameter_scales_with_femur_length() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    assert_almost_equal(
        dims.head_diameter.value,
        dims.length.value * Float32(0.1030),
        atol=TOLERANCE,
    )


def test_right_head_is_medial() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE, RIGHT)
    assert_true(dims.head_center.x < dims.greater_trochanter.x)
    assert_true(dims.head_center.x < dims.neck_base.x)


def test_left_head_is_medial_on_the_other_side() raises:
    var right = femur_dimensions(Length(6.0, FOOT), MALE, RIGHT)
    var left = femur_dimensions(Length(6.0, FOOT), MALE, LEFT)
    assert_almost_equal(
        left.head_center.x, -right.head_center.x, atol=TOLERANCE
    )
    assert_almost_equal(left.head_center.y, right.head_center.y, atol=TOLERANCE)
    assert_true(left.head_center.x > left.greater_trochanter.x)
    assert_true(left.side == LEFT)


def test_taller_male_has_a_longer_femur() raises:
    var short = femur_dimensions(Length(5.0, FOOT), MALE)
    var tall = femur_dimensions(Length(6.0, FOOT), MALE)
    assert_true(tall.length > short.length)
    assert_true(tall.head_diameter > short.head_diameter)
    assert_true(tall.bicondylar_width > short.bicondylar_width)


def test_midshaft_is_inside_and_a_far_point_is_outside() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    assert_true(femur_distance(dims, dims.neck_base) < 0)
    assert_true(femur_distance(dims, Vector3(10, 0, 0)) > 0)


def test_head_center_is_inside_the_solid() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    assert_true(femur_distance(dims, dims.head_center) < 0)


def test_condyle_center_is_inside_the_solid() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), FEMALE, LEFT)
    assert_true(femur_distance(dims, dims.medial_condyle) < 0)
    assert_true(femur_distance(dims, dims.lateral_condyle) < 0)


def test_greater_trochanter_is_inside_the_solid() raises:
    var dims = femur_dimensions(Length(1.2, METER), MALE)
    assert_true(femur_distance(dims, dims.greater_trochanter) < 0)
    assert_true(femur_distance(dims, dims.lesser_trochanter) < 0)


def test_direction_of_a_zero_span_is_plus_y() raises:
    var origin = Vector3(1, 2, 3)
    var zero = _direction(origin, origin)
    assert_equal(zero.x, Float32(0))
    assert_equal(zero.y, Float32(1))
    assert_equal(zero.z, Float32(0))
    var unit = _direction(Vector3(0, 0, 0), Vector3(3, 0, 0))
    assert_almost_equal(unit.x, Float32(1), atol=TOLERANCE)


def test_a_degenerated_segment_is_a_sphere() raises:
    var at = Vector3(1, 2, 3)
    var on = _sd_segment(at, at, at, 0.5, 0.25)
    assert_almost_equal(on, Float32(-0.5), atol=TOLERANCE)
    var away = _sd_segment(Vector3(1, 2, 4), at, at, 0.5, 0.25)
    assert_almost_equal(away, Float32(0.5), atol=TOLERANCE)


def test_spec_holds_stature_and_sex() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    assert_equal(person.stature.value, Length(6.0, FOOT).value)
    assert_true(person.sex == MALE)


def test_femur_mesh_has_positions_normals_and_uvs() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var bone = femur(person, RIGHT, 8)
    assert_true(bone.has_attribute(String(POSITION)))
    assert_true(bone.has_attribute(String(NORMAL)))
    assert_true(bone.has_attribute(String(UV)))
    assert_true(bone.vertex_count() > 0)
    assert_true(bone.triangle_count() > 0)
    assert_true(len(bone.index) > 0)
    ref normals = bone.attribute_view(String(NORMAL))
    for vertex in range(bone.vertex_count()):
        var n = normals.vector3(vertex)
        assert_almost_equal(n.length(), Float32(1), atol=Float64(1e-3))
    var box = bone.bounding_box()
    var span = box.max.y - box.min.y
    var length = femur_dimensions(Length(6.0, FOOT), MALE).length.value
    assert_true(span > length * Float32(0.70))
    assert_true(span < length * Float32(1.30))


def test_more_detail_makes_more_triangles() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), FEMALE)
    var coarse = femur(person, LEFT, 8)
    var finer = femur(person, LEFT, 12)
    assert_true(finer.triangle_count() > coarse.triangle_count())


def test_left_mesh_mirrors_the_right() raises:
    var person = HumanoidSpec(Length(5.5, FOOT), MALE)
    var right = femur(person, RIGHT, 8)
    var left = femur(person, LEFT, 8)
    var right_box = right.bounding_box()
    var left_box = left.bounding_box()
    assert_true(right_box.min.x < 0)
    assert_true(left_box.max.x > 0)
    assert_almost_equal(-right_box.min.x, left_box.max.x, atol=Float64(1e-3))


def test_refuses_an_invalid_sex() raises:
    with assert_raises():
        _ = femur_dimensions(Length(6.0, FOOT), Sex(9))


def test_refuses_an_invalid_side() raises:
    with assert_raises():
        _ = femur_dimensions(Length(6.0, FOOT), MALE, BodySide(9))


def test_refuses_a_short_stature() raises:
    with assert_raises():
        _ = femur_dimensions(Length(1.19, METER), MALE)


def test_refuses_a_tall_stature() raises:
    with assert_raises():
        _ = femur_dimensions(Length(2.51, METER), FEMALE)


def test_refuses_a_non_finite_stature() raises:
    with assert_raises():
        _ = femur_dimensions(Length(nan[DType.float32](), METER), MALE)
    with assert_raises():
        _ = femur_dimensions(Length(inf[DType.float32](), METER), FEMALE)


def test_stature_bounds_are_accepted() raises:
    var short = femur_dimensions(MIN_STATURE, FEMALE)
    var tall = femur_dimensions(MAX_STATURE, MALE)
    assert_true(tall.length > short.length)


def test_refuses_a_low_detail() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = femur_from_dimensions(dims, 7)


def test_refuses_a_high_detail() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = femur_from_dimensions(dims, 65)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
