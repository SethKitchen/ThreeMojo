# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the stature-scaled neck and head: the frame, the bones, the
joint tissues and cartilages, the muscles, the vessels, the nerves, the
lymph nodes, the skin and the hair."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import Athleticism
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.side import LEFT, RIGHT, BodySide
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.head.assembly import add_head
from extensions.humanoid.skeleton.head.bones.dimensions import (
    C1,
    C2,
    C3,
    C7,
    HYOID,
    MANDIBLE,
    SKULL,
    TEETH,
    HeadBone,
    head_bone_distance,
    head_bone_field,
    head_bone_label,
    named_head_bones,
)
from extensions.humanoid.skeleton.head.bones.geometry import (
    head_bone,
    head_bone_from_dimensions,
)
from extensions.humanoid.skeleton.head.bones.mass import (
    head_bone_mass,
    head_bone_mass_from_dimensions,
    head_bone_occupancy,
)
from extensions.humanoid.skeleton.head.contents import (
    ALL,
    BONES,
    EYES,
    HAIR,
    LIGAMENTS,
    LYMPH,
    MUSCLES,
    NERVES,
    SKIN,
    VESSELS,
    HeadContents,
)
from extensions.humanoid.skeleton.head.frame import (
    CERVICAL,
    HeadMuscleDimensions,
    head_dimensions,
    head_muscle_dimensions,
)
from extensions.humanoid.skeleton.head.hair.dimensions import (
    EYEBROWS,
    SCALP_HAIR,
    HeadHair,
    head_hair_distance,
    head_hair_field,
    head_hair_label,
    is_paired_head_hair,
    named_head_hair,
)
from extensions.humanoid.skeleton.head.hair.geometry import (
    head_hair,
    head_hair_from_dimensions,
)
from extensions.humanoid.skeleton.head.hair.mass import (
    head_hair_mass,
    head_hair_mass_from_dimensions,
)
from extensions.humanoid.skeleton.head.ligaments.dimensions import (
    ATLANTO_OCCIPITAL_JOINTS,
    CERVICAL_DISCS,
    LARYNX,
    NUCHAL_LIGAMENT,
    TEMPOROMANDIBULAR_JOINT,
    TRACHEA,
    HeadLigament,
    head_ligament_distance,
    head_ligament_field,
    head_ligament_label,
    head_ligament_tissue,
    is_head_cartilage,
    is_paired_head_ligament,
    named_head_ligaments,
)
from extensions.humanoid.skeleton.head.ligaments.geometry import (
    head_ligament,
    head_ligament_from_dimensions,
)
from extensions.humanoid.skeleton.head.ligaments.mass import (
    head_ligament_mass,
    head_ligament_mass_from_dimensions,
    head_ligament_occupancy,
)
from extensions.humanoid.skeleton.head.lymph.dimensions import (
    DEEP_CERVICAL_NODES,
    SUBMANDIBULAR_NODES,
    HeadLymph,
    head_lymph_distance,
    head_lymph_field,
    head_lymph_label,
    named_head_lymph,
)
from extensions.humanoid.skeleton.head.lymph.geometry import (
    head_lymph,
    head_lymph_from_dimensions,
)
from extensions.humanoid.skeleton.head.lymph.mass import (
    head_lymph_mass,
    head_lymph_mass_from_dimensions,
    head_lymph_occupancy,
)
from extensions.humanoid.skeleton.head.muscles.dimensions import (
    MASSETER,
    ORBICULARIS_ORIS,
    STERNOCLEIDOMASTOID,
    SUPRAHYOID,
    HeadMuscle,
    head_muscle_distance,
    head_muscle_field,
    head_muscle_label,
    head_muscle_paths,
    is_paired_head_muscle,
    named_head_muscles,
)
from extensions.humanoid.skeleton.head.muscles.geometry import (
    head_muscle,
    head_muscle_from_dimensions,
)
from extensions.humanoid.skeleton.head.muscles.mass import (
    head_muscle_mass,
    head_muscle_mass_from_dimensions,
    head_muscle_occupancy,
)
from extensions.humanoid.skeleton.head.nerves.dimensions import (
    CERVICAL_SPINAL_CORD,
    VAGUS_NERVE,
    HeadNerve,
    head_nerve_distance,
    head_nerve_field,
    head_nerve_label,
    is_paired_head_nerve,
    named_head_nerves,
)
from extensions.humanoid.skeleton.head.nerves.geometry import (
    head_nerve,
    head_nerve_from_dimensions,
)
from extensions.humanoid.skeleton.head.nerves.mass import (
    head_nerve_mass,
    head_nerve_mass_from_dimensions,
    head_nerve_occupancy,
)
from extensions.humanoid.skeleton.head.skin.dimensions import (
    HeadSkinField,
    HeadSkinLayerField,
    head_skin_distance,
)
from extensions.humanoid.skeleton.head.skin.geometry import (
    head_skin_from_dimensions,
    head_skin_mesh,
)
from extensions.humanoid.skeleton.head.skin.mass import (
    head_skin_mass,
    head_skin_mass_from_dimensions,
    head_skin_occupancy,
)
from extensions.humanoid.skeleton.head.vessels.dimensions import (
    COMMON_CAROTID_ARTERY,
    INTERNAL_JUGULAR_VEIN,
    HeadVessel,
    head_vessel_distance,
    head_vessel_field,
    head_vessel_label,
    is_head_artery,
    named_head_vessels,
)
from extensions.humanoid.skeleton.head.vessels.geometry import (
    head_vessel,
    head_vessel_from_dimensions,
)
from extensions.humanoid.skeleton.head.vessels.mass import (
    head_vessel_mass,
    head_vessel_mass_from_dimensions,
    head_vessel_occupancy,
)
from extensions.humanoid.skeleton.occupancy import (
    CORTICAL_FILL,
    EMPTY,
    TRABECULAR_FILL,
)
from extensions.humanoid.skeleton.soft_tissue import (
    SOFT_EMPTY,
    SOFT_FILL,
    cartilage_tissue,
    hair_tissue,
    ligament_tissue,
    lymph_tissue,
    meniscus_tissue,
    muscle_tissue,
    nerve_tissue,
    skin_tissue,
)
from extensions.humanoid.skeleton.tissue import (
    cortical_tissue,
    trabecular_tissue,
)
from materials.material import MaterialId
from math.vector3 import Vector3
from std.math import nan
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length, METER, MILLIMETER

comptime COARSE = Length(10.0, MILLIMETER)


def _person() -> HumanoidSpec:
    """Return the six-foot male template."""
    return HumanoidSpec(Length(6.0, FOOT), MALE)


def test_the_neck_climbs_from_t1_to_the_skull() raises:
    var dims = head_dimensions(Length(6.0, FOOT), MALE)
    dims.validate()
    assert_equal(len(dims.centers), CERVICAL)
    # Each vertebra stands above the one below it, and C7 above T1.
    for index in range(CERVICAL - 1):  # pragma: no branch
        assert_true(dims.centers[index].y > dims.centers[index + 1].y)
    assert_true(dims.centers[CERVICAL - 1].y > dims.torso.centers[0].y)
    # A hundred template centimeters is a meter on the six-foot template.
    assert_true(abs(dims.cm(100) - 1.0) < 0.001)
    assert_true(abs(dims.at(0, 84.4, 0).y - dims.frame.at(0, 84.4, 0).y) < 1e-6)
    # A woman's neck is narrower.
    var woman = head_dimensions(Length(6.0, FOOT), FEMALE)
    assert_true(woman.widths[3] < dims.widths[3])


def test_the_head_refuses_bad_input() raises:
    with assert_raises():
        _ = head_dimensions(Length(0.5, METER), MALE)
    var dims = head_dimensions(Length(6.0, FOOT), MALE)
    var bad = dims.copy()
    _ = bad.centers.pop()
    with assert_raises(contains="seven"):
        bad.validate()
    bad = dims.copy()
    _ = bad.widths.pop()
    with assert_raises(contains="seven"):
        bad.validate()
    bad = dims.copy()
    _ = bad.depths.pop()
    with assert_raises(contains="seven"):
        bad.validate()
    bad = dims.copy()
    _ = bad.heights.pop()
    with assert_raises(contains="seven"):
        bad.validate()
    bad = dims.copy()
    bad.centers[2] = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises():
        bad.validate()
    bad = dims.copy()
    bad.widths[1] = 0
    with assert_raises(contains="positive"):
        bad.validate()
    bad = dims.copy()
    bad.depths[1] = 0
    with assert_raises(contains="positive"):
        bad.validate()
    bad = dims.copy()
    bad.heights[1] = 0
    with assert_raises(contains="positive"):
        bad.validate()
    with assert_raises(contains="athleticism"):
        _ = head_muscle_dimensions(
            HumanoidSpec(Length(6.0, FOOT), MALE, Athleticism(4))
        )
    with assert_raises():
        _ = HeadMuscleDimensions(dims.copy(), Athleticism(9))
    var muscles = head_muscle_dimensions(_person())
    var edited = muscles.copy()
    edited.scale = 0
    with assert_raises(contains="scale"):
        edited.validate()
    edited = muscles.copy()
    edited.athleticism = Athleticism(5)
    with assert_raises(contains="athleticism"):
        edited.validate()


def test_bones_are_named_and_solid() raises:
    var dims = head_dimensions(Length(6.0, FOOT), MALE)
    var bones = named_head_bones()
    assert_equal(len(bones), 11)
    assert_equal(head_bone_label(C1), "atlas")
    assert_equal(head_bone_label(C2), "axis")
    assert_equal(head_bone_label(C3), "C3")
    assert_equal(head_bone_label(C7), "C7")
    assert_equal(head_bone_label(SKULL), "skull")
    assert_equal(head_bone_label(MANDIBLE), "mandible")
    assert_equal(head_bone_label(TEETH), "teeth")
    assert_equal(head_bone_label(HYOID), "hyoid")
    assert_equal(head_bone_label(HeadBone(11)), "head bone")
    assert_equal(head_bone_label(HeadBone(-1)), "head bone")
    assert_false(HeadBone(-1).is_valid())
    for index in range(len(bones)):  # pragma: no branch
        var field = head_bone_field(dims, bones[index])
        assert_true(field.high.y > field.low.y)
    # The vault's shell, the atlas's lateral mass, the chin, the front
    # teeth and the hyoid's body are bone; the orbit is not.
    assert_true(head_bone_distance(dims, SKULL, dims.at(0, 83.9, -1.0)) < 0)
    assert_true(head_bone_distance(dims, SKULL, dims.at(0, 75.4, -1.0)) > 0)
    assert_true(head_bone_distance(dims, SKULL, dims.at(3.2, 71.9, 8.4)) > 0)
    assert_true(head_bone_distance(dims, C1, dims.at(1.6, 65.6, -2.1)) < 0)
    assert_true(head_bone_distance(dims, MANDIBLE, dims.at(0, 61.9, 7.7)) < 0)
    assert_true(head_bone_distance(dims, TEETH, dims.at(0, 65.1, 7.0)) < 0)
    assert_true(head_bone_distance(dims, HYOID, dims.at(0, 59.2, 4.3)) < 0)
    # The axis's dens rises into the atlas's ring.
    assert_true(head_bone_distance(dims, C2, dims.at(0, 66.0, -1.8)) < 0)
    with assert_raises(contains="cervical"):
        _ = head_bone_field(dims, HeadBone(11))
    var short = dims.copy()
    _ = short.centers.pop()
    with assert_raises():
        _ = head_bone_field(short, SKULL)
    var mesh = head_bone(_person(), C3, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(head_bone_from_dimensions(dims, HYOID, 8).triangle_count() > 0)
    with assert_raises():
        _ = head_bone_from_dimensions(dims, C7, 7)


def test_bone_mass() raises:
    var person = _person()
    var skull = head_bone_mass(person, SKULL, COARSE)
    assert_true(skull.mass.value > 0.3 and skull.mass.value < 2.5)
    var dims = head_dimensions(person.stature, MALE)
    var atlas = head_bone_mass_from_dimensions(
        dims, C1, cortical_tissue(), trabecular_tissue(), COARSE
    )
    assert_true(atlas.mass.value > 0.002 and atlas.mass.value < 0.2)
    assert_equal(
        head_bone_occupancy(dims, SKULL, dims.at(0, 75.4, -1.0)), EMPTY
    )
    assert_equal(
        head_bone_occupancy(dims, MANDIBLE, dims.at(0, 61.9, 7.7)),
        TRABECULAR_FILL,
    )
    var shell = head_bone_occupancy(dims, SKULL, dims.at(0, 83.9, -1.0))
    assert_true(shell == CORTICAL_FILL or shell == TRABECULAR_FILL)
    with assert_raises():
        _ = head_bone_mass(person, SKULL, Length(1.0, MILLIMETER))


def test_ligaments_and_cartilages() raises:
    var dims = head_dimensions(Length(6.0, FOOT), MALE)
    var parts = named_head_ligaments()
    assert_equal(len(parts), 6)
    for index in range(len(parts)):  # pragma: no branch
        var part = parts[index]
        assert_true(head_ligament_label(part) != "head ligament")
        var right = head_ligament_field(dims, part, RIGHT)
        var left = head_ligament_field(dims, part, LEFT)
        assert_true(right.high.y > right.low.y and left.high.y > left.low.y)
        var report = head_ligament_mass_from_dimensions(
            dims, part, head_ligament_tissue(part)
        )
        assert_true(report.mass.value > 0 and report.mass.value < 0.2)
    assert_equal(head_ligament_label(HeadLigament(6)), "head ligament")
    assert_true(is_paired_head_ligament(TEMPOROMANDIBULAR_JOINT))
    assert_false(is_paired_head_ligament(LARYNX))
    assert_true(is_head_cartilage(TRACHEA))
    assert_true(is_head_cartilage(CERVICAL_DISCS))
    assert_false(is_head_cartilage(NUCHAL_LIGAMENT))
    assert_false(is_head_cartilage(ATLANTO_OCCIPITAL_JOINTS))
    assert_equal(
        head_ligament_tissue(CERVICAL_DISCS).wet_density.value,
        meniscus_tissue().wet_density.value,
    )
    assert_equal(
        head_ligament_tissue(TEMPOROMANDIBULAR_JOINT).wet_density.value,
        meniscus_tissue().wet_density.value,
    )
    assert_equal(
        head_ligament_tissue(LARYNX).wet_density.value,
        cartilage_tissue().wet_density.value,
    )
    assert_equal(
        head_ligament_tissue(TRACHEA).wet_density.value,
        cartilage_tissue().wet_density.value,
    )
    assert_equal(
        head_ligament_tissue(NUCHAL_LIGAMENT).wet_density.value,
        ligament_tissue().wet_density.value,
    )
    # The disc between C3 and C4, the jaw joint over the condyle, and
    # the trachea in the midline.
    var c3 = dims.centers[2]
    var c4 = dims.centers[3]
    var disc = Vector3(0, 0.5 * (c3.y + c4.y), 0.5 * (c3.z + c4.z))
    assert_true(head_ligament_distance(dims, CERVICAL_DISCS, RIGHT, disc) < 0)
    assert_true(
        head_ligament_distance(
            dims, TEMPOROMANDIBULAR_JOINT, LEFT, dims.at(-5.0, 71.4, 0.2)
        )
        < 0
    )
    assert_equal(
        head_ligament_occupancy(dims, TRACHEA, RIGHT, dims.at(0, 52.0, 2.0)),
        SOFT_FILL,
    )
    assert_true(head_ligament_mass(_person(), LARYNX).mass.value > 0)
    with assert_raises(contains="named part"):
        _ = head_ligament_field(dims, HeadLigament(6), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = head_ligament_field(dims, LARYNX, BodySide(4))
    with assert_raises():
        _ = is_paired_head_ligament(HeadLigament(-2))
    with assert_raises():
        _ = is_head_cartilage(HeadLigament(-2))
    with assert_raises():
        _ = head_ligament_tissue(HeadLigament(-2))
    var mesh = head_ligament(_person(), TEMPOROMANDIBULAR_JOINT, LEFT, 8)
    assert_true(mesh.triangle_count() > 0)
    assert_true(
        head_ligament_from_dimensions(dims, LARYNX, RIGHT, 8).triangle_count()
        > 0
    )


def test_muscles() raises:
    var dims = head_muscle_dimensions(_person())
    var parts = named_head_muscles()
    assert_equal(len(parts), 15)
    for index in range(len(parts)):  # pragma: no branch
        var part = parts[index]
        assert_true(head_muscle_label(part) != "head muscle")
        var right = head_muscle_field(dims, part, RIGHT)
        var left = head_muscle_field(dims, part, LEFT)
        assert_true(right.high.y > right.low.y and left.high.y > left.low.y)
        var report = head_muscle_mass_from_dimensions(
            dims, part, muscle_tissue()
        )
        assert_true(report.mass.value > 0.0005 and report.mass.value < 0.5)
    assert_equal(head_muscle_label(HeadMuscle(15)), "head muscle")
    assert_false(is_paired_head_muscle(SUPRAHYOID))
    assert_false(is_paired_head_muscle(ORBICULARIS_ORIS))
    assert_true(is_paired_head_muscle(MASSETER))
    # The masseter lies on the ramus; the sternocleidomastoid crosses
    # the neck.
    var h = dims.head.copy()
    assert_true(
        head_muscle_distance(dims, MASSETER, RIGHT, h.at(5.7, 66.8, 1.2)) < 0
    )
    assert_true(
        head_muscle_distance(dims, MASSETER, LEFT, h.at(-5.7, 66.8, 1.2)) < 0
    )
    assert_equal(
        head_muscle_occupancy(
            dims, STERNOCLEIDOMASTOID, RIGHT, h.at(3.9, 60.5, 1.9)
        ),
        SOFT_FILL,
    )
    assert_equal(
        head_muscle_occupancy(dims, MASSETER, RIGHT, h.at(0, 84.0, 0)),
        SOFT_EMPTY,
    )
    assert_true(head_muscle_mass(_person(), MASSETER).mass.value > 0.005)
    with assert_raises():
        _ = head_muscle_paths(HeadMuscle(15))
    with assert_raises():
        _ = is_paired_head_muscle(HeadMuscle(-1))
    with assert_raises(contains="named muscle"):
        _ = head_muscle_field(dims, HeadMuscle(15), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = head_muscle_field(dims, MASSETER, BodySide(4))
    assert_true(head_muscle(_person(), MASSETER, RIGHT, 8).triangle_count() > 0)
    assert_true(
        head_muscle_from_dimensions(
            dims, ORBICULARIS_ORIS, RIGHT, 8
        ).triangle_count()
        > 0
    )


def test_vessels() raises:
    var dims = head_muscle_dimensions(_person())
    var parts = named_head_vessels()
    assert_equal(len(parts), 6)
    for index in range(len(parts)):  # pragma: no branch
        var part = parts[index]
        assert_true(head_vessel_label(part) != "head vessel")
        var right = head_vessel_field(dims, part, RIGHT)
        var left = head_vessel_field(dims, part, LEFT)
        assert_true(right.high.x > 0 and left.low.x < 0)
        var report = head_vessel_mass_from_dimensions(
            dims, part, muscle_tissue()
        )
        assert_true(report.mass.value > 0 and report.mass.value < 0.1)
    assert_equal(head_vessel_label(HeadVessel(6)), "head vessel")
    assert_false(HeadVessel(-1).is_valid())
    assert_true(is_head_artery(COMMON_CAROTID_ARTERY))
    assert_false(is_head_artery(INTERNAL_JUGULAR_VEIN))
    var h = dims.head.copy()
    assert_true(
        head_vessel_distance(
            dims, COMMON_CAROTID_ARTERY, RIGHT, h.at(1.9, 52.0, 1.4)
        )
        < 0
    )
    assert_equal(
        head_vessel_occupancy(
            dims, INTERNAL_JUGULAR_VEIN, LEFT, h.at(-3.1, 59.0, 1.3)
        ),
        SOFT_FILL,
    )
    assert_true(
        head_vessel_mass(_person(), COMMON_CAROTID_ARTERY).mass.value > 0
    )
    assert_true(
        head_vessel_mass(_person(), INTERNAL_JUGULAR_VEIN).mass.value > 0
    )
    with assert_raises():
        _ = is_head_artery(HeadVessel(6))
    with assert_raises(contains="named artery"):
        _ = head_vessel_field(dims, HeadVessel(6), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = head_vessel_field(dims, COMMON_CAROTID_ARTERY, BodySide(4))
    assert_true(
        head_vessel(_person(), INTERNAL_JUGULAR_VEIN, RIGHT, 8).triangle_count()
        > 0
    )
    assert_true(
        head_vessel_from_dimensions(
            dims, COMMON_CAROTID_ARTERY, LEFT, 8
        ).triangle_count()
        > 0
    )


def test_nerves() raises:
    var dims = head_muscle_dimensions(_person())
    var parts = named_head_nerves()
    assert_equal(len(parts), 5)
    for index in range(len(parts)):  # pragma: no branch
        var part = parts[index]
        assert_true(head_nerve_label(part) != "head nerve")
        var right = head_nerve_field(dims, part, RIGHT)
        var left = head_nerve_field(dims, part, LEFT)
        assert_true(right.high.y > right.low.y and left.high.y > left.low.y)
        var report = head_nerve_mass_from_dimensions(dims, part, nerve_tissue())
        assert_true(report.mass.value > 0 and report.mass.value < 0.1)
    assert_equal(head_nerve_label(HeadNerve(5)), "head nerve")
    assert_false(HeadNerve(-1).is_valid())
    assert_false(is_paired_head_nerve(CERVICAL_SPINAL_CORD))
    assert_true(is_paired_head_nerve(VAGUS_NERVE))
    var h = dims.head.copy()
    var canal = h.centers[3]
    assert_true(
        head_nerve_distance(
            dims,
            CERVICAL_SPINAL_CORD,
            LEFT,
            Vector3(0, canal.y, canal.z - h.depths[3] - h.cm(0.85)),
        )
        < 0
    )
    assert_equal(
        head_nerve_occupancy(dims, VAGUS_NERVE, RIGHT, h.at(0, 84.0, 0)),
        SOFT_EMPTY,
    )
    assert_true(head_nerve_mass(_person(), VAGUS_NERVE).mass.value > 0)
    with assert_raises():
        _ = is_paired_head_nerve(HeadNerve(5))
    with assert_raises(contains="named nerve"):
        _ = head_nerve_field(dims, HeadNerve(5), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = head_nerve_field(dims, VAGUS_NERVE, BodySide(4))
    assert_true(
        head_nerve(_person(), VAGUS_NERVE, LEFT, 8).triangle_count() > 0
    )
    assert_true(
        head_nerve_from_dimensions(
            dims, CERVICAL_SPINAL_CORD, RIGHT, 8
        ).triangle_count()
        > 0
    )


def test_lymph() raises:
    var dims = head_muscle_dimensions(_person())
    var parts = named_head_lymph()
    assert_equal(len(parts), 5)
    for index in range(len(parts)):  # pragma: no branch
        var part = parts[index]
        assert_true(head_lymph_label(part) != "head lymph")
        var right = head_lymph_field(dims, part, RIGHT)
        var left = head_lymph_field(dims, part, LEFT)
        assert_true(right.high.x > 0 and left.low.x < 0)
        var report = head_lymph_mass_from_dimensions(dims, part, lymph_tissue())
        assert_true(report.mass.value > 0 and report.mass.value < 0.05)
    assert_equal(head_lymph_label(HeadLymph(5)), "head lymph")
    assert_false(HeadLymph(-1).is_valid())
    var h = dims.head.copy()
    assert_true(
        head_lymph_distance(
            dims, DEEP_CERVICAL_NODES, RIGHT, h.at(3.6, 59.0, 1.6)
        )
        < 0
    )
    assert_equal(
        head_lymph_occupancy(
            dims, SUBMANDIBULAR_NODES, LEFT, h.at(-3.6, 61.9, 2.9)
        ),
        SOFT_FILL,
    )
    assert_true(head_lymph_mass(_person(), SUBMANDIBULAR_NODES).mass.value > 0)
    with assert_raises(contains="named group"):
        _ = head_lymph_field(dims, HeadLymph(5), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = head_lymph_field(dims, DEEP_CERVICAL_NODES, BodySide(4))
    assert_true(
        head_lymph(_person(), DEEP_CERVICAL_NODES, RIGHT, 8).triangle_count()
        > 0
    )
    assert_true(
        head_lymph_from_dimensions(
            dims, SUBMANDIBULAR_NODES, LEFT, 8
        ).triangle_count()
        > 0
    )


def test_skin() raises:
    var dims = head_muscle_dimensions(_person())
    var h = dims.head.copy()
    var skin = HeadSkinField(dims)
    # The top of the head is its stature; the brain case and the throat
    # are inside, the air in front of the nose outside.
    assert_true(abs(skin.distance(h.at(0, 84.4, -1.0))) < 0.004)
    assert_true(skin.distance(h.at(0, 75.0, -1.0)) < 0)
    assert_true(skin.distance(h.at(0, 57.0, 2.0)) < 0)
    assert_true(skin.distance(h.at(0, 68.0, 13.0)) > 0)
    # The nose's tip stands in front of the upper lip.
    assert_true(skin.distance(h.at(0, 68.7, 11.0)) < 0)
    var normal = skin.gradient(h.at(0, 84.4, -1.0))
    assert_true(normal.y > 0.8)
    assert_true(head_skin_distance(dims, h.at(0, 90.0, 0)) > 0)
    var layer = HeadSkinLayerField(dims)
    assert_true(layer.distance(h.at(0, 75.0, -1.0)) > 0)
    assert_equal(head_skin_occupancy(dims, h.at(0, 75.0, -1.0)), SOFT_EMPTY)
    var report = head_skin_mass_from_dimensions(dims, skin_tissue(), COARSE)
    assert_true(report.mass.value > 0.02 and report.mass.value < 1.0)
    assert_true(head_skin_mass(_person(), COARSE).mass.value > 0.02)
    assert_true(head_skin_mesh(_person(), 8).triangle_count() > 0)
    assert_true(head_skin_from_dimensions(dims, 8).triangle_count() > 0)
    with assert_raises():
        _ = head_skin_from_dimensions(dims, 7)


def test_hair() raises:
    var dims = head_muscle_dimensions(_person())
    var parts = named_head_hair()
    assert_equal(len(parts), 2)
    assert_equal(head_hair_label(SCALP_HAIR), "scalp hair")
    assert_equal(head_hair_label(EYEBROWS), "eyebrow")
    assert_equal(head_hair_label(HeadHair(2)), "head hair")
    assert_false(HeadHair(-1).is_valid())
    assert_true(is_paired_head_hair(EYEBROWS))
    assert_false(is_paired_head_hair(SCALP_HAIR))
    var h = dims.head.copy()
    # The crown is covered; the forehead below the hairline is not.
    assert_true(
        head_hair_distance(dims, SCALP_HAIR, RIGHT, h.at(0, 84.85, -1.0)) < 0
    )
    assert_true(
        head_hair_distance(dims, SCALP_HAIR, RIGHT, h.at(0, 76.0, 9.6)) > 0
    )
    # The left brow lies on the skin over the left eye: somewhere on a
    # line from in front of the face back into it.
    var inside = False
    for step in range(40):  # pragma: no branch
        var z = Float32(11.0) - Float32(step) * Float32(0.1)
        if head_hair_distance(dims, EYEBROWS, LEFT, h.at(-2.7, 74.5, z)) < 0:
            inside = True
    assert_true(inside)
    var scalp = head_hair_mass_from_dimensions(dims, SCALP_HAIR, hair_tissue())
    assert_true(scalp.mass.value > 0.01 and scalp.mass.value < 0.3)
    assert_true(head_hair_mass(_person(), EYEBROWS).mass.value > 0)
    with assert_raises():
        _ = is_paired_head_hair(HeadHair(2))
    with assert_raises(contains="scalp"):
        _ = head_hair_field(dims, HeadHair(2), RIGHT)
    with assert_raises(contains="RIGHT or LEFT"):
        _ = head_hair_field(dims, SCALP_HAIR, BodySide(4))
    assert_true(head_hair(_person(), EYEBROWS, RIGHT, 8).triangle_count() > 0)
    assert_true(
        head_hair_from_dimensions(dims, SCALP_HAIR, RIGHT, 8).triangle_count()
        > 0
    )


def test_contents_bits() raises:
    var every = ALL
    assert_true(every.includes_bones() and every.includes_ligaments())
    assert_true(every.includes_muscles() and every.includes_vessels())
    assert_true(every.includes_lymph() and every.includes_nerves())
    assert_true(every.includes_skin() and every.includes_hair())
    assert_false(BONES.includes_hair())
    assert_equal(BONES.plus(HAIR).value, 129)
    assert_false(HeadContents(0).is_valid())
    assert_false(HeadContents(512).is_valid())
    assert_true(every.includes_eyes())
    assert_false(SKIN.includes_eyes())
    assert_true(EYES.includes_eyes())
    with assert_raises():
        _ = HeadContents(0).includes_bones()
    with assert_raises():
        _ = BONES.plus(HeadContents(0))
    assert_equal(
        LIGAMENTS.plus(MUSCLES).plus(VESSELS).plus(LYMPH).plus(NERVES).value,
        62,
    )
    assert_true(SKIN.includes_skin())


def test_add_head_places_every_layer() raises:
    var assets = Assets()
    var scene = Scene()
    var root = scene.add(Object3D())
    var paint = MaterialId(0)
    _ = add_head(
        scene, assets, root, _person(), paint, paint, paint, paint, ALL, 8, 8
    )
    # 11 bones, 7 joint tissues, 28 muscles, 12 vessels, 9 nerves, 10
    # node groups, the skin, 3 hair groups and 2 eyes.
    assert_equal(len(scene.meshes), 83)
    var dressed = Scene()
    var top = dressed.add(Object3D())
    _ = add_head(
        dressed,
        assets,
        top,
        _person(),
        paint,
        paint,
        paint,
        paint,
        VESSELS.plus(SKIN),
        8,
        8,
        artery_paint=paint,
        vein_paint=paint,
        skin_paint=paint,
    )
    assert_equal(len(dressed.meshes), 13)
    with assert_raises(contains="named layer set"):
        _ = add_head(
            scene,
            assets,
            root,
            _person(),
            paint,
            paint,
            paint,
            paint,
            HeadContents(0),
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
