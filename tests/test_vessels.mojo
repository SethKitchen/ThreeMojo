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
from extensions.humanoid.skeleton.leg.assembly import add_leg
from extensions.humanoid.skeleton.leg.contents import VESSELS
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    muscle_dimensions,
)
from extensions.humanoid.skeleton.leg.vessels.dimensions import (
    ANTERIOR_TIBIAL_ARTERY,
    FEMORAL_ARTERY,
    FEMORAL_VEIN,
    GREAT_SAPHENOUS_VEIN,
    PERONEAL_ARTERY,
    POPLITEAL_ARTERY,
    POPLITEAL_VEIN,
    POSTERIOR_TIBIAL_ARTERY,
    SMALL_SAPHENOUS_VEIN,
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
from extensions.humanoid.skeleton.occupancy import MAX_STEP
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
    MILLIMETER,
)

comptime TOLERANCE = Float64(1e-4)


def test_vessel_parts_are_named() raises:
    var parts = named_vessel_parts()
    assert_equal(len(parts), 9)
    var index = 0
    while index < len(parts):
        assert_true(parts[index].is_valid())
        var label = vessel_part_label(parts[index])
        assert_true(label.byte_length() > 0)
        index += 1
    assert_false(VesselPart(-1).is_valid())
    assert_false(VesselPart(9).is_valid())
    assert_equal(vessel_part_label(VesselPart(99)), "vessel")
    assert_true(is_artery(FEMORAL_ARTERY))
    assert_true(is_artery(PERONEAL_ARTERY))
    assert_false(is_artery(FEMORAL_VEIN))
    assert_false(is_artery(SMALL_SAPHENOUS_VEIN))
    with assert_raises():
        _ = is_artery(VesselPart(9))


def test_vessel_labels_match_the_diagram() raises:
    assert_equal(vessel_part_label(FEMORAL_ARTERY), "femoral artery")
    assert_equal(vessel_part_label(POPLITEAL_ARTERY), "popliteal artery")
    assert_equal(
        vessel_part_label(ANTERIOR_TIBIAL_ARTERY), "anterior tibial artery"
    )
    assert_equal(
        vessel_part_label(POSTERIOR_TIBIAL_ARTERY), "posterior tibial artery"
    )
    assert_equal(vessel_part_label(PERONEAL_ARTERY), "peroneal artery")
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


def test_vessel_mesh_has_positions_normals_and_uvs() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    _assert_mesh(vessel_mesh(person, FEMORAL_ARTERY, RIGHT, 8))
    _assert_mesh(vessel_mesh(person, GREAT_SAPHENOUS_VEIN, LEFT, 8))


def test_vessel_mass_is_positive() raises:
    var step = MAX_STEP
    var artery = vessel_mass(
        HumanoidSpec(Length(6.0, FOOT), MALE), FEMORAL_ARTERY, RIGHT, step
    )
    assert_true(artery.mass.to(GRAM) > Float32(0))
    var vein = vessel_mass(
        HumanoidSpec(Length(5.5, FOOT), FEMALE), FEMORAL_VEIN, LEFT, step
    )
    assert_true(vein.mass.to(GRAM) > Float32(0))


def test_vessel_field_refuses_a_bad_part() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    with assert_raises():
        _ = VesselField(dims, VesselPart(9))
    with assert_raises():
        _ = vessel_from_dimensions(dims, VesselPart(9), 8)
    with assert_raises():
        _ = vessel_mesh(HumanoidSpec(Length(6.0, FOOT), MALE), VesselPart(9))
    with assert_raises():
        _ = vessel_from_dimensions(dims, FEMORAL_ARTERY, 7)
    with assert_raises():
        _ = vessel_from_dimensions(dims, FEMORAL_ARTERY, 65)


def test_vessel_mass_refuses_a_bad_part_or_tissue() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    with assert_raises():
        _ = vessel_mass(
            HumanoidSpec(Length(6.0, FOOT), MALE), VesselPart(9), RIGHT
        )
    with assert_raises():
        _ = vessel_mass_from_dimensions(
            dims, VesselPart(9), arterial_tissue(), Length(20.0, MILLIMETER)
        )
    var bad = arterial_tissue()
    bad.kind = SoftTissueKind(11)
    with assert_raises():
        _ = vessel_mass_from_dimensions(
            dims, FEMORAL_ARTERY, bad, Length(20.0, MILLIMETER)
        )


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
    assert_equal(len(scene.meshes), 9)


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


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
