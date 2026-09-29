# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the stature-scaled torso and the body it completes."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import Athleticism
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.arm.frame import arm_dimensions
from extensions.humanoid.skeleton.bone import bone_phong
from extensions.humanoid.skeleton.field import flip_x, mix_point
from extensions.humanoid.skeleton.look import (
    artery_phong,
    cartilage_phong,
    ligament_phong,
    lymph_phong,
    muscle_phong,
    nerve_phong,
    skin_phong,
    tendon_phong,
    vein_phong,
)
from extensions.humanoid.skeleton.occupancy import TRABECULAR_FILL
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    pelvis_dimensions,
)
from extensions.humanoid.skeleton.soft_tissue import (
    CARTILAGE,
    LIGAMENT,
    MENISCUS,
    SOFT_FILL,
    lymph_tissue,
    muscle_tissue,
    nerve_tissue,
)
from extensions.humanoid.skeleton.torso.assembly import add_torso
from extensions.humanoid.skeleton.torso.body import (
    BodySkinField,
    add_body,
    body_skin_mesh,
)
from extensions.humanoid.skeleton.torso.bones.dimensions import (
    ARM_ABDUCTION,
    CLAVICLE,
    L1,
    L3,
    L5,
    RIB_1,
    RIB_7,
    RIB_12,
    SCAPULA,
    STERNUM,
    T1,
    T7,
    VERTEBRAE,
    TorsoBone,
    along_path,
    canal_center,
    cartilage_end,
    clavicle_path,
    is_paired_bone,
    named_torso_bones,
    rib_path,
    shoulder_girdle,
    spinous_tip,
    template_points,
    torso_bone_distance,
    torso_bone_field,
    torso_bone_label,
    torso_cm,
    torso_dimensions,
    torso_side_point,
    upper_arm_point,
)
from extensions.humanoid.skeleton.torso.bones.geometry import torso_bone
from extensions.humanoid.skeleton.torso.bones.mass import (
    torso_bone_mass,
    torso_bone_mass_from_dimensions,
    torso_bone_occupancy,
)
from extensions.humanoid.skeleton.torso.contents import (
    ALL,
    BONES,
    BOTH,
    LIGAMENTS,
    LYMPH,
    MUSCLES,
    NERVES,
    SKIN,
    VESSELS,
    TorsoContents,
)
from extensions.humanoid.skeleton.torso.ligaments.dimensions import (
    ACROMIOCLAVICULAR_JOINT,
    ANTERIOR_LONGITUDINAL_LIGAMENT,
    CORACOCLAVICULAR_LIGAMENT,
    COSTAL_CARTILAGES,
    INTERVERTEBRAL_DISCS,
    STERNOCLAVICULAR_JOINT,
    SUPRASPINOUS_LIGAMENT,
    TorsoLigament,
    is_paired_ligament,
    named_torso_ligaments,
    torso_ligament_distance,
    torso_ligament_field,
    torso_ligament_label,
    torso_ligament_tissue,
)
from extensions.humanoid.skeleton.torso.ligaments.geometry import (
    torso_ligament,
)
from extensions.humanoid.skeleton.torso.ligaments.mass import (
    torso_ligament_mass,
    torso_ligament_mass_from_dimensions,
    torso_ligament_occupancy,
)
from extensions.humanoid.skeleton.torso.lymph.dimensions import (
    AXILLARY_NODES,
    CISTERNA_CHYLI,
    PARASTERNAL_NODES,
    THORACIC_DUCT,
    TorsoLymph,
    is_paired_lymph,
    named_torso_lymph,
    torso_lymph_distance,
    torso_lymph_field,
    torso_lymph_label,
)
from extensions.humanoid.skeleton.torso.lymph.geometry import torso_lymph
from extensions.humanoid.skeleton.torso.lymph.mass import (
    torso_lymph_mass,
    torso_lymph_mass_from_dimensions,
    torso_lymph_occupancy,
)
from extensions.humanoid.skeleton.torso.muscles.dimensions import (
    DIAPHRAGM,
    ERECTOR_SPINAE,
    INTERCOSTALS,
    LATISSIMUS_DORSI,
    PECTORALIS_MAJOR,
    PECTORALIS_MINOR,
    RHOMBOIDS,
    SUBCLAVIUS,
    TRAPEZIUS,
    TorsoMuscle,
    TorsoMuscleDimensions,
    is_paired_muscle,
    named_torso_muscles,
    torso_muscle_dimensions,
    torso_muscle_distance,
    torso_muscle_field,
    torso_muscle_label,
)
from extensions.humanoid.skeleton.torso.muscles.geometry import torso_muscle
from extensions.humanoid.skeleton.torso.muscles.mass import (
    torso_muscle_mass,
    torso_muscle_mass_from_dimensions,
    torso_muscle_occupancy,
)
from extensions.humanoid.skeleton.torso.nerves.dimensions import (
    BRACHIAL_PLEXUS,
    ILIOHYPOGASTRIC_NERVE,
    SPINAL_CORD,
    SYMPATHETIC_TRUNK,
    TorsoNerve,
    is_paired_nerve,
    named_torso_nerves,
    torso_nerve_distance,
    torso_nerve_field,
    torso_nerve_label,
)
from extensions.humanoid.skeleton.torso.nerves.geometry import torso_nerve
from extensions.humanoid.skeleton.torso.nerves.mass import (
    torso_nerve_mass,
    torso_nerve_mass_from_dimensions,
    torso_nerve_occupancy,
)
from extensions.humanoid.skeleton.torso.skin.dimensions import (
    TorsoSkinField,
    torso_fat,
    torso_skin_distance,
)
from extensions.humanoid.skeleton.torso.skin.geometry import torso_skin_mesh
from extensions.humanoid.skeleton.torso.skin.mass import (
    torso_skin_mass,
    torso_skin_occupancy,
)
from extensions.humanoid.skeleton.torso.sweep import (
    Dome,
    Sweep,
    SweepField,
    floats,
    pow_mean,
    spline_points,
    tube,
)
from extensions.humanoid.skeleton.torso.vessels.dimensions import (
    AZYGOS_VEIN,
    EPIGASTRIC_ARTERY,
    INTERCOSTAL_VEINS,
    SUBCLAVIAN_ARTERY,
    SUBCLAVIAN_VEIN,
    THORACIC_AORTA,
    UPPER_ABDOMINAL_AORTA,
    UPPER_VENA_CAVA,
    TorsoVessel,
    is_paired_vessel,
    is_torso_artery,
    named_torso_vessels,
    torso_vessel_distance,
    torso_vessel_field,
    torso_vessel_label,
)
from extensions.humanoid.skeleton.torso.vessels.geometry import torso_vessel
from extensions.humanoid.skeleton.torso.vessels.mass import (
    torso_vessel_mass,
    torso_vessel_mass_from_dimensions,
    torso_vessel_occupancy,
)
from extensions.humanoid.skeleton.tissue import (
    cortical_tissue,
    trabecular_tissue,
)
from math.vector3 import Vector3
from std.math import nan
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
    """Return the six-foot male the suite measures."""
    return HumanoidSpec(Length(6.0, FOOT), MALE)


def test_sweeps_measure_themselves() raises:
    var sweep = Sweep(Vector3(1, 0, 0))
    sweep.round(Vector3(0, 0, 0), 0.01)
    # One station is a ball.
    assert_almost_equal(
        sweep.distance(Vector3(0.02, 0, 0), 0.001), 0.01, atol=TOLERANCE
    )
    assert_true(sweep.volume() > 4.0e-6 and sweep.volume() < 4.3e-6)
    sweep.round(Vector3(0, 0.1, 0), 0.01)
    assert_almost_equal(
        sweep.distance(Vector3(0.03, 0.05, 0), 0.001), 0.02, atol=1.0e-4
    )
    assert_equal(sweep.gap(Vector3(0, 0.05, 0)), 0)
    assert_almost_equal(sweep.gap(Vector3(0.05, 0.05, 0)), 0.04, atol=TOLERANCE)
    assert_true(sweep.volume() > 3.1e-5)
    var sweeps = List[Sweep]()
    sweeps.append(sweep^)
    var domes = List[Dome]()
    domes.append(Dome(Vector3(0, 0, 0), Vector3(0.1, 0.1, 0.1), 0.005, 0.0))
    var field = SweepField(sweeps^, domes^, LEFT, 0.002, 0.001, 0.004)
    assert_true(field.distance(Vector3(0, 0.1, 0)) < 0)
    assert_true(field.distance(Vector3(0, -0.1, 0)) > 0)
    assert_true(field.distance(Vector3(0.5, 0.5, 0.5)) > 0.3)
    # Straight above the dome, the surface faces up.
    assert_true(field.gradient(Vector3(0, 0.3, 0)).y > 0.5)
    assert_true(field.volume() > 0)
    var wide = field.widened(0.02)
    assert_true(wide.distance(Vector3(0.015, 0.05, 0)) < 0)
    assert_almost_equal(pow_mean(Vector3(1, 1, 1)), 1, atol=TOLERANCE)
    var path = spline_points(template_list(), 2)
    assert_equal(len(path), 5)
    assert_equal(len(floats(1, 2, 3)), 3)
    assert_equal(len(tube(template_list(), 0.01, 0.02).stations), 3)


def template_list() -> List[Vector3]:
    """Return three points along x."""
    var points = List[Vector3]()
    points.append(Vector3(0, 0, 0))
    points.append(Vector3(1, 0, 0))
    points.append(Vector3(2, 0, 0))
    return points^


def test_the_column_stands_on_the_sacrum() raises:
    var dims = torso_dimensions(Length(6.0, FOOT), MALE)
    dims.validate()
    var pelvis = pelvis_dimensions(Length(6.0, FOOT), MALE)
    assert_equal(len(dims.centers), VERTEBRAE)
    # L5 sits just above the promontory; T1 near the base of the neck.
    var l5 = dims.centers[L5.value]
    assert_true(l5.y > pelvis.promontory.y)
    assert_true(l5.y - pelvis.promontory.y < 0.06)
    var t1 = dims.centers[T1.value]
    assert_true(t1.y > 0.44 and t1.y < 0.56)
    # A lumbar lordosis and a thoracic kyphosis.
    assert_true(dims.centers[L3.value].z > dims.centers[T7.value].z)
    assert_true(dims.centers[T7.value].z < t1.z)
    # Bodies grow down the column.
    assert_true(dims.widths[L5.value] > dims.widths[T7.value])
    assert_true(dims.notch.z > t1.z)
    assert_true(dims.xiphoid.y < dims.notch.y)
    var woman = torso_dimensions(Length(6.0, FOOT), FEMALE)
    assert_true(woman.widths[L3.value] < dims.widths[L3.value])
    assert_equal(torso_cm(dims, 100), dims.frame.cm(100))
    var mirrored = torso_side_point(Vector3(1, 2, 3), LEFT)
    assert_equal(mirrored.x, -1)
    assert_equal(torso_side_point(Vector3(1, 2, 3), RIGHT).x, 1)
    assert_equal(len(template_points(dims.frame, floats(1, 2, 3, 4, 5, 6))), 2)
    assert_true(spinous_tip(dims, T7.value).z < canal_center(dims, T7.value).z)


def test_torso_refuses_bad_input() raises:
    with assert_raises():
        _ = torso_dimensions(Length(0.5, METER), MALE)
    var dims = torso_dimensions(Length(6.0, FOOT), MALE)
    var short = dims.copy()
    _ = short.centers.pop()
    with assert_raises(contains="seventeen"):
        short.validate()
    var flat = dims.copy()
    flat.heights[3] = 0
    with assert_raises(contains="positive"):
        flat.validate()
    var lost = dims.copy()
    lost.notch = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises():
        lost.validate()
    with assert_raises(contains="RIGHT or LEFT"):
        _ = torso_bone_field(dims, T1, BodySide(4))
    with assert_raises(contains="named vertebra"):
        _ = is_paired_bone(TorsoBone(32))


def test_bones_are_named_and_solid() raises:
    var dims = torso_dimensions(Length(6.0, FOOT), MALE)
    var bones = named_torso_bones()
    assert_equal(len(bones), 32)
    assert_equal(torso_bone_label(T1), "T1")
    assert_equal(torso_bone_label(L3), "L3")
    assert_equal(torso_bone_label(STERNUM), "sternum")
    assert_equal(torso_bone_label(RIB_7), "rib 7")
    assert_equal(torso_bone_label(TorsoBone(-1)), "torso bone")
    assert_equal(torso_bone_label(CLAVICLE), "clavicle")
    assert_equal(torso_bone_label(SCAPULA), "scapula")
    assert_false(TorsoBone(32).is_valid())
    assert_true(is_paired_bone(SCAPULA))
    assert_true(is_paired_bone(RIB_1))
    assert_false(is_paired_bone(L1))
    for index in range(len(bones)):
        var field = torso_bone_field(dims, bones[index], RIGHT)
        assert_true(field.high.y > field.low.y)
    assert_true(torso_bone_distance(dims, L3, LEFT, dims.centers[L3.value]) < 0)
    assert_true(torso_bone_distance(dims, STERNUM, RIGHT, dims.notch) < 0)
    var rib = rib_path(dims, RIB_7.value - RIB_1.value)
    var middle = along_path(rib, 0.5)
    assert_true(torso_bone_distance(dims, RIB_7, RIGHT, middle) < 0)
    assert_true(torso_bone_distance(dims, RIB_7, LEFT, flip_x(middle)) < 0)
    assert_true(torso_bone_distance(dims, RIB_7, LEFT, middle) > 0)
    # Floating ribs end at the side, short of the front.
    var twelfth = rib_path(dims, RIB_12.value - RIB_1.value)
    assert_true(twelfth[len(twelfth) - 1].z < rib[len(rib) - 1].z)
    assert_true(cartilage_end(dims, 0).y > cartilage_end(dims, 9).y)
    var mesh = torso_bone(_person(), RIB_7, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)


def test_the_shoulder_girdle_rides_the_chest() raises:
    var dims = torso_dimensions(Length(6.0, FOOT), MALE)
    var g = shoulder_girdle(dims)
    # The clavicle runs from the manubrium out, up and back to the
    # acromion, bowing forward on the way.
    assert_true(g.sternoclavicular.x < g.acromioclavicular.x)
    assert_true(g.acromioclavicular.y > g.sternoclavicular.y)
    assert_true(g.acromioclavicular.z < g.sternoclavicular.z)
    var path = clavicle_path(dims)
    assert_true(along_path(path, 0.3).z > g.sternoclavicular.z)
    assert_true(torso_bone_distance(dims, CLAVICLE, RIGHT, path[3]) < 0)
    assert_true(torso_bone_distance(dims, CLAVICLE, LEFT, flip_x(path[3])) < 0)
    assert_true(
        torso_bone_distance(dims, STERNUM, RIGHT, g.sternoclavicular) < 0.02
    )
    # The scapula lies on the back, behind the ribs, from about the
    # second rib to the seventh; its glenoid holds the humeral head.
    assert_true(torso_bone_distance(dims, SCAPULA, RIGHT, g.glenoid) < 0)
    assert_true(torso_bone_distance(dims, SCAPULA, RIGHT, g.acromion) < 0.005)
    assert_true(torso_bone_distance(dims, SCAPULA, RIGHT, g.coracoid) < 0.005)
    assert_true(g.superior_angle.y > g.inferior_angle.y)
    assert_true(g.inferior_angle.y > dims.centers[L1.value].y)
    var blade = mix_point(g.spine_root, g.inferior_angle, 0.5)
    for rib in range(1, 7):
        var part = TorsoBone(RIB_1.value + rib)
        assert_true(torso_bone_distance(dims, part, RIGHT, blade) > 0)
    assert_true(torso_bone_distance(dims, SCAPULA, RIGHT, blade) < 0.01)
    # The humeral head sits lateral of the glenoid, under the acromion.
    assert_true(g.shoulder.x > g.glenoid.x)
    assert_true(g.shoulder.y < g.acromion.y)
    assert_true(torso_bone_distance(dims, SCAPULA, RIGHT, g.shoulder) > 0)
    # The arm hangs from the humeral head, turned out from the side.
    var top = upper_arm_point(dims, 0, 0, 0)
    assert_almost_equal(top.x, g.shoulder.x, atol=TOLERANCE)
    var elbow = upper_arm_point(dims, 0, -30, 0)
    assert_true(elbow.x > g.shoulder.x)
    assert_true(elbow.y < g.shoulder.y - 0.25)
    assert_true(ARM_ABDUCTION > 0 and ARM_ABDUCTION < 0.2)
    # A woman's shoulders are narrower.
    var woman = shoulder_girdle(torso_dimensions(Length(6.0, FOOT), FEMALE))
    assert_true(woman.shoulder.x < g.shoulder.x)


def test_bone_mass() raises:
    var person = _person()
    var lumbar = torso_bone_mass(person, L3, COARSE)
    assert_true(lumbar.mass.value > 0.02 and lumbar.mass.value < 0.2)
    var dims = torso_dimensions(person.stature, MALE)
    var rib = torso_bone_mass_from_dimensions(
        dims, RIB_7, cortical_tissue(), trabecular_tissue(), COARSE
    )
    assert_true(rib.mass.value > 0.005 and rib.mass.value < 0.1)
    var scapula = torso_bone_mass(person, SCAPULA, COARSE)
    assert_true(scapula.mass.value > 0.05 and scapula.mass.value < 0.4)
    assert_equal(
        torso_bone_occupancy(dims, L3, RIGHT, dims.centers[L3.value]),
        TRABECULAR_FILL,
    )
    with assert_raises():
        _ = torso_bone_mass(person, L3, Length(1.0, MILLIMETER))


def test_ligaments() raises:
    var dims = torso_dimensions(Length(6.0, FOOT), MALE)
    var parts = named_torso_ligaments()
    assert_equal(len(parts), 7)
    for index in range(len(parts)):
        var part = parts[index]
        assert_true(torso_ligament_label(part) != "torso ligament")
        var field = torso_ligament_field(dims, part, LEFT)
        assert_true(field.volume() > 0)
        assert_true(
            torso_ligament_mass_from_dimensions(
                dims, part, torso_ligament_tissue(part)
            ).mass.value
            > 0
        )
    # A disc lies between two bodies.
    var between = (dims.centers[L3.value] + dims.centers[L3.value + 1]) * 0.5
    assert_true(
        torso_ligament_distance(dims, INTERVERTEBRAL_DISCS, RIGHT, between) < 0
    )
    assert_equal(
        torso_ligament_occupancy(dims, INTERVERTEBRAL_DISCS, LEFT, between),
        SOFT_FILL,
    )
    assert_true(is_paired_ligament(COSTAL_CARTILAGES))
    assert_false(is_paired_ligament(SUPRASPINOUS_LIGAMENT))
    assert_equal(torso_ligament_tissue(INTERVERTEBRAL_DISCS).kind, MENISCUS)
    assert_equal(torso_ligament_tissue(COSTAL_CARTILAGES).kind, CARTILAGE)
    assert_equal(
        torso_ligament_tissue(ANTERIOR_LONGITUDINAL_LIGAMENT).kind, LIGAMENT
    )
    assert_false(TorsoLigament(-1).is_valid())
    assert_equal(torso_ligament_label(TorsoLigament(7)), "torso ligament")
    with assert_raises(contains="named part"):
        _ = is_paired_ligament(TorsoLigament(7))
    with assert_raises(contains="named part"):
        _ = torso_ligament_tissue(TorsoLigament(7))
    # The girdle's joints: a disc at each end of the clavicle's run, and
    # the coracoclavicular ligament between the coracoid and the
    # clavicle.
    var girdle = shoulder_girdle(dims)
    assert_true(is_paired_ligament(ACROMIOCLAVICULAR_JOINT))
    assert_equal(torso_ligament_tissue(STERNOCLAVICULAR_JOINT).kind, MENISCUS)
    assert_true(
        torso_ligament_distance(
            dims, STERNOCLAVICULAR_JOINT, RIGHT, girdle.sternoclavicular
        )
        < 0
    )
    assert_true(
        torso_ligament_distance(
            dims,
            ACROMIOCLAVICULAR_JOINT,
            LEFT,
            flip_x(girdle.acromioclavicular),
        )
        < 0.004
    )
    var cc = torso_ligament_field(dims, CORACOCLAVICULAR_LIGAMENT, RIGHT)
    assert_true(cc.high.y > girdle.coracoid.y)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = torso_ligament_field(dims, COSTAL_CARTILAGES, BodySide(3))
    var mesh = torso_ligament(_person(), COSTAL_CARTILAGES, RIGHT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(
        torso_ligament_mass(_person(), INTERVERTEBRAL_DISCS).mass.value > 0
    )


def test_muscles() raises:
    var dims = torso_muscle_dimensions(_person())
    var parts = named_torso_muscles()
    assert_equal(len(parts), 15)
    for index in range(len(parts)):
        var part = parts[index]
        assert_true(torso_muscle_label(part) != "torso muscle")
        var right = torso_muscle_field(dims, part, RIGHT)
        var left = torso_muscle_field(dims, part, LEFT)
        assert_true(right.high.x > 0)
        if is_paired_muscle(part):
            assert_true(left.low.x < right.low.x or left.high.x < right.high.x)
        var report = torso_muscle_mass_from_dimensions(
            dims, part, muscle_tissue()
        )
        assert_true(report.mass.value > 0.001 and report.mass.value < 3.0)
    # The diaphragm domes over the abdomen on either side.
    var dome = dims.torso.frame.at(0, 36.0 - 0.1, -0.5)
    assert_true(torso_muscle_distance(dims, DIAPHRAGM, RIGHT, dome) < 0.01)
    assert_false(is_paired_muscle(DIAPHRAGM))
    var erector = torso_muscle_field(dims, ERECTOR_SPINAE, RIGHT)
    var inside = erector.sweeps[0].stations[3].p
    assert_equal(
        torso_muscle_occupancy(dims, ERECTOR_SPINAE, RIGHT, inside), SOFT_FILL
    )
    assert_false(TorsoMuscle(-1).is_valid())
    assert_equal(torso_muscle_label(TorsoMuscle(15)), "torso muscle")
    with assert_raises(contains="named muscle"):
        _ = is_paired_muscle(TorsoMuscle(15))
    # The girdle's muscles reach the scapula, the coracoid and the
    # clavicle; the pectoralis major and the latissimus reach the
    # humerus.
    var girdle = shoulder_girdle(dims.torso)
    assert_true(
        torso_muscle_distance(dims, PECTORALIS_MINOR, RIGHT, girdle.coracoid)
        < 0.012
    )
    var pectoral = torso_muscle_field(dims, PECTORALIS_MAJOR, RIGHT)
    assert_true(pectoral.high.x > girdle.shoulder.x)
    var latissimus = torso_muscle_field(dims, LATISSIMUS_DORSI, RIGHT)
    assert_true(latissimus.high.x > girdle.shoulder.x)
    var rhomboids = torso_muscle_field(dims, RHOMBOIDS, RIGHT)
    assert_true(rhomboids.low.x < 0.01 and rhomboids.high.x < girdle.glenoid.x)
    var subclavius = torso_muscle_field(dims, SUBCLAVIUS, LEFT)
    assert_true(subclavius.high.x < 0)
    var trapezius = torso_muscle_field(dims, TRAPEZIUS, RIGHT)
    assert_true(trapezius.high.y > girdle.acromion.y)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = torso_muscle_field(dims, INTERCOSTALS, BodySide(3))
    with assert_raises(contains="athleticism"):
        _ = torso_muscle_dimensions(
            HumanoidSpec(Length(6.0, FOOT), MALE, Athleticism(4))
        )
    var edited = dims.copy()
    edited.scale = 0
    with assert_raises(contains="scale"):
        edited.validate()
    edited = dims.copy()
    edited.athleticism = Athleticism(5)
    with assert_raises(contains="athleticism"):
        edited.validate()
    var mesh = torso_muscle(_person(), PECTORALIS_MAJOR, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(torso_muscle_mass(_person(), DIAPHRAGM).mass.value > 0)


def test_vessels() raises:
    var dims = torso_muscle_dimensions(_person())
    var parts = named_torso_vessels()
    assert_equal(len(parts), 10)
    var arteries = 0
    for index in range(len(parts)):
        var part = parts[index]
        if is_torso_artery(part):
            arteries += 1
        assert_true(torso_vessel_label(part) != "torso vessel")
        var field = torso_vessel_field(dims, part, LEFT)
        var first = field.sweeps[0].stations[1].p
        if field.mirror:
            first = flip_x(first)
        assert_true(field.distance(first) < 0)
        assert_true(
            torso_vessel_mass_from_dimensions(
                dims, part, muscle_tissue()
            ).mass.value
            > 0
        )
    assert_equal(arteries, 6)
    # The subclavian vessels run out under the clavicle to the armpit,
    # where the arm's axillary vessels begin.
    var girdle = shoulder_girdle(dims.torso)
    var subclavian = torso_vessel_field(dims, SUBCLAVIAN_ARTERY, RIGHT)
    assert_true(subclavian.high.x > 0.5 * girdle.shoulder.x)
    assert_true(is_paired_vessel(SUBCLAVIAN_VEIN))
    assert_false(is_torso_artery(SUBCLAVIAN_VEIN))
    assert_false(is_paired_vessel(AZYGOS_VEIN))
    assert_true(is_paired_vessel(INTERCOSTAL_VEINS))
    # The thoracic aorta meets the upper abdominal aorta, which meets
    # the pelvis's at its top.
    var chest = torso_vessel_field(dims, THORACIC_AORTA, RIGHT)
    var belly = torso_vessel_field(dims, UPPER_ABDOMINAL_AORTA, RIGHT)
    var last = chest.sweeps[0].stations[len(chest.sweeps[0].stations) - 1].p
    assert_almost_equal(last.y, belly.sweeps[0].stations[0].p.y, atol=TOLERANCE)
    var cava = torso_vessel_field(dims, UPPER_VENA_CAVA, RIGHT)
    assert_true(cava.sweeps[0].stations[0].p.x > 0)
    assert_equal(
        torso_vessel_occupancy(dims, THORACIC_AORTA, RIGHT, last), SOFT_FILL
    )
    assert_true(
        torso_vessel_distance(dims, EPIGASTRIC_ARTERY, LEFT, Vector3(0, 1, 0))
        > 0
    )
    assert_false(TorsoVessel(-1).is_valid())
    assert_equal(torso_vessel_label(TorsoVessel(10)), "torso vessel")
    with assert_raises(contains="artery or vein"):
        _ = is_torso_artery(TorsoVessel(10))
    with assert_raises(contains="artery or vein"):
        _ = is_paired_vessel(TorsoVessel(10))
    with assert_raises(contains="RIGHT or LEFT"):
        _ = torso_vessel_field(dims, THORACIC_AORTA, BodySide(3))
    var mesh = torso_vessel(_person(), EPIGASTRIC_ARTERY, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(torso_vessel_mass(_person(), THORACIC_AORTA).mass.value > 0)
    assert_true(torso_vessel_mass(_person(), AZYGOS_VEIN).mass.value > 0)


def test_nerves() raises:
    var dims = torso_muscle_dimensions(_person())
    var parts = named_torso_nerves()
    assert_equal(len(parts), 5)
    for index in range(len(parts)):
        var part = parts[index]
        assert_true(torso_nerve_label(part) != "torso nerve")
        var field = torso_nerve_field(dims, part, RIGHT)
        assert_true(field.distance(field.sweeps[0].stations[1].p) < 0)
        assert_true(
            torso_nerve_mass_from_dimensions(
                dims, part, nerve_tissue()
            ).mass.value
            > 0
        )
    # The cord runs down the canal.
    var t = dims.torso.copy()
    var canal = canal_center(t, T7.value)
    assert_true(torso_nerve_distance(dims, SPINAL_CORD, LEFT, canal) < 0)
    assert_equal(
        torso_nerve_occupancy(dims, SPINAL_CORD, RIGHT, canal), SOFT_FILL
    )
    assert_false(is_paired_nerve(SPINAL_CORD))
    assert_true(is_paired_nerve(SYMPATHETIC_TRUNK))
    assert_false(TorsoNerve(-1).is_valid())
    assert_equal(torso_nerve_label(TorsoNerve(5)), "torso nerve")
    # The plexus reaches the armpit, in reach of the humeral head.
    var plexus = torso_nerve_field(dims, BRACHIAL_PLEXUS, LEFT)
    var girdle = shoulder_girdle(dims.torso)
    assert_true(plexus.low.x < -0.5 * girdle.shoulder.x)
    assert_true(is_paired_nerve(BRACHIAL_PLEXUS))
    with assert_raises(contains="named nerve"):
        _ = is_paired_nerve(TorsoNerve(5))
    with assert_raises(contains="RIGHT or LEFT"):
        _ = torso_nerve_field(dims, SPINAL_CORD, BodySide(3))
    var mesh = torso_nerve(_person(), ILIOHYPOGASTRIC_NERVE, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(torso_nerve_mass(_person(), SPINAL_CORD).mass.value > 0)


def test_lymph() raises:
    var dims = torso_muscle_dimensions(_person())
    var parts = named_torso_lymph()
    assert_equal(len(parts), 5)
    for index in range(len(parts)):
        var part = parts[index]
        assert_true(torso_lymph_label(part) != "torso lymph")
        var field = torso_lymph_field(dims, part, RIGHT)
        assert_true(field.distance(field.sweeps[0].stations[0].p) < 0)
        assert_true(
            torso_lymph_mass_from_dimensions(
                dims, part, lymph_tissue()
            ).mass.value
            > 0
        )
    var cistern = torso_lymph_field(dims, CISTERNA_CHYLI, LEFT)
    var sac = cistern.sweeps[0].stations[1].p
    assert_equal(
        torso_lymph_occupancy(dims, CISTERNA_CHYLI, LEFT, sac), SOFT_FILL
    )
    assert_true(torso_lymph_distance(dims, THORACIC_DUCT, RIGHT, sac) < 0.02)
    assert_true(is_paired_lymph(PARASTERNAL_NODES))
    assert_false(is_paired_lymph(THORACIC_DUCT))
    assert_false(TorsoLymph(-1).is_valid())
    assert_equal(torso_lymph_label(TorsoLymph(5)), "torso lymph")
    # The axillary nodes lie in the armpit, under the humeral head.
    var axilla = torso_lymph_field(dims, AXILLARY_NODES, RIGHT)
    var girdle = shoulder_girdle(dims.torso)
    assert_true(axilla.high.y < girdle.shoulder.y + 0.02)
    assert_true(axilla.high.x > 0.6 * girdle.shoulder.x)
    assert_true(is_paired_lymph(AXILLARY_NODES))
    with assert_raises(contains="named part"):
        _ = is_paired_lymph(TorsoLymph(5))
    with assert_raises(contains="RIGHT or LEFT"):
        _ = torso_lymph_field(dims, THORACIC_DUCT, BodySide(3))
    var mesh = torso_lymph(_person(), PARASTERNAL_NODES, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(torso_lymph_mass(_person(), THORACIC_DUCT).mass.value > 0)


def test_torso_skin() raises:
    var dims = torso_muscle_dimensions(_person())
    var skin = TorsoSkinField(dims)
    var f = dims.torso.frame
    assert_true(skin.distance(f.at(0, 30.0, 0)) < 0)
    assert_true(skin.distance(f.at(0, 30.0, 40.0)) > 0)
    # The sternum lies under the chest's fat and dermis.
    assert_true(skin.distance(dims.torso.notch) < -0.005)
    assert_true(skin.gradient(f.at(0, 36.0, 14.0)).z > 0.3)
    assert_true(torso_skin_distance(dims, f.at(0, 30.0, 0)) < 0)
    assert_true(torso_fat(MALE, True) > torso_fat(MALE, False))
    assert_true(torso_fat(FEMALE, True) > torso_fat(MALE, True))
    assert_true(torso_fat(FEMALE, False) > torso_fat(MALE, False))
    assert_equal(torso_skin_occupancy(dims, f.at(0, 30.0, 0)).value, 0)
    var report = torso_skin_mass(_person(), Length(12.0, MILLIMETER))
    assert_true(report.mass.value > 0 and report.mass.value < 6.0)
    # A woman's skin carries breast tissue.
    var woman = TorsoSkinField(
        torso_muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), FEMALE))
    )
    var wf = torso_dimensions(Length(6.0, FOOT), FEMALE).frame
    assert_true(woman.distance(wf.at(9.8, 38.5, 13.5)) < 0)
    var mesh = torso_skin_mesh(_person(), 8)
    assert_true(mesh.triangle_count() > 0)


def test_contents_bits() raises:
    assert_true(BONES.includes_bones())
    assert_true(LIGAMENTS.includes_ligaments())
    assert_true(MUSCLES.includes_muscles())
    assert_true(VESSELS.includes_vessels())
    assert_true(LYMPH.includes_lymph())
    assert_true(NERVES.includes_nerves())
    assert_true(SKIN.includes_skin())
    assert_equal(BONES.plus(LIGAMENTS).plus(MUSCLES).value, BOTH.value)
    assert_true(ALL.includes_skin())
    var bad = TorsoContents(0)
    assert_false(bad.is_valid())
    assert_false(TorsoContents(128).is_valid())
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
        _ = BONES.plus(bad)


def test_add_torso_places_every_layer() raises:
    var person = _person()
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var bone = assets.materials.add(bone_phong())
    var ligament = assets.materials.add(ligament_phong())
    var cartilage = assets.materials.add(cartilage_phong())
    var muscle = assets.materials.add(muscle_phong())
    _ = add_torso(
        scene,
        assets,
        root,
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        ALL,
        8,
    )
    # Forty-six bones, eleven joint parts, twenty-nine muscles, sixteen
    # vessels, eight lymphatics, nine nerves and one skin.
    assert_equal(len(scene.meshes), 120)
    var lymph_scene = Scene()
    var lymph_root = lymph_scene.add(Object3D())
    _ = add_torso(
        lymph_scene,
        assets,
        lymph_root,
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        LYMPH.plus(VESSELS).plus(NERVES),
        8,
        Vector3(0, 0, 0),
        assets.materials.add(artery_phong()),
        assets.materials.add(vein_phong()),
        assets.materials.add(lymph_phong()),
        assets.materials.add(nerve_phong()),
    )
    assert_equal(len(lymph_scene.meshes), 33)
    # The skin alone: no layer before it is drawn.
    var skin_scene = Scene()
    _ = add_torso(
        skin_scene,
        assets,
        skin_scene.add(Object3D()),
        person,
        bone,
        ligament,
        cartilage,
        muscle,
        SKIN,
        8,
    )
    assert_equal(len(skin_scene.meshes), 1)
    with assert_raises(contains="named layer set"):
        _ = add_torso(
            scene,
            assets,
            root,
            person,
            bone,
            ligament,
            cartilage,
            muscle,
            TorsoContents(0),
        )


def test_add_body_joins_torso_and_lower_body() raises:
    var person = _person()
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var bone = assets.materials.add(bone_phong())
    var cartilage = assets.materials.add(cartilage_phong())
    var ligament = assets.materials.add(ligament_phong())
    var muscle = assets.materials.add(muscle_phong())
    var tendon = assets.materials.add(tendon_phong())
    _ = add_body(
        scene,
        assets,
        root,
        person,
        bone,
        cartilage,
        cartilage,
        ligament,
        muscle,
        tendon,
        LYMPH,
        8,
    )
    # The lower body's twenty-six lymph solids, the torso's eight, and
    # each arm's four and each hand's two.
    assert_equal(len(scene.meshes), 46)
    var skinned = Scene()
    var skin_root = skinned.add(Object3D())
    _ = add_body(
        skinned,
        assets,
        skin_root,
        person,
        bone,
        cartilage,
        cartilage,
        ligament,
        muscle,
        tendon,
        SKIN,
        8,
        8,
        8,
    )
    # One skin down to the wrists, and each hand's own.
    assert_equal(len(skinned.meshes), 3)
    var painted = Scene()
    var painted_root = painted.add(Object3D())
    _ = add_body(
        painted,
        assets,
        painted_root,
        person,
        bone,
        cartilage,
        cartilage,
        ligament,
        muscle,
        tendon,
        SKIN,
        8,
        8,
        8,
        skin_paint=assets.materials.add(skin_phong()),
    )
    assert_equal(len(painted.meshes), 3)
    with assert_raises(contains="named layer set"):
        _ = add_body(
            scene,
            assets,
            root,
            person,
            bone,
            cartilage,
            cartilage,
            ligament,
            muscle,
            tendon,
            TorsoContents(0),
        )


def test_body_skin_is_one_surface() raises:
    var person = _person()
    var field = BodySkinField(person)
    var f = torso_dimensions(person.stature, MALE).frame
    # The chest, the waist, the hips and a knee are all inside.
    assert_true(field.distance(f.at(0, 38.0, 0)) < 0)
    assert_true(field.distance(f.at(0, 14.5, 0)) < 0)
    assert_true(field.distance(Vector3(0, 0.02, 0)) < 0)
    assert_true(field.distance(Vector3(0, 0.02, 0.5)) > 0)
    assert_true(field.low.y < -0.8)
    assert_true(field.high.y > 0.5)
    assert_true(field.gradient(f.at(0, 14.5, 30.0)).z > 0.3)
    # Both arms are inside it, down to the wrists.
    var arm = arm_dimensions(person.stature, MALE).frame
    assert_true(field.distance(arm.elbow) < 0)
    assert_true(field.distance(flip_x(arm.elbow)) < 0)
    assert_true(field.distance(arm.upper(0, -15, 0)) < 0)
    assert_true(field.distance(flip_x(arm.fore(0, -12, 0))) < 0)
    assert_true(field.low.x < -arm.wrist.x and field.high.x > arm.wrist.x)
    with assert_raises():
        _ = body_skin_mesh(person, 7)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
