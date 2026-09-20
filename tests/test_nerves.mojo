# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for stature-scaled peripheral nerves of the leg."""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_phong
from extensions.humanoid.skeleton.leg.assembly import add_leg
from extensions.humanoid.skeleton.leg.contents import NERVES
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    muscle_dimensions,
)
from extensions.humanoid.skeleton.leg.nerves.dimensions import (
    COMMON_PERONEAL_NERVE,
    FEMORAL_NERVE,
    SAPHENOUS_NERVE,
    SCIATIC_NERVE,
    SURAL_NERVE,
    TIBIAL_NERVE,
    NerveField,
    NervePart,
    named_nerve_parts,
    nerve_distance,
    nerve_part_label,
)
from extensions.humanoid.skeleton.leg.nerves.geometry import (
    nerve_from_dimensions,
    nerve_mesh,
)
from extensions.humanoid.skeleton.leg.nerves.mass import (
    nerve_mass,
    nerve_mass_from_dimensions,
    nerve_occupancy,
)
from extensions.humanoid.skeleton.look import (
    cartilage_phong,
    ligament_phong,
    meniscus_phong,
    muscle_phong,
    nerve_phong,
    tendon_phong,
)
from extensions.humanoid.skeleton.occupancy import MAX_STEP
from extensions.humanoid.skeleton.soft_tissue import (
    NERVE,
    SOFT_EMPTY,
    SOFT_FILL,
    SoftTissueKind,
    nerve_tissue,
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


def test_nerve_parts_are_named() raises:
    var parts = named_nerve_parts()
    assert_equal(len(parts), 6)
    var index = 0
    while index < len(parts):
        assert_true(parts[index].is_valid())
        var label = nerve_part_label(parts[index])
        assert_true(label.byte_length() > 0)
        index += 1
    assert_false(NervePart(-1).is_valid())
    assert_false(NervePart(6).is_valid())
    assert_equal(nerve_part_label(NervePart(99)), "nerve")


def test_nerve_labels_match_the_diagram() raises:
    assert_equal(nerve_part_label(FEMORAL_NERVE), "femoral nerve")
    assert_equal(nerve_part_label(SCIATIC_NERVE), "sciatic nerve")
    assert_equal(nerve_part_label(TIBIAL_NERVE), "tibial nerve")
    assert_equal(
        nerve_part_label(COMMON_PERONEAL_NERVE), "common peroneal nerve"
    )
    assert_equal(nerve_part_label(SAPHENOUS_NERVE), "saphenous nerve")
    assert_equal(nerve_part_label(SURAL_NERVE), "sural nerve")


def test_nerve_tissue() raises:
    assert_true(NERVE.is_valid())
    var tissue = nerve_tissue()
    assert_true(tissue.kind == NERVE)
    assert_almost_equal(
        tissue.wet_density.to(GRAM_PER_CUBIC_CENTIMETER),
        Float32(1.04),
        atol=TOLERANCE,
    )
    assert_almost_equal(tissue.water_fraction, Float32(0.77), atol=TOLERANCE)
    assert_almost_equal(
        tissue.elastic_modulus.to(MEGAPASCAL), Float32(0.50), atol=TOLERANCE
    )
    tissue.validate()


def test_every_named_nerve_has_an_interior() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT)
    var left = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE), LEFT)
    var parts = named_nerve_parts()
    var index = 0
    while index < len(parts):
        var part = parts[index]
        var field = NerveField(dims, part)
        assert_true(nerve_distance(dims, part, field.chain.p2) < 0)
        assert_true(nerve_occupancy(dims, part, field.chain.p2) == SOFT_FILL)
        assert_true(
            nerve_occupancy(dims, part, Vector3(10, 0, 0)) == SOFT_EMPTY
        )
        var n = field.gradient(Vector3(10, 0, 0))
        assert_true(n.length() > Float32(0.5))
        var left_field = NerveField(left, part)
        assert_true(left_field.distance(left_field.chain.p2) < 0)
        index += 1


def test_nerve_mesh_has_positions_normals_and_uvs() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    _assert_mesh(nerve_mesh(person, SCIATIC_NERVE, RIGHT, 8))
    _assert_mesh(nerve_mesh(person, FEMORAL_NERVE, LEFT, 8))
    _assert_mesh(nerve_mesh(person, COMMON_PERONEAL_NERVE, RIGHT, 8))


def test_nerve_mass_is_positive() raises:
    var step = MAX_STEP
    var sciatic = nerve_mass(
        HumanoidSpec(Length(6.0, FOOT), MALE), SCIATIC_NERVE, RIGHT, step
    )
    assert_true(sciatic.mass.to(GRAM) > Float32(0))
    var femoral = nerve_mass(
        HumanoidSpec(Length(5.5, FOOT), FEMALE), SURAL_NERVE, LEFT, step
    )
    assert_true(femoral.mass.to(GRAM) > Float32(0))


def test_nerve_field_refuses_a_bad_part() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    with assert_raises():
        _ = NerveField(dims, NervePart(6))
    with assert_raises():
        _ = nerve_from_dimensions(dims, NervePart(6), 8)
    with assert_raises():
        _ = nerve_mesh(HumanoidSpec(Length(6.0, FOOT), MALE), NervePart(6))
    with assert_raises():
        _ = nerve_from_dimensions(dims, SCIATIC_NERVE, 7)
    with assert_raises():
        _ = nerve_from_dimensions(dims, SCIATIC_NERVE, 65)


def test_nerve_mass_refuses_a_bad_part_or_tissue() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    with assert_raises():
        _ = nerve_mass(
            HumanoidSpec(Length(6.0, FOOT), MALE), NervePart(6), RIGHT
        )
    with assert_raises():
        _ = nerve_mass_from_dimensions(
            dims, NervePart(6), nerve_tissue(), Length(20.0, MILLIMETER)
        )
    var bad = nerve_tissue()
    bad.kind = SoftTissueKind(11)
    with assert_raises():
        _ = nerve_mass_from_dimensions(
            dims, SCIATIC_NERVE, bad, Length(20.0, MILLIMETER)
        )


def test_add_leg_can_draw_only_nerves() raises:
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
        NERVES,
        8,
        nerve_paint=assets.materials.add(nerve_phong()),
    )
    assert_equal(len(scene.meshes), 6)


def test_nerve_look_material() raises:
    var paint = nerve_phong()
    assert_true(paint.kind == PHONG)


def _assert_mesh(bone: BufferGeometry) raises:
    """Refuse a mesh with missing attributes or no triangles."""
    assert_true(bone.has_attribute(String(POSITION)))
    assert_true(bone.has_attribute(String(NORMAL)))
    assert_true(bone.has_attribute(String(UV)))
    assert_true(bone.triangle_count() > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
