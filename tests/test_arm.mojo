# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the stature-scaled arm: its frame, bones, joint tissues,
muscles, vessels, nerves, lymphatics, skin and hair."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import TONED, Athleticism
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.arm.assembly import (
    UNSET_PAINT,
    add_arm,
    resolved_paint,
)
from extensions.humanoid.skeleton.arm.bones.dimensions import (
    HUMERUS,
    RADIUS,
    ULNA,
    ArmBone,
    arm_bone_distance,
    arm_bone_field,
    arm_bone_label,
    humeral_head,
    named_arm_bones,
)
from extensions.humanoid.skeleton.arm.bones.geometry import (
    arm_bone,
    arm_bone_from_dimensions,
)
from extensions.humanoid.skeleton.arm.bones.mass import (
    arm_bone_mass,
    arm_bone_mass_from_dimensions,
    arm_bone_occupancy,
    fill_at,
)
from extensions.humanoid.skeleton.arm.contents import (
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
    ArmContents,
)
from extensions.humanoid.skeleton.arm.frame import (
    ArmMuscleDimensions,
    arm_dimensions,
    arm_frame,
    arm_muscle_dimensions,
    turn,
)
from extensions.humanoid.skeleton.arm.hair.dimensions import (
    FOREARM_HAIR,
    UPPER_ARM_HAIR,
    ArmHair,
    arm_hair_distance,
    arm_hair_field,
    arm_hair_label,
    named_arm_hair,
    shaft,
    surface_root,
)
from extensions.humanoid.skeleton.arm.hair.geometry import (
    arm_hair_from_dimensions,
    arm_hair_mesh,
)
from extensions.humanoid.skeleton.arm.hair.mass import (
    arm_hair_mass,
    arm_hair_mass_from_dimensions,
)
from extensions.humanoid.skeleton.arm.ligaments.dimensions import (
    ANNULAR_LIGAMENT,
    ARTICULAR_CARTILAGE,
    GLENOID_LABRUM,
    INTEROSSEOUS_MEMBRANE,
    ArmLigament,
    arm_ligament_distance,
    arm_ligament_field,
    arm_ligament_label,
    arm_ligament_tissue,
    joint_pad,
    named_arm_ligaments,
)
from extensions.humanoid.skeleton.arm.ligaments.geometry import (
    arm_ligament,
    arm_ligament_from_dimensions,
)
from extensions.humanoid.skeleton.arm.ligaments.mass import (
    arm_ligament_mass,
    arm_ligament_mass_from_dimensions,
    arm_ligament_occupancy,
)
from extensions.humanoid.skeleton.arm.limb import add_upper_limb
from extensions.humanoid.skeleton.arm.lymph.dimensions import (
    CUBITAL_NODES,
    ArmLymph,
    arm_lymph_distance,
    arm_lymph_field,
    arm_lymph_label,
    arm_lymph_paths,
    named_arm_lymph,
)
from extensions.humanoid.skeleton.arm.lymph.geometry import (
    arm_lymph,
    arm_lymph_from_dimensions,
)
from extensions.humanoid.skeleton.arm.lymph.mass import (
    arm_lymph_mass,
    arm_lymph_mass_from_dimensions,
    arm_lymph_occupancy,
)
from extensions.humanoid.skeleton.arm.muscles.dimensions import (
    BICEPS_BRACHII,
    DELTOID,
    ON_FORE,
    ON_HAND,
    ON_TORSO,
    ON_UPPER,
    SUBSCAPULARIS,
    TRICEPS_BRACHII,
    ArmMuscle,
    arm_muscle_distance,
    arm_muscle_field,
    arm_muscle_label,
    arm_muscle_paths,
    named_arm_muscles,
    paths_field,
    station_point,
)
from extensions.humanoid.skeleton.arm.muscles.geometry import (
    arm_muscle,
    arm_muscle_from_dimensions,
)
from extensions.humanoid.skeleton.arm.muscles.mass import (
    arm_muscle_mass,
    arm_muscle_mass_from_dimensions,
    arm_muscle_occupancy,
)
from extensions.humanoid.skeleton.arm.nerves.dimensions import (
    MEDIAN_NERVE,
    ULNAR_NERVE,
    ArmNerve,
    arm_nerve_distance,
    arm_nerve_field,
    arm_nerve_label,
    arm_nerve_paths,
    named_arm_nerves,
)
from extensions.humanoid.skeleton.arm.nerves.geometry import (
    arm_nerve,
    arm_nerve_from_dimensions,
)
from extensions.humanoid.skeleton.arm.nerves.mass import (
    arm_nerve_mass,
    arm_nerve_mass_from_dimensions,
    arm_nerve_occupancy,
)
from extensions.humanoid.skeleton.arm.skin.dimensions import (
    ArmSkinField,
    ArmSkinLayerField,
    append_stations,
    arm_fat,
    lies_on_scapula,
)
from extensions.humanoid.skeleton.arm.skin.geometry import (
    arm_skin_from_dimensions,
    arm_skin_mesh,
)
from extensions.humanoid.skeleton.arm.skin.mass import (
    arm_skin_mass,
    arm_skin_mass_from_dimensions,
    arm_skin_occupancy,
)
from extensions.humanoid.skeleton.arm.vessels.dimensions import (
    AXILLARY_ARTERY,
    BRACHIAL_ARTERY,
    CEPHALIC_VEIN,
    ArmVessel,
    arm_vessel_distance,
    arm_vessel_field,
    arm_vessel_label,
    arm_vessel_paths,
    is_arm_artery,
    named_arm_vessels,
)
from extensions.humanoid.skeleton.arm.vessels.geometry import (
    arm_vessel,
    arm_vessel_from_dimensions,
)
from extensions.humanoid.skeleton.arm.vessels.mass import (
    arm_vessel_mass,
    arm_vessel_mass_from_dimensions,
    arm_vessel_occupancy,
)
from extensions.humanoid.skeleton.bone import bone_phong
from extensions.humanoid.skeleton.field import flip_x
from extensions.humanoid.skeleton.loft import LoftSample
from extensions.humanoid.skeleton.look import (
    artery_phong,
    cartilage_phong,
    hair_phong,
    ligament_phong,
    lymph_phong,
    muscle_phong,
    nerve_phong,
    skin_phong,
    vein_phong,
)
from extensions.humanoid.skeleton.occupancy import (
    CORTICAL_FILL,
    EMPTY,
    TRABECULAR_FILL,
)
from extensions.anatomy.soft_tissue import (
    CARTILAGE,
    LIGAMENT,
    MENISCUS,
    arterial_tissue,
    hair_tissue,
    ligament_tissue,
    lymph_tissue,
    muscle_tissue,
    nerve_tissue,
    skin_tissue,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SOFT_EMPTY,
    SOFT_FILL,
)
from extensions.anatomy.tissue import (
    cortical_tissue,
    trabecular_tissue,
)
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    shoulder_girdle,
    upper_arm_point,
)
from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    torso_muscle_dimensions,
)
from extensions.humanoid.skeleton.torso.nerves.dimensions import (
    BRACHIAL_PLEXUS,
    torso_nerve_field,
)
from extensions.humanoid.skeleton.torso.sweep import Sweep, SweepField, floats
from extensions.humanoid.skeleton.torso.vessels.dimensions import (
    SUBCLAVIAN_ARTERY,
    torso_vessel_field,
)
from materials.material import MaterialId
from math.vector3 import Vector3
from std.math import inf, nan, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length, METER, MILLIMETER

comptime TOLERANCE = 1.0e-5
comptime COARSE = Length(10.0, MILLIMETER)


def _person() -> HumanoidSpec:
    """Return the six-foot toned male the suite measures."""
    return HumanoidSpec(Length(6.0, FOOT), MALE, TONED)


def test_the_arm_hangs_from_the_scapula() raises:
    var dims = arm_dimensions(Length(6.0, FOOT), MALE)
    dims.validate()
    var f = dims.frame
    var girdle = shoulder_girdle(dims.torso)
    # The shoulder is the humeral head, under the acromion.
    assert_almost_equal(f.shoulder.x, girdle.shoulder.x, atol=TOLERANCE)
    assert_almost_equal(humeral_head(dims).y, girdle.shoulder.y, atol=TOLERANCE)
    # The elbow and the wrist hang below it, each a little farther out.
    assert_true(f.elbow.y < f.shoulder.y - 0.28)
    assert_true(f.wrist.y < f.elbow.y - 0.24)
    assert_true(f.elbow.x > f.shoulder.x and f.wrist.x > f.elbow.x)
    # The upper arm is the torso's own; the forearm turns out more.
    var up = f.upper(0, -10, 0)
    var torso_up = upper_arm_point(dims.torso, 0, -10, 0)
    assert_almost_equal(up.x, torso_up.x, atol=TOLERANCE)
    assert_true(f.fore_angle > f.upper_angle)
    assert_almost_equal(f.hand(0, 0, 0).y, f.wrist.y, atol=TOLERANCE)
    var palm = f.hand_direction(0, 0, 2)
    assert_almost_equal(palm.length(), 1, atol=TOLERANCE)
    # A hundred template centimeters is a meter on the six-foot template.
    assert_almost_equal(f.cm(100), 1.0, atol=0.001)
    var same = turn(0, 1, 2, 3)
    assert_almost_equal(same.x, 1, atol=TOLERANCE)
    var quarter = turn(Float32(pi / 2), 0, -1, 0)
    assert_almost_equal(quarter.x, 1, atol=TOLERANCE)
    # A woman's forearm carries out farther.
    var woman = arm_dimensions(Length(6.0, FOOT), FEMALE)
    assert_true(woman.frame.fore_angle > f.fore_angle)
    assert_almost_equal(
        arm_frame(dims.torso).elbow.y, f.elbow.y, atol=TOLERANCE
    )


def test_arm_refuses_bad_input() raises:
    with assert_raises():
        _ = arm_dimensions(Length(0.5, METER), MALE)
    var dims = arm_dimensions(Length(6.0, FOOT), MALE)
    var lost = dims.copy()
    lost.frame.elbow = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises(contains="elbow"):
        lost.validate()
    var short = dims.copy()
    _ = short.torso.centers.pop()
    with assert_raises(contains="seventeen"):
        short.validate()
    with assert_raises(contains="athleticism"):
        _ = arm_muscle_dimensions(
            HumanoidSpec(Length(6.0, FOOT), MALE, Athleticism(4))
        )
    with assert_raises():
        _ = ArmMuscleDimensions(dims.copy(), Athleticism(9))
    var muscles = arm_muscle_dimensions(_person())
    var edited = muscles.copy()
    edited.scale = 0
    with assert_raises(contains="scale"):
        edited.validate()
    edited = muscles.copy()
    edited.athleticism = Athleticism(5)
    with assert_raises(contains="athleticism"):
        edited.validate()


def test_bones_are_named_and_solid() raises:
    var dims = arm_dimensions(Length(6.0, FOOT), MALE)
    var f = dims.frame
    var bones = named_arm_bones()
    assert_equal(len(bones), 3)
    assert_equal(arm_bone_label(HUMERUS), "humerus")
    assert_equal(arm_bone_label(RADIUS), "radius")
    assert_equal(arm_bone_label(ULNA), "ulna")
    assert_equal(arm_bone_label(ArmBone(3)), "arm bone")
    assert_false(ArmBone(-1).is_valid())
    for index in range(len(bones)):
        var right = arm_bone_field(dims, bones[index], RIGHT)
        var left = arm_bone_field(dims, bones[index], LEFT)
        assert_true(right.high.x > 0 and left.low.x < 0)
        assert_true(right.high.y > right.low.y)
    # The humerus holds the shoulder's ball and the elbow's axis; the
    # radius and the ulna run below it, the radius on the thumb side.
    assert_true(arm_bone_distance(dims, HUMERUS, RIGHT, f.shoulder) < 0)
    assert_true(arm_bone_distance(dims, HUMERUS, RIGHT, f.elbow) < 0)
    assert_true(
        arm_bone_distance(dims, HUMERUS, LEFT, flip_x(f.upper(1.0, -10, 0.1)))
        < 0
    )
    assert_true(
        arm_bone_distance(dims, RADIUS, RIGHT, f.fore(2.2, -14, 0.3)) < 0
    )
    assert_true(
        arm_bone_distance(dims, ULNA, RIGHT, f.fore(-1.2, -14, -0.2)) < 0
    )
    assert_true(
        arm_bone_distance(dims, RADIUS, RIGHT, f.fore(-1.2, -14, -0.2)) > 0
    )
    with assert_raises(contains="humerus"):
        _ = arm_bone_field(dims, ArmBone(3), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = arm_bone_field(dims, HUMERUS, BodySide(4))
    var mesh = arm_bone(_person(), RADIUS, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    with assert_raises():
        _ = arm_bone_from_dimensions(dims, ULNA, RIGHT, 7)


def test_bone_mass() raises:
    var person = _person()
    var humerus = arm_bone_mass(person, HUMERUS, COARSE)
    assert_true(humerus.mass.value > 0.08 and humerus.mass.value < 0.6)
    var dims = arm_dimensions(person.stature, MALE)
    var ulna = arm_bone_mass_from_dimensions(
        dims, ULNA, cortical_tissue(), trabecular_tissue(), COARSE
    )
    assert_true(ulna.mass.value > 0.02 and ulna.mass.value < 0.3)
    assert_equal(
        arm_bone_occupancy(dims, HUMERUS, RIGHT, dims.frame.shoulder),
        TRABECULAR_FILL,
    )
    assert_equal(fill_at(0.01, 0.001), EMPTY)
    assert_equal(fill_at(-0.0005, 0.001), CORTICAL_FILL)
    assert_equal(fill_at(-0.01, 0.001), TRABECULAR_FILL)
    with assert_raises():
        _ = arm_bone_mass(person, HUMERUS, Length(1.0, MILLIMETER))


def test_muscles() raises:
    var dims = arm_muscle_dimensions(_person())
    var parts = named_arm_muscles()
    assert_equal(len(parts), 30)
    var total = Float32(0)
    for index in range(len(parts)):
        var part = parts[index]
        assert_true(arm_muscle_label(part) != "arm muscle")
        var right = arm_muscle_field(dims, part, RIGHT)
        var left = arm_muscle_field(dims, part, LEFT)
        assert_true(right.high.x > 0 and left.low.x < 0)
        var report = arm_muscle_mass_from_dimensions(
            dims, part, muscle_tissue()
        )
        assert_true(report.mass.value > 0.002 and report.mass.value < 0.5)
        total += report.mass.value
    # An arm's muscles weigh a couple of kilograms.
    assert_true(total > 1.2 and total < 3.5)
    assert_equal(arm_muscle_label(ArmMuscle(30)), "arm muscle")
    assert_false(ArmMuscle(-1).is_valid())
    with assert_raises(contains="named muscle"):
        _ = arm_muscle_paths(ArmMuscle(30))
    with assert_raises(contains="RIGHT or LEFT"):
        _ = arm_muscle_field(dims, DELTOID, BodySide(3))
    # The deltoid caps the shoulder; the biceps lies in front of the
    # humerus and the triceps behind it.
    var f = dims.arm.frame
    assert_true(
        arm_muscle_distance(dims, DELTOID, RIGHT, f.upper(4.3, -0.8, 0.2)) < 0
    )
    assert_true(
        arm_muscle_distance(dims, BICEPS_BRACHII, RIGHT, f.upper(0.4, -20, 4.3))
        < 0
    )
    assert_true(
        arm_muscle_distance(
            dims, TRICEPS_BRACHII, LEFT, flip_x(f.upper(0.3, -18, -3.4))
        )
        < 0
    )
    assert_equal(
        arm_muscle_occupancy(
            dims, BICEPS_BRACHII, RIGHT, f.upper(0.4, -20, 4.3)
        ),
        SOFT_FILL,
    )
    # A toned arm's bellies are thicker than an untoned one's.
    var untoned = arm_muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    assert_true(
        arm_muscle_field(untoned, BICEPS_BRACHII, RIGHT).volume()
        < arm_muscle_field(dims, BICEPS_BRACHII, RIGHT).volume()
    )
    # Each frame places a station its own way.
    assert_almost_equal(
        station_point(dims.arm, ON_TORSO, 1, 2, 3).y,
        dims.arm.torso.frame.at(1, 2, 3).y,
        atol=TOLERANCE,
    )
    assert_almost_equal(
        station_point(dims.arm, ON_UPPER, 0, 0, 0).y,
        f.shoulder.y,
        atol=TOLERANCE,
    )
    assert_almost_equal(
        station_point(dims.arm, ON_FORE, 0, 0, 0).y, f.elbow.y, atol=TOLERANCE
    )
    assert_almost_equal(
        station_point(dims.arm, ON_HAND, 0, 0, 0).y, f.wrist.y, atol=TOLERANCE
    )
    var paths = List[List[Float32]]()
    paths.append(floats(1, 0, 0, 1, 0, 0, 0, 1, 1, 1, 1, 0, -5, 0, 1, 1, 0))
    var field = paths_field(dims.arm, paths, 2, LEFT, 0.2)
    assert_true(field.mirror)
    assert_true(field.sweeps[0].stations[0].ml > field.sweeps[0].stations[1].ml)
    var mesh = arm_muscle(_person(), BICEPS_BRACHII, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(arm_muscle_mass(_person(), SUBSCAPULARIS).mass.value > 0)
    with assert_raises():
        _ = arm_muscle_from_dimensions(dims, DELTOID, RIGHT, 70)


def test_ligaments() raises:
    var dims = arm_dimensions(Length(6.0, FOOT), MALE)
    var parts = named_arm_ligaments()
    assert_equal(len(parts), 8)
    for index in range(len(parts)):
        var part = parts[index]
        assert_true(arm_ligament_label(part) != "arm ligament")
        var field = arm_ligament_field(dims, part, LEFT)
        assert_true(field.volume() > 0 and field.high.x < 0)
        assert_true(
            arm_ligament_mass_from_dimensions(
                dims, part, arm_ligament_tissue(part)
            ).mass.value
            > 0
        )
    assert_equal(arm_ligament_tissue(GLENOID_LABRUM).kind, MENISCUS)
    assert_equal(arm_ligament_tissue(ARTICULAR_CARTILAGE).kind, CARTILAGE)
    assert_equal(arm_ligament_tissue(ANNULAR_LIGAMENT).kind, LIGAMENT)
    assert_equal(arm_ligament_label(ArmLigament(8)), "arm ligament")
    assert_false(ArmLigament(-1).is_valid())
    with assert_raises(contains="named part"):
        _ = arm_ligament_tissue(ArmLigament(8))
    with assert_raises(contains="named part"):
        _ = arm_ligament_field(dims, ArmLigament(8), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = arm_ligament_field(dims, ANNULAR_LIGAMENT, BodySide(2))
    # The annular ligament rings the radial neck; the membrane spans the
    # gap between the shafts.
    var f = dims.frame
    var ring = f.fore(1.7 + 1.2, -2.4, 0.5)
    assert_true(arm_ligament_distance(dims, ANNULAR_LIGAMENT, RIGHT, ring) < 0)
    assert_equal(
        arm_ligament_occupancy(
            dims, INTEROSSEOUS_MEMBRANE, RIGHT, f.fore(0.55, -12, 0.1)
        ),
        SOFT_FILL,
    )
    # A pad lies thin along its normal.
    var pad = joint_pad(Vector3(0, 0, 0), Vector3(0, 1, 0), 0.001, 0.01)
    assert_true(abs(pad.stations[0].p.y) < TOLERANCE)
    var side = joint_pad(Vector3(0, 0, 0), Vector3(0, 0, 1), 0.001, 0.01)
    assert_true(side.stations[0].ml < side.stations[0].ap)
    var mesh = arm_ligament(_person(), GLENOID_LABRUM, RIGHT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(
        arm_ligament_mass(_person(), INTEROSSEOUS_MEMBRANE).mass.value > 0
    )
    with assert_raises():
        _ = arm_ligament_from_dimensions(dims, GLENOID_LABRUM, RIGHT, 7)


def test_vessels() raises:
    var dims = arm_muscle_dimensions(_person())
    var parts = named_arm_vessels()
    assert_equal(len(parts), 9)
    var arteries = 0
    for index in range(len(parts)):
        var part = parts[index]
        if is_arm_artery(part):
            arteries += 1
        assert_true(arm_vessel_label(part) != "arm vessel")
        var field = arm_vessel_field(dims, part, LEFT)
        var inside = flip_x(field.sweeps[0].stations[1].p)
        assert_true(field.distance(inside) < 0)
        assert_true(
            arm_vessel_mass_from_dimensions(
                dims, part, arterial_tissue()
            ).mass.value
            > 0
        )
    assert_equal(arteries, 4)
    # The axillary artery takes over from the torso's subclavian.
    var subclavian = torso_vessel_field(
        torso_muscle_dimensions(_person()), SUBCLAVIAN_ARTERY, RIGHT
    )
    var run = subclavian.sweeps[0].stations.copy()
    var axillary = arm_vessel_field(dims, AXILLARY_ARTERY, RIGHT)
    var start = axillary.sweeps[0].stations[0].p
    assert_true((run[len(run) - 1].p - start).length() < 0.005)
    assert_equal(
        arm_vessel_occupancy(dims, AXILLARY_ARTERY, RIGHT, start), SOFT_FILL
    )
    assert_true(
        arm_vessel_distance(dims, BRACHIAL_ARTERY, RIGHT, Vector3(0, 0, 0)) > 0
    )
    assert_equal(arm_vessel_label(ArmVessel(9)), "arm vessel")
    assert_false(ArmVessel(-1).is_valid())
    with assert_raises(contains="artery or vein"):
        _ = is_arm_artery(ArmVessel(9))
    with assert_raises(contains="artery or vein"):
        _ = arm_vessel_paths(ArmVessel(9))
    with assert_raises(contains="RIGHT or LEFT"):
        _ = arm_vessel_field(dims, CEPHALIC_VEIN, BodySide(3))
    var mesh = arm_vessel(_person(), CEPHALIC_VEIN, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(arm_vessel_mass(_person(), BRACHIAL_ARTERY).mass.value > 0)
    assert_true(arm_vessel_mass(_person(), CEPHALIC_VEIN).mass.value > 0)


def test_nerves() raises:
    var dims = arm_muscle_dimensions(_person())
    var parts = named_arm_nerves()
    assert_equal(len(parts), 5)
    # Every nerve leaves the torso's brachial plexus in the armpit.
    var plexus = torso_nerve_field(
        torso_muscle_dimensions(_person()), BRACHIAL_PLEXUS, RIGHT
    )
    var cord = plexus.sweeps[0].stations.copy()
    var armpit = cord[len(cord) - 1].p
    for index in range(len(parts)):
        var part = parts[index]
        assert_true(arm_nerve_label(part) != "arm nerve")
        var field = arm_nerve_field(dims, part, RIGHT)
        assert_true((field.sweeps[0].stations[0].p - armpit).length() < 0.005)
        assert_true(
            arm_nerve_mass_from_dimensions(
                dims, part, nerve_tissue()
            ).mass.value
            > 0
        )
    # The median nerve runs through the carpal tunnel; the ulnar nerve
    # passes behind the medial epicondyle.
    var f = dims.arm.frame
    assert_true(
        arm_nerve_distance(dims, MEDIAN_NERVE, RIGHT, f.fore(0.7, -28.3, 1.6))
        < 0
    )
    assert_equal(
        arm_nerve_occupancy(
            dims, ULNAR_NERVE, RIGHT, f.upper(-3.4, -31.5, -1.2)
        ),
        SOFT_FILL,
    )
    assert_equal(arm_nerve_label(ArmNerve(5)), "arm nerve")
    assert_false(ArmNerve(-1).is_valid())
    with assert_raises(contains="named nerve"):
        _ = arm_nerve_paths(ArmNerve(5))
    with assert_raises(contains="RIGHT or LEFT"):
        _ = arm_nerve_field(dims, MEDIAN_NERVE, BodySide(3))
    var mesh = arm_nerve(_person(), ULNAR_NERVE, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(arm_nerve_mass(_person(), MEDIAN_NERVE).mass.value > 0)


def test_lymph() raises:
    var dims = arm_muscle_dimensions(_person())
    var parts = named_arm_lymph()
    assert_equal(len(parts), 4)
    for index in range(len(parts)):
        var part = parts[index]
        assert_true(arm_lymph_label(part) != "arm lymph")
        var field = arm_lymph_field(dims, part, LEFT)
        assert_true(field.high.x < 0)
        assert_true(
            arm_lymph_mass_from_dimensions(
                dims, part, lymph_tissue()
            ).mass.value
            > 0
        )
    var nodes = arm_lymph_field(dims, CUBITAL_NODES, RIGHT)
    var node = nodes.sweeps[0].stations[0].p
    assert_true(arm_lymph_distance(dims, CUBITAL_NODES, RIGHT, node) < 0)
    assert_equal(
        arm_lymph_occupancy(dims, CUBITAL_NODES, RIGHT, node), SOFT_FILL
    )
    assert_equal(arm_lymph_label(ArmLymph(4)), "arm lymph")
    assert_false(ArmLymph(-1).is_valid())
    with assert_raises(contains="named part"):
        _ = arm_lymph_paths(ArmLymph(4))
    with assert_raises(contains="RIGHT or LEFT"):
        _ = arm_lymph_field(dims, CUBITAL_NODES, BodySide(3))
    var mesh = arm_lymph(_person(), CUBITAL_NODES, RIGHT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(arm_lymph_mass(_person(), CUBITAL_NODES).mass.value > 0)


def test_skin() raises:
    var dims = arm_muscle_dimensions(_person())
    var f = dims.arm.frame
    var right = ArmSkinField(dims, RIGHT)
    var left = ArmSkinField(dims, LEFT)
    # The elbow and the middle of the forearm are inside; a point a
    # hand's breadth out is not.
    assert_true(right.distance(f.elbow) < 0)
    assert_true(right.distance(f.fore(0.5, -14, 0.4)) < 0)
    assert_true(left.distance(flip_x(f.elbow)) < 0)
    assert_true(left.low.x < 0 and left.high.x < 0)
    assert_true(right.distance(f.upper(12, -15, 0)) > 0)
    assert_true(right.gradient(f.upper(6, -15, 0)).x > 0.5)
    var layer = ArmSkinLayerField(dims, RIGHT)
    assert_true(layer.distance(f.elbow) > 0)
    assert_true(arm_fat(MALE, True) > arm_fat(MALE, False))
    assert_true(arm_fat(FEMALE, True) > arm_fat(MALE, True))
    assert_true(arm_fat(FEMALE, False) > arm_fat(MALE, False))
    assert_true(lies_on_scapula(SUBSCAPULARIS))
    assert_false(lies_on_scapula(DELTOID))
    with assert_raises(contains="RIGHT or LEFT"):
        _ = ArmSkinField(dims, BodySide(3))
    # Lone stations stand alone, and a station too near the midline is
    # left out.
    var samples = List[LoftSample]()
    append_stations(samples, arm_lymph_field(dims, CUBITAL_NODES, RIGHT), 0)
    assert_equal(len(samples), 2)
    assert_false(samples[0].joins)
    var none = List[LoftSample]()
    append_stations(none, arm_lymph_field(dims, CUBITAL_NODES, RIGHT), 1.0)
    assert_equal(len(none), 0)
    var mesh = arm_skin_mesh(_person(), LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    with assert_raises():
        _ = arm_skin_from_dimensions(dims, RIGHT, 7)
    var report = arm_skin_mass(_person(), COARSE)
    assert_true(report.mass.value > 0.05 and report.mass.value < 1.0)
    assert_true(
        arm_skin_mass_from_dimensions(dims, skin_tissue(), COARSE).mass.value
        > 0
    )
    assert_equal(arm_skin_occupancy(dims, RIGHT, f.elbow), SOFT_EMPTY)


def test_hair() raises:
    var dims = arm_muscle_dimensions(_person())
    var parts = named_arm_hair()
    assert_equal(len(parts), 2)
    var skin = ArmSkinField(dims, RIGHT)
    for index in range(len(parts)):
        var part = parts[index]
        assert_true(arm_hair_label(part) != "arm hair")
        var field = arm_hair_field(dims, part, RIGHT)
        assert_equal(len(field.sweeps), 8)
        # Each shaft rises from the skin.
        var root = field.sweeps[0].stations[0].p
        assert_true(abs(skin.distance(root)) < 0.001)
        var tip = field.sweeps[0].stations[1].p
        assert_true(arm_hair_distance(dims, part, RIGHT, tip) < 0)
        assert_true(
            arm_hair_mass_from_dimensions(dims, part, hair_tissue()).mass.value
            > 0
        )
    assert_equal(arm_hair_label(ArmHair(2)), "arm hair")
    assert_false(ArmHair(-1).is_valid())
    with assert_raises(contains="named hair group"):
        _ = arm_hair_field(dims, ArmHair(2), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = arm_hair_field(dims, FOREARM_HAIR, BodySide(3))
    var f = dims.arm.frame
    var exit = surface_root(skin, f.elbow, Vector3(1, 0, 0), 0.2)
    assert_true(abs(skin.distance(exit)) < 0.001)
    var one = shaft(
        Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, -1, 0), 0.01, 0.0001
    )
    assert_true(one.stations[1].p.y < -0.009)
    var right = arm_hair_mesh(_person(), UPPER_ARM_HAIR, RIGHT, 8)
    var left = arm_hair_from_dimensions(dims, FOREARM_HAIR, LEFT, 8)
    assert_true(right.triangle_count() > 0 and left.triangle_count() > 0)
    with assert_raises():
        _ = arm_hair_mesh(_person(), UPPER_ARM_HAIR, RIGHT, 7)
    assert_true(arm_hair_mass(_person(), FOREARM_HAIR).mass.value > 0)


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
    var bad = ArmContents(0)
    assert_false(bad.is_valid())
    assert_false(ArmContents(256).is_valid())
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


def test_add_arm_places_every_layer() raises:
    var person = _person()
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var bone = assets.materials.add(bone_phong())
    var ligament = assets.materials.add(ligament_phong())
    var cartilage = assets.materials.add(cartilage_phong())
    var muscle = assets.materials.add(muscle_phong())
    _ = add_arm(
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
    # Three bones, eight joint parts, thirty muscles, nine vessels, four
    # lymphatics, five nerves, one skin and two hair groups.
    assert_equal(len(scene.meshes), 62)
    var painted = Scene()
    var painted_root = painted.add(Object3D())
    _ = add_arm(
        painted,
        assets,
        painted_root,
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        LEFT,
        VESSELS.plus(LYMPH).plus(NERVES).plus(SKIN).plus(HAIR),
        8,
        8,
        Vector3(0, 0, 0),
        assets.materials.add(artery_phong()),
        assets.materials.add(vein_phong()),
        assets.materials.add(lymph_phong()),
        assets.materials.add(nerve_phong()),
        assets.materials.add(skin_phong()),
        assets.materials.add(hair_phong()),
    )
    assert_equal(len(painted.meshes), 21)
    var given = MaterialId(0)
    assert_equal(resolved_paint(assets, given, bone_phong()).value, 0)
    assert_true(resolved_paint(assets, UNSET_PAINT, bone_phong()).value > 0)
    with assert_raises(contains="named layer set"):
        _ = add_arm(
            scene,
            assets,
            root,
            person,
            bone,
            ligament,
            cartilage,
            muscle,
            RIGHT,
            ArmContents(0),
        )
    with assert_raises(contains="RIGHT or LEFT"):
        _ = add_arm(
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


def test_add_upper_limb_draws_the_arm_and_its_hand() raises:
    var person = _person()
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var bone = assets.materials.add(bone_phong())
    var ligament = assets.materials.add(ligament_phong())
    var cartilage = assets.materials.add(cartilage_phong())
    var muscle = assets.materials.add(muscle_phong())
    _ = add_upper_limb(
        scene,
        assets,
        root,
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        LEFT,
        BONES.plus(SKIN),
        8,
        8,
        8,
    )
    # The arm's three bones and skin, and the hand's twenty-seven bones
    # and skin.
    assert_equal(len(scene.meshes), 32)
    with assert_raises(contains="named layer set"):
        _ = add_upper_limb(
            scene,
            assets,
            root,
            person,
            bone,
            ligament,
            cartilage,
            muscle,
            RIGHT,
            ArmContents(0),
        )


def test_arm_muscle_scale_must_be_finite() raises:
    for invalid in [
        nan[DType.float32](),
        inf[DType.float32](),
        -inf[DType.float32](),
    ]:
        var dims = arm_muscle_dimensions(_person())
        dims.scale = invalid
        with assert_raises(contains="scale"):
            dims.validate()


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
