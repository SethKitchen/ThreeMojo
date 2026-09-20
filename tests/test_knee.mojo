# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for knee cartilage, menisci, collaterals and soft tissue."""

from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import MAX_STATURE, MIN_STATURE, HumanoidSpec
from extensions.humanoid.skeleton.leg.knee.dimensions import (
    ARTICULAR_CARTILAGE,
    LATERAL_COLLATERAL,
    LATERAL_MENISCUS,
    MEDIAL_COLLATERAL,
    MEDIAL_MENISCUS,
    CartilageField,
    CollateralField,
    KneePart,
    MeniscusField,
    femur_origin,
    fibula_origin,
    knee_dimensions,
    knee_distance,
    knee_part_label,
    patella_origin,
    tibia_origin,
)
from extensions.humanoid.skeleton.leg.knee.geometry import (
    articular_cartilage,
    knee_from_dimensions,
    knee_mesh,
)
from extensions.humanoid.skeleton.leg.knee.mass import (
    articular_cartilage_mass,
    knee_mass,
    knee_mass_from_dimensions,
    knee_occupancy,
    lateral_collateral_mass,
    lateral_meniscus_mass,
    medial_collateral_mass,
    medial_meniscus_mass,
)
from extensions.humanoid.skeleton.leg.femur.dimensions import femur_dimensions
from extensions.humanoid.skeleton.leg.fibula.dimensions import (
    fibula_dimensions,
)
from extensions.humanoid.skeleton.leg.patella.dimensions import (
    patella_dimensions,
)
from extensions.humanoid.skeleton.leg.tibia.dimensions import tibia_dimensions
from extensions.humanoid.skeleton.look import (
    cartilage_phong,
    ligament_phong,
    meniscus_phong,
)
from extensions.humanoid.skeleton.occupancy import MAX_STEP, MIN_STEP
from extensions.humanoid.skeleton.soft_tissue import (
    CARTILAGE,
    LIGAMENT,
    MENISCUS,
    MUSCLE,
    SOFT_EMPTY,
    SOFT_FILL,
    TENDON,
    SoftOccupancy,
    SoftTissue,
    SoftTissueKind,
    cartilage_tissue,
    classify_soft,
    filled_density,
    ligament_tissue,
    meniscus_tissue,
)
from materials.material import DOUBLE_SIDE, PHONG
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
    Density,
    FOOT,
    GRAM,
    GRAM_PER_CUBIC_CENTIMETER,
    Length,
    MEGAPASCAL,
    METER,
    MILLIMETER,
    NEWTON,
    Pressure,
    STANDARD_GRAVITY,
)

comptime TOLERANCE = Float64(1e-5)


def test_soft_kinds_are_valid() raises:
    assert_true(CARTILAGE.is_valid())
    assert_true(LIGAMENT.is_valid())
    assert_true(MENISCUS.is_valid())
    assert_true(MUSCLE.is_valid())
    assert_true(TENDON.is_valid())
    assert_false(SoftTissueKind(5).is_valid())
    assert_false(SoftTissueKind(-1).is_valid())
    assert_true(SOFT_EMPTY.is_valid())
    assert_true(SOFT_FILL.is_valid())
    assert_false(SoftOccupancy(2).is_valid())
    assert_false(SoftOccupancy(-1).is_valid())
    assert_true(ARTICULAR_CARTILAGE.is_valid())
    assert_true(MEDIAL_MENISCUS.is_valid())
    assert_true(LATERAL_MENISCUS.is_valid())
    assert_true(MEDIAL_COLLATERAL.is_valid())
    assert_true(LATERAL_COLLATERAL.is_valid())
    assert_false(KneePart(5).is_valid())
    assert_false(KneePart(-1).is_valid())


def test_cartilage_tissue_matches_the_named_template() raises:
    var tissue = cartilage_tissue()
    assert_true(tissue.kind == CARTILAGE)
    assert_almost_equal(
        tissue.wet_density.to(GRAM_PER_CUBIC_CENTIMETER),
        Float32(1.12),
        atol=TOLERANCE,
    )
    assert_almost_equal(tissue.water_fraction, Float32(0.75), atol=TOLERANCE)
    assert_almost_equal(
        tissue.elastic_modulus.to(MEGAPASCAL), Float32(0.70), atol=TOLERANCE
    )
    assert_almost_equal(tissue.poisson_ratio, Float32(0.45), atol=TOLERANCE)
    tissue.validate()


def test_ligament_and_meniscus_templates() raises:
    var ligament = ligament_tissue()
    assert_true(ligament.kind == LIGAMENT)
    assert_almost_equal(ligament.water_fraction, Float32(0.65), atol=TOLERANCE)
    ligament.validate()
    var meniscus = meniscus_tissue()
    assert_true(meniscus.kind == MENISCUS)
    assert_almost_equal(
        meniscus.wet_density.to(GRAM_PER_CUBIC_CENTIMETER),
        Float32(1.10),
        atol=TOLERANCE,
    )
    meniscus.validate()


def test_filled_density_and_classify() raises:
    var tissue = cartilage_tissue()
    assert_equal(filled_density(SOFT_EMPTY, tissue).value, Float32(0))
    assert_equal(
        filled_density(SOFT_FILL, tissue).value, tissue.wet_density.value
    )
    with assert_raises():
        _ = filled_density(SoftOccupancy(9), tissue)
    assert_true(classify_soft(Float32(0.1)) == SOFT_EMPTY)
    assert_true(classify_soft(Float32(0)) == SOFT_EMPTY)
    assert_true(classify_soft(Float32(-0.1)) == SOFT_FILL)


def test_soft_tissue_validate_refusals() raises:
    var tissue = cartilage_tissue()
    tissue.kind = SoftTissueKind(9)
    with assert_raises():
        tissue.validate()
    tissue = cartilage_tissue()
    tissue.wet_density = Density(
        nan[DType.float32](), GRAM_PER_CUBIC_CENTIMETER
    )
    with assert_raises():
        tissue.validate()
    tissue = cartilage_tissue()
    tissue.wet_density = Density(0)
    with assert_raises():
        tissue.validate()
    tissue = cartilage_tissue()
    tissue.wet_density = Density(-1.0, GRAM_PER_CUBIC_CENTIMETER)
    with assert_raises():
        tissue.validate()
    tissue = cartilage_tissue()
    tissue.water_fraction = nan[DType.float32]()
    with assert_raises():
        tissue.validate()
    tissue = cartilage_tissue()
    tissue.water_fraction = Float32(-0.01)
    with assert_raises():
        tissue.validate()
    tissue = cartilage_tissue()
    tissue.water_fraction = Float32(1.01)
    with assert_raises():
        tissue.validate()
    tissue = cartilage_tissue()
    tissue.elastic_modulus = Pressure(nan[DType.float32](), MEGAPASCAL)
    with assert_raises():
        tissue.validate()
    tissue = cartilage_tissue()
    tissue.elastic_modulus = Pressure(0)
    with assert_raises():
        tissue.validate()
    tissue = cartilage_tissue()
    tissue.elastic_modulus = Pressure(-1.0, MEGAPASCAL)
    with assert_raises():
        tissue.validate()
    tissue = cartilage_tissue()
    tissue.poisson_ratio = nan[DType.float32]()
    with assert_raises():
        tissue.validate()
    tissue = cartilage_tissue()
    tissue.poisson_ratio = Float32(-0.01)
    with assert_raises():
        tissue.validate()
    tissue = cartilage_tissue()
    tissue.poisson_ratio = Float32(1.01)
    with assert_raises():
        tissue.validate()


def test_six_foot_male_cartilage_uses_shepherd_means() raises:
    var dims = knee_dimensions(Length(6.0, FOOT), MALE)
    var S = Length(6.0, FOOT).value
    assert_almost_equal(
        dims.femoral_thickness.value, S * Float32(0.001203), atol=TOLERANCE
    )
    assert_almost_equal(
        dims.tibial_thickness.value, S * Float32(0.001367), atol=TOLERANCE
    )
    assert_almost_equal(
        dims.patellar_thickness.value, S * Float32(0.001805), atol=TOLERANCE
    )
    assert_true(dims.side == RIGHT)
    assert_true(dims.femoral_medial_cartilage.y > 0)
    assert_true(
        dims.femoral_medial_cartilage.y > dims.tibial_medial_cartilage.y
    )


def test_female_knee_uses_the_female_ratios() raises:
    var dims = knee_dimensions(Length(6.0, FOOT), FEMALE)
    var S = Length(6.0, FOOT).value
    assert_almost_equal(
        dims.femoral_thickness.value, S * Float32(0.001150), atol=TOLERANCE
    )
    assert_true(dims.medial_meniscus_ap.value < S * Float32(0.0230))


def test_left_knee_mirrors_the_right() raises:
    var right = knee_dimensions(Length(6.0, FOOT), MALE, RIGHT)
    var left = knee_dimensions(Length(6.0, FOOT), MALE, LEFT)
    assert_almost_equal(
        left.femoral_medial_cartilage.x,
        -right.femoral_medial_cartilage.x,
        atol=Float64(1e-4),
    )
    assert_true(left.side == LEFT)
    assert_true(left.lcl_fibula.x < 0)
    assert_true(right.lcl_fibula.x > 0)


def test_cartilage_landmarks_are_inside() raises:
    var dims = knee_dimensions(Length(6.0, FOOT), MALE)
    assert_true(
        knee_distance(dims, ARTICULAR_CARTILAGE, dims.femoral_medial_cartilage)
        < 0
    )
    assert_true(
        knee_distance(dims, ARTICULAR_CARTILAGE, dims.tibial_lateral_cartilage)
        < 0
    )
    assert_true(knee_distance(dims, ARTICULAR_CARTILAGE, Vector3(10, 0, 0)) > 0)
    assert_true(
        knee_occupancy(dims, ARTICULAR_CARTILAGE, Vector3(10, 0, 0))
        == SOFT_EMPTY
    )
    assert_true(
        knee_occupancy(dims, ARTICULAR_CARTILAGE, dims.patellar_cartilage)
        == SOFT_FILL
    )


def test_menisci_and_collaterals_are_inside_at_landmarks() raises:
    var dims = knee_dimensions(Length(6.0, FOOT), MALE)
    var field = MeniscusField(dims, MEDIAL_MENISCUS)
    assert_true(field.distance(field.p2) < 0)
    assert_true(knee_distance(dims, MEDIAL_MENISCUS, field.p2) < 0)
    var lateral = MeniscusField(dims, LATERAL_MENISCUS)
    assert_true(lateral.distance(lateral.p2) < 0)
    assert_true(knee_distance(dims, LATERAL_MENISCUS, lateral.p2) < 0)
    var mcl = CollateralField(dims, MEDIAL_COLLATERAL)
    var mid = Vector3(
        0.5 * (mcl.a.x + mcl.b.x),
        0.5 * (mcl.a.y + mcl.b.y),
        0.5 * (mcl.a.z + mcl.b.z),
    )
    assert_true(knee_distance(dims, MEDIAL_COLLATERAL, mid) < 0)
    var lcl = CollateralField(dims, LATERAL_COLLATERAL)
    var lmid = Vector3(
        0.5 * (lcl.a.x + lcl.b.x),
        0.5 * (lcl.a.y + lcl.b.y),
        0.5 * (lcl.a.z + lcl.b.z),
    )
    assert_true(knee_distance(dims, LATERAL_COLLATERAL, lmid) < 0)


def test_meniscus_and_collateral_fields_refuse_the_wrong_part() raises:
    var dims = knee_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = MeniscusField(dims, ARTICULAR_CARTILAGE)
    with assert_raises():
        _ = CollateralField(dims, ARTICULAR_CARTILAGE)


def test_narrow_meniscus_clamps_the_ellipse() raises:
    var dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.medial_meniscus_ap = Length(4.0, MILLIMETER)
    var field = MeniscusField(dims, MEDIAL_MENISCUS)
    assert_true(field.r2 > 0)
    assert_true(field.distance(field.p0) < 0)


def test_gradient_at_a_far_point_points_out() raises:
    var dims = knee_dimensions(Length(6.0, FOOT), FEMALE)
    var n = CartilageField(dims).gradient(Vector3(10, 0, 0))
    assert_almost_equal(n.length(), Float32(1), atol=Float64(1e-3))
    assert_true(n.x > 0)
    var mn = MeniscusField(dims, MEDIAL_MENISCUS).gradient(Vector3(10, 0, 0))
    assert_true(mn.x > 0)
    var cn = CollateralField(dims, LATERAL_COLLATERAL).gradient(
        Vector3(10, 0, 0)
    )
    assert_true(cn.x > 0)


def test_part_labels() raises:
    assert_equal(knee_part_label(ARTICULAR_CARTILAGE), "articular cartilage")
    assert_equal(knee_part_label(MEDIAL_MENISCUS), "medial meniscus")
    assert_equal(knee_part_label(LATERAL_MENISCUS), "lateral meniscus")
    assert_equal(knee_part_label(MEDIAL_COLLATERAL), "medial collateral")
    assert_equal(knee_part_label(LATERAL_COLLATERAL), "lateral collateral")
    assert_equal(knee_part_label(KneePart(9)), "knee")


def test_cartilage_mesh_has_positions_normals_and_uvs() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var mesh = articular_cartilage(person, RIGHT, 8)
    _assert_mesh(mesh, Float32(0.08))


def test_stature_bounds_and_refusals() raises:
    knee_dimensions(MIN_STATURE, FEMALE).validate()
    knee_dimensions(MAX_STATURE, MALE).validate()
    with assert_raises():
        _ = knee_dimensions(Length(1.19, METER), MALE)
    with assert_raises():
        _ = knee_dimensions(Length(2.51, METER), FEMALE)
    with assert_raises():
        _ = knee_dimensions(Length(inf[DType.float32](), METER), FEMALE)
    with assert_raises():
        _ = knee_dimensions(Length(6.0, FOOT), Sex(9))
    with assert_raises():
        _ = knee_dimensions(Length(6.0, FOOT), MALE, BodySide(9))


def test_refuses_invalid_detail_and_part() raises:
    var dims = knee_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = knee_from_dimensions(dims, ARTICULAR_CARTILAGE, 7)
    with assert_raises():
        _ = knee_from_dimensions(dims, ARTICULAR_CARTILAGE, 65)
    with assert_raises():
        _ = knee_from_dimensions(dims, KneePart(9), 8)
    with assert_raises():
        _ = knee_mesh(
            HumanoidSpec(Length(6.0, FOOT), MALE), KneePart(9), RIGHT, 8
        )
    with assert_raises():
        _ = knee_distance(dims, KneePart(9), Vector3(0, 0, 0))
    with assert_raises():
        _ = knee_occupancy(dims, KneePart(9), Vector3(0, 0, 0))
    with assert_raises():
        _ = knee_mass(HumanoidSpec(Length(6.0, FOOT), MALE), KneePart(9), RIGHT)
    with assert_raises():
        _ = knee_mass_from_dimensions(
            dims, KneePart(9), cartilage_tissue(), Length(5.0, MILLIMETER)
        )


def test_validate_refuses_zero_and_bad_edits() raises:
    var dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.femoral_thickness = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.tibial_thickness = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.patellar_thickness = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.medial_meniscus_ap = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.medial_meniscus_radial = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.medial_meniscus_height = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.lateral_meniscus_ap = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.lateral_meniscus_radial = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.lateral_meniscus_height = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.mcl_length = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.mcl_radius = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.lcl_length = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.lcl_radius = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.femoral_width = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.tibial_width = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.tibial_ap = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.patella_height = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.patella_width = Length(0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.femoral_medial_cartilage = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.femoral_lateral_cartilage = Vector3(0, nan[DType.float32](), 0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.trochlear_cartilage = Vector3(0, 0, nan[DType.float32]())
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.tibial_medial_cartilage = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.tibial_lateral_cartilage = Vector3(0, nan[DType.float32](), 0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.patellar_cartilage = Vector3(0, 0, nan[DType.float32]())
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.medial_meniscus_center = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.lateral_meniscus_center = Vector3(0, nan[DType.float32](), 0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.mcl_femur = Vector3(0, 0, nan[DType.float32]())
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.mcl_tibia = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.lcl_femur = Vector3(0, nan[DType.float32](), 0)
    with assert_raises():
        dims.validate()
    dims = knee_dimensions(Length(6.0, FOOT), MALE)
    dims.lcl_fibula = Vector3(0, 0, nan[DType.float32]())
    with assert_raises():
        dims.validate()
    with assert_raises():
        _ = knee_from_dimensions(dims, ARTICULAR_CARTILAGE, 8)


def test_mass_contract() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var step = Length(5.0, MILLIMETER)
    var cartilage = articular_cartilage_mass(person, RIGHT, step)
    assert_true(cartilage.mass.to(GRAM) > Float32(1))
    assert_true(cartilage.mass.to(GRAM) < Float32(200))
    assert_true(cartilage.envelope.value > 0)
    assert_almost_equal(
        cartilage.weight().value,
        cartilage.mass.value * STANDARD_GRAVITY.value,
        atol=TOLERANCE,
    )
    assert_true(cartilage.weight().to(NEWTON) > Float32(0.01))
    var med = medial_meniscus_mass(person, RIGHT, step)
    assert_true(med.mass.to(GRAM) > Float32(0.2))
    var lat = lateral_meniscus_mass(person, LEFT, step)
    assert_true(lat.mass.to(GRAM) > Float32(0.2))
    var mcl = medial_collateral_mass(person, RIGHT, step)
    assert_true(mcl.mass.to(GRAM) > Float32(0.2))
    var lcl = lateral_collateral_mass(person, RIGHT, step)
    assert_true(lcl.mass.to(GRAM) > Float32(0.2))
    var defaulted = articular_cartilage_mass(person)
    assert_true(defaulted.mass.to(GRAM) > Float32(1))


def test_left_and_right_cartilage_masses_agree() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var step = Length(5.0, MILLIMETER)
    var right = articular_cartilage_mass(person, RIGHT, step)
    var left = articular_cartilage_mass(person, LEFT, step)
    var scale = right.mass.value
    if scale < left.mass.value:
        scale = left.mass.value
    var gap = right.mass.value - left.mass.value
    if gap < 0:
        gap = -gap
    assert_true(gap < scale * Float32(0.20))


def test_a_taller_knee_has_more_cartilage_mass() raises:
    var step = Length(5.0, MILLIMETER)
    var short = articular_cartilage_mass(
        HumanoidSpec(Length(5.0, FOOT), FEMALE), LEFT, step
    )
    var tall = articular_cartilage_mass(
        HumanoidSpec(Length(6.5, FOOT), MALE), RIGHT, step
    )
    assert_true(tall.mass > short.mass)


def test_mass_refuses_bad_step_and_tissue() raises:
    var dims = knee_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = knee_mass_from_dimensions(
            dims,
            ARTICULAR_CARTILAGE,
            cartilage_tissue(),
            MIN_STEP.scaled(0.5),
        )
    with assert_raises():
        _ = knee_mass_from_dimensions(
            dims,
            ARTICULAR_CARTILAGE,
            cartilage_tissue(),
            MAX_STEP + Length(1.0, MILLIMETER),
        )
    var bad = cartilage_tissue()
    bad.kind = SoftTissueKind(9)
    with assert_raises():
        _ = knee_mass_from_dimensions(
            dims, ARTICULAR_CARTILAGE, bad, Length(5.0, MILLIMETER)
        )


def test_origin_helpers_refuse_bad_inputs() raises:
    var femur = femur_dimensions(Length(6.0, FOOT), MALE)
    var tibia = tibia_dimensions(Length(6.0, FOOT), MALE)
    var fibula = fibula_dimensions(Length(6.0, FOOT), MALE)
    var patella = patella_dimensions(Length(6.0, FOOT), MALE)
    with assert_raises():
        _ = femur_origin(femur, Length(0))
    with assert_raises():
        _ = tibia_origin(tibia, Length(0))
    with assert_raises():
        _ = patella_origin(femur, Vector3(0, 0, 0), patella, Length(0))
    with assert_raises():
        _ = patella_origin(
            femur,
            Vector3(nan[DType.float32](), 0, 0),
            patella,
            Length(2.0, MILLIMETER),
        )
    with assert_raises():
        _ = fibula_origin(tibia, Vector3(nan[DType.float32](), 0, 0), fibula)
    femur.length = Length(0)
    with assert_raises():
        _ = femur_origin(femur, Length(2.0, MILLIMETER))


def test_look_materials() raises:
    var cart = cartilage_phong()
    assert_true(cart.kind == PHONG)
    assert_true(cart.side == DOUBLE_SIDE)
    assert_false(cart.transparent)
    var men = meniscus_phong()
    assert_true(men.kind == PHONG)
    var lig = ligament_phong()
    assert_true(lig.kind == PHONG)


def _assert_mesh(bone: BufferGeometry, limit: Float32) raises:
    """Refuse a mesh with missing attributes, no triangles, or long edges."""
    assert_true(bone.has_attribute(String(POSITION)))
    assert_true(bone.has_attribute(String(NORMAL)))
    assert_true(bone.has_attribute(String(UV)))
    assert_true(bone.triangle_count() > 0)
    ref normals = bone.attribute_view(String(NORMAL))
    for vertex in range(bone.vertex_count()):
        assert_almost_equal(
            normals.vector3(vertex).length(), Float32(1), atol=Float64(1e-3)
        )
    ref pos = bone.attribute_view(String(POSITION))
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
