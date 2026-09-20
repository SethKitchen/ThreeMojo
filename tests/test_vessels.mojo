# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for stature-scaled leg arteries and veins."""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_phong
from extensions.humanoid.skeleton.field import tube_chain_volume
from extensions.humanoid.skeleton.leg.assembly import add_leg
from extensions.humanoid.skeleton.leg.contents import VESSELS
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    muscle_dimensions,
)
from extensions.humanoid.skeleton.leg.vessels.dimensions import (
    ANTERIOR_TIBIAL_ARTERY,
    FEMORAL_ARTERY,
    FEMORAL_VEIN,
    FIBULAR_ARTERY,
    GREAT_SAPHENOUS_VEIN,
    PERONEAL_ARTERY,
    POPLITEAL_ARTERY,
    POPLITEAL_VEIN,
    POSTERIOR_TIBIAL_ARTERY,
    SMALL_SAPHENOUS_VEIN,
    TIBIOPERONEAL_TRUNK,
    VesselField,
    VesselPart,
    is_artery,
    named_vessel_parts,
    vessel_distance,
    vessel_part_label,
)
from extensions.humanoid.skeleton.leg.vessels.geometry import (
    vessel_from_dimensions,
    vessel_mesh,
)
from extensions.humanoid.skeleton.leg.vessels.mass import (
    vessel_mass,
    vessel_mass_from_dimensions,
    vessel_occupancy,
)
from extensions.humanoid.skeleton.look import (
    artery_phong,
    cartilage_phong,
    ligament_phong,
    meniscus_phong,
    muscle_phong,
    tendon_phong,
    vein_phong,
)
from extensions.humanoid.skeleton.soft_tissue import (
    ARTERIAL,
    SOFT_EMPTY,
    SOFT_FILL,
    VENOUS,
    SoftTissueKind,
    arterial_tissue,
    venous_tissue,
)
from materials.material import PHONG
from math.vector3 import Vector3
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
    GRAM_PER_CUBIC_CENTIMETER,
    Length,
    MEGAPASCAL,
)

comptime TOLERANCE = Float64(1e-4)


def test_vessel_parts_are_named() raises:
    var parts = named_vessel_parts()
    assert_equal(len(parts), 10)
    var index = 0
    while index < len(parts):
        assert_true(parts[index].is_valid())
        var label = vessel_part_label(parts[index])
        assert_true(label.byte_length() > 0)
        index += 1
    assert_false(VesselPart(-1).is_valid())
    assert_false(VesselPart(10).is_valid())
    assert_equal(vessel_part_label(VesselPart(99)), "vessel")
    assert_true(is_artery(FEMORAL_ARTERY))
    assert_true(FIBULAR_ARTERY == PERONEAL_ARTERY)
    assert_true(is_artery(PERONEAL_ARTERY))
    assert_false(is_artery(FEMORAL_VEIN))
    assert_false(is_artery(SMALL_SAPHENOUS_VEIN))
    with assert_raises():
        _ = is_artery(VesselPart(10))


def test_vessel_labels_match_the_diagram() raises:
    assert_equal(vessel_part_label(FEMORAL_ARTERY), "femoral artery")
    assert_equal(vessel_part_label(POPLITEAL_ARTERY), "popliteal artery")
    assert_equal(
        vessel_part_label(ANTERIOR_TIBIAL_ARTERY), "anterior tibial artery"
    )
    assert_equal(vessel_part_label(TIBIOPERONEAL_TRUNK), "tibioperoneal trunk")
    assert_equal(
        vessel_part_label(POSTERIOR_TIBIAL_ARTERY), "posterior tibial artery"
    )
    assert_equal(vessel_part_label(FIBULAR_ARTERY), "fibular artery")
    assert_equal(vessel_part_label(FEMORAL_VEIN), "femoral vein")
    assert_equal(vessel_part_label(POPLITEAL_VEIN), "popliteal vein")
    assert_equal(
        vessel_part_label(GREAT_SAPHENOUS_VEIN), "great saphenous vein"
    )
    assert_equal(
        vessel_part_label(SMALL_SAPHENOUS_VEIN), "small saphenous vein"
    )


def test_arterial_and_venous_tissue() raises:
    assert_true(ARTERIAL.is_valid())
    assert_true(VENOUS.is_valid())
    var artery = arterial_tissue()
    assert_true(artery.kind == ARTERIAL)
    assert_almost_equal(
        artery.wet_density.to(GRAM_PER_CUBIC_CENTIMETER),
        Float32(1.06),
        atol=TOLERANCE,
    )
    assert_almost_equal(artery.water_fraction, Float32(0.80), atol=TOLERANCE)
    assert_almost_equal(
        artery.elastic_modulus.to(MEGAPASCAL), Float32(0.50), atol=TOLERANCE
    )
    artery.validate()
    var vein = venous_tissue()
    assert_true(vein.kind == VENOUS)
    assert_almost_equal(
        vein.elastic_modulus.to(MEGAPASCAL), Float32(0.30), atol=TOLERANCE
    )
    vein.validate()


def test_every_named_vessel_has_an_interior() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT)
    var left = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE), LEFT)
    var parts = named_vessel_parts()
    var index = 0
    while index < len(parts):
        var part = parts[index]
        var field = VesselField(dims, part)
        assert_true(vessel_distance(dims, part, field.chain.p2) < 0)
        assert_true(vessel_occupancy(dims, part, field.chain.p2) == SOFT_FILL)
        assert_true(
            vessel_occupancy(dims, part, Vector3(10, 0, 0)) == SOFT_EMPTY
        )
        var n = field.gradient(Vector3(10, 0, 0))
        assert_true(n.length() > Float32(0.5))
        var left_field = VesselField(left, part)
        assert_true(left_field.distance(left_field.chain.p2) < 0)
        index += 1


def test_vessel_continuity_and_surface_relations() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT)
    var femoral = VesselField(dims, FEMORAL_ARTERY)
    var popliteal = VesselField(dims, POPLITEAL_ARTERY)
    var anterior = VesselField(dims, ANTERIOR_TIBIAL_ARTERY)
    var trunk = VesselField(dims, TIBIOPERONEAL_TRUNK)
    var posterior = VesselField(dims, POSTERIOR_TIBIAL_ARTERY)
    var fibular = VesselField(dims, FIBULAR_ARTERY)
    _assert_same_point(femoral.chain.p4, popliteal.chain.p0)
    _assert_same_point(popliteal.chain.p4, anterior.chain.p0)
    _assert_same_point(popliteal.chain.p4, trunk.chain.p0)
    _assert_same_point(trunk.chain.p4, posterior.chain.p0)
    _assert_same_point(trunk.chain.p4, fibular.chain.p0)
    assert_almost_equal(
        trunk.chain.p4.y - trunk.chain.p0.y,
        Float32(-0.0175) * dims.stature.value,
        atol=TOLERANCE,
    )
    assert_almost_equal(posterior.chain.r2, Float32(0.00105), atol=TOLERANCE)
    var femoral_vein = VesselField(dims, FEMORAL_VEIN)
    var popliteal_vein = VesselField(dims, POPLITEAL_VEIN)
    var great = VesselField(dims, GREAT_SAPHENOUS_VEIN)
    var small = VesselField(dims, SMALL_SAPHENOUS_VEIN)
    _assert_same_point(popliteal_vein.chain.p4, femoral_vein.chain.p0)
    _assert_same_point(great.chain.p4, femoral_vein.chain.p4)
    _assert_same_point(small.chain.p4, popliteal_vein.chain.p3)
    assert_true(small.chain.p4.y > Float32(0))
    assert_true(popliteal_vein.chain.p2.z < popliteal.chain.p2.z)
    assert_true(great.chain.p0.z > dims.med_mal.z)
    assert_true(small.chain.p0.z < dims.lat_mal.z)


def test_vessel_mesh_has_positions_normals_and_uvs() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    _assert_mesh(vessel_mesh(person, FEMORAL_ARTERY, RIGHT, 8))
    _assert_mesh(vessel_mesh(person, GREAT_SAPHENOUS_VEIN, LEFT, 8))


def test_vessel_mass_is_positive() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var artery = vessel_mass(person, FEMORAL_ARTERY, RIGHT)
    assert_true(artery.mass.to(GRAM) > Float32(0))
    var physical = VesselField(muscle_dimensions(person, RIGHT), FEMORAL_ARTERY)
    assert_almost_equal(
        artery.envelope.value,
        tube_chain_volume(physical.chain),
        atol=Float64(1e-8),
    )
    var vein = vessel_mass(
        HumanoidSpec(Length(5.5, FOOT), FEMALE), FEMORAL_VEIN, LEFT
    )
    assert_true(vein.mass.to(GRAM) > Float32(0))


def test_vessel_field_refuses_a_bad_part() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    with assert_raises():
        _ = VesselField(dims, VesselPart(10))
    with assert_raises():
        _ = vessel_from_dimensions(dims, VesselPart(10), 8)
    with assert_raises():
        _ = vessel_mesh(HumanoidSpec(Length(6.0, FOOT), MALE), VesselPart(10))
    with assert_raises():
        _ = vessel_from_dimensions(dims, FEMORAL_ARTERY, 7)
    with assert_raises():
        _ = vessel_from_dimensions(dims, FEMORAL_ARTERY, 65)


def test_vessel_mass_refuses_a_bad_part_or_tissue() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    with assert_raises():
        _ = vessel_mass(
            HumanoidSpec(Length(6.0, FOOT), MALE), VesselPart(10), RIGHT
        )
    with assert_raises():
        _ = vessel_mass_from_dimensions(dims, VesselPart(10), arterial_tissue())
    var bad = arterial_tissue()
    bad.kind = SoftTissueKind(11)
    with assert_raises():
        _ = vessel_mass_from_dimensions(dims, FEMORAL_ARTERY, bad)


def test_add_leg_can_draw_only_vessels() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    _ = add_leg(
        scene,
        assets,
        root,
        person,
        assets.materials.add(bone_phong()),
        assets.materials.add(cartilage_phong()),
        assets.materials.add(meniscus_phong()),
        assets.materials.add(ligament_phong()),
        assets.materials.add(muscle_phong()),
        assets.materials.add(tendon_phong()),
        RIGHT,
        VESSELS,
        8,
        assets.materials.add(artery_phong()),
        assets.materials.add(vein_phong()),
    )
    assert_equal(len(scene.meshes), 10)


def test_vessel_look_materials() raises:
    var artery = artery_phong()
    assert_true(artery.kind == PHONG)
    var vein = vein_phong()
    assert_true(vein.kind == PHONG)


def _assert_mesh(bone: BufferGeometry) raises:
    """Refuse a mesh with missing attributes or no triangles."""
    assert_true(bone.has_attribute(String(POSITION)))
    assert_true(bone.has_attribute(String(NORMAL)))
    assert_true(bone.has_attribute(String(UV)))
    assert_true(bone.triangle_count() > 0)


def _assert_same_point(a: Vector3, b: Vector3) raises:
    """Assert that two topology endpoints are the same point."""
    assert_almost_equal(a.x, b.x, atol=TOLERANCE)
    assert_almost_equal(a.y, b.y, atol=TOLERANCE)
    assert_almost_equal(a.z, b.z, atol=TOLERANCE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
