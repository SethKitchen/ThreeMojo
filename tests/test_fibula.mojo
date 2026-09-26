# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the stature-scaled fibula."""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import MAX_STATURE, MIN_STATURE, HumanoidSpec
from extensions.humanoid.skeleton.occupancy import (
    CORTICAL_FILL,
    EMPTY,
    MARROW,
    MAX_STEP,
    MIN_STEP,
    TRABECULAR_FILL,
)
from extensions.humanoid.skeleton.tissue import (
    BoneKind,
    cortical_tissue,
    trabecular_tissue,
)
from extensions.humanoid.skeleton.leg.fibula.dimensions import (
    FibulaField,
    fibula_dimensions,
    fibula_distance,
)
from extensions.humanoid.skeleton.leg.fibula.geometry import (
    fibula,
    fibula_from_dimensions,
)
from extensions.humanoid.skeleton.leg.fibula.mass import (
    fibula_mass,
    fibula_mass_from_dimensions,
    fibula_occupancy,
)
from math.vector3 import Vector3
from std.math import inf, nan
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import (
    CENTIMETER,
    FOOT,
    GRAM,
    Length,
    METER,
    MILLIMETER,
    NEWTON,
    STANDARD_GRAVITY,
)

comptime TOLERANCE = Float64(1e-5)


def test_six_foot_male_fibula_length_matches_trotter_gleser() raises:
    var dims = fibula_dimensions(Length(6.0, FOOT), MALE)
    var stature_cm = Length(6.0, FOOT).to(CENTIMETER)
    var expected_cm = (stature_cm - Float32(71.78)) / Float32(2.68)
    assert_almost_equal(dims.length.to(CENTIMETER), expected_cm, atol=TOLERANCE)
    assert_true(dims.side == RIGHT)


def test_six_foot_female_uses_the_female_fibula_line() raises:
    var dims = fibula_dimensions(Length(6.0, FOOT), FEMALE)
    var stature_cm = Length(6.0, FOOT).to(CENTIMETER)
    var expected_cm = (stature_cm - Float32(59.61)) / Float32(2.93)
    assert_almost_equal(dims.length.to(CENTIMETER), expected_cm, atol=TOLERANCE)


def test_left_fibula_mirrors_the_right() raises:
    var right = fibula_dimensions(Length(6.0, FOOT), MALE, RIGHT)
    var left = fibula_dimensions(Length(6.0, FOOT), MALE, LEFT)
    assert_almost_equal(
        left.head_center.x, -right.head_center.x, atol=TOLERANCE
    )
    assert_true(left.side == LEFT)


def test_landmarks_are_inside_the_solid() raises:
    var dims = fibula_dimensions(Length(6.0, FOOT), FEMALE, LEFT)
    assert_true(fibula_distance(dims, dims.head_center) < 0)
    assert_true(fibula_distance(dims, dims.lateral_malleolus) < 0)
    assert_true(fibula_distance(dims, dims.styloid) < 0)
    assert_true(fibula_distance(dims, Vector3(10, 0, 0)) > 0)


def test_midshaft_ap_and_ml_are_independent() raises:
    var dims = fibula_dimensions(Length(6.0, FOOT), MALE)
    var tall_ap = dims
    tall_ap.midshaft_ap = Length(16.0, MILLIMETER)
    tall_ap.midshaft_ml = Length(8.0, MILLIMETER)
    tall_ap.validate()
    var round = dims
    round.midshaft_ap = Length(12.0, MILLIMETER)
    round.midshaft_ml = Length(12.0, MILLIMETER)
    round.validate()
    var field_ap = FibulaField(tall_ap)
    var field_round = FibulaField(round)
    var anterior = Vector3(
        field_ap.s2.x, field_ap.s2.y, field_ap.s2.z + Float32(0.007)
    )
    var lateral = Vector3(
        field_ap.s2.x + Float32(0.007), field_ap.s2.y, field_ap.s2.z
    )
    assert_true(field_ap.distance(anterior) < field_round.distance(anterior))
    assert_true(field_ap.distance(lateral) > field_round.distance(lateral))


def test_gradient_at_a_far_point_points_out() raises:
    var n = FibulaField(fibula_dimensions(Length(6.0, FOOT), MALE)).gradient(
        Vector3(10, 0, 0)
    )
    assert_almost_equal(n.length(), Float32(1), atol=Float64(1e-3))
    assert_true(n.x > 0)


def test_fibula_mesh_has_positions_normals_and_uvs() raises:
    var bone = fibula(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT, 8)
    assert_true(bone.has_attribute(String(POSITION)))
    assert_true(bone.has_attribute(String(NORMAL)))
    assert_true(bone.has_attribute(String(UV)))
    assert_true(bone.triangle_count() > 0)
    ref normals = bone.attribute_view(String(NORMAL))
    for vertex in range(bone.vertex_count()):
        assert_almost_equal(
            normals.vector3(vertex).length(), Float32(1), atol=Float64(1e-3)
        )
    var span = bone.bounding_box().max.y - bone.bounding_box().min.y
    var length = fibula_dimensions(Length(6.0, FOOT), MALE).length.value
    assert_true(span > length * Float32(0.70))
    assert_true(span < length * Float32(1.40))
    _assert_outward_and_short(bone)


def test_stature_bounds_and_refusals() raises:
    fibula_dimensions(MIN_STATURE, FEMALE).validate()
    fibula_dimensions(MAX_STATURE, MALE).validate()
    with assert_raises():
        _ = fibula_dimensions(Length(1.19, METER), MALE)
    with assert_raises():
        _ = fibula_dimensions(Length(2.51, METER), FEMALE)
    with assert_raises():
        _ = fibula_dimensions(Length(inf[DType.float32](), METER), MALE)
    with assert_raises():
        _ = fibula_dimensions(Length(6.0, FOOT), Sex(9))
    with assert_raises():
        _ = fibula_dimensions(Length(6.0, FOOT), MALE, BodySide(9))


def test_refuses_invalid_detail() raises:
    var dims = fibula_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = fibula_from_dimensions(dims, 7)
    with assert_raises():
        _ = fibula_from_dimensions(dims, 65)


def test_validate_refuses_zero_and_bad_edits() raises:
    var dims = fibula_dimensions(Length(6.0, FOOT), MALE)
    dims.head_diameter = Length(0)
    with assert_raises():
        dims.validate()
    with assert_raises():
        _ = fibula_from_dimensions(dims, 8)
    with assert_raises():
        _ = fibula_distance(dims, Vector3(0, 0, 0))
    with assert_raises():
        _ = fibula_occupancy(dims, Vector3(0, 0, 0))
    with assert_raises():
        _ = fibula_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            Length(20.0, MILLIMETER),
        )
    dims = fibula_dimensions(Length(6.0, FOOT), MALE)
    dims.lateral_bow = Length(-0.01, METER)
    with assert_raises():
        dims.validate()
    dims = fibula_dimensions(Length(6.0, FOOT), MALE)
    dims.styloid = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises():
        dims.validate()
    dims = fibula_dimensions(Length(6.0, FOOT), MALE)
    dims.head_center = Vector3(0, nan[DType.float32](), 0)
    with assert_raises():
        dims.validate()
    dims = fibula_dimensions(Length(6.0, FOOT), MALE)
    dims.lateral_malleolus = Vector3(0, 0, nan[DType.float32]())
    with assert_raises():
        dims.validate()


def test_occupancy_regions() raises:
    var dims = fibula_dimensions(Length(6.0, FOOT), MALE)
    var field = FibulaField(dims)
    assert_true(fibula_occupancy(dims, Vector3(10, 0, 0)) == EMPTY)
    assert_true(fibula_occupancy(dims, field.s2) == MARROW)
    assert_true(fibula_occupancy(dims, dims.head_center) == TRABECULAR_FILL)
    assert_true(
        fibula_occupancy(dims, dims.lateral_malleolus) == TRABECULAR_FILL
    )
    assert_true(fibula_occupancy(dims, field.s0) != MARROW)
    assert_true(fibula_occupancy(dims, field.s4) != MARROW)
    var found_shell = False
    var i = 0
    while i < 20:
        var p = Vector3(
            field.s2.x + Float32(i) * Float32(0.001), field.s2.y, field.s2.z
        )
        if fibula_occupancy(dims, p) == CORTICAL_FILL:
            found_shell = True
        i = i + 1
    assert_true(found_shell)


def test_mass_contract() raises:
    var report = fibula_mass(
        HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT, Length(20.0, MILLIMETER)
    )
    var grams = report.mass.to(GRAM)
    assert_true(grams > Float32(8))
    assert_true(grams < Float32(400))
    assert_true(report.solid_tissue.value > 0)
    assert_true(report.weight().to(NEWTON) > Float32(0.05))
    assert_almost_equal(
        report.weight().value,
        report.mass.value * STANDARD_GRAVITY.value,
        atol=TOLERANCE,
    )


def test_full_porosity_has_no_mass_but_keeps_regions() raises:
    var cortical = cortical_tissue()
    cortical.porosity = Float32(1)
    var trabecular = trabecular_tissue()
    trabecular.porosity = Float32(1)
    var report = fibula_mass_from_dimensions(
        fibula_dimensions(Length(6.0, FOOT), MALE),
        cortical,
        trabecular,
        Length(20.0, MILLIMETER),
    )
    assert_equal(report.mass.value, Float32(0))
    assert_true(report.cortical_region.value > 0)


def test_left_and_right_masses_agree() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var step = Length(10.0, MILLIMETER)
    var right = fibula_mass(person, RIGHT, step)
    var left = fibula_mass(person, LEFT, step)
    var scale = right.mass.value
    if scale < left.mass.value:
        scale = left.mass.value
    var gap = right.mass.value - left.mass.value
    if gap < 0:
        gap = -gap
    assert_true(gap < scale * Float32(0.20))


def test_a_taller_fibula_has_more_mass() raises:
    var step = Length(20.0, MILLIMETER)
    var short = fibula_mass(HumanoidSpec(Length(5.0, FOOT), FEMALE), LEFT, step)
    var tall = fibula_mass(HumanoidSpec(Length(6.5, FOOT), MALE), RIGHT, step)
    assert_true(tall.mass > short.mass)


def test_mass_refuses_bad_step_and_tissue() raises:
    var dims = fibula_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = fibula_mass_from_dimensions(
            dims, cortical_tissue(), trabecular_tissue(), MIN_STEP.scaled(0.5)
        )
    with assert_raises():
        _ = fibula_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            MAX_STEP + Length(1.0, MILLIMETER),
        )
    with assert_raises():
        _ = fibula_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            Length(nan[DType.float32](), MILLIMETER),
        )
    var bad = cortical_tissue()
    bad.kind = BoneKind(9)
    with assert_raises():
        _ = fibula_mass_from_dimensions(
            dims, bad, trabecular_tissue(), Length(10.0, MILLIMETER)
        )
    var worse = trabecular_tissue()
    worse.kind = BoneKind(9)
    with assert_raises():
        _ = fibula_mass_from_dimensions(
            dims, cortical_tissue(), worse, Length(10.0, MILLIMETER)
        )


def _assert_outward_and_short(bone: BufferGeometry) raises:
    """Refuse a triangle that winds against its stored normals or spans a gap.
    """
    ref pos = bone.attribute_view(String(POSITION))
    ref normals = bone.attribute_view(String(NORMAL))
    for triangle in range(bone.triangle_count()):
        var ia = bone.corner_index(triangle, 0)
        var ib = bone.corner_index(triangle, 1)
        var ic = bone.corner_index(triangle, 2)
        var a = pos.vector3(ia)
        var b = pos.vector3(ib)
        var c = pos.vector3(ic)
        var ab = b - a
        var ac = c - a
        var bc = c - b
        assert_true(ab.length() < Float32(0.08))
        assert_true(ac.length() < Float32(0.08))
        assert_true(bc.length() < Float32(0.08))
        ab.cross(ac)
        if ab.length() < Float32(1e-10):
            continue
        var mean = (
            normals.vector3(ia) + normals.vector3(ib) + normals.vector3(ic)
        )
        assert_true(ab.dot(mean) > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
