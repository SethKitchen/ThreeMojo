# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the stature-scaled pelvis and the lower body it joins."""

from core.assets import Assets
from core.buffer_geometry import POSITION
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import Athleticism
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_phong
from extensions.humanoid.skeleton.field import flip_x, mix_point, ud_triangle
from extensions.humanoid.skeleton.leg.assembly import assemble_leg
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    muscle_dimensions,
)
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
from extensions.humanoid.skeleton.pelvis.assembly import (
    add_pelvis,
    assemble_pelvis,
)
from extensions.humanoid.skeleton.pelvis.bones.dimensions import (
    COCCYX,
    FEMALE_ASIS_WIDTH,
    LEFT_HIP_BONE,
    MALE_ASIS_WIDTH,
    RIGHT_HIP_BONE,
    SACRUM,
    PelvisBone,
    PelvisBoneField,
    pelvis_bone_distance,
    pelvis_bone_label,
    pelvis_dimensions,
    pelvis_frame,
    named_pelvis_bones,
    sacral_back,
    sacral_front,
    sided,
    sided_bounds,
)
from extensions.humanoid.skeleton.pelvis.bones.geometry import (
    pelvis_bone,
    pelvis_bone_from_dimensions,
)
from extensions.humanoid.skeleton.pelvis.bones.mass import (
    pelvis_bone_mass,
    pelvis_bone_mass_from_dimensions,
    pelvis_bone_occupancy,
)
from extensions.humanoid.skeleton.pelvis.contents import (
    ALL,
    BONES,
    BOTH,
    LIGAMENTS,
    LYMPH,
    MUSCLES,
    NERVES,
    SKIN,
    VESSELS,
    PelvisContents,
)
from extensions.humanoid.skeleton.pelvis.ligaments.dimensions import (
    ACETABULAR_CARTILAGE,
    ACETABULAR_LABRUM,
    INGUINAL,
    INTERPUBIC_DISC,
    SACROTUBEROUS,
    PelvisLigament,
    PelvisLigamentField,
    abs_gap,
    is_midline,
    named_pelvis_ligaments,
    pelvis_ligament_distance,
    pelvis_ligament_label,
    pelvis_ligament_tissue,
)
from extensions.humanoid.skeleton.pelvis.ligaments.geometry import (
    pelvis_ligament,
)
from extensions.humanoid.skeleton.pelvis.ligaments.mass import (
    pelvis_ligament_mass,
    pelvis_ligament_mass_from_dimensions,
    pelvis_ligament_occupancy,
)
from extensions.humanoid.skeleton.pelvis.lower_body import (
    LowerBodySkinField,
    add_lower_body,
    lower_body_skin_mesh,
)
from extensions.humanoid.skeleton.pelvis.lymph.dimensions import (
    ILIAC_LYMPHATICS,
    SACRAL_NODES,
    PelvisLymph,
    PelvisLymphField,
    named_pelvis_lymph,
    pelvis_lymph_distance,
    pelvis_lymph_label,
)
from extensions.humanoid.skeleton.pelvis.lymph.geometry import pelvis_lymph
from extensions.humanoid.skeleton.pelvis.lymph.mass import (
    pelvis_lymph_mass,
    pelvis_lymph_mass_from_dimensions,
    pelvis_lymph_occupancy,
)
from extensions.humanoid.skeleton.pelvis.muscles.dimensions import (
    GEMELLI,
    ILIACUS,
    PIRIFORMIS,
    PSOAS_MAJOR,
    PelvisMuscle,
    PelvisMuscleField,
    max_f,
    named_pelvis_muscles,
    pelvis_muscle_dimensions,
    pelvis_muscle_distance,
    pelvis_muscle_label,
)
from extensions.humanoid.skeleton.pelvis.muscles.geometry import (
    pelvis_muscle,
)
from extensions.humanoid.skeleton.pelvis.muscles.mass import (
    pelvis_muscle_mass,
    pelvis_muscle_mass_from_dimensions,
    pelvis_muscle_occupancy,
)
from extensions.humanoid.skeleton.pelvis.nerves.dimensions import (
    PELVIC_FEMORAL_NERVE,
    SACRAL_PLEXUS,
    PelvisNerve,
    PelvisNerveField,
    named_pelvis_nerves,
    pelvis_nerve_distance,
    pelvis_nerve_label,
)
from extensions.humanoid.skeleton.pelvis.nerves.geometry import pelvis_nerve
from extensions.humanoid.skeleton.pelvis.nerves.mass import (
    pelvis_nerve_mass,
    pelvis_nerve_mass_from_dimensions,
    pelvis_nerve_occupancy,
)
from extensions.humanoid.skeleton.pelvis.skin.dimensions import (
    MALE_PELVIC_FAT,
    PelvisSkinField,
    pelvic_fat,
    pelvis_skin_distance,
)
from extensions.humanoid.skeleton.pelvis.skin.geometry import pelvis_skin_mesh
from extensions.humanoid.skeleton.pelvis.skin.mass import (
    pelvis_skin_mass,
    pelvis_skin_occupancy,
)
from extensions.humanoid.skeleton.pelvis.vessels.dimensions import (
    ABDOMINAL_AORTA,
    COMMON_ILIAC_VEIN,
    EXTERNAL_ILIAC_ARTERY,
    EXTERNAL_ILIAC_VEIN,
    INFERIOR_VENA_CAVA,
    PelvisVessel,
    PelvisVesselField,
    is_pelvic_artery,
    is_unpaired_vessel,
    named_pelvis_vessels,
    pelvis_vessel_distance,
    pelvis_vessel_label,
    vessel_landmarks,
)
from extensions.humanoid.skeleton.pelvis.vessels.geometry import pelvis_vessel
from extensions.humanoid.skeleton.pelvis.vessels.mass import (
    pelvis_vessel_mass,
    pelvis_vessel_mass_from_dimensions,
    pelvis_vessel_occupancy,
)
from extensions.humanoid.skeleton.tissue import (
    cortical_tissue,
    trabecular_tissue,
)
from extensions.humanoid.skeleton.soft_tissue import (
    CARTILAGE,
    LIGAMENT,
    MENISCUS,
    SOFT_FILL,
    arterial_tissue,
    lymph_tissue,
    muscle_tissue,
    nerve_tissue,
)
from math.vector3 import Vector3
from std.math import cos, nan, sin
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, KILOGRAM, Length, METER, MILLIMETER

comptime TOLERANCE = 1.0e-5
# Coarse grids keep the suite quick.
comptime COARSE = Length(10.0, MILLIMETER)


def _person() -> HumanoidSpec:
    """Return the six-foot male the suite measures."""
    return HumanoidSpec(Length(6.0, FOOT), MALE)


def _sides() -> List[BodySide]:
    """Return the right side, then the left."""
    var sides = List[BodySide]()
    sides.append(RIGHT)
    sides.append(LEFT)
    return sides^


def _local(point: Vector3, side: BodySide) -> Vector3:
    """Return a right-side point moved to `side`."""
    if side == LEFT:
        return flip_x(point)
    return point


def test_hip_joint_centers_follow_harrington() raises:
    var person = _person()
    var S = person.stature.value
    var dims = pelvis_dimensions(person.stature, MALE)
    assert_almost_equal(dims.breadth.value, MALE_ASIS_WIDTH * S, atol=TOLERANCE)
    # Harrington's regression puts the joint centers about 17 cm apart
    # for a six-foot male.
    assert_true(dims.hip_span.value > 0.16 and dims.hip_span.value < 0.19)
    assert_almost_equal(dims.hip.x, 0.5 * dims.hip_span.value, atol=TOLERANCE)
    assert_equal(dims.hip.y, 0)
    # The anterior superior spine is above, in front of and lateral to
    # the joint center.
    assert_true(dims.asis.y > 0.07 and dims.asis.y < 0.10)
    assert_true(dims.asis.z > 0.04 and dims.asis.z < 0.06)
    assert_true(dims.asis.x > dims.hip.x)
    # The socket opens laterally, down and forward.
    assert_almost_equal(dims.socket_axis.length(), 1, atol=TOLERANCE)
    assert_true(dims.socket_axis.x > 0)
    assert_true(dims.socket_axis.y < 0)
    assert_true(dims.socket_axis.z > 0)
    # The crest is the top, the tuberosity near the bottom.
    assert_true(dims.crest_top.y > dims.asis.y)
    assert_true(dims.tuberosity.y < dims.symphysis_top.y)
    assert_true(dims.height.value > 0.19 and dims.height.value < 0.26)
    assert_true(dims.psis.z < dims.promontory.z)
    assert_equal(dims.promontory.x, 0)


def test_female_pelvis_is_wider_and_shorter() raises:
    var man = pelvis_dimensions(Length(6.0, FOOT), MALE)
    var woman = pelvis_dimensions(Length(6.0, FOOT), FEMALE)
    var S = woman.stature.value
    assert_almost_equal(
        woman.breadth.value, FEMALE_ASIS_WIDTH * S, atol=TOLERANCE
    )
    assert_true(woman.hip_span.value > man.hip_span.value)
    assert_true(woman.height.value < man.height.value)
    # The pubic arch is wider again.
    assert_true(woman.ramus.x / man.ramus.x > woman.tubercle.x / man.tubercle.x)
    assert_true(woman.sacral_bow < man.sacral_bow)


def test_pelvis_refuses_a_bad_spec_and_bad_edits() raises:
    with assert_raises():
        _ = pelvis_dimensions(Length(0.5, METER), MALE)
    with assert_raises():
        _ = pelvis_dimensions(Length(6.0, FOOT), Sex(9))
    var dims = pelvis_dimensions(Length(6.0, FOOT), MALE)
    var bent = dims
    bent.socket_axis = Vector3(0, 0, 0)
    with assert_raises(contains="unit vector"):
        bent.validate()
    bent.socket_axis = Vector3(2, 0, 0)
    with assert_raises(contains="unit vector"):
        bent.validate()
    var flat = dims
    flat.sacral_bow = -0.01
    with assert_raises(contains="sacral bow"):
        flat.validate()
    var lost = dims
    lost.coccyx_tip = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises():
        lost.validate()
    var narrow = dims
    narrow.breadth = Length(0.0, METER)
    with assert_raises():
        _ = PelvisBoneField(narrow, SACRUM)


def test_sides_mirror_on_x() raises:
    var dims = pelvis_dimensions(Length(6.0, FOOT), MALE)
    var left = dims.hip_center(LEFT)
    assert_equal(left.x, -dims.hip.x)
    assert_equal(dims.hip_center(RIGHT).x, dims.hip.x)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = sided(dims.hip, BodySide(5))
    var box = sided_bounds(Vector3(0.1, 0, 0), Vector3(0.2, 1, 1), LEFT)
    assert_equal(box.low.x, -0.2)
    assert_equal(box.high.x, -0.1)
    var same = sided_bounds(Vector3(0.1, 0, 0), Vector3(0.2, 1, 1), RIGHT)
    assert_equal(same.low.x, 0.1)


def test_frame_and_sacrum_helpers() raises:
    var dims = pelvis_dimensions(Length(6.0, FOOT), MALE)
    var woman = pelvis_dimensions(Length(6.0, FOOT), FEMALE)
    var male_frame = pelvis_frame(dims)
    var female_frame = pelvis_frame(woman)
    var male_point = male_frame.template(10, 10, 10)
    var female_point = female_frame.template(10, 10, 10)
    assert_true(female_point.x > male_point.x)
    assert_true(female_point.y < male_point.y)
    assert_equal(female_point.z, male_point.z)
    assert_true(female_frame.arched(0.1, 0, 0).x > female_frame.at(0.1, 0, 0).x)
    assert_equal(male_frame.midline(0.1, 0.1).x, 0)
    var front = sacral_front(dims, 0)
    assert_almost_equal(front.y, dims.promontory.y, atol=TOLERANCE)
    var apex = sacral_front(dims, 1)
    assert_almost_equal(apex.z, dims.sacral_apex.z, atol=TOLERANCE)
    var back = sacral_back(dims)
    assert_almost_equal(back.length(), 1, atol=TOLERANCE)
    assert_true(back.z < 0)
    # The middle of the front bows back behind the straight line.
    var middle = sacral_front(dims, 0.5)
    var chord = mix_point(dims.promontory, dims.sacral_apex, 0.5)
    assert_true(middle.z < chord.z)


def test_triangle_distance() raises:
    var a = Vector3(0, 0, 0)
    var b = Vector3(1, 0, 0)
    var c = Vector3(0, 1, 0)
    assert_almost_equal(
        ud_triangle(Vector3(0.2, 0.2, 0.5), a, b, c), 0.5, atol=TOLERANCE
    )
    assert_almost_equal(
        ud_triangle(Vector3(2, 0, 0), a, b, c), 1, atol=TOLERANCE
    )
    assert_almost_equal(
        ud_triangle(Vector3(-1, 0.5, 0), a, b, c), 1, atol=TOLERANCE
    )
    # A triangle that has collapsed to a line is still measured.
    assert_almost_equal(
        ud_triangle(Vector3(0.5, 1, 0), a, a, b), 1, atol=TOLERANCE
    )


def test_bones_are_solid_and_keep_their_joints_open() raises:
    var dims = pelvis_dimensions(Length(6.0, FOOT), MALE)
    var right = PelvisBoneField(dims, RIGHT_HIP_BONE)
    var left = PelvisBoneField(dims, LEFT_HIP_BONE)
    assert_true(right.distance(dims.tuberosity) < 0)
    assert_true(left.distance(flip_x(dims.tuberosity)) < 0)
    assert_almost_equal(
        right.distance(dims.crest_top),
        left.distance(flip_x(dims.crest_top)),
        atol=TOLERANCE,
    )
    assert_true(right.high.x > 0.1)
    assert_true(left.low.x < -0.1)
    # The femoral head's socket, the sacroiliac joint and the symphysis
    # are open.
    assert_true(right.distance(dims.hip) > 0)
    assert_true(right.distance(right.sacrum.c1) > 0)
    assert_true(right.distance(Vector3(0, dims.symphysis_top.y, 0)) > 0)
    var sacrum = PelvisBoneField(dims, SACRUM)
    assert_true(sacrum.distance(sacrum.sacrum.c1) < 0)
    assert_true(sacrum.distance(dims.hip) > 0)
    var coccyx = PelvisBoneField(dims, COCCYX)
    assert_true(coccyx.distance(coccyx.coccyx1) < 0)
    assert_true(coccyx.distance(dims.promontory) > 0)
    var normal = right.gradient(dims.crest_top + Vector3(0, 0.02, 0))
    assert_true(normal.y > 0.5)
    assert_true(pelvis_bone_distance(dims, SACRUM, Vector3(0, 1, 0)) > 0.5)
    with assert_raises(contains="four bones"):
        _ = PelvisBoneField(dims, PelvisBone(4))


def test_bones_are_named() raises:
    var bones = named_pelvis_bones()
    assert_equal(len(bones), 4)
    assert_false(PelvisBone(-1).is_valid())
    assert_false(PelvisBone(4).is_valid())
    assert_equal(pelvis_bone_label(RIGHT_HIP_BONE), "right hip bone")
    assert_equal(pelvis_bone_label(LEFT_HIP_BONE), "left hip bone")
    assert_equal(pelvis_bone_label(SACRUM), "sacrum")
    assert_equal(pelvis_bone_label(COCCYX), "coccyx")
    assert_equal(pelvis_bone_label(PelvisBone(9)), "pelvic bone")


def test_bone_meshes() raises:
    var person = _person()
    var bones = named_pelvis_bones()
    for index in range(len(bones)):
        var mesh = pelvis_bone(person, bones[index], 8)
        assert_true(mesh.has_attribute(String(POSITION)))
        assert_true(mesh.triangle_count() > 0)
    var dims = pelvis_dimensions(person.stature, MALE)
    with assert_raises(contains="four bones"):
        _ = pelvis_bone_from_dimensions(dims, PelvisBone(7), 8)
    with assert_raises():
        _ = pelvis_bone(person, SACRUM, 7)


def test_bone_mass() raises:
    var person = _person()
    var right = pelvis_bone_mass(person, RIGHT_HIP_BONE, COARSE)
    assert_true(right.mass.value > 0.15 and right.mass.value < 1.2)
    var sacrum = pelvis_bone_mass(person, SACRUM, COARSE)
    assert_true(sacrum.mass.value > 0.08 and sacrum.mass.value < 0.8)
    var coccyx = pelvis_bone_mass(person, COCCYX, Length(4.0, MILLIMETER))
    assert_true(coccyx.mass.value < 0.05)
    var dims = pelvis_dimensions(person.stature, MALE)
    assert_equal(
        pelvis_bone_occupancy(dims, RIGHT_HIP_BONE, dims.tuberosity),
        TRABECULAR_FILL,
    )
    var left = pelvis_bone_mass(person, LEFT_HIP_BONE, COARSE)
    assert_almost_equal(right.mass.value, left.mass.value, rtol=0.15)
    with assert_raises(contains="four bones"):
        _ = pelvis_bone_mass_from_dimensions(
            dims, PelvisBone(5), cortical_tissue(), trabecular_tissue()
        )
    with assert_raises():
        _ = pelvis_bone_mass(person, SACRUM, Length(1.0, MILLIMETER))


def test_muscle_dimensions_join_the_legs() raises:
    var person = _person()
    var dims = pelvis_muscle_dimensions(person)
    var leg = muscle_dimensions(person, RIGHT)
    var hip = dims.leg_origin_at(RIGHT) + leg.hip
    assert_almost_equal(hip.x, dims.pelvis.hip.x, atol=TOLERANCE)
    assert_almost_equal(hip.y, dims.pelvis.hip.y, atol=TOLERANCE)
    assert_almost_equal(hip.z, dims.pelvis.hip.z, atol=TOLERANCE)
    var left_leg = muscle_dimensions(person, LEFT)
    var left_hip = dims.leg_origin_at(LEFT) + left_leg.hip
    assert_almost_equal(left_hip.x, -dims.pelvis.hip.x, atol=TOLERANCE)
    assert_true(dims.gt.x > dims.pelvis.hip.x)
    assert_true(dims.lt.y < dims.pelvis.hip.y)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = dims.leg_origin_at(BodySide(3))
    with assert_raises(contains="athleticism"):
        _ = pelvis_muscle_dimensions(
            HumanoidSpec(Length(6.0, FOOT), MALE, Athleticism(4))
        )
    var edited = dims
    edited.athleticism = Athleticism(5)
    with assert_raises(contains="athleticism"):
        edited.validate()
    edited = dims
    edited.scale = 0
    with assert_raises(contains="radius scale"):
        edited.validate()
    edited = dims
    edited.k = 0
    with assert_raises(contains="blend radius"):
        edited.validate()
    edited = dims
    edited.epsilon = 0
    with assert_raises(contains="gradient step"):
        edited.validate()


def test_muscles_are_solid_on_both_sides() raises:
    var dims = pelvis_muscle_dimensions(_person())
    var parts = named_pelvis_muscles()
    assert_equal(len(parts), 14)
    var sides = _sides()
    for index in range(len(parts)):
        var right = PelvisMuscleField(dims, parts[index], RIGHT)
        var inside = right.chains.c0.p2
        assert_true(right.distance(inside) < 0)
        for s in range(2):
            var point = _local(inside, sides[s])
            assert_true(
                pelvis_muscle_distance(dims, parts[index], sides[s], point) < 0
            )
        assert_true(pelvis_muscle_label(parts[index]) != "pelvic muscle")
        var report = pelvis_muscle_mass_from_dimensions(
            dims, parts[index], muscle_tissue()
        )
        assert_true(report.mass.value > 0.0005)
        assert_true(report.mass.value < 1.5)
    var left = PelvisMuscleField(dims, PIRIFORMIS, LEFT)
    assert_true(left.high.x < 0)
    var normal = left.gradient(Vector3(0, 0, 0))
    assert_true(normal.length() > 0.5)
    assert_equal(
        pelvis_muscle_occupancy(
            dims,
            ILIACUS,
            RIGHT,
            PelvisMuscleField(dims, ILIACUS, RIGHT).chains.c1.p1,
        ),
        SOFT_FILL,
    )
    assert_false(PelvisMuscle(-1).is_valid())
    assert_false(PelvisMuscle(14).is_valid())
    assert_equal(pelvis_muscle_label(PelvisMuscle(20)), "pelvic muscle")
    with assert_raises(contains="named muscle"):
        _ = PelvisMuscleField(dims, PelvisMuscle(14), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = PelvisMuscleField(dims, ILIACUS, BodySide(4))
    assert_equal(max_f(1, 2), 2)
    assert_equal(max_f(3, 2), 3)
    # The psoas and the iliacus meet in one tendon at the lesser
    # trochanter.
    var psoas = PelvisMuscleField(dims, PSOAS_MAJOR, RIGHT)
    assert_true(
        PelvisMuscleField(dims, ILIACUS, RIGHT).distance(psoas.chains.c0.p4) < 0
    )
    var mesh = pelvis_muscle(_person(), GEMELLI, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(pelvis_muscle_mass(_person(), GEMELLI).mass.value > 0)


def test_ligaments_and_joint_tissues() raises:
    var dims = pelvis_muscle_dimensions(_person())
    var p = dims.pelvis
    var parts = named_pelvis_ligaments()
    assert_equal(len(parts), 12)
    for index in range(len(parts)):
        var part = parts[index]
        var field = PelvisLigamentField(dims, part, RIGHT)
        assert_true(field.volume() > 0)
        var report = pelvis_ligament_mass_from_dimensions(
            dims, part, pelvis_ligament_tissue(part)
        )
        assert_true(report.mass.value > 0)
        assert_true(pelvis_ligament_label(part) != "pelvic ligament")
        if part.value <= 8:
            assert_true(field.distance(field.segments.a0) < 0)
            var mirrored = PelvisLigamentField(dims, part, LEFT)
            assert_true(mirrored.distance(flip_x(field.segments.a0)) < 0)
            assert_false(is_midline(part))
    # The labrum rides the rim; the cartilage lines the socket but not
    # its bare fossa; the disc fills the symphysis.
    var axis = p.socket_axis
    var across = Vector3(axis.y, -axis.x, 0)
    across.normalize()
    var labrum = PelvisLigamentField(dims, ACETABULAR_LABRUM, RIGHT)
    assert_true(labrum.distance(p.hip + across * labrum.ring) < 0)
    var cartilage = PelvisLigamentField(dims, ACETABULAR_CARTILAGE, LEFT)
    var middle = 0.5 * (cartilage.inner + cartilage.outer)
    var slope = Float32(60) * Float32(3.14159265) / 180
    var lined = axis * (-cos(slope)) + across * sin(slope)
    assert_true(cartilage.distance(flip_x(p.hip + lined * middle)) < 0)
    assert_true(cartilage.distance(flip_x(p.hip - axis * middle)) > 0)
    var disc = PelvisLigamentField(dims, INTERPUBIC_DISC, LEFT)
    var center = mix_point(p.symphysis_top, p.symphysis_bottom, 0.5)
    assert_true(disc.distance(center) < 0)
    assert_true(is_midline(INTERPUBIC_DISC))
    assert_equal(
        pelvis_ligament_occupancy(dims, INTERPUBIC_DISC, RIGHT, center),
        SOFT_FILL,
    )
    assert_equal(pelvis_ligament_tissue(ACETABULAR_CARTILAGE).kind, CARTILAGE)
    assert_equal(pelvis_ligament_tissue(ACETABULAR_LABRUM).kind, MENISCUS)
    assert_equal(pelvis_ligament_tissue(INTERPUBIC_DISC).kind, MENISCUS)
    assert_equal(pelvis_ligament_tissue(INGUINAL).kind, LIGAMENT)
    assert_equal(abs_gap(-2), 2)
    assert_equal(abs_gap(2), 2)
    assert_true(
        pelvis_ligament_distance(dims, SACROTUBEROUS, RIGHT, p.tuberosity)
        < 0.02
    )
    assert_true(labrum.gradient(p.hip + across * labrum.ring).length() > 0.5)
    assert_false(PelvisLigament(-1).is_valid())
    assert_equal(pelvis_ligament_label(PelvisLigament(12)), "pelvic ligament")
    with assert_raises(contains="named ligament"):
        _ = PelvisLigamentField(dims, PelvisLigament(12), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = PelvisLigamentField(dims, INGUINAL, BodySide(2))
    with assert_raises(contains="named ligament"):
        _ = is_midline(PelvisLigament(13))
    with assert_raises(contains="named ligament"):
        _ = pelvis_ligament_tissue(PelvisLigament(13))
    var mesh = pelvis_ligament(_person(), ACETABULAR_LABRUM, RIGHT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(pelvis_ligament_mass(_person(), INGUINAL).mass.value > 0)


def test_vessels_join_the_aorta_and_the_legs() raises:
    var dims = pelvis_muscle_dimensions(_person())
    var parts = named_pelvis_vessels()
    assert_equal(len(parts), 13)
    var arteries = 0
    var unpaired = 0
    for index in range(len(parts)):
        var part = parts[index]
        if is_pelvic_artery(part):
            arteries += 1
        if is_unpaired_vessel(part):
            unpaired += 1
        var right = PelvisVesselField(dims, part, RIGHT)
        assert_true(right.distance(right.chain.p2) < 0)
        var left = PelvisVesselField(dims, part, LEFT)
        assert_true(pelvis_vessel_label(part) != "pelvic vessel")
        assert_true(
            pelvis_vessel_mass_from_dimensions(
                dims, part, arterial_tissue()
            ).mass.value
            > 0
        )
        if is_unpaired_vessel(part):
            assert_almost_equal(
                left.distance(right.chain.p2),
                right.distance(right.chain.p2),
                atol=TOLERANCE,
            )
        else:
            # A paired vessel mirrors; the left common iliac vein takes
            # its own path to the vena cava.
            assert_true(left.distance(flip_x(left.chain.p2)) < 0)
    assert_equal(arteries, 9)
    assert_equal(unpaired, 3)
    # Each external iliac vessel ends where the leg's femoral one starts.
    var artery = PelvisVesselField(dims, EXTERNAL_ILIAC_ARTERY, RIGHT)
    assert_equal(artery.chain.p4.y, dims.femoral_artery.y)
    var vein = PelvisVesselField(dims, EXTERNAL_ILIAC_VEIN, RIGHT)
    assert_equal(vein.chain.p4.z, dims.femoral_vein.z)
    # Both common iliac veins reach the vena cava right of the midline.
    var cava = PelvisVesselField(dims, INFERIOR_VENA_CAVA, LEFT)
    var right_join = PelvisVesselField(dims, COMMON_ILIAC_VEIN, RIGHT)
    var left_join = PelvisVesselField(dims, COMMON_ILIAC_VEIN, LEFT)
    assert_true(cava.chain.p0.x > 0)
    assert_almost_equal(
        flip_x(left_join.chain.p0).x, right_join.chain.p0.x, atol=TOLERANCE
    )
    var aorta = PelvisVesselField(dims, ABDOMINAL_AORTA, RIGHT)
    assert_true(aorta.chain.p0.x < 0)
    var marks = vessel_landmarks(dims.pelvis)
    assert_equal(marks.bifurcation.x, 0)
    var wide = right_join.widened(0.01)
    assert_equal(wide.chain.r2, 0.01)
    assert_true(wide.gradient(wide.chain.p2 + Vector3(0.02, 0, 0)).x > 0.5)
    assert_equal(
        pelvis_vessel_occupancy(dims, ABDOMINAL_AORTA, LEFT, aorta.chain.p2),
        SOFT_FILL,
    )
    assert_true(
        pelvis_vessel_distance(dims, ABDOMINAL_AORTA, RIGHT, Vector3(0, 1, 0))
        > 0
    )
    assert_false(PelvisVessel(-1).is_valid())
    assert_equal(pelvis_vessel_label(PelvisVessel(13)), "pelvic vessel")
    with assert_raises(contains="artery or vein"):
        _ = PelvisVesselField(dims, PelvisVessel(13), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = PelvisVesselField(dims, ABDOMINAL_AORTA, BodySide(2))
    with assert_raises(contains="artery or vein"):
        _ = is_pelvic_artery(PelvisVessel(14))
    with assert_raises(contains="artery or vein"):
        _ = is_unpaired_vessel(PelvisVessel(14))
    var mesh = pelvis_vessel(_person(), COMMON_ILIAC_VEIN, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    var artery_mass = pelvis_vessel_mass(_person(), ABDOMINAL_AORTA)
    var vein_mass = pelvis_vessel_mass(_person(), INFERIOR_VENA_CAVA)
    assert_true(artery_mass.mass.value > 0 and vein_mass.mass.value > 0)


def test_nerves_join_the_legs() raises:
    var dims = pelvis_muscle_dimensions(_person())
    var parts = named_pelvis_nerves()
    assert_equal(len(parts), 8)
    for index in range(len(parts)):
        var part = parts[index]
        var right = PelvisNerveField(dims, part, RIGHT)
        assert_true(right.distance(right.chain.p2) < 0)
        var left = PelvisNerveField(dims, part, LEFT)
        assert_true(left.distance(flip_x(right.chain.p2)) < 0)
        assert_true(pelvis_nerve_label(part) != "pelvic nerve")
        assert_true(
            pelvis_nerve_mass_from_dimensions(
                dims, part, nerve_tissue()
            ).mass.value
            > 0
        )
    var sciatic = PelvisNerveField(dims, SACRAL_PLEXUS, RIGHT)
    assert_equal(sciatic.chain.p4.x, dims.sciatic_nerve.x)
    var femoral = PelvisNerveField(dims, PELVIC_FEMORAL_NERVE, RIGHT)
    assert_equal(femoral.chain.p4.y, dims.femoral_nerve.y)
    var wide = femoral.widened(0.01)
    assert_equal(wide.chain.r0, 0.01)
    assert_true(wide.gradient(wide.chain.p2 + Vector3(0.02, 0, 0)).x > 0.5)
    assert_equal(
        pelvis_nerve_occupancy(dims, SACRAL_PLEXUS, RIGHT, sciatic.chain.p2),
        SOFT_FILL,
    )
    assert_true(
        pelvis_nerve_distance(dims, SACRAL_PLEXUS, LEFT, Vector3(0, 1, 0)) > 0
    )
    assert_false(PelvisNerve(-1).is_valid())
    assert_equal(pelvis_nerve_label(PelvisNerve(8)), "pelvic nerve")
    with assert_raises(contains="named nerve"):
        _ = PelvisNerveField(dims, PelvisNerve(8), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = PelvisNerveField(dims, SACRAL_PLEXUS, BodySide(2))
    var mesh = pelvis_nerve(_person(), SACRAL_PLEXUS, RIGHT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(pelvis_nerve_mass(_person(), SACRAL_PLEXUS).mass.value > 0)


def test_lymph_follows_the_vessels() raises:
    var dims = pelvis_muscle_dimensions(_person())
    var parts = named_pelvis_lymph()
    assert_equal(len(parts), 5)
    for index in range(len(parts)):
        var part = parts[index]
        var right = PelvisLymphField(dims, part, RIGHT)
        var inside = right.c0
        if part == ILIAC_LYMPHATICS:
            inside = right.chain.p2
        assert_true(right.distance(inside) < 0)
        var left = PelvisLymphField(dims, part, LEFT)
        assert_true(left.distance(flip_x(inside)) < 0)
        assert_true(right.volume() > 0)
        assert_true(pelvis_lymph_label(part) != "pelvic lymph")
        assert_true(
            pelvis_lymph_mass_from_dimensions(
                dims, part, lymph_tissue()
            ).mass.value
            > 0
        )
    var trunk = PelvisLymphField(dims, ILIAC_LYMPHATICS, RIGHT)
    assert_equal(trunk.chain.p0.y, dims.inguinal.y)
    var wide = trunk.widened(0.01)
    assert_equal(wide.chain.r1, 0.01)
    assert_true(wide.gradient(wide.chain.p2 + Vector3(0.02, 0, 0)).x > 0.5)
    var nodes = PelvisLymphField(dims, SACRAL_NODES, RIGHT)
    assert_equal(
        pelvis_lymph_occupancy(dims, SACRAL_NODES, RIGHT, nodes.c2), SOFT_FILL
    )
    assert_true(
        pelvis_lymph_distance(dims, SACRAL_NODES, LEFT, Vector3(0, 1, 0)) > 0
    )
    assert_false(PelvisLymph(-1).is_valid())
    assert_equal(pelvis_lymph_label(PelvisLymph(5)), "pelvic lymph")
    with assert_raises(contains="group or trunk"):
        _ = PelvisLymphField(dims, PelvisLymph(5), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = PelvisLymphField(dims, SACRAL_NODES, BodySide(2))
    var mesh = pelvis_lymph(_person(), ILIAC_LYMPHATICS, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(pelvis_lymph_mass(_person(), SACRAL_NODES).mass.value > 0)


def test_pelvic_skin_covers_the_bones() raises:
    var dims = pelvis_muscle_dimensions(_person())
    var p = dims.pelvis
    var skin = PelvisSkinField(dims)
    assert_true(skin.distance(Vector3(0, 0.02, 0)) < 0)
    assert_true(skin.distance(Vector3(0, 0.02, 0.5)) > 0)
    # The anterior superior spine lies under fat and dermis.
    assert_true(skin.distance(p.asis) < -0.5 * MALE_PELVIC_FAT)
    assert_true(skin.gradient(p.asis + Vector3(0, 0, 0.05)).z > 0.3)
    assert_true(pelvis_skin_distance(dims, Vector3(0, 0.02, 0)) < 0)
    assert_equal(skin.subcutaneous, pelvic_fat(MALE))
    assert_true(pelvic_fat(FEMALE) > pelvic_fat(MALE))
    var mesh = pelvis_skin_mesh(_person(), 8)
    assert_true(mesh.triangle_count() > 0)
    var report = pelvis_skin_mass(_person(), Length(12.0, MILLIMETER))
    assert_true(report.mass.value > 0 and report.mass.value < 5.0)
    assert_equal(pelvis_skin_occupancy(dims, Vector3(0, 0.02, 0)).value, 0)


def test_contents_bits() raises:
    assert_true(BONES.includes_bones())
    assert_false(BONES.includes_ligaments())
    assert_true(LIGAMENTS.includes_ligaments())
    assert_true(MUSCLES.includes_muscles())
    assert_true(VESSELS.includes_vessels())
    assert_true(LYMPH.includes_lymph())
    assert_true(NERVES.includes_nerves())
    assert_true(SKIN.includes_skin())
    assert_equal(BONES.plus(LIGAMENTS).plus(MUSCLES).value, BOTH.value)
    assert_true(ALL.includes_skin())
    assert_false(PelvisContents(0).is_valid())
    assert_false(PelvisContents(128).is_valid())
    var bad = PelvisContents(0)
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


def test_add_pelvis_places_every_layer() raises:
    var person = _person()
    var pose = assemble_pelvis(person)
    assert_equal(pose.hip_center(LEFT).x, -pose.bones.hip.x)
    assert_equal(pose.leg_origin(LEFT).x, -pose.leg_origin(RIGHT).x)
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var bone = assets.materials.add(bone_phong())
    var ligament = assets.materials.add(ligament_phong())
    var cartilage = assets.materials.add(cartilage_phong())
    var muscle = assets.materials.add(muscle_phong())
    var node = add_pelvis(
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
        Vector3(0.01, 0.9, 0),
    )
    # Four bones, twenty-three joint parts, twenty-eight muscles,
    # twenty-three vessels, ten lymph solids, sixteen nerves, one skin.
    assert_equal(len(scene.meshes), 105)
    scene.update()
    var origin = scene.world_matrix(node).transform_point(Vector3(0, 0, 0))
    assert_almost_equal(origin.y, Float32(0.9), atol=TOLERANCE)
    with assert_raises(contains="named layer set"):
        _ = add_pelvis(
            scene,
            assets,
            root,
            person,
            bone,
            ligament,
            cartilage,
            muscle,
            PelvisContents(0),
        )
    with assert_raises():
        _ = add_pelvis(
            scene,
            assets,
            root,
            person,
            bone,
            ligament,
            cartilage,
            muscle,
            BONES,
            7,
        )


def test_add_lower_body_joins_pelvis_legs_and_feet() raises:
    var person = _person()
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var bone = assets.materials.add(bone_phong())
    var cartilage = assets.materials.add(cartilage_phong())
    var ligament = assets.materials.add(ligament_phong())
    var muscle = assets.materials.add(muscle_phong())
    var tendon = assets.materials.add(tendon_phong())
    # Lymph only, with every look given: the pelvis, both legs and both
    # feet each draw theirs.
    _ = add_lower_body(
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
        8,
        Vector3(0, 0, 0),
        assets.materials.add(artery_phong()),
        assets.materials.add(vein_phong()),
        assets.materials.add(lymph_phong()),
        assets.materials.add(nerve_phong()),
    )
    # Ten pelvic solids, four in each leg and four in each foot.
    assert_equal(len(scene.meshes), 26)
    # Skin only: the pelvis, the legs and the feet draw nothing else.
    var skinned = Scene()
    var skin_root = skinned.add(Object3D())
    _ = add_lower_body(
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
        skin_paint=assets.materials.add(skin_phong()),
    )
    assert_equal(len(skinned.meshes), 1)
    with assert_raises(contains="named layer set"):
        _ = add_lower_body(
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
            PelvisContents(0),
        )


def test_lower_body_skin_is_one_surface() raises:
    var person = _person()
    var field = LowerBodySkinField(person)
    var dims = pelvis_muscle_dimensions(person)
    # The hip joint centers, a knee and the groin are all inside.
    assert_true(field.distance(dims.pelvis.hip) < 0)
    assert_true(field.distance(flip_x(dims.pelvis.hip)) < 0)
    assert_true(field.distance(dims.leg_origin_at(RIGHT)) < 0)
    assert_true(field.distance(Vector3(0, 0.02, 0)) < 0)
    # The knees may touch, but the ankles stand apart.
    var ankle = dims.leg_origin_at(RIGHT) + assemble_leg(person).ankle_center()
    assert_true(field.distance(Vector3(0, ankle.y, ankle.z)) > 0)
    assert_true(field.low.y < dims.leg_origin_at(RIGHT).y - 0.3)
    assert_true(field.gradient(Vector3(0, 0.02, 0.4)).z > 0.3)
    with assert_raises():
        _ = lower_body_skin_mesh(person, 7)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
