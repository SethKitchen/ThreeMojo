# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for stature-scaled leg muscles and athleticism."""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.athleticism import (
    TONED,
    UNTONED,
    Athleticism,
    radius_scale,
)
from extensions.humanoid.sex import FEMALE, MALE, Sex
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_phong
from extensions.humanoid.skeleton.leg.assembly import add_leg
from extensions.humanoid.skeleton.leg.contents import MUSCLES
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    ACHILLES_TENDON,
    ADDUCTOR_LONGUS,
    BICEPS_FEMORIS,
    EXTENSOR_DIGITORUM_LONGUS,
    GASTROCNEMIUS,
    GLUTEUS_MAXIMUS,
    GLUTEUS_MEDIUS,
    GRACILIS,
    ILIOTIBIAL_TRACT,
    PECTINEUS,
    PERONEUS_BREVIS,
    PERONEUS_LONGUS,
    RECTUS_FEMORIS,
    SARTORIUS,
    SEMIMEMBRANOSUS,
    SEMITENDINOSUS,
    SOLEUS,
    TENSOR_FASCIAE_LATAE,
    TIBIALIS_ANTERIOR,
    VASTUS_LATERALIS,
    VASTUS_MEDIALIS,
    MuscleField,
    MusclePart,
    is_tendon,
    muscle_dimensions,
    muscle_distance,
    muscle_part_label,
    named_muscle_parts,
)
from extensions.humanoid.skeleton.leg.muscles.geometry import (
    muscle_from_dimensions,
    muscle_mesh,
)
from extensions.humanoid.skeleton.leg.muscles.mass import (
    muscle_mass,
    muscle_mass_from_dimensions,
    muscle_occupancy,
)
from extensions.humanoid.skeleton.look import muscle_phong, tendon_phong
from extensions.humanoid.skeleton.occupancy import MAX_STEP
from extensions.humanoid.skeleton.soft_tissue import (
    MUSCLE,
    SOFT_EMPTY,
    SOFT_FILL,
    TENDON,
    SoftTissueKind,
    muscle_tissue,
    tendon_tissue,
)
from materials.material import PHONG
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
from units.si import (
    FOOT,
    GRAM,
    GRAM_PER_CUBIC_CENTIMETER,
    Length,
    MEGAPASCAL,
    MILLIMETER,
)

comptime TOLERANCE = Float64(1e-4)


def test_athleticism_is_valid() raises:
    assert_true(UNTONED.is_valid())
    assert_true(TONED.is_valid())
    assert_false(Athleticism(2).is_valid())
    assert_false(Athleticism(-1).is_valid())
    assert_almost_equal(radius_scale(UNTONED), Float32(0.80), atol=TOLERANCE)
    assert_almost_equal(radius_scale(TONED), Float32(1.25), atol=TOLERANCE)
    with assert_raises():
        _ = radius_scale(Athleticism(9))


def test_spec_defaults_to_untoned() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    assert_true(person.athleticism == UNTONED)
    var athlete = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    assert_true(athlete.athleticism == TONED)


def test_muscle_parts_are_named() raises:
    var parts = named_muscle_parts()
    assert_equal(len(parts), 21)
    var index = 0
    while index < len(parts):
        assert_true(parts[index].is_valid())
        var label = muscle_part_label(parts[index])
        assert_true(label.byte_length() > 0)
        index += 1
    assert_false(MusclePart(-1).is_valid())
    assert_false(MusclePart(21).is_valid())
    assert_equal(muscle_part_label(MusclePart(99)), "muscle")
    assert_true(is_tendon(ILIOTIBIAL_TRACT))
    assert_true(is_tendon(ACHILLES_TENDON))
    assert_false(is_tendon(RECTUS_FEMORIS))
    with assert_raises():
        _ = is_tendon(MusclePart(21))


def test_muscle_and_tendon_tissue() raises:
    assert_true(MUSCLE.is_valid())
    assert_true(TENDON.is_valid())
    var muscle = muscle_tissue()
    assert_true(muscle.kind == MUSCLE)
    assert_almost_equal(
        muscle.wet_density.to(GRAM_PER_CUBIC_CENTIMETER),
        Float32(1.06),
        atol=TOLERANCE,
    )
    assert_almost_equal(muscle.water_fraction, Float32(0.75), atol=TOLERANCE)
    assert_almost_equal(
        muscle.elastic_modulus.to(MEGAPASCAL), Float32(0.02), atol=TOLERANCE
    )
    var tendon = tendon_tissue()
    assert_true(tendon.kind == TENDON)
    assert_almost_equal(
        tendon.wet_density.to(GRAM_PER_CUBIC_CENTIMETER),
        Float32(1.12),
        atol=TOLERANCE,
    )


def test_every_named_muscle_has_an_interior() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT)
    var left = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE), LEFT)
    var parts = named_muscle_parts()
    var index = 0
    while index < len(parts):
        var part = parts[index]
        var field = MuscleField(dims, part)
        assert_true(muscle_distance(dims, part, field.p2) < 0)
        assert_true(muscle_occupancy(dims, part, field.p2) == SOFT_FILL)
        assert_true(
            muscle_occupancy(dims, part, Vector3(10, 0, 0)) == SOFT_EMPTY
        )
        var n = field.gradient(Vector3(10, 0, 0))
        assert_true(n.length() > Float32(0.5))
        var left_field = MuscleField(left, part)
        assert_true(left_field.distance(left_field.p2) < 0)
        index += 1


def test_toned_muscle_is_heavier_than_untoned() raises:
    var step = MAX_STEP
    var plain = muscle_mass(
        HumanoidSpec(Length(6.0, FOOT), MALE, UNTONED),
        RECTUS_FEMORIS,
        RIGHT,
        step,
    )
    var athlete = muscle_mass(
        HumanoidSpec(Length(6.0, FOOT), MALE, TONED),
        RECTUS_FEMORIS,
        RIGHT,
        step,
    )
    assert_true(athlete.mass.to(GRAM) > plain.mass.to(GRAM))
    var left = muscle_mass(
        HumanoidSpec(Length(5.5, FOOT), FEMALE, TONED),
        GLUTEUS_MAXIMUS,
        LEFT,
        step,
    )
    assert_true(left.mass.to(GRAM) > Float32(0))
    var tract = muscle_mass(
        HumanoidSpec(Length(6.0, FOOT), MALE),
        ILIOTIBIAL_TRACT,
        RIGHT,
        step,
    )
    assert_true(tract.mass.to(GRAM) > Float32(0))


def test_muscle_mesh_has_positions_normals_and_uvs() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    _assert_mesh(muscle_mesh(person, RECTUS_FEMORIS, RIGHT, 8))
    _assert_mesh(muscle_mesh(person, GASTROCNEMIUS, RIGHT, 8))
    _assert_mesh(muscle_mesh(person, ACHILLES_TENDON, LEFT, 8))


def test_muscle_field_refuses_a_bad_part() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    with assert_raises():
        _ = MuscleField(dims, MusclePart(21))
    with assert_raises():
        _ = muscle_from_dimensions(dims, MusclePart(21), 8)
    with assert_raises():
        _ = muscle_mesh(HumanoidSpec(Length(6.0, FOOT), MALE), MusclePart(21))
    with assert_raises():
        _ = muscle_from_dimensions(dims, RECTUS_FEMORIS, 7)
    with assert_raises():
        _ = muscle_from_dimensions(dims, RECTUS_FEMORIS, 65)


def test_muscle_dimensions_validate() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    dims.athleticism = Athleticism(9)
    with assert_raises():
        dims.validate()
    dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    dims.scale = Float32(0)
    with assert_raises():
        dims.validate()
    dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    dims.k = Float32(0)
    with assert_raises():
        dims.validate()
    dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    dims.epsilon = Float32(0)
    with assert_raises():
        dims.validate()
    dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    dims.hip = Vector3(nan[DType.float32](), 0, 0)
    with assert_raises():
        dims.validate()
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    person.athleticism = Athleticism(9)
    with assert_raises():
        _ = muscle_dimensions(person)
    with assert_raises():
        _ = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), Sex(9)))


def test_muscle_mass_refuses_a_bad_part_or_tissue() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    with assert_raises():
        _ = muscle_mass(
            HumanoidSpec(Length(6.0, FOOT), MALE), MusclePart(21), RIGHT
        )
    with assert_raises():
        _ = muscle_mass_from_dimensions(
            dims, MusclePart(21), muscle_tissue(), Length(20.0, MILLIMETER)
        )
    var bad = muscle_tissue()
    bad.kind = SoftTissueKind(9)
    with assert_raises():
        _ = muscle_mass_from_dimensions(
            dims, RECTUS_FEMORIS, bad, Length(20.0, MILLIMETER)
        )


def test_add_leg_can_draw_only_muscles() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
    _ = add_leg(
        scene,
        assets,
        root,
        person,
        assets.materials.add(bone_phong()),
        assets.materials.add(muscle_phong()),
        assets.materials.add(muscle_phong()),
        assets.materials.add(tendon_phong()),
        assets.materials.add(muscle_phong()),
        assets.materials.add(tendon_phong()),
        RIGHT,
        MUSCLES,
        8,
    )
    assert_equal(len(scene.meshes), 21)


def test_look_materials() raises:
    var muscle = muscle_phong()
    assert_true(muscle.kind == PHONG)
    var tendon = tendon_phong()
    assert_true(tendon.kind == PHONG)


def _assert_mesh(bone: BufferGeometry) raises:
    """Refuse a mesh with missing attributes or no triangles."""
    assert_true(bone.has_attribute(String(POSITION)))
    assert_true(bone.has_attribute(String(NORMAL)))
    assert_true(bone.has_attribute(String(UV)))
    assert_true(bone.triangle_count() > 0)


def test_part_labels_match_the_diagram() raises:
    assert_equal(muscle_part_label(GLUTEUS_MAXIMUS), "gluteus maximus")
    assert_equal(muscle_part_label(GLUTEUS_MEDIUS), "gluteus medius")
    assert_equal(
        muscle_part_label(TENSOR_FASCIAE_LATAE), "tensor fasciae latae"
    )
    assert_equal(muscle_part_label(ILIOTIBIAL_TRACT), "iliotibial tract")
    assert_equal(muscle_part_label(SARTORIUS), "sartorius")
    assert_equal(muscle_part_label(RECTUS_FEMORIS), "rectus femoris")
    assert_equal(muscle_part_label(VASTUS_LATERALIS), "vastus lateralis")
    assert_equal(muscle_part_label(VASTUS_MEDIALIS), "vastus medialis")
    assert_equal(muscle_part_label(PECTINEUS), "pectineus")
    assert_equal(muscle_part_label(ADDUCTOR_LONGUS), "adductor longus")
    assert_equal(muscle_part_label(GRACILIS), "gracilis")
    assert_equal(muscle_part_label(BICEPS_FEMORIS), "biceps femoris")
    assert_equal(muscle_part_label(SEMITENDINOSUS), "semitendinosus")
    assert_equal(muscle_part_label(SEMIMEMBRANOSUS), "semimembranosus")
    assert_equal(muscle_part_label(GASTROCNEMIUS), "gastrocnemius")
    assert_equal(muscle_part_label(SOLEUS), "soleus")
    assert_equal(muscle_part_label(TIBIALIS_ANTERIOR), "tibialis anterior")
    assert_equal(
        muscle_part_label(EXTENSOR_DIGITORUM_LONGUS),
        "extensor digitorum longus",
    )
    assert_equal(muscle_part_label(PERONEUS_LONGUS), "peroneus longus")
    assert_equal(muscle_part_label(PERONEUS_BREVIS), "peroneus brevis")
    assert_equal(muscle_part_label(ACHILLES_TENDON), "Achilles tendon")


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
