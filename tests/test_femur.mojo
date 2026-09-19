# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the humanoid spec, osteometric femur and the femur mesh."""

from core.buffer_geometry import NORMAL, POSITION, UV
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import (
    BoneKind,
    cortical_tissue,
    trabecular_tissue,
)
from extensions.humanoid.skeleton.leg.femur.dimensions import (
    MAX_STATURE,
    MIN_STATURE,
    FemurField,
    _sd_segment,
    femur_dimensions,
    femur_distance,
)
from extensions.humanoid.skeleton.leg.femur.geometry import (
    _direction,
    femur,
    femur_from_dimensions,
)
from extensions.humanoid.skeleton.leg.femur.mass import (
    CORTICAL_FILL,
    EMPTY,
    MARROW,
    MAX_STEP,
    MIN_STEP,
    TRABECULAR_FILL,
    BoneOccupancy,
    _Tally,
    _cells,
    add_fill,
    femur_mass,
    femur_mass_from_dimensions,
    femur_occupancy,
    mineral_density,
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
from units.si import (
    CENTIMETER,
    CUBIC_CENTIMETER,
    FOOT,
    GRAM,
    Length,
    METER,
    MILLIMETER,
    NEWTON,
    STANDARD_GRAVITY,
)

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


def test_occupancy_outside_is_empty() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    assert_true(femur_occupancy(dims, Vector3(10, 0, 0)) == EMPTY)
    assert_false(BoneOccupancy(9).is_valid())
    assert_false(BoneOccupancy(-1).is_valid())
    assert_true(EMPTY.is_valid())
    assert_true(CORTICAL_FILL.is_valid())
    assert_true(TRABECULAR_FILL.is_valid())
    assert_true(MARROW.is_valid())


def test_head_interior_is_trabecular() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    assert_true(femur_occupancy(dims, dims.head_center) == TRABECULAR_FILL)


def test_condyle_interior_is_trabecular() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), FEMALE, LEFT)
    assert_true(femur_occupancy(dims, dims.medial_condyle) == TRABECULAR_FILL)


def test_just_inside_the_head_is_cortical() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var radius = dims.head_diameter.value * Float32(0.5)
    var shell = Vector3(
        dims.head_center.x + radius - Float32(0.002),
        dims.head_center.y,
        dims.head_center.z,
    )
    assert_true(femur_occupancy(dims, shell) == CORTICAL_FILL)


def test_midshaft_cavity_is_marrow() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var field = FemurField(dims)
    assert_true(femur_occupancy(dims, field.s2) == MARROW)


def test_distal_shaft_center_is_not_marrow() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var field = FemurField(dims)
    assert_true(femur_occupancy(dims, field.s0) != MARROW)


def test_proximal_shaft_center_is_not_marrow() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var field = FemurField(dims)
    assert_true(femur_occupancy(dims, field.s4) != MARROW)


def test_mineral_density_matches_the_fill() raises:
    var cortical = cortical_tissue()
    var trabecular = trabecular_tissue()
    assert_equal(mineral_density(EMPTY, cortical, trabecular).value, Float32(0))
    assert_equal(
        mineral_density(MARROW, cortical, trabecular).value, Float32(0)
    )
    assert_equal(
        mineral_density(CORTICAL_FILL, cortical, trabecular).value,
        cortical.apparent_density().value,
    )
    assert_equal(
        mineral_density(TRABECULAR_FILL, cortical, trabecular).value,
        trabecular.apparent_density().value,
    )
    with assert_raises():
        _ = mineral_density(BoneOccupancy(9), cortical, trabecular)


def test_six_foot_male_mass_is_a_few_hundred_grams() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = femur_mass(person, RIGHT, Length(20.0, MILLIMETER))
    var grams = report.mass.to(GRAM)
    assert_true(grams > Float32(80))
    assert_true(grams < Float32(1500))
    var envelope_cm3 = report.envelope.to(CUBIC_CENTIMETER)
    assert_true(envelope_cm3 > Float32(50))
    assert_true(envelope_cm3 < Float32(2000))
    assert_true(report.envelope >= report.bone)
    assert_true(report.cortical.value > 0)
    assert_true(report.trabecular.value > 0)
    var weight = report.weight()
    assert_almost_equal(
        weight.value, report.mass.value * STANDARD_GRAVITY.value, atol=TOLERANCE
    )
    assert_true(weight.to(NEWTON) > Float32(0.5))
    var moon = report.weight(STANDARD_GRAVITY.scaled(0.165))
    assert_true(moon < weight)


def test_a_taller_femur_has_more_mass() raises:
    var step = Length(20.0, MILLIMETER)
    var short = femur_mass(HumanoidSpec(Length(5.0, FOOT), FEMALE), LEFT, step)
    var tall = femur_mass(HumanoidSpec(Length(6.5, FOOT), MALE), RIGHT, step)
    assert_true(tall.mass > short.mass)
    assert_true(tall.envelope > short.envelope)


def test_add_fill_counts_every_occupancy() raises:
    var cortical = cortical_tissue()
    var trabecular = trabecular_tissue()
    var tally = _Tally(0, 0, 0, 0)
    add_fill(tally, EMPTY, 1.0, cortical, trabecular)
    assert_equal(tally.envelope, Float32(0))
    assert_equal(tally.mass, Float32(0))
    add_fill(tally, CORTICAL_FILL, 2.0, cortical, trabecular)
    assert_almost_equal(tally.cortical, Float32(2), atol=TOLERANCE)
    add_fill(tally, TRABECULAR_FILL, 3.0, cortical, trabecular)
    assert_almost_equal(tally.trabecular, Float32(3), atol=TOLERANCE)
    var mass_before = tally.mass
    add_fill(tally, MARROW, 4.0, cortical, trabecular)
    assert_almost_equal(tally.envelope, Float32(9), atol=TOLERANCE)
    assert_equal(tally.mass, mass_before)


def test_a_span_shorter_than_the_step_still_has_one_cell() raises:
    assert_equal(_cells(Float32(0.01), Float32(1.0)), 1)
    assert_true(_cells(Float32(0.55), Float32(0.005)) > 1)


def test_refuses_a_short_mass_step() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = femur_mass_from_dimensions(
            dims, cortical_tissue(), trabecular_tissue(), MIN_STEP.scaled(0.5)
        )


def test_refuses_a_long_mass_step() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = femur_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            MAX_STEP + Length(1.0, MILLIMETER),
        )


def test_refuses_a_non_finite_mass_step() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = femur_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            Length(nan[DType.float32](), MILLIMETER),
        )
    with assert_raises():
        _ = femur_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            Length(inf[DType.float32](), MILLIMETER),
        )


def test_mass_refuses_invalid_tissue() raises:
    var dims = femur_dimensions(Length(6.0, FOOT), MALE)
    var bad = cortical_tissue()
    bad.kind = BoneKind(9)
    with assert_raises():
        _ = femur_mass_from_dimensions(
            dims, bad, trabecular_tissue(), Length(10.0, MILLIMETER)
        )
    var worse = trabecular_tissue()
    worse.kind = BoneKind(9)
    with assert_raises():
        _ = femur_mass_from_dimensions(
            dims, cortical_tissue(), worse, Length(10.0, MILLIMETER)
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
