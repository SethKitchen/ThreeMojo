# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the stature-scaled foot."""

from core.assets import Assets
from core.buffer_geometry import NORMAL, POSITION, UV
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import TONED, Athleticism
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import MAX_STATURE, MIN_STATURE, HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_phong
from extensions.humanoid.skeleton.field import mix_point
from extensions.humanoid.skeleton.foot.assembly import add_foot, assemble_foot
from extensions.humanoid.skeleton.foot.bones.dimensions import (
    CALCANEUS,
    FEMALE_ANKLE_HEIGHT,
    FEMALE_FOOT_BREADTH,
    FEMALE_FOOT_LENGTH,
    HALLUX_PROXIMAL,
    MALE_ANKLE_HEIGHT,
    MALE_FOOT_BREADTH,
    MALE_FOOT_LENGTH,
    METATARSAL_1,
    TALUS,
    TOE5_DISTAL,
    FootBone,
    FootBoneField,
    FootDimensions,
    bone_distance,
    bone_part_label,
    foot_dimensions,
    medial_axis,
    named_foot_bones,
)
from extensions.humanoid.skeleton.foot.bones.geometry import (
    bone_from_dimensions,
    foot_bone,
)
from extensions.humanoid.skeleton.foot.bones.mass import (
    foot_bone_mass,
    foot_bone_mass_from_dimensions,
    foot_bone_occupancy,
)
from extensions.humanoid.skeleton.foot.chain import tube_set_volume
from extensions.humanoid.skeleton.foot.contents import (
    ALL,
    BONES,
    BOTH,
    HAIR,
    INTEGUMENT,
    LIGAMENTS,
    LYMPH,
    MUSCLES,
    NERVES,
    SKIN,
    VESSELS,
    FootContents,
)
from extensions.humanoid.skeleton.foot.hair.dimensions import (
    DIGITAL_HAIR,
    DORSAL_HAIR,
    FootHair,
    FootHairField,
    foot_hair_distance,
    foot_hair_part_label,
    named_foot_hair,
)
from extensions.humanoid.skeleton.foot.hair.geometry import (
    foot_hair_mesh,
    hair_from_dimensions,
)
from extensions.humanoid.skeleton.foot.hair.mass import (
    foot_hair_mass,
    foot_hair_mass_from_dimensions,
    foot_hair_occupancy,
)
from extensions.humanoid.skeleton.foot.ligaments.dimensions import (
    ANTERIOR_TALOFIBULAR,
    BIFURCATE,
    DELTOID,
    FootLigament,
    FootLigamentField,
    ligament_distance,
    ligament_part_label,
    named_foot_ligaments,
)
from extensions.humanoid.skeleton.foot.ligaments.geometry import (
    foot_ligament,
    ligament_from_dimensions,
)
from extensions.humanoid.skeleton.foot.ligaments.mass import (
    ligament_mass,
    ligament_mass_from_dimensions,
    ligament_occupancy,
)
from extensions.humanoid.skeleton.foot.lymph.dimensions import (
    DORSAL_LYMPHATICS,
    FootLymph,
    FootLymphField,
    display_lymph_field,
    lymph_distance,
    lymph_part_label,
    named_foot_lymph,
)
from extensions.humanoid.skeleton.foot.lymph.geometry import (
    foot_lymph,
    lymph_from_dimensions,
)
from extensions.humanoid.skeleton.foot.lymph.mass import (
    foot_lymph_mass,
    foot_lymph_mass_from_dimensions,
    foot_lymph_occupancy,
)
from extensions.humanoid.skeleton.foot.muscles.dimensions import (
    ABDUCTOR_HALLUCIS,
    CALCANEAL_TENDON,
    EXTENSOR_DIGITORUM_BREVIS,
    EXTENSOR_DIGITORUM_LONGUS_TENDON,
    FLEXOR_HALLUCIS_BREVIS,
    FIBULARIS_BREVIS_TENDON,
    FIBULARIS_LONGUS_TENDON,
    PERONEUS_BREVIS_TENDON,
    PERONEUS_LONGUS_TENDON,
    PLANTAR_INTEROSSEI,
    FootMuscle,
    FootMuscleField,
    foot_muscle_dimensions,
    foot_muscle_distance,
    foot_muscle_part_label,
    is_tendon,
    named_foot_muscles,
)
from extensions.humanoid.skeleton.foot.muscles.geometry import (
    foot_muscle,
    muscle_from_dimensions,
)
from extensions.humanoid.skeleton.foot.muscles.mass import (
    foot_muscle_mass,
    foot_muscle_mass_from_dimensions,
    foot_muscle_occupancy,
)
from extensions.humanoid.skeleton.foot.nerves.dimensions import (
    DEEP_FIBULAR_NERVE,
    DEEP_PERONEAL_NERVE,
    SUPERFICIAL_FIBULAR_NERVE,
    SUPERFICIAL_PERONEAL_NERVE,
    TIBIAL_NERVE,
    FootNerve,
    FootNerveField,
    display_nerve_field,
    named_foot_nerves,
    nerve_distance,
    nerve_part_label,
)
from extensions.humanoid.skeleton.foot.nerves.geometry import (
    foot_nerve,
    nerve_from_dimensions,
)
from extensions.humanoid.skeleton.foot.nerves.mass import (
    foot_nerve_mass,
    foot_nerve_mass_from_dimensions,
    foot_nerve_occupancy,
)
from extensions.humanoid.skeleton.foot.skin.dimensions import (
    SkinField,
    SkinLayerField,
    skin_distance,
)
from extensions.humanoid.skeleton.foot.skin.geometry import (
    foot_skin_mesh,
    skin_from_dimensions,
)
from extensions.humanoid.skeleton.foot.skin.mass import (
    foot_skin_mass,
    foot_skin_mass_from_dimensions,
    foot_skin_occupancy,
)
from extensions.humanoid.skeleton.foot.vessels.dimensions import (
    DORSAL_VENOUS_ARCH,
    DORSALIS_PEDIS_ARTERY,
    GREAT_SAPHENOUS_VEIN,
    FootVessel,
    FootVesselField,
    display_vessel_field,
    is_artery,
    named_foot_vessels,
    vessel_distance,
    vessel_part_label,
)
from extensions.humanoid.skeleton.foot.vessels.geometry import (
    foot_vessel,
    vessel_from_dimensions,
)
from extensions.humanoid.skeleton.foot.vessels.mass import (
    foot_vessel_mass,
    foot_vessel_mass_from_dimensions,
    foot_vessel_occupancy,
)
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.look import (
    artery_phong,
    ligament_phong,
    muscle_phong,
    tendon_phong,
)
from extensions.humanoid.skeleton.occupancy import (
    CORTICAL_FILL,
    EMPTY,
    MAX_STEP,
    MIN_STEP,
    TRABECULAR_FILL,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SOFT_EMPTY,
    SOFT_FILL,
    SoftTissueKind,
    arterial_tissue,
    hair_tissue,
    ligament_tissue,
    lymph_tissue,
    muscle_tissue,
    nerve_tissue,
    skin_tissue,
    tendon_tissue,
)
from extensions.humanoid.skeleton.tissue import (
    BoneKind,
    cortical_tissue,
    trabecular_tissue,
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


def _person() -> HumanoidSpec:
    """Return a six-foot untoned male."""
    return HumanoidSpec(Length(6.0, FOOT), MALE)


def _right_foot() raises -> FootDimensions:
    """Return right-foot landmarks for a six-foot male."""
    return foot_dimensions(Length(6.0, FOOT), MALE)


def _assert_unit_out(normal: Vector3) raises:
    """Require a far-field gradient to be a unit vector toward plus x."""
    assert_almost_equal(normal.length(), Float32(1), atol=Float64(1e-3))
    assert_true(normal.x > 0)


def test_male_and_female_feet_use_authored_ratios() raises:
    var male = foot_dimensions(Length(6.0, FOOT), MALE)
    var S = male.stature.value
    assert_almost_equal(male.length.value, S * MALE_FOOT_LENGTH, atol=TOLERANCE)
    assert_almost_equal(male.width.value, S * MALE_FOOT_BREADTH, atol=TOLERANCE)
    assert_almost_equal(
        male.height.value, S * MALE_ANKLE_HEIGHT, atol=TOLERANCE
    )
    var female = foot_dimensions(Length(6.0, FOOT), FEMALE, LEFT)
    var Sf = female.stature.value
    assert_almost_equal(
        female.length.value, Sf * FEMALE_FOOT_LENGTH, atol=TOLERANCE
    )
    assert_almost_equal(
        female.width.value, Sf * FEMALE_FOOT_BREADTH, atol=TOLERANCE
    )
    assert_almost_equal(
        female.height.value, Sf * FEMALE_ANKLE_HEIGHT, atol=TOLERANCE
    )
    assert_equal(len(named_foot_bones()), 26)


def test_landmarks_follow_the_arch_and_meet_the_leg() raises:
    var foot = _right_foot()
    assert_true(foot.navicular.y > foot.cuboid.y)
    assert_true(foot.cuboid.y > foot.heel.y)
    assert_true(foot.mt2_base.z < foot.mt1_base.z)
    assert_true(foot.mt2_head.z > foot.mt1_head.z)
    assert_true(foot.mt1_head.z > foot.mt5_head.z)
    assert_almost_equal(
        foot.toe2_tip.z, foot.heel.z + foot.length.value, atol=TOLERANCE
    )
    assert_almost_equal(foot.heel.x, Float32(0), atol=TOLERANCE)
    var leg = assemble_leg(_person())
    var delta = leg.muscles.heel - leg.ankle_center()
    assert_almost_equal(delta.x, foot.heel.x, atol=TOLERANCE)
    assert_almost_equal(delta.y, foot.heel.y, atol=TOLERANCE)
    assert_almost_equal(delta.z, foot.heel.z, atol=TOLERANCE)
    var medial = leg.ankle_center() + foot.medial_malleolus
    var expected = leg.tibia_origin + leg.tibia.medial_malleolus
    assert_almost_equal(medial.x, expected.x, atol=TOLERANCE)
    assert_almost_equal(medial.y, expected.y, atol=TOLERANCE)
    assert_almost_equal(medial.z, expected.z, atol=TOLERANCE)
    var lateral = leg.ankle_center() + foot.lateral_malleolus
    var fibular = leg.fibula_origin + leg.fibula.lateral_malleolus
    assert_almost_equal(lateral.x, fibular.x, atol=TOLERANCE)
    assert_almost_equal(lateral.y, fibular.y, atol=TOLERANCE)
    assert_almost_equal(lateral.z, fibular.z, atol=TOLERANCE)
    var axis = medial_axis(foot)
    assert_almost_equal(axis.length(), Float32(1), atol=Float64(1e-4))
    assert_true(axis.x < 0)


def test_left_foot_mirrors_x() raises:
    var right = _right_foot()
    var left = foot_dimensions(Length(6.0, FOOT), MALE, LEFT)
    assert_almost_equal(left.mt1_head.x, -right.mt1_head.x, atol=TOLERANCE)
    assert_almost_equal(left.mt5_head.x, -right.mt5_head.x, atol=TOLERANCE)
    assert_almost_equal(left.heel.x, Float32(0), atol=TOLERANCE)
    assert_almost_equal(
        left.medial_malleolus.x, -right.medial_malleolus.x, atol=TOLERANCE
    )
    assert_almost_equal(
        left.lateral_malleolus.x, -right.lateral_malleolus.x, atol=TOLERANCE
    )
    assert_almost_equal(left.heel.y, right.heel.y, atol=TOLERANCE)
    assert_almost_equal(left.toe2_tip.z, right.toe2_tip.z, atol=TOLERANCE)


def test_every_bone_has_a_solid_and_a_label() raises:
    var dims = _right_foot()
    var parts = named_foot_bones()
    var index = 0
    while index < len(parts):
        var part = parts[index]
        assert_true(part.is_valid())
        var label = bone_part_label(part)
        assert_true(label.byte_length() > 0)
        var field = FootBoneField(dims, part)
        var d = bone_distance(dims, part, field.segments.a0)
        assert_true(d < 0)
        index += 1
    assert_equal(bone_part_label(FootBone(99)), "foot bone")
    assert_false(FootBone(-1).is_valid())
    assert_false(FootBone(26).is_valid())
    _assert_unit_out(FootBoneField(dims, CALCANEUS).gradient(Vector3(10, 0, 0)))
    with assert_raises():
        _ = FootBoneField(dims, FootBone(40))
    with assert_raises():
        _ = bone_from_dimensions(dims, FootBone(-2), 8)


def test_bone_occupancy_is_shell_then_trabecular() raises:
    var dims = _right_foot()
    var field = FootBoneField(dims, HALLUX_PROXIMAL)
    var center = mix_point(field.segments.a0, field.segments.b0, 0.5)
    assert_equal(
        foot_bone_occupancy(dims, HALLUX_PROXIMAL, center), TRABECULAR_FILL
    )
    assert_equal(
        foot_bone_occupancy(dims, HALLUX_PROXIMAL, Vector3(10, 0, 0)), EMPTY
    )
    var low = center
    var high = center + Vector3(0, 0.04, 0)
    var step = 0
    while step < 16:
        var middle = (low + high) * Float32(0.5)
        if bone_distance(dims, HALLUX_PROXIMAL, middle) < -field.shell:
            low = middle
        else:
            high = middle
        step += 1
    var shell = (low + high) * Float32(0.5)
    assert_equal(
        foot_bone_occupancy(dims, HALLUX_PROXIMAL, shell), CORTICAL_FILL
    )
    var report = foot_bone_mass(
        _person(), CALCANEUS, RIGHT, Length(8.0, MILLIMETER)
    )
    assert_true(report.mass.to(GRAM) > Float32(1))
    assert_true(report.trabecular_region.value > 0)
    assert_almost_equal(
        report.weight().value,
        report.mass.value * STANDARD_GRAVITY.value,
        atol=TOLERANCE,
    )
    var heavier = foot_bone_mass(
        HumanoidSpec(Length(6.5, FOOT), MALE),
        CALCANEUS,
        LEFT,
        Length(8.0, MILLIMETER),
    )
    assert_true(heavier.mass > report.mass)


def test_bone_mass_refuses_bad_inputs() raises:
    var dims = _right_foot()
    with assert_raises():
        _ = foot_bone_mass_from_dimensions(
            dims,
            FootBone(30),
            cortical_tissue(),
            trabecular_tissue(),
            Length(8.0, MILLIMETER),
        )
    with assert_raises():
        _ = foot_bone_mass_from_dimensions(
            dims,
            CALCANEUS,
            cortical_tissue(),
            trabecular_tissue(),
            MIN_STEP.scaled(0.5),
        )
    with assert_raises():
        _ = foot_bone_mass_from_dimensions(
            dims,
            CALCANEUS,
            cortical_tissue(),
            trabecular_tissue(),
            MAX_STEP + Length(1.0, MILLIMETER),
        )
    var bad = cortical_tissue()
    bad.kind = BoneKind(9)
    with assert_raises():
        _ = foot_bone_mass_from_dimensions(
            dims, TALUS, bad, trabecular_tissue(), Length(8.0, MILLIMETER)
        )
    var mesh = foot_bone(_person(), TOE5_DISTAL, RIGHT, 8)
    assert_true(mesh.has_attribute(String(POSITION)))
    assert_true(mesh.has_attribute(String(NORMAL)))
    assert_true(mesh.has_attribute(String(UV)))
    assert_true(mesh.triangle_count() > 0)
    with assert_raises():
        _ = foot_bone(_person(), CALCANEUS, RIGHT, 7)
    with assert_raises():
        _ = bone_from_dimensions(dims, CALCANEUS, 65)


def test_ligaments_span_one_two_and_three_bands() raises:
    var dims = _right_foot()
    var parts = named_foot_ligaments()
    assert_equal(len(parts), 10)
    var index = 0
    while index < len(parts):
        var part = parts[index]
        assert_true(part.is_valid())
        assert_true(ligament_part_label(part).byte_length() > 0)
        var field = FootLigamentField(dims, part)
        assert_true(ligament_distance(dims, part, field.segments.a0) < 0)
        var report = ligament_mass(_person(), part)
        assert_true(report.mass.to(GRAM) > Float32(0))
        assert_true(report.envelope.value > 0)
        index += 1
    assert_equal(ligament_part_label(FootLigament(12)), "ligament")
    assert_false(FootLigament(-1).is_valid())
    assert_equal(FootLigamentField(dims, DELTOID).segments.count, 3)
    assert_equal(FootLigamentField(dims, BIFURCATE).segments.count, 2)
    assert_equal(
        FootLigamentField(dims, ANTERIOR_TALOFIBULAR).segments.count, 1
    )
    var outside = Vector3(10, 0, 0)
    assert_equal(
        ligament_occupancy(dims, ANTERIOR_TALOFIBULAR, outside), SOFT_EMPTY
    )
    var deltoid = FootLigamentField(dims, DELTOID)
    assert_equal(
        ligament_occupancy(dims, DELTOID, deltoid.segments.a0), SOFT_FILL
    )
    _assert_unit_out(deltoid.gradient(outside))
    var bad = ligament_tissue()
    bad.kind = SoftTissueKind(40)
    with assert_raises():
        _ = ligament_mass_from_dimensions(dims, DELTOID, bad)
    with assert_raises():
        _ = ligament_mass_from_dimensions(
            dims, FootLigament(-1), ligament_tissue()
        )
    with assert_raises():
        _ = FootLigamentField(dims, FootLigament(-1))
    with assert_raises():
        _ = ligament_from_dimensions(dims, FootLigament(11), 8)
    var mesh = foot_ligament(_person(), ANTERIOR_TALOFIBULAR, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)


def test_tendons_do_not_scale_and_bellies_do() raises:
    var toned = foot_muscle_dimensions(
        HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    )
    var plain = foot_muscle_dimensions(_person())
    var toned_belly = FootMuscleField(toned, ABDUCTOR_HALLUCIS)
    var plain_belly = FootMuscleField(plain, ABDUCTOR_HALLUCIS)
    assert_true(toned_belly.tubes.c0.r2 > plain_belly.tubes.c0.r2)
    var toned_tendon = FootMuscleField(toned, CALCANEAL_TENDON)
    var plain_tendon = FootMuscleField(plain, CALCANEAL_TENDON)
    assert_almost_equal(
        toned_tendon.tubes.c0.r0, plain_tendon.tubes.c0.r0, atol=TOLERANCE
    )
    assert_true(is_tendon(CALCANEAL_TENDON))
    assert_false(is_tendon(ABDUCTOR_HALLUCIS))
    assert_true(PERONEUS_LONGUS_TENDON == FIBULARIS_LONGUS_TENDON)
    assert_true(PERONEUS_BREVIS_TENDON == FIBULARIS_BREVIS_TENDON)
    var parts = named_foot_muscles()
    assert_equal(len(parts), 21)
    var index = 0
    while index < len(parts):
        var part = parts[index]
        assert_true(part.is_valid())
        assert_true(foot_muscle_part_label(part).byte_length() > 0)
        var field = FootMuscleField(plain, part)
        assert_true(foot_muscle_distance(plain, part, field.tubes.c0.p2) < 0)
        var report = foot_muscle_mass(_person(), part)
        assert_true(report.envelope.value > 0)
        index += 1
    assert_equal(FootMuscleField(plain, CALCANEAL_TENDON).tubes.count, 1)
    assert_equal(FootMuscleField(plain, FLEXOR_HALLUCIS_BREVIS).tubes.count, 2)
    assert_equal(FootMuscleField(plain, PLANTAR_INTEROSSEI).tubes.count, 3)
    assert_equal(
        FootMuscleField(plain, EXTENSOR_DIGITORUM_BREVIS).tubes.count, 3
    )
    assert_equal(
        FootMuscleField(plain, EXTENSOR_DIGITORUM_LONGUS_TENDON).tubes.count, 4
    )
    var outside = Vector3(10, 0, 0)
    assert_equal(
        foot_muscle_occupancy(plain, CALCANEAL_TENDON, outside), SOFT_EMPTY
    )
    assert_equal(
        foot_muscle_occupancy(
            plain, ABDUCTOR_HALLUCIS, plain_belly.tubes.c0.p2
        ),
        SOFT_FILL,
    )
    _assert_unit_out(plain_tendon.gradient(outside))
    assert_equal(foot_muscle_part_label(FootMuscle(40)), "foot muscle")
    assert_false(FootMuscle(-1).is_valid())
    with assert_raises():
        _ = is_tendon(FootMuscle(30))
    with assert_raises():
        _ = muscle_from_dimensions(plain, FootMuscle(30), 8)
    var tendon = tendon_tissue()
    tendon.kind = SoftTissueKind(41)
    with assert_raises():
        _ = foot_muscle_mass_from_dimensions(plain, CALCANEAL_TENDON, tendon)
    with assert_raises():
        _ = foot_muscle_mass_from_dimensions(
            plain, FootMuscle(-1), tendon_tissue()
        )
    with assert_raises():
        _ = FootMuscleField(plain, FootMuscle(-1))
    var mesh = foot_muscle(_person(), ABDUCTOR_HALLUCIS, RIGHT, 8)
    assert_true(mesh.triangle_count() > 0)
    var achilles = foot_muscle(
        HumanoidSpec(Length(6.0, FOOT), FEMALE, TONED),
        CALCANEAL_TENDON,
        LEFT,
        8,
    )
    assert_true(achilles.triangle_count() > 0)


def test_vessels_keep_physical_mass() raises:
    var dims = _right_foot()
    var parts = named_foot_vessels()
    assert_equal(len(parts), 9)
    var index = 0
    while index < len(parts):
        var part = parts[index]
        assert_true(part.is_valid())
        assert_true(vessel_part_label(part).byte_length() > 0)
        var field = FootVesselField(dims, part)
        assert_true(vessel_distance(dims, part, field.tubes.c0.p2) < 0)
        index += 1
    assert_true(is_artery(DORSALIS_PEDIS_ARTERY))
    assert_false(is_artery(GREAT_SAPHENOUS_VEIN))
    var physical = FootVesselField(dims, DORSALIS_PEDIS_ARTERY)
    var volume = tube_set_volume(physical.tubes)
    var report = foot_vessel_mass(_person(), DORSALIS_PEDIS_ARTERY)
    assert_almost_equal(report.envelope.value, volume, atol=Float64(1e-12))
    var shown = display_vessel_field(dims, DORSALIS_PEDIS_ARTERY)
    assert_true(tube_set_volume(shown.tubes) > volume)
    var arch = FootVesselField(dims, DORSAL_VENOUS_ARCH)
    assert_true(FootBoneField(dims, CALCANEUS).distance(arch.tubes.c0.p2) > 0)
    assert_true(
        FootBoneField(dims, METATARSAL_1).distance(arch.tubes.c0.p2) > 0
    )
    assert_equal(
        foot_vessel_occupancy(dims, DORSALIS_PEDIS_ARTERY, Vector3(10, 0, 0)),
        SOFT_EMPTY,
    )
    assert_equal(
        foot_vessel_occupancy(
            dims, DORSALIS_PEDIS_ARTERY, physical.tubes.c0.p2
        ),
        SOFT_FILL,
    )
    _assert_unit_out(physical.gradient(Vector3(10, 0, 0)))
    assert_equal(vessel_part_label(FootVessel(20)), "foot vessel")
    assert_false(FootVessel(-1).is_valid())
    with assert_raises():
        _ = is_artery(FootVessel(15))
    var bad = arterial_tissue()
    bad.kind = SoftTissueKind(42)
    with assert_raises():
        _ = foot_vessel_mass_from_dimensions(dims, DORSALIS_PEDIS_ARTERY, bad)
    with assert_raises():
        _ = foot_vessel_mass_from_dimensions(
            dims, FootVessel(-1), arterial_tissue()
        )
    with assert_raises():
        _ = FootVesselField(dims, FootVessel(-1))
    var vein = foot_vessel_mass(_person(), GREAT_SAPHENOUS_VEIN)
    assert_true(vein.envelope.value > 0)
    with assert_raises():
        _ = vessel_from_dimensions(dims, FootVessel(15), 8)
    var mesh = foot_vessel(_person(), GREAT_SAPHENOUS_VEIN, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)


def test_lymph_and_nerves_use_physical_radii() raises:
    var dims = _right_foot()
    var lymph = named_foot_lymph()
    assert_equal(len(lymph), 4)
    var index = 0
    while index < len(lymph):
        var part = lymph[index]
        assert_true(part.is_valid())
        assert_true(lymph_part_label(part).byte_length() > 0)
        var field = FootLymphField(dims, part)
        assert_true(lymph_distance(dims, part, field.tubes.c0.p2) < 0)
        var report = foot_lymph_mass(_person(), part, LEFT)
        assert_true(report.envelope.value > 0)
        index += 1
    var physical = FootLymphField(dims, DORSAL_LYMPHATICS)
    var shown = display_lymph_field(dims, DORSAL_LYMPHATICS)
    assert_true(tube_set_volume(shown.tubes) > tube_set_volume(physical.tubes))
    assert_equal(lymph_part_label(FootLymph(9)), "foot lymph")
    assert_equal(
        foot_lymph_occupancy(dims, DORSAL_LYMPHATICS, physical.tubes.c0.p2),
        SOFT_FILL,
    )
    assert_equal(
        foot_lymph_occupancy(dims, DORSAL_LYMPHATICS, Vector3(10, 0, 0)),
        SOFT_EMPTY,
    )
    _assert_unit_out(physical.gradient(Vector3(10, 0, 0)))
    var bad_lymph = lymph_tissue()
    bad_lymph.kind = SoftTissueKind(43)
    with assert_raises():
        _ = foot_lymph_mass_from_dimensions(dims, DORSAL_LYMPHATICS, bad_lymph)
    with assert_raises():
        _ = foot_lymph_mass_from_dimensions(dims, FootLymph(-1), lymph_tissue())
    with assert_raises():
        _ = FootLymphField(dims, FootLymph(-1))
    with assert_raises():
        _ = lymph_from_dimensions(dims, FootLymph(-1), 8)
    var lymph_mesh = foot_lymph(_person(), DORSAL_LYMPHATICS, RIGHT, 8)
    assert_true(lymph_mesh.triangle_count() > 0)
    var nerves = named_foot_nerves()
    assert_equal(len(nerves), 7)
    index = 0
    while index < len(nerves):
        var part = nerves[index]
        assert_true(part.is_valid())
        assert_true(nerve_part_label(part).byte_length() > 0)
        var field = FootNerveField(dims, part)
        assert_true(nerve_distance(dims, part, field.tubes.c0.p2) < 0)
        var report = foot_nerve_mass(_person(), part)
        assert_true(report.envelope.value > 0)
        index += 1
    assert_true(DEEP_PERONEAL_NERVE == DEEP_FIBULAR_NERVE)
    assert_true(SUPERFICIAL_PERONEAL_NERVE == SUPERFICIAL_FIBULAR_NERVE)
    assert_equal(FootNerveField(dims, SUPERFICIAL_FIBULAR_NERVE).tubes.count, 2)
    var nerve = FootNerveField(dims, TIBIAL_NERVE)
    var nerve_shown = display_nerve_field(dims, TIBIAL_NERVE)
    assert_true(
        tube_set_volume(nerve_shown.tubes) > tube_set_volume(nerve.tubes)
    )
    assert_equal(nerve_part_label(FootNerve(12)), "foot nerve")
    assert_false(FootNerve(-1).is_valid())
    assert_equal(
        foot_nerve_occupancy(dims, TIBIAL_NERVE, nerve.tubes.c0.p2), SOFT_FILL
    )
    assert_equal(
        foot_nerve_occupancy(dims, TIBIAL_NERVE, Vector3(10, 0, 0)), SOFT_EMPTY
    )
    _assert_unit_out(nerve.gradient(Vector3(10, 0, 0)))
    var bad_nerve = nerve_tissue()
    bad_nerve.kind = SoftTissueKind(44)
    with assert_raises():
        _ = foot_nerve_mass_from_dimensions(dims, TIBIAL_NERVE, bad_nerve)
    with assert_raises():
        _ = foot_nerve_mass_from_dimensions(dims, FootNerve(-1), nerve_tissue())
    with assert_raises():
        _ = FootNerveField(dims, FootNerve(-1))
    with assert_raises():
        _ = nerve_from_dimensions(dims, FootNerve(8), 8)
    var nerve_mesh = foot_nerve(_person(), TIBIAL_NERVE, LEFT, 8)
    assert_true(nerve_mesh.triangle_count() > 0)


def _worst_station(skin: SkinField, point: Vector3, mut worst: Float32):
    """Keep the largest signed distance."""
    var d = skin.distance(point)
    if d > worst:
        worst = d


def test_skin_wraps_physical_stations() raises:
    var dims = foot_muscle_dimensions(_person())
    var skin = SkinField(dims)
    var worst = Float32(-1)
    _worst_station(skin, dims.foot.medial_malleolus, worst)
    _worst_station(skin, dims.foot.lateral_malleolus, worst)
    var bones = named_foot_bones()
    var index = 0
    while index < len(bones):
        var field = FootBoneField(dims.foot, bones[index])
        _worst_station(skin, field.segments.a0, worst)
        _worst_station(skin, field.segments.b0, worst)
        if field.segments.count >= 2:
            _worst_station(skin, field.segments.a1, worst)
            _worst_station(skin, field.segments.b1, worst)
        index += 1
    var muscles = named_foot_muscles()
    index = 0
    while index < len(muscles):
        var field = FootMuscleField(dims, muscles[index])
        _worst_station(skin, field.tubes.c0.p0, worst)
        _worst_station(skin, field.tubes.c0.p2, worst)
        _worst_station(skin, field.tubes.c0.p4, worst)
        if field.tubes.count >= 2:
            _worst_station(skin, field.tubes.c1.p2, worst)
        if field.tubes.count >= 3:
            _worst_station(skin, field.tubes.c2.p2, worst)
        if field.tubes.count >= 4:
            _worst_station(skin, field.tubes.c3.p2, worst)
        index += 1
    var vessels = named_foot_vessels()
    index = 0
    while index < len(vessels):
        var field = FootVesselField(dims.foot, vessels[index])
        _worst_station(skin, field.tubes.c0.p0, worst)
        _worst_station(skin, field.tubes.c0.p2, worst)
        _worst_station(skin, field.tubes.c0.p4, worst)
        index += 1
    var lymph = named_foot_lymph()
    index = 0
    while index < len(lymph):
        var field = FootLymphField(dims.foot, lymph[index])
        _worst_station(skin, field.tubes.c0.p0, worst)
        _worst_station(skin, field.tubes.c0.p4, worst)
        index += 1
    var nerves = named_foot_nerves()
    index = 0
    while index < len(nerves):
        var field = FootNerveField(dims.foot, nerves[index])
        _worst_station(skin, field.tubes.c0.p0, worst)
        _worst_station(skin, field.tubes.c0.p4, worst)
        if field.tubes.count >= 2:
            _worst_station(skin, field.tubes.c1.p4, worst)
        index += 1
    var ligaments = named_foot_ligaments()
    index = 0
    while index < len(ligaments):
        var field = FootLigamentField(dims.foot, ligaments[index])
        _worst_station(skin, field.segments.a0, worst)
        _worst_station(skin, field.segments.b0, worst)
        if field.segments.count >= 2:
            _worst_station(skin, field.segments.a1, worst)
        if field.segments.count >= 3:
            _worst_station(skin, field.segments.a2, worst)
        index += 1
    assert_true(worst < 0)
    assert_true(skin_distance(dims, dims.foot.talar_body) < 0)
    assert_true(skin_distance(dims, Vector3(10, 0, 0)) > 0)
    var layer = SkinLayerField(dims)
    var inside = dims.foot.talar_body
    var outside = inside + Vector3(0, 0.25, 0)
    var step = 0
    while step < 18:
        var middle = (inside + outside) * Float32(0.5)
        if layer.outer.distance(middle) < 0:
            inside = middle
        else:
            outside = middle
        step += 1
    var normal = layer.outer.gradient(outside)
    var dermal = outside - normal * (Float32(0.4) * layer.thickness)
    assert_equal(foot_skin_occupancy(dims, dermal), SOFT_FILL)
    assert_equal(foot_skin_occupancy(dims, dims.foot.talar_body), SOFT_EMPTY)
    assert_equal(foot_skin_occupancy(dims, Vector3(10, 0, 0)), SOFT_EMPTY)
    _assert_unit_out(layer.gradient(Vector3(10, 0, 0)))
    var report = foot_skin_mass(_person(), RIGHT, Length(10.0, MILLIMETER))
    assert_true(report.mass.to(GRAM) > Float32(1))
    var bad = skin_tissue()
    bad.kind = SoftTissueKind(45)
    with assert_raises():
        _ = foot_skin_mass_from_dimensions(dims, bad, Length(10.0, MILLIMETER))
    with assert_raises():
        _ = skin_from_dimensions(dims, 7)
    var mesh = foot_skin_mesh(_person(), RIGHT, 8)
    assert_true(mesh.triangle_count() > 0)


def test_hair_roots_sit_on_the_skin() raises:
    var dims = foot_muscle_dimensions(_person())
    var skin = SkinField(dims)
    var dorsal = FootHairField(dims, DORSAL_HAIR)
    var digital = FootHairField(dims, DIGITAL_HAIR)
    var root = skin.distance(dorsal.a0)
    assert_true(root >= 0)
    assert_true(root < Float32(0.001))
    var toe = skin.distance(digital.a0)
    assert_true(toe >= 0)
    assert_true(toe < Float32(0.001))
    assert_true(dorsal.a0.y > dims.foot.talar_body.y)
    assert_true(dorsal.radius > digital.radius)
    assert_true(dorsal.radius < Float32(0.00003))
    assert_equal(len(named_foot_hair()), 2)
    assert_equal(foot_hair_part_label(DORSAL_HAIR), "dorsal hair")
    assert_equal(foot_hair_part_label(DIGITAL_HAIR), "digital hair")
    assert_equal(foot_hair_part_label(FootHair(5)), "foot hair")
    assert_false(FootHair(-1).is_valid())
    var mid = (dorsal.a0 + dorsal.b0) * Float32(0.5)
    assert_true(foot_hair_distance(dims, DORSAL_HAIR, mid) < 0)
    assert_equal(foot_hair_occupancy(dims, DORSAL_HAIR, mid), SOFT_FILL)
    assert_equal(
        foot_hair_occupancy(dims, DIGITAL_HAIR, Vector3(10, 0, 0)), SOFT_EMPTY
    )
    _assert_unit_out(dorsal.gradient(Vector3(10, 0, 0)))
    var report = foot_hair_mass(_person(), DORSAL_HAIR)
    assert_true(report.envelope.value > 0)
    assert_true(report.envelope.value < Float32(1e-8))
    var left = foot_muscle_dimensions(_person(), LEFT)
    var mirrored = FootHairField(left, DIGITAL_HAIR)
    assert_true(mirrored.a1.x > 0)
    var bad = hair_tissue()
    bad.kind = SoftTissueKind(46)
    with assert_raises():
        _ = foot_hair_mass_from_dimensions(dims, DORSAL_HAIR, bad)
    with assert_raises():
        _ = foot_hair_mass_from_dimensions(dims, FootHair(-1), hair_tissue())
    with assert_raises():
        _ = hair_from_dimensions(dims, FootHair(3), 8)
    with assert_raises():
        _ = FootHairField(dims, FootHair(4))
    var mesh = foot_hair_mesh(_person(), DORSAL_HAIR, RIGHT, 8)
    assert_true(mesh.triangle_count() > 0)


def test_dimensions_refuse_bad_edits() raises:
    with assert_raises():
        _ = foot_dimensions(MIN_STATURE.scaled(0.5), MALE)
    with assert_raises():
        _ = foot_dimensions(MAX_STATURE + Length(0.1, METER), FEMALE)
    with assert_raises():
        _ = foot_dimensions(Length(nan[DType.float32](), METER), MALE)
    with assert_raises():
        _ = foot_dimensions(Length(inf[DType.float32](), METER), MALE)
    with assert_raises():
        _ = foot_dimensions(Length(6.0, FOOT), Sex(4))
    with assert_raises():
        _ = foot_dimensions(Length(6.0, FOOT), MALE, BodySide(3))
    var foot = _right_foot()
    foot.length = Length(0)
    with assert_raises():
        foot.validate()
    foot = _right_foot()
    foot.heel = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises():
        foot.validate()
    with assert_raises():
        _ = foot_muscle_dimensions(
            HumanoidSpec(Length(6.0, FOOT), MALE, Athleticism(4))
        )
    var muscles = foot_muscle_dimensions(_person())
    muscles.athleticism = Athleticism(5)
    with assert_raises():
        muscles.validate()
    muscles = foot_muscle_dimensions(_person())
    muscles.scale = 0
    with assert_raises():
        muscles.validate()
    muscles = foot_muscle_dimensions(_person())
    muscles.k = 0
    with assert_raises():
        muscles.validate()
    muscles = foot_muscle_dimensions(_person())
    muscles.epsilon = -1
    with assert_raises():
        muscles.validate()
    var pose = assemble_foot(_person(), LEFT)
    assert_almost_equal(pose.plafond().x, Float32(0), atol=TOLERANCE)
    assert_almost_equal(pose.plafond().y, Float32(0), atol=TOLERANCE)
    assert_almost_equal(pose.plafond().z, Float32(0), atol=TOLERANCE)
    assert_equal(pose.side, LEFT)


def test_foot_contents_combine_named_layers() raises:
    assert_true(BONES.is_valid())
    assert_true(LIGAMENTS.is_valid())
    assert_true(MUSCLES.is_valid())
    assert_true(VESSELS.is_valid())
    assert_true(LYMPH.is_valid())
    assert_true(NERVES.is_valid())
    assert_true(SKIN.is_valid())
    assert_true(HAIR.is_valid())
    assert_true(BOTH.is_valid())
    assert_true(INTEGUMENT.is_valid())
    assert_true(ALL.is_valid())
    assert_false(FootContents(0).is_valid())
    assert_false(FootContents(-1).is_valid())
    assert_false(FootContents(256).is_valid())
    assert_true(BONES.includes_bones())
    assert_false(MUSCLES.includes_bones())
    assert_true(LIGAMENTS.includes_ligaments())
    assert_false(BONES.includes_ligaments())
    assert_true(MUSCLES.includes_muscles())
    assert_false(BONES.includes_muscles())
    assert_true(VESSELS.includes_vessels())
    assert_false(BONES.includes_vessels())
    assert_true(LYMPH.includes_lymph())
    assert_false(BONES.includes_lymph())
    assert_true(NERVES.includes_nerves())
    assert_false(BONES.includes_nerves())
    assert_true(SKIN.includes_skin())
    assert_false(BONES.includes_skin())
    assert_true(HAIR.includes_hair())
    assert_false(BONES.includes_hair())
    assert_true(BOTH.includes_bones())
    assert_true(BOTH.includes_ligaments())
    assert_true(BOTH.includes_muscles())
    assert_false(BOTH.includes_vessels())
    assert_true(INTEGUMENT.includes_skin())
    assert_true(INTEGUMENT.includes_hair())
    assert_true(ALL.includes_hair())
    var combined = BONES.plus(LIGAMENTS).plus(VESSELS)
    assert_true(combined.includes_bones())
    assert_true(combined.includes_ligaments())
    assert_true(combined.includes_vessels())
    assert_false(combined.includes_muscles())
    var bad = FootContents(0)
    with assert_raises():
        _ = bad.includes_bones()
    with assert_raises():
        _ = bad.includes_ligaments()
    with assert_raises():
        _ = bad.includes_muscles()
    with assert_raises():
        _ = bad.includes_vessels()
    with assert_raises():
        _ = bad.includes_lymph()
    with assert_raises():
        _ = bad.includes_nerves()
    with assert_raises():
        _ = bad.includes_skin()
    with assert_raises():
        _ = bad.includes_hair()
    with assert_raises():
        _ = bad.plus(BONES)
    with assert_raises():
        _ = BONES.plus(FootContents(256))


def test_add_foot_places_every_layer() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var person = _person()
    var bone_paint = assets.materials.add(bone_phong())
    var ligament_paint = assets.materials.add(ligament_phong())
    var muscle_paint = assets.materials.add(muscle_phong())
    var tendon_paint = assets.materials.add(tendon_phong())
    var artery_paint = assets.materials.add(artery_phong())
    var node = add_foot(
        scene,
        assets,
        root,
        person,
        bone_paint,
        ligament_paint,
        muscle_paint,
        tendon_paint,
        RIGHT,
        ALL,
        8,
        Vector3(0.02, -0.04, 0.06),
        artery_paint,
    )
    assert_equal(len(scene.meshes), 80)
    scene.update()
    var origin = scene.world_matrix(node).transform_point(Vector3(0, 0, 0))
    assert_almost_equal(origin.x, Float32(0.02), atol=TOLERANCE)
    assert_almost_equal(origin.y, Float32(-0.04), atol=TOLERANCE)
    assert_almost_equal(origin.z, Float32(0.06), atol=TOLERANCE)
    var lymph_scene = Scene()
    var lymph_assets = Assets()
    var lymph_root = lymph_scene.add(Object3D())
    _ = add_foot(
        lymph_scene,
        lymph_assets,
        lymph_root,
        person,
        bone_paint,
        ligament_paint,
        muscle_paint,
        tendon_paint,
        contents=LYMPH,
        detail=8,
    )
    assert_equal(len(lymph_scene.meshes), 4)
    with assert_raises():
        _ = add_foot(
            scene,
            assets,
            root,
            person,
            bone_paint,
            ligament_paint,
            muscle_paint,
            tendon_paint,
            contents=FootContents(0),
        )
    with assert_raises():
        _ = add_foot(
            scene,
            assets,
            root,
            person,
            bone_paint,
            ligament_paint,
            muscle_paint,
            tendon_paint,
            contents=SKIN,
            detail=7,
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
