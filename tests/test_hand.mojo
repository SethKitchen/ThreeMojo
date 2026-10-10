# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the stature-scaled hand and its fingers: bones, joint
tissues, muscles and tendons, vessels, nerves, lymphatics, skin and
hair."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.arm.frame import (
    arm_dimensions,
    arm_muscle_dimensions,
)
from extensions.humanoid.skeleton.bone import bone_phong
from extensions.humanoid.skeleton.field import flip_x
from extensions.humanoid.skeleton.hand.assembly import add_hand
from extensions.humanoid.skeleton.hand.bones.dimensions import (
    CAPITATE,
    DISTAL_PHALANX_1,
    DISTAL_PHALANX_5,
    HAMATE,
    INDEX,
    LITTLE,
    LUNATE,
    METACARPAL_1,
    METACARPAL_3,
    MIDDLE,
    MIDDLE_PHALANX_2,
    PISIFORM,
    PROXIMAL_PHALANX_1,
    RING,
    SCAPHOID,
    THUMB,
    TRAPEZIUM,
    Finger,
    HandBone,
    bone_finger,
    finger_bones,
    finger_joints,
    finger_label,
    finger_scale,
    hand_bone_distance,
    hand_bone_field,
    hand_bone_label,
    named_fingers,
    named_hand_bones,
)
from extensions.humanoid.skeleton.hand.bones.geometry import (
    hand_bone,
    hand_bone_from_dimensions,
)
from extensions.humanoid.skeleton.hand.bones.mass import (
    hand_bone_mass,
    hand_bone_mass_from_dimensions,
    hand_bone_occupancy,
)
from extensions.humanoid.skeleton.hand.contents import (
    ALL,
    BONES,
    BOTH,
    HAIR,
    LIGAMENTS,
    LYMPH,
    MUSCLES,
    NERVES,
    SKIN,
    VESSELS,
    HandContents,
)
from extensions.humanoid.skeleton.hand.hair.dimensions import (
    FINGER_HAIR,
    HAND_HAIR,
    HandHair,
    hand_hair_distance,
    hand_hair_field,
    hand_hair_label,
    named_hand_hair,
)
from extensions.humanoid.skeleton.hand.hair.geometry import (
    hand_hair_from_dimensions,
    hand_hair_mesh,
)
from extensions.humanoid.skeleton.hand.hair.mass import (
    hand_hair_mass,
    hand_hair_mass_from_dimensions,
)
from extensions.humanoid.skeleton.hand.ligaments.dimensions import (
    COLLATERAL_LIGAMENTS,
    FLEXOR_RETINACULUM,
    JOINT_CARTILAGE,
    PALMAR_APONEUROSIS,
    TRIANGULAR_FIBROCARTILAGE,
    VOLAR_PLATES,
    HandLigament,
    hand_ligament_distance,
    hand_ligament_field,
    hand_ligament_label,
    hand_ligament_tissue,
    named_hand_ligaments,
    palmar_direction,
)
from extensions.humanoid.skeleton.hand.ligaments.geometry import (
    hand_ligament,
    hand_ligament_from_dimensions,
)
from extensions.humanoid.skeleton.hand.ligaments.mass import (
    hand_ligament_mass,
    hand_ligament_mass_from_dimensions,
    hand_ligament_occupancy,
)
from extensions.humanoid.skeleton.hand.lymph.dimensions import (
    DORSAL_LYMPHATICS,
    PALMAR_PLEXUS,
    HandLymph,
    hand_lymph_distance,
    hand_lymph_field,
    hand_lymph_label,
    named_hand_lymph,
)
from extensions.humanoid.skeleton.hand.lymph.geometry import (
    hand_lymph,
    hand_lymph_from_dimensions,
)
from extensions.humanoid.skeleton.hand.lymph.mass import (
    hand_lymph_mass,
    hand_lymph_mass_from_dimensions,
    hand_lymph_occupancy,
)
from extensions.humanoid.skeleton.hand.muscles.dimensions import (
    ADDUCTOR_POLLICIS,
    DORSAL_INTEROSSEI,
    EXTENSOR_TENDONS,
    FLEXOR_TENDONS,
    LUMBRICALS,
    HandMuscle,
    hand_muscle_distance,
    hand_muscle_field,
    hand_muscle_label,
    is_hand_tendon,
    joints_x,
    named_hand_muscles,
)
from extensions.humanoid.skeleton.hand.muscles.geometry import (
    hand_muscle,
    hand_muscle_from_dimensions,
)
from extensions.humanoid.skeleton.hand.muscles.mass import (
    hand_muscle_mass,
    hand_muscle_mass_from_dimensions,
    hand_muscle_occupancy,
    hand_muscle_tissue,
)
from extensions.humanoid.skeleton.hand.nerves.dimensions import (
    DIGITAL_NERVES,
    MEDIAN_BRANCHES,
    HandNerve,
    hand_nerve_distance,
    hand_nerve_field,
    hand_nerve_label,
    named_hand_nerves,
)
from extensions.humanoid.skeleton.hand.nerves.geometry import (
    hand_nerve,
    hand_nerve_from_dimensions,
)
from extensions.humanoid.skeleton.hand.nerves.mass import (
    hand_nerve_mass,
    hand_nerve_mass_from_dimensions,
    hand_nerve_occupancy,
)
from extensions.humanoid.skeleton.hand.skin.dimensions import (
    HandSkinField,
    HandSkinLayerField,
)
from extensions.humanoid.skeleton.hand.skin.geometry import (
    hand_skin_from_dimensions,
    hand_skin_mesh,
)
from extensions.humanoid.skeleton.hand.skin.mass import (
    hand_skin_mass,
    hand_skin_mass_from_dimensions,
    hand_skin_occupancy,
)
from extensions.humanoid.skeleton.hand.vessels.dimensions import (
    DEEP_PALMAR_ARCH,
    DIGITAL_ARTERIES,
    DORSAL_DIGITAL_VEINS,
    DORSAL_VENOUS_NETWORK,
    SUPERFICIAL_PALMAR_ARCH,
    HandVessel,
    hand_vessel_distance,
    hand_vessel_field,
    hand_vessel_label,
    is_hand_artery,
    named_hand_vessels,
)
from extensions.humanoid.skeleton.hand.vessels.geometry import (
    hand_vessel,
    hand_vessel_from_dimensions,
)
from extensions.humanoid.skeleton.hand.vessels.mass import (
    hand_vessel_mass,
    hand_vessel_mass_from_dimensions,
    hand_vessel_occupancy,
)
from extensions.humanoid.skeleton.look import (
    artery_phong,
    cartilage_phong,
    hair_phong,
    ligament_phong,
    lymph_phong,
    muscle_phong,
    nerve_phong,
    skin_phong,
    tendon_phong,
    vein_phong,
)
from extensions.humanoid.skeleton.occupancy import TRABECULAR_FILL
from extensions.anatomy.soft_tissue import (
    CARTILAGE,
    LIGAMENT,
    MENISCUS,
    MUSCLE,
    TENDON,
    arterial_tissue,
    hair_tissue,
    lymph_tissue,
    nerve_tissue,
    skin_tissue,
    tendon_tissue,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SOFT_EMPTY,
    SOFT_FILL,
)
from extensions.anatomy.tissue import (
    cortical_tissue,
    trabecular_tissue,
)
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length, MILLIMETER

comptime TOLERANCE = 1.0e-5
comptime COARSE = Length(4.0, MILLIMETER)


def _person() -> HumanoidSpec:
    """Return the six-foot toned male the suite measures."""
    return HumanoidSpec(Length(6.0, FOOT), MALE, TONED)


def test_digits_are_chains_of_joints() raises:
    var dims = arm_dimensions(Length(6.0, FOOT), MALE)
    var f = dims.frame
    var digits = named_fingers()
    assert_equal(len(digits), 5)
    assert_equal(finger_label(THUMB), "thumb")
    assert_equal(finger_label(INDEX), "index finger")
    assert_equal(finger_label(MIDDLE), "middle finger")
    assert_equal(finger_label(RING), "ring finger")
    assert_equal(finger_label(LITTLE), "little finger")
    assert_equal(finger_label(Finger(5)), "finger")
    assert_false(Finger(-1).is_valid())
    # The thumb has two phalanges, a finger three.
    assert_equal(len(finger_bones(THUMB)), 3)
    assert_equal(len(finger_bones(INDEX)), 4)
    assert_equal(len(finger_joints(dims, THUMB)), 4)
    assert_equal(len(finger_joints(dims, MIDDLE)), 5)
    # The middle finger reaches farthest, about twenty centimeters below
    # the wrist; the thumb stands forward of the palm.
    var middle = finger_joints(dims, MIDDLE)
    var reach = f.wrist.y - middle[len(middle) - 1].y
    assert_true(reach > 0.17 and reach < 0.23)
    var little = finger_joints(dims, LITTLE)
    assert_true(little[len(little) - 1].y > middle[len(middle) - 1].y)
    var thumb = finger_joints(dims, THUMB)
    assert_true(thumb[len(thumb) - 1].z > f.wrist.z + 0.02)
    assert_true(finger_scale(THUMB) > finger_scale(LITTLE))
    with assert_raises(contains="thumb or a named finger"):
        _ = finger_bones(Finger(5))
    with assert_raises(contains="thumb or a named finger"):
        _ = finger_joints(dims, Finger(5))
    with assert_raises(contains="thumb or a named finger"):
        _ = finger_scale(Finger(5))


def test_bones_are_named_and_solid() raises:
    var dims = arm_dimensions(Length(6.0, FOOT), MALE)
    var bones = named_hand_bones()
    assert_equal(len(bones), 27)
    assert_equal(hand_bone_label(SCAPHOID), "scaphoid")
    assert_equal(hand_bone_label(HAMATE), "hamate")
    assert_equal(hand_bone_label(METACARPAL_3), "metacarpal 3")
    assert_equal(hand_bone_label(PROXIMAL_PHALANX_1), "proximal phalanx 1")
    assert_equal(hand_bone_label(MIDDLE_PHALANX_2), "middle phalanx 2")
    assert_equal(hand_bone_label(DISTAL_PHALANX_5), "distal phalanx 5")
    assert_equal(hand_bone_label(HandBone(27)), "hand bone")
    assert_false(HandBone(-1).is_valid())
    for index in range(len(bones)):
        var right = hand_bone_field(dims, bones[index], RIGHT)
        var left = hand_bone_field(dims, bones[index], LEFT)
        assert_true(right.high.x > 0 and left.low.x < 0)
    # Each digit's bones belong to it.
    assert_equal(bone_finger(METACARPAL_1), THUMB)
    assert_equal(bone_finger(MIDDLE_PHALANX_2), INDEX)
    assert_equal(bone_finger(DISTAL_PHALANX_5), LITTLE)
    assert_equal(bone_finger(PROXIMAL_PHALANX_1), THUMB)
    with assert_raises(contains="belongs to a finger"):
        _ = bone_finger(LUNATE)
    with assert_raises(contains="belongs to a finger"):
        _ = bone_finger(HandBone(40))
    # A long bone lies between two joints of its chain, and stops short
    # of both.
    var chain = finger_joints(dims, MIDDLE)
    var middle = (chain[1] + chain[2]) * Float32(0.5)
    var proximal = finger_bones(MIDDLE)[1]
    assert_true(hand_bone_distance(dims, proximal, RIGHT, middle) < 0)
    assert_true(hand_bone_distance(dims, proximal, RIGHT, chain[1]) > 0)
    assert_true(hand_bone_distance(dims, proximal, LEFT, flip_x(middle)) < 0)
    # The pisiform sits in front of the triquetrum, the trapezium under
    # the thumb.
    var f = dims.frame
    assert_true(
        hand_bone_distance(dims, PISIFORM, RIGHT, f.hand(-1.5, -1.35, 0.9)) < 0
    )
    assert_true(
        hand_bone_distance(dims, TRAPEZIUM, RIGHT, f.hand(2.0, -2.7, 0.7)) < 0
    )
    with assert_raises(contains="named carpal"):
        _ = hand_bone_field(dims, HandBone(27), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = hand_bone_field(dims, CAPITATE, BodySide(4))
    var mesh = hand_bone(_person(), DISTAL_PHALANX_1, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    with assert_raises():
        _ = hand_bone_from_dimensions(dims, CAPITATE, RIGHT, 7)


def test_bone_mass() raises:
    var person = _person()
    var metacarpal = hand_bone_mass(person, METACARPAL_3, COARSE)
    assert_true(metacarpal.mass.value > 0.002 and metacarpal.mass.value < 0.03)
    var dims = arm_dimensions(person.stature, MALE)
    var capitate = hand_bone_mass_from_dimensions(
        dims, CAPITATE, cortical_tissue(), trabecular_tissue(), COARSE
    )
    assert_true(capitate.mass.value > 0.001 and capitate.mass.value < 0.03)
    var center = dims.frame.hand(0.0, -2.75, 0.25)
    assert_equal(
        hand_bone_occupancy(dims, CAPITATE, RIGHT, center), TRABECULAR_FILL
    )
    with assert_raises():
        _ = hand_bone_mass(person, CAPITATE, Length(1.0, MILLIMETER))


def test_muscles_and_tendons() raises:
    var dims = arm_muscle_dimensions(_person())
    var parts = named_hand_muscles()
    assert_equal(len(parts), 14)
    var tendons = 0
    for index in range(len(parts)):
        var part = parts[index]
        if is_hand_tendon(part):
            tendons += 1
            assert_equal(hand_muscle_tissue(part).kind, TENDON)
        else:
            assert_equal(hand_muscle_tissue(part).kind, MUSCLE)
        assert_true(hand_muscle_label(part) != "hand muscle")
        var right = hand_muscle_field(dims, part, RIGHT)
        var left = hand_muscle_field(dims, part, LEFT)
        assert_true(right.high.x > 0 and left.low.x < 0)
        assert_true(
            hand_muscle_mass_from_dimensions(
                dims, part, hand_muscle_tissue(part)
            ).mass.value
            > 0
        )
    assert_equal(tendons, 4)
    # The flexor tendons run in front of each finger's bones, the
    # extensor tendons behind them.
    var f = dims.arm.frame
    var flexors = hand_muscle_field(dims, FLEXOR_TENDONS, RIGHT)
    var extensors = hand_muscle_field(dims, EXTENSOR_TENDONS, RIGHT)
    assert_equal(len(flexors.sweeps), 4)
    var palm = f.hand_direction(0, 0, 1)
    var front = flexors.sweeps[0].stations[2].p
    var back = extensors.sweeps[0].stations[2].p
    assert_true((front - back).dot(palm) > 0.01)
    assert_equal(len(hand_muscle_field(dims, LUMBRICALS, RIGHT).sweeps), 4)
    var first = hand_muscle_field(dims, DORSAL_INTEROSSEI, RIGHT)
    var belly = first.sweeps[0].stations[1].p
    assert_true(hand_muscle_distance(dims, DORSAL_INTEROSSEI, RIGHT, belly) < 0)
    assert_equal(
        hand_muscle_occupancy(dims, DORSAL_INTEROSSEI, RIGHT, belly), SOFT_FILL
    )
    assert_equal(joints_x(THUMB), 2.5)
    assert_equal(joints_x(Finger(4)), -2.1)
    assert_equal(hand_muscle_label(HandMuscle(14)), "hand muscle")
    assert_false(HandMuscle(-1).is_valid())
    with assert_raises(contains="named muscle or tendon group"):
        _ = is_hand_tendon(HandMuscle(14))
    with assert_raises(contains="RIGHT or LEFT"):
        _ = hand_muscle_field(dims, ADDUCTOR_POLLICIS, BodySide(3))
    var mesh = hand_muscle(_person(), ADDUCTOR_POLLICIS, LEFT, 8)
    var tendon = hand_muscle_from_dimensions(dims, FLEXOR_TENDONS, RIGHT, 8)
    assert_true(mesh.triangle_count() > 0 and tendon.triangle_count() > 0)
    assert_true(hand_muscle_mass(_person(), FLEXOR_TENDONS).mass.value > 0)
    assert_true(hand_muscle_mass(_person(), ADDUCTOR_POLLICIS).mass.value > 0)


def test_ligaments() raises:
    var dims = arm_dimensions(Length(6.0, FOOT), MALE)
    var parts = named_hand_ligaments()
    assert_equal(len(parts), 7)
    for index in range(len(parts)):
        var part = parts[index]
        assert_true(hand_ligament_label(part) != "hand ligament")
        var field = hand_ligament_field(dims, part, LEFT)
        assert_true(field.volume() > 0 and field.high.x < 0)
        assert_true(
            hand_ligament_mass_from_dimensions(
                dims, part, hand_ligament_tissue(part)
            ).mass.value
            > 0
        )
    assert_equal(hand_ligament_tissue(TRIANGULAR_FIBROCARTILAGE).kind, MENISCUS)
    assert_equal(hand_ligament_tissue(JOINT_CARTILAGE).kind, CARTILAGE)
    assert_equal(hand_ligament_tissue(FLEXOR_RETINACULUM).kind, LIGAMENT)
    assert_equal(hand_ligament_label(HandLigament(7)), "hand ligament")
    assert_false(HandLigament(-1).is_valid())
    with assert_raises(contains="named part"):
        _ = hand_ligament_tissue(HandLigament(7))
    with assert_raises(contains="RIGHT or LEFT"):
        _ = hand_ligament_field(dims, VOLAR_PLATES, BodySide(3))
    # Two collateral ligaments at each of the fourteen joints, and a
    # volar plate in front of each.
    assert_equal(
        len(hand_ligament_field(dims, COLLATERAL_LIGAMENTS, RIGHT).sweeps), 28
    )
    assert_equal(len(hand_ligament_field(dims, VOLAR_PLATES, RIGHT).sweeps), 14)
    assert_equal(
        len(hand_ligament_field(dims, PALMAR_APONEUROSIS, RIGHT).sweeps), 4
    )
    # The thumb's front turns toward the fingers.
    assert_true(palmar_direction(dims, THUMB).x < 0)
    assert_true(palmar_direction(dims, INDEX).z > 0.9)
    var f = dims.frame
    var tunnel = f.hand(0.2, -2.4, 1.95)
    assert_true(
        hand_ligament_distance(dims, FLEXOR_RETINACULUM, RIGHT, tunnel) < 0
    )
    assert_equal(
        hand_ligament_occupancy(dims, FLEXOR_RETINACULUM, RIGHT, tunnel),
        SOFT_FILL,
    )
    var mesh = hand_ligament(_person(), PALMAR_APONEUROSIS, RIGHT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(hand_ligament_mass(_person(), JOINT_CARTILAGE).mass.value > 0)
    with assert_raises():
        _ = hand_ligament_from_dimensions(dims, VOLAR_PLATES, RIGHT, 7)


def test_vessels() raises:
    var dims = arm_muscle_dimensions(_person())
    var parts = named_hand_vessels()
    assert_equal(len(parts), 5)
    var arteries = 0
    for index in range(len(parts)):
        var part = parts[index]
        if is_hand_artery(part):
            arteries += 1
        assert_true(hand_vessel_label(part) != "hand vessel")
        var field = hand_vessel_field(dims, part, RIGHT)
        assert_true(field.distance(field.sweeps[0].stations[1].p) < 0)
        assert_true(
            hand_vessel_mass_from_dimensions(
                dims, part, arterial_tissue()
            ).mass.value
            > 0
        )
    assert_equal(arteries, 3)
    # Two digital arteries run along each digit; one dorsal vein does.
    assert_equal(
        len(hand_vessel_field(dims, DIGITAL_ARTERIES, LEFT).sweeps), 10
    )
    assert_equal(
        len(hand_vessel_field(dims, DORSAL_DIGITAL_VEINS, LEFT).sweeps), 5
    )
    var arch = hand_vessel_field(dims, DEEP_PALMAR_ARCH, RIGHT)
    var start = arch.sweeps[0].stations[0].p
    assert_true(hand_vessel_distance(dims, DEEP_PALMAR_ARCH, RIGHT, start) < 0)
    assert_equal(
        hand_vessel_occupancy(dims, DEEP_PALMAR_ARCH, RIGHT, start), SOFT_FILL
    )
    assert_equal(hand_vessel_label(HandVessel(5)), "hand vessel")
    assert_false(HandVessel(-1).is_valid())
    with assert_raises(contains="artery or vein"):
        _ = is_hand_artery(HandVessel(5))
    with assert_raises(contains="RIGHT or LEFT"):
        _ = hand_vessel_field(dims, SUPERFICIAL_PALMAR_ARCH, BodySide(3))
    var mesh = hand_vessel(_person(), DORSAL_VENOUS_NETWORK, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(
        hand_vessel_mass(_person(), SUPERFICIAL_PALMAR_ARCH).mass.value > 0
    )
    assert_true(
        hand_vessel_mass(_person(), DORSAL_VENOUS_NETWORK).mass.value > 0
    )


def test_nerves() raises:
    var dims = arm_muscle_dimensions(_person())
    var parts = named_hand_nerves()
    assert_equal(len(parts), 4)
    for index in range(len(parts)):
        var part = parts[index]
        assert_true(hand_nerve_label(part) != "hand nerve")
        var field = hand_nerve_field(dims, part, LEFT)
        assert_true(field.high.x < 0)
        assert_true(
            hand_nerve_mass_from_dimensions(
                dims, part, nerve_tissue()
            ).mass.value
            > 0
        )
    assert_equal(len(hand_nerve_field(dims, DIGITAL_NERVES, RIGHT).sweeps), 10)
    var branches = hand_nerve_field(dims, MEDIAN_BRANCHES, RIGHT)
    var root = branches.sweeps[1].stations[0].p
    assert_true(hand_nerve_distance(dims, MEDIAN_BRANCHES, RIGHT, root) < 0)
    assert_equal(
        hand_nerve_occupancy(dims, MEDIAN_BRANCHES, RIGHT, root), SOFT_FILL
    )
    assert_equal(hand_nerve_label(HandNerve(4)), "hand nerve")
    assert_false(HandNerve(-1).is_valid())
    with assert_raises(contains="named nerve"):
        _ = hand_nerve_field(dims, HandNerve(4), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = hand_nerve_field(dims, MEDIAN_BRANCHES, BodySide(3))
    var mesh = hand_nerve(_person(), DIGITAL_NERVES, RIGHT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(hand_nerve_mass(_person(), MEDIAN_BRANCHES).mass.value > 0)
    with assert_raises():
        _ = hand_nerve_from_dimensions(dims, MEDIAN_BRANCHES, RIGHT, 7)


def test_lymph() raises:
    var dims = arm_muscle_dimensions(_person())
    var parts = named_hand_lymph()
    assert_equal(len(parts), 2)
    for index in range(len(parts)):
        var part = parts[index]
        assert_true(hand_lymph_label(part) != "hand lymph")
        var field = hand_lymph_field(dims, part, LEFT)
        assert_true(field.high.x < 0)
        assert_true(
            hand_lymph_mass_from_dimensions(
                dims, part, lymph_tissue()
            ).mass.value
            > 0
        )
    var back = hand_lymph_field(dims, DORSAL_LYMPHATICS, RIGHT)
    assert_equal(len(back.sweeps), 5)
    var run = back.sweeps[0].stations[1].p
    assert_true(hand_lymph_distance(dims, DORSAL_LYMPHATICS, RIGHT, run) < 0)
    assert_equal(
        hand_lymph_occupancy(dims, DORSAL_LYMPHATICS, RIGHT, run), SOFT_FILL
    )
    assert_equal(hand_lymph_label(HandLymph(2)), "hand lymph")
    assert_false(HandLymph(-1).is_valid())
    with assert_raises(contains="named part"):
        _ = hand_lymph_field(dims, HandLymph(2), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = hand_lymph_field(dims, PALMAR_PLEXUS, BodySide(3))
    var mesh = hand_lymph(_person(), PALMAR_PLEXUS, RIGHT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(hand_lymph_mass(_person(), PALMAR_PLEXUS).mass.value > 0)
    with assert_raises():
        _ = hand_lymph_from_dimensions(dims, PALMAR_PLEXUS, RIGHT, 7)


def test_skin() raises:
    var dims = arm_muscle_dimensions(_person())
    var right = HandSkinField(dims, RIGHT)
    var left = HandSkinField(dims, LEFT)
    # The palm, a knuckle and a fingertip's bone are inside; the gap
    # between two fingertips is not.
    var arm = dims.arm.copy()
    var f = arm.frame
    assert_true(right.distance(f.hand(0.0, -6.0, 0.4)) < 0)
    var middle = finger_joints(arm, MIDDLE)
    var ring = finger_joints(arm, RING)
    assert_true(right.distance(middle[1]) < 0)
    assert_true(right.distance(middle[len(middle) - 2]) < 0)
    var between = (middle[3] + ring[3]) * Float32(0.5)
    assert_true(right.distance(between) > -0.004)
    assert_true(left.distance(flip_x(middle[1])) < 0)
    assert_true(left.low.x < 0 and left.high.x < 0)
    assert_true(
        right.gradient(f.hand(0.0, -6.0, 3.0)).dot(f.hand_direction(0, 0, 1))
        > 0.3
    )
    var layer = HandSkinLayerField(dims, RIGHT)
    assert_true(layer.distance(middle[1]) > 0)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = HandSkinField(dims, BodySide(3))
    var woman = HandSkinField(
        arm_muscle_dimensions(HumanoidSpec(Length(5.5, FOOT), FEMALE)), LEFT
    )
    assert_true(woman.high.x - woman.low.x < right.high.x - right.low.x)
    var mesh = hand_skin_mesh(_person(), LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    with assert_raises():
        _ = hand_skin_from_dimensions(dims, RIGHT, 7)
    var report = hand_skin_mass(_person(), COARSE)
    assert_true(report.mass.value > 0.01 and report.mass.value < 0.3)
    assert_true(
        hand_skin_mass_from_dimensions(dims, skin_tissue(), COARSE).mass.value
        > 0
    )
    assert_equal(hand_skin_occupancy(dims, RIGHT, middle[1]), SOFT_EMPTY)


def test_hair() raises:
    var dims = arm_muscle_dimensions(_person())
    var parts = named_hand_hair()
    assert_equal(len(parts), 2)
    var skin = HandSkinField(dims, RIGHT)
    for index in range(len(parts)):
        var part = parts[index]
        assert_true(hand_hair_label(part) != "hand hair group")
        var field = hand_hair_field(dims, part, RIGHT)
        var root = field.sweeps[0].stations[0].p
        assert_true(abs(skin.distance(root)) < 0.001)
        var tip = field.sweeps[0].stations[1].p
        assert_true(hand_hair_distance(dims, part, RIGHT, tip) < 0)
        assert_true(
            hand_hair_mass_from_dimensions(dims, part, hair_tissue()).mass.value
            > 0
        )
    assert_equal(len(hand_hair_field(dims, FINGER_HAIR, LEFT).sweeps), 4)
    assert_equal(hand_hair_label(HandHair(2)), "hand hair group")
    assert_false(HandHair(-1).is_valid())
    with assert_raises(contains="named hair group"):
        _ = hand_hair_field(dims, HandHair(2), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = hand_hair_field(dims, HAND_HAIR, BodySide(3))
    var right = hand_hair_mesh(_person(), HAND_HAIR, RIGHT, 8)
    var left = hand_hair_from_dimensions(dims, FINGER_HAIR, LEFT, 8)
    assert_true(right.triangle_count() > 0 and left.triangle_count() > 0)
    with assert_raises():
        _ = hand_hair_mesh(_person(), HAND_HAIR, RIGHT, 7)
    assert_true(hand_hair_mass(_person(), FINGER_HAIR).mass.value > 0)


def test_contents_bits() raises:
    assert_true(BONES.includes_bones())
    assert_true(LIGAMENTS.includes_ligaments())
    assert_true(MUSCLES.includes_muscles())
    assert_true(VESSELS.includes_vessels())
    assert_true(LYMPH.includes_lymph())
    assert_true(NERVES.includes_nerves())
    assert_true(SKIN.includes_skin())
    assert_true(HAIR.includes_hair())
    assert_equal(BONES.plus(LIGAMENTS).plus(MUSCLES).value, BOTH.value)
    assert_true(ALL.includes_hair())
    var bad = HandContents(0)
    assert_false(bad.is_valid())
    assert_false(HandContents(256).is_valid())
    with assert_raises(contains="named layer set"):
        _ = bad.includes_bones()
    with assert_raises(contains="named layer set"):
        _ = bad.includes_ligaments()
    with assert_raises(contains="named layer set"):
        _ = bad.includes_muscles()
    with assert_raises(contains="named layer set"):
        _ = bad.includes_vessels()
    with assert_raises(contains="named layer set"):
        _ = bad.includes_lymph()
    with assert_raises(contains="named layer set"):
        _ = bad.includes_nerves()
    with assert_raises(contains="named layer set"):
        _ = bad.includes_skin()
    with assert_raises(contains="named layer set"):
        _ = bad.includes_hair()
    with assert_raises(contains="named layer set"):
        _ = BONES.plus(bad)


def test_add_hand_places_every_layer() raises:
    var person = _person()
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var bone = assets.materials.add(bone_phong())
    var ligament = assets.materials.add(ligament_phong())
    var cartilage = assets.materials.add(cartilage_phong())
    var muscle = assets.materials.add(muscle_phong())
    _ = add_hand(
        scene,
        assets,
        root,
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        RIGHT,
        ALL,
        8,
        8,
    )
    # Twenty-seven bones, seven joint parts, fourteen muscles and tendon
    # groups, five vessels, two lymphatics, four nerves, one skin and
    # two hair groups.
    assert_equal(len(scene.meshes), 62)
    var painted = Scene()
    var painted_root = painted.add(Object3D())
    _ = add_hand(
        painted,
        assets,
        painted_root,
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        LEFT,
        MUSCLES.plus(VESSELS).plus(LYMPH).plus(NERVES).plus(SKIN).plus(HAIR),
        8,
        8,
        Vector3(0, 0, 0),
        assets.materials.add(tendon_phong()),
        assets.materials.add(artery_phong()),
        assets.materials.add(vein_phong()),
        assets.materials.add(lymph_phong()),
        assets.materials.add(nerve_phong()),
        assets.materials.add(skin_phong()),
        assets.materials.add(hair_phong()),
    )
    assert_equal(len(painted.meshes), 28)
    with assert_raises(contains="named layer set"):
        _ = add_hand(
            scene,
            assets,
            root,
            person,
            bone,
            ligament,
            cartilage,
            muscle,
            RIGHT,
            HandContents(0),
        )
    with assert_raises(contains="RIGHT or LEFT"):
        _ = add_hand(
            scene,
            assets,
            root,
            person,
            bone,
            ligament,
            cartilage,
            muscle,
            BodySide(3),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
