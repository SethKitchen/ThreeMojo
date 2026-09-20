# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the stature-scaled tibia."""

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
from extensions.humanoid.skeleton.leg.tibia.dimensions import (
    TibiaField,
    measured_torsion,
    tibia_dimensions,
    tibia_distance,
)
from extensions.humanoid.skeleton.leg.tibia.geometry import (
    tibia,
    tibia_from_dimensions,
)
from extensions.humanoid.skeleton.leg.tibia.mass import (
    tibia_mass,
    tibia_mass_from_dimensions,
    tibia_occupancy,
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
    Angle,
    CENTIMETER,
    CUBIC_CENTIMETER,
    DEGREE,
    FOOT,
    GRAM,
    Length,
    METER,
    MILLIMETER,
    NEWTON,
    STANDARD_GRAVITY,
)

comptime TOLERANCE = Float64(1e-5)


def test_six_foot_male_tibia_length_matches_trotter_gleser() raises:
    var dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    var stature_cm = Length(6.0, FOOT).to(CENTIMETER)
    var expected_cm = (stature_cm - Float32(78.62)) / Float32(2.52)
    assert_almost_equal(dims.length.to(CENTIMETER), expected_cm, atol=TOLERANCE)
    assert_true(dims.sex == MALE)
    assert_true(dims.side == RIGHT)


def test_six_foot_female_uses_the_female_tibia_line() raises:
    var dims = tibia_dimensions(Length(6.0, FOOT), FEMALE)
    var stature_cm = Length(6.0, FOOT).to(CENTIMETER)
    var expected_cm = (stature_cm - Float32(61.53)) / Float32(2.90)
    assert_almost_equal(dims.length.to(CENTIMETER), expected_cm, atol=TOLERANCE)


def test_generated_torsion_matches_the_template() raises:
    var male = tibia_dimensions(Length(6.0, FOOT), MALE)
    var female = tibia_dimensions(Length(6.0, FOOT), FEMALE)
    assert_almost_equal(
        measured_torsion(male).to(DEGREE), Float32(23.0), atol=Float64(2.5)
    )
    assert_almost_equal(
        measured_torsion(female).to(DEGREE), Float32(27.0), atol=Float64(2.5)
    )


def test_measured_torsion_folds_a_negative_angle() raises:
    var dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    var stored = dims.fibular_notch
    dims.fibular_notch = dims.medial_malleolus
    dims.medial_malleolus = stored
    var ang = measured_torsion(dims).to(DEGREE)
    assert_true(ang > Float32(0))
    assert_true(ang < Float32(90))
    var right = tibia_dimensions(Length(6.0, FOOT), MALE, RIGHT)
    var left = tibia_dimensions(Length(6.0, FOOT), MALE, LEFT)
    assert_almost_equal(
        left.medial_condyle.x, -right.medial_condyle.x, atol=TOLERANCE
    )
    assert_true(left.side == LEFT)
    var left_angle = measured_torsion(left).to(DEGREE)
    var right_angle = measured_torsion(right).to(DEGREE)
    assert_almost_equal(left_angle, right_angle, atol=Float64(2.5))


def test_landmarks_are_inside_the_solid() raises:
    var dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    assert_true(tibia_distance(dims, dims.medial_condyle) < 0)
    assert_true(tibia_distance(dims, dims.lateral_condyle) < 0)
    assert_true(tibia_distance(dims, dims.tuberosity) < 0)
    assert_true(tibia_distance(dims, dims.eminence) < 0)
    assert_true(tibia_distance(dims, dims.plafond) < 0)
    assert_true(tibia_distance(dims, dims.medial_malleolus) < 0)
    assert_true(tibia_distance(dims, Vector3(10, 0, 0)) > 0)


def test_midshaft_ap_and_ml_are_independent() raises:
    var dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    var tall_ap = dims
    tall_ap.midshaft_ap = Length(40.0, MILLIMETER)
    tall_ap.midshaft_ml = Length(20.0, MILLIMETER)
    tall_ap.validate()
    var round = dims
    round.midshaft_ap = Length(30.0, MILLIMETER)
    round.midshaft_ml = Length(30.0, MILLIMETER)
    round.validate()
    var field_ap = TibiaField(tall_ap)
    var field_round = TibiaField(round)
    var anterior = Vector3(
        field_ap.s2.x, field_ap.s2.y, field_ap.s2.z + Float32(0.018)
    )
    var lateral = Vector3(
        field_ap.s2.x + Float32(0.012), field_ap.s2.y, field_ap.s2.z
    )
    assert_true(field_ap.distance(anterior) < field_round.distance(anterior))
    assert_true(field_ap.distance(lateral) > field_round.distance(lateral))


def test_gradient_at_a_far_point_points_out() raises:
    var field = TibiaField(tibia_dimensions(Length(6.0, FOOT), MALE))
    var n = field.gradient(Vector3(10, 0, 0))
    assert_almost_equal(n.length(), Float32(1), atol=Float64(1e-3))
    assert_true(n.x > 0)


def test_tibia_mesh_has_positions_normals_and_uvs() raises:
    var bone = tibia(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT, 8)
    assert_true(bone.has_attribute(String(POSITION)))
    assert_true(bone.has_attribute(String(NORMAL)))
    assert_true(bone.has_attribute(String(UV)))
    assert_true(bone.triangle_count() > 0)
    ref normals = bone.attribute_view(String(NORMAL))
    for vertex in range(bone.vertex_count()):
        var n = normals.vector3(vertex)
        assert_almost_equal(n.length(), Float32(1), atol=Float64(1e-3))
    var box = bone.bounding_box()
    var span = box.max.y - box.min.y
    var length = tibia_dimensions(Length(6.0, FOOT), MALE).length.value
    assert_true(span > length * Float32(0.70))
    assert_true(span < length * Float32(1.40))


def test_isosurface_winding_and_interior_residual() raises:
    var dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    var field = TibiaField(dims)
    var coarse = tibia_from_dimensions(dims, 8)
    var finer = tibia_from_dimensions(dims, 12)
    _assert_outward_and_short(coarse)
    _assert_outward_and_short(finer)
    var e8 = _max_positive_centroid(coarse, field)
    var e12 = _max_positive_centroid(finer, field)
    assert_true(e8 < Float32(0.020))
    assert_true(e12 < Float32(0.015))
    assert_true(e12 < e8 * Float32(1.05))


def test_more_detail_makes_more_triangles() raises:
    var person = HumanoidSpec(Length(5.5, FOOT), FEMALE)
    var coarse = tibia(person, LEFT, 8)
    var finer = tibia(person, LEFT, 12)
    assert_true(finer.triangle_count() > coarse.triangle_count())


def test_stature_bounds_and_refusals() raises:
    tibia_dimensions(MIN_STATURE, FEMALE).validate()
    tibia_dimensions(MAX_STATURE, MALE).validate()
    with assert_raises():
        _ = tibia_dimensions(Length(1.19, METER), MALE)
    with assert_raises():
        _ = tibia_dimensions(Length(2.51, METER), FEMALE)
    with assert_raises():
        _ = tibia_dimensions(Length(nan[DType.float32](), METER), MALE)
    with assert_raises():
        _ = tibia_dimensions(Length(inf[DType.float32](), METER), FEMALE)
    with assert_raises():
        _ = tibia_dimensions(Length(6.0, FOOT), Sex(9))
    with assert_raises():
        _ = tibia_dimensions(Length(6.0, FOOT), MALE, BodySide(9))


def test_refuses_invalid_detail() raises:
    var dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = tibia_from_dimensions(dims, 7)
    with assert_raises():
        _ = tibia_from_dimensions(dims, 65)


def test_validate_refuses_zero_and_bad_edits() raises:
    var dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    dims.proximal_width = Length(0)
    with assert_raises():
        dims.validate()
    with assert_raises():
        _ = tibia_from_dimensions(dims, 8)
    with assert_raises():
        _ = tibia_distance(dims, Vector3(0, 0, 0))
    with assert_raises():
        _ = tibia_occupancy(dims, Vector3(0, 0, 0))
    with assert_raises():
        _ = measured_torsion(dims)
    with assert_raises():
        _ = tibia_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            Length(20.0, MILLIMETER),
        )
    dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    dims.length = Length(nan[DType.float32](), METER)
    with assert_raises():
        dims.validate()
    dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    dims.anterior_bow = Length(-0.01, METER)
    with assert_raises():
        dims.validate()
    dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    dims.torsion = Angle(90.0, DEGREE)
    with assert_raises():
        dims.validate()
    dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    dims.torsion = Angle(nan[DType.float32](), DEGREE)
    with assert_raises():
        dims.validate()
    dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    dims.retroversion = Angle(-1.0, DEGREE)
    with assert_raises():
        dims.validate()
    dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    dims.medial_malleolus = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises():
        dims.validate()
    dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    dims.fibular_notch = Vector3(0, nan[DType.float32](), 0)
    with assert_raises():
        dims.validate()
    dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    dims.eminence = Vector3(0, 0, nan[DType.float32]())
    with assert_raises():
        dims.validate()


def test_occupancy_regions() raises:
    var dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    var field = TibiaField(dims)
    assert_true(tibia_occupancy(dims, Vector3(10, 0, 0)) == EMPTY)
    assert_true(tibia_occupancy(dims, field.s2) == MARROW)
    assert_true(tibia_occupancy(dims, dims.medial_condyle) == TRABECULAR_FILL)
    assert_true(tibia_occupancy(dims, dims.plafond) == TRABECULAR_FILL)
    assert_true(tibia_occupancy(dims, dims.medial_malleolus) == TRABECULAR_FILL)
    assert_true(tibia_occupancy(dims, field.s0) != MARROW)
    assert_true(tibia_occupancy(dims, field.s4) != MARROW)
    var found_shell = False
    var i = 0
    while i < 25:
        var p = Vector3(
            field.s2.x + Float32(i) * Float32(0.002), field.s2.y, field.s2.z
        )
        if tibia_occupancy(dims, p) == CORTICAL_FILL:
            found_shell = True
        i = i + 1
    assert_true(found_shell)


def test_mass_contract() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var report = tibia_mass(person, RIGHT, Length(20.0, MILLIMETER))
    var grams = report.mass.to(GRAM)
    assert_true(grams > Float32(40))
    assert_true(grams < Float32(1200))
    var region = report.cortical_region.value + report.trabecular_region.value
    assert_true(report.solid_tissue.value > 0)
    assert_true(report.solid_tissue.value < region)
    assert_true(report.envelope.to(CUBIC_CENTIMETER) > Float32(20))
    var weight = report.weight()
    assert_almost_equal(
        weight.value, report.mass.value * STANDARD_GRAVITY.value, atol=TOLERANCE
    )
    assert_true(weight.to(NEWTON) > Float32(0.2))


def test_full_porosity_has_no_mass_but_keeps_regions() raises:
    var dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    var cortical = cortical_tissue()
    cortical.porosity = Float32(1)
    var trabecular = trabecular_tissue()
    trabecular.porosity = Float32(1)
    var report = tibia_mass_from_dimensions(
        dims, cortical, trabecular, Length(20.0, MILLIMETER)
    )
    assert_equal(report.mass.value, Float32(0))
    assert_equal(report.solid_tissue.value, Float32(0))
    assert_true(report.cortical_region.value > 0)


def test_left_and_right_masses_agree() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var step = Length(20.0, MILLIMETER)
    var right = tibia_mass(person, RIGHT, step)
    var left = tibia_mass(person, LEFT, step)
    var scale = right.mass.value
    if scale < left.mass.value:
        scale = left.mass.value
    var gap = right.mass.value - left.mass.value
    if gap < 0:
        gap = -gap
    assert_true(gap < scale * Float32(0.15))


def test_a_taller_tibia_has_more_mass() raises:
    var step = Length(20.0, MILLIMETER)
    var short = tibia_mass(HumanoidSpec(Length(5.0, FOOT), FEMALE), LEFT, step)
    var tall = tibia_mass(HumanoidSpec(Length(6.5, FOOT), MALE), RIGHT, step)
    assert_true(tall.mass > short.mass)


def test_mass_refuses_bad_step_and_tissue() raises:
    var dims = tibia_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = tibia_mass_from_dimensions(
            dims, cortical_tissue(), trabecular_tissue(), MIN_STEP.scaled(0.5)
        )
    with assert_raises():
        _ = tibia_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            MAX_STEP + Length(1.0, MILLIMETER),
        )
    with assert_raises():
        _ = tibia_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            Length(nan[DType.float32](), MILLIMETER),
        )
    var bad = cortical_tissue()
    bad.kind = BoneKind(9)
    with assert_raises():
        _ = tibia_mass_from_dimensions(
            dims, bad, trabecular_tissue(), Length(10.0, MILLIMETER)
        )
    var worse = trabecular_tissue()
    worse.kind = BoneKind(9)
    with assert_raises():
        _ = tibia_mass_from_dimensions(
            dims, cortical_tissue(), worse, Length(10.0, MILLIMETER)
        )


def _max_positive_centroid(
    bone: BufferGeometry, field: TibiaField
) raises -> Float32:
    """Return the largest positive field value at a triangle centroid."""
    ref pos = bone.attribute_view(String(POSITION))
    var worst = Float32(0)
    for triangle in range(bone.triangle_count()):
        var ia = bone.corner_index(triangle, 0)
        var ib = bone.corner_index(triangle, 1)
        var ic = bone.corner_index(triangle, 2)
        var a = pos.vector3(ia)
        var b = pos.vector3(ib)
        var c = pos.vector3(ic)
        var centroid = Vector3(
            (a.x + b.x + c.x) * Float32(1.0 / 3.0),
            (a.y + b.y + c.y) * Float32(1.0 / 3.0),
            (a.z + b.z + c.z) * Float32(1.0 / 3.0),
        )
        var d = field.distance(centroid)
        if d > worst:
            worst = d
    return worst


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
