# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the stature-scaled patella."""

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
from extensions.humanoid.skeleton.leg.patella.dimensions import (
    PatellaField,
    patella_dimensions,
    patella_distance,
)
from extensions.humanoid.skeleton.leg.patella.geometry import (
    patella,
    patella_from_dimensions,
)
from extensions.humanoid.skeleton.leg.patella.mass import (
    patella_mass,
    patella_mass_from_dimensions,
    patella_occupancy,
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
    FOOT,
    GRAM,
    Length,
    METER,
    MILLIMETER,
    NEWTON,
    STANDARD_GRAVITY,
)

comptime TOLERANCE = Float64(1e-5)


def test_six_foot_male_patella_uses_authored_stature_ratios() raises:
    var dims = patella_dimensions(Length(6.0, FOOT), MALE)
    var S = Length(6.0, FOOT).value
    assert_almost_equal(dims.height.value, S * Float32(0.0253), atol=TOLERANCE)
    assert_almost_equal(dims.width.value, S * Float32(0.0248), atol=TOLERANCE)
    assert_almost_equal(
        dims.thickness.value, S * Float32(0.0123), atol=TOLERANCE
    )
    assert_true(dims.side == RIGHT)
    assert_true(dims.apex.y < dims.base.y)


def test_female_patella_uses_the_female_ratios() raises:
    var dims = patella_dimensions(Length(6.0, FOOT), FEMALE)
    var S = Length(6.0, FOOT).value
    assert_almost_equal(dims.height.value, S * Float32(0.0240), atol=TOLERANCE)


def test_left_patella_mirrors_the_right() raises:
    var right = patella_dimensions(Length(6.0, FOOT), MALE, RIGHT)
    var left = patella_dimensions(Length(6.0, FOOT), MALE, LEFT)
    assert_almost_equal(left.ridge.x, -right.ridge.x, atol=TOLERANCE)
    assert_true(left.side == LEFT)


def test_landmarks_and_center_are_inside() raises:
    var dims = patella_dimensions(Length(6.0, FOOT), MALE)
    assert_true(patella_distance(dims, Vector3(0, 0, 0)) < 0)
    assert_true(patella_distance(dims, dims.apex) < 0)
    assert_true(patella_distance(dims, dims.base) < 0)
    assert_true(patella_distance(dims, Vector3(10, 0, 0)) > 0)


def test_lateral_facet_is_the_larger_side() raises:
    var right = PatellaField(patella_dimensions(Length(6.0, FOOT), MALE, RIGHT))
    var left = PatellaField(patella_dimensions(Length(6.0, FOOT), MALE, LEFT))
    assert_true(right.lateral.x > 0)
    assert_true(left.lateral.x < 0)
    assert_true(right.lateral_r.x > right.medial_r.x)


def test_gradient_at_a_far_point_points_out() raises:
    var n = PatellaField(
        patella_dimensions(Length(6.0, FOOT), FEMALE)
    ).gradient(Vector3(10, 0, 0))
    assert_almost_equal(n.length(), Float32(1), atol=Float64(1e-3))
    assert_true(n.x > 0)


def test_patella_mesh_has_positions_normals_and_uvs() raises:
    var bone = patella(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT, 8)
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
    var height = patella_dimensions(Length(6.0, FOOT), MALE).height.value
    assert_true(span > height * Float32(0.70))
    assert_true(span < height * Float32(1.50))
    _assert_outward_and_short(bone, Float32(0.04))


def test_stature_bounds_and_refusals() raises:
    patella_dimensions(MIN_STATURE, FEMALE).validate()
    patella_dimensions(MAX_STATURE, MALE).validate()
    with assert_raises():
        _ = patella_dimensions(Length(1.19, METER), MALE)
    with assert_raises():
        _ = patella_dimensions(Length(2.51, METER), FEMALE)
    with assert_raises():
        _ = patella_dimensions(Length(inf[DType.float32](), METER), FEMALE)
    with assert_raises():
        _ = patella_dimensions(Length(6.0, FOOT), Sex(9))
    with assert_raises():
        _ = patella_dimensions(Length(6.0, FOOT), MALE, BodySide(9))


def test_refuses_invalid_detail() raises:
    var dims = patella_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = patella_from_dimensions(dims, 7)
    with assert_raises():
        _ = patella_from_dimensions(dims, 65)


def test_validate_refuses_zero_and_bad_edits() raises:
    var dims = patella_dimensions(Length(6.0, FOOT), MALE)
    dims.height = Length(0)
    with assert_raises():
        dims.validate()
    with assert_raises():
        _ = patella_from_dimensions(dims, 8)
    with assert_raises():
        _ = patella_distance(dims, Vector3(0, 0, 0))
    with assert_raises():
        _ = patella_occupancy(dims, Vector3(0, 0, 0))
    with assert_raises():
        _ = patella_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            Length(5.0, MILLIMETER),
        )
    dims = patella_dimensions(Length(6.0, FOOT), MALE)
    dims.width = Length(nan[DType.float32](), METER)
    with assert_raises():
        dims.validate()
    dims = patella_dimensions(Length(6.0, FOOT), MALE)
    dims.apex = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises():
        dims.validate()
    dims = patella_dimensions(Length(6.0, FOOT), MALE)
    dims.base = Vector3(0, nan[DType.float32](), 0)
    with assert_raises():
        dims.validate()
    dims = patella_dimensions(Length(6.0, FOOT), MALE)
    dims.ridge = Vector3(0, 0, nan[DType.float32]())
    with assert_raises():
        dims.validate()


def test_occupancy_has_no_marrow() raises:
    var dims = patella_dimensions(Length(6.0, FOOT), MALE)
    assert_true(patella_occupancy(dims, Vector3(10, 0, 0)) == EMPTY)
    assert_true(patella_occupancy(dims, Vector3(0, 0, 0)) == TRABECULAR_FILL)
    assert_false(patella_occupancy(dims, Vector3(0, 0, 0)) == MARROW)
    var field = PatellaField(dims)
    var rim = Vector3(0, 0, field.body.z + field.body_r.z * Float32(0.92))
    assert_true(patella_occupancy(dims, rim) == CORTICAL_FILL)


def test_mass_contract() raises:
    var report = patella_mass(
        HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT, Length(5.0, MILLIMETER)
    )
    var grams = report.mass.to(GRAM)
    assert_true(grams > Float32(4))
    assert_true(grams < Float32(80))
    assert_true(report.solid_tissue.value > 0)
    assert_true(report.trabecular_region.value > 0)
    assert_true(report.weight().to(NEWTON) > Float32(0.02))
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
    var report = patella_mass_from_dimensions(
        patella_dimensions(Length(6.0, FOOT), MALE),
        cortical,
        trabecular,
        Length(5.0, MILLIMETER),
    )
    assert_equal(report.mass.value, Float32(0))
    assert_equal(report.solid_tissue.value, Float32(0))
    assert_true(report.cortical_region.value > 0)
    assert_true(report.trabecular_region.value > 0)


def test_left_and_right_masses_agree() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var step = Length(5.0, MILLIMETER)
    var right = patella_mass(person, RIGHT, step)
    var left = patella_mass(person, LEFT, step)
    var scale = right.mass.value
    if scale < left.mass.value:
        scale = left.mass.value
    var gap = right.mass.value - left.mass.value
    if gap < 0:
        gap = -gap
    assert_true(gap < scale * Float32(0.15))


def test_a_taller_patella_has_more_mass() raises:
    var step = Length(5.0, MILLIMETER)
    var short = patella_mass(
        HumanoidSpec(Length(5.0, FOOT), FEMALE), LEFT, step
    )
    var tall = patella_mass(HumanoidSpec(Length(6.5, FOOT), MALE), RIGHT, step)
    assert_true(tall.mass > short.mass)


def test_mass_refuses_bad_step_and_tissue() raises:
    var dims = patella_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = patella_mass_from_dimensions(
            dims, cortical_tissue(), trabecular_tissue(), MIN_STEP.scaled(0.5)
        )
    with assert_raises():
        _ = patella_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            MAX_STEP + Length(1.0, MILLIMETER),
        )
    with assert_raises():
        _ = patella_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            Length(nan[DType.float32](), MILLIMETER),
        )
    with assert_raises():
        _ = patella_mass_from_dimensions(
            dims,
            cortical_tissue(),
            trabecular_tissue(),
            Length(inf[DType.float32](), MILLIMETER),
        )
    var bad = cortical_tissue()
    bad.kind = BoneKind(9)
    with assert_raises():
        _ = patella_mass_from_dimensions(
            dims, bad, trabecular_tissue(), Length(5.0, MILLIMETER)
        )
    var worse = trabecular_tissue()
    worse.kind = BoneKind(9)
    with assert_raises():
        _ = patella_mass_from_dimensions(
            dims, cortical_tissue(), worse, Length(5.0, MILLIMETER)
        )


def _assert_outward_and_short(bone: BufferGeometry, limit: Float32) raises:
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
        assert_true(ab.length() < limit)
        assert_true(ac.length() < limit)
        assert_true(bc.length() < limit)
        ab.cross(ac)
        if ab.length() < Float32(1e-10):
            continue
        var mean = (
            normals.vector3(ia) + normals.vector3(ib) + normals.vector3(ic)
        )
        assert_true(ab.dot(mean) > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
