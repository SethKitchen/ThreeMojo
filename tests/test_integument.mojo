# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for the stature-scaled leg skin envelope and hair shafts."""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_phong
from extensions.humanoid.skeleton.field import TubeChain
from extensions.humanoid.skeleton.leg.assembly import add_leg
from extensions.humanoid.skeleton.leg.contents import INTEGUMENT
from extensions.humanoid.skeleton.leg.hair.dimensions import (
    CALF_HAIR,
    THIGH_HAIR,
    HairField,
    HairPart,
    hair_distance,
    hair_part_label,
    named_hair_parts,
)
from extensions.humanoid.skeleton.leg.hair.geometry import (
    hair_from_dimensions,
    hair_mesh,
)
from extensions.humanoid.skeleton.leg.hair.mass import (
    hair_mass,
    hair_mass_from_dimensions,
    hair_occupancy,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    muscle_dimensions,
)
from extensions.humanoid.skeleton.leg.skin.dimensions import (
    SkinField,
    skin_distance,
)
from extensions.humanoid.skeleton.leg.skin.geometry import (
    skin_from_dimensions,
    skin_mesh,
)
from extensions.humanoid.skeleton.leg.skin.mass import (
    skin_mass,
    skin_occupancy,
)
from extensions.humanoid.skeleton.look import (
    MAX_SOFT_LOOK,
    MIN_SOFT_LOOK,
    cartilage_phong,
    hair_phong,
    ligament_phong,
    meniscus_phong,
    muscle_phong,
    skin_albedo,
    skin_phong,
    tendon_phong,
)
from extensions.humanoid.skeleton.occupancy import MAX_STEP
from extensions.humanoid.skeleton.soft_tissue import (
    HAIR as HAIR_KIND,
    SKIN as SKIN_KIND,
    SOFT_FILL,
    hair_tissue,
    skin_tissue,
)
from materials.material import DOUBLE_SIDE, PHONG
from math.vector3 import Vector3
from render.srgb import SRGB
from render.texture_store import NO_TEXTURE, TextureStore
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


def test_hair_parts_are_named() raises:
    var parts = named_hair_parts()
    assert_equal(len(parts), 2)
    assert_true(parts[0].is_valid())
    assert_true(parts[1].is_valid())
    assert_false(HairPart(-1).is_valid())
    assert_false(HairPart(2).is_valid())
    assert_equal(hair_part_label(THIGH_HAIR), "thigh hair")
    assert_equal(hair_part_label(CALF_HAIR), "calf hair")
    assert_equal(hair_part_label(HairPart(99)), "hair")


def test_skin_and_hair_tissue() raises:
    assert_true(SKIN_KIND.is_valid())
    assert_true(HAIR_KIND.is_valid())
    var skin = skin_tissue()
    assert_true(skin.kind == SKIN_KIND)
    assert_almost_equal(
        skin.wet_density.to(GRAM_PER_CUBIC_CENTIMETER),
        Float32(1.10),
        atol=TOLERANCE,
    )
    assert_almost_equal(skin.water_fraction, Float32(0.70), atol=TOLERANCE)
    assert_almost_equal(
        skin.elastic_modulus.to(MEGAPASCAL), Float32(0.20), atol=TOLERANCE
    )
    skin.validate()
    var keratin = hair_tissue()
    assert_true(keratin.kind == HAIR_KIND)
    assert_almost_equal(
        keratin.wet_density.to(GRAM_PER_CUBIC_CENTIMETER),
        Float32(1.32),
        atol=TOLERANCE,
    )
    assert_almost_equal(keratin.water_fraction, Float32(0.12), atol=TOLERANCE)
    keratin.validate()


def test_skin_envelope_has_an_interior() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT)
    var field = SkinField(dims)
    var inside = field.rectus_femoris.p2
    assert_true(skin_distance(dims, inside) < 0)
    assert_true(field.distance(inside) < -field.dermis)
    assert_true(field.distance(Vector3(10, 0, 0)) > 0)
    var surface = _outer_surface(field, inside, Vector3(0, 0, 1))
    var dermis = surface - Vector3(0, 0, 0.5 * field.dermis)
    assert_true(skin_occupancy(dims, dermis) == SOFT_FILL)
    var n = field.gradient(Vector3(10, 0, 0))
    assert_true(n.length() > Float32(0.5))
    _assert_chain_inside(field, field.femoral_artery.chain, "femoral artery")
    _assert_chain_inside(
        field, field.popliteal_artery.chain, "popliteal artery"
    )
    _assert_chain_inside(
        field, field.anterior_tibial_artery.chain, "anterior tibial artery"
    )
    _assert_chain_inside(
        field, field.posterior_tibial_artery.chain, "posterior tibial artery"
    )
    _assert_chain_inside(field, field.fibular_artery.chain, "fibular artery")
    _assert_chain_inside(field, field.femoral_vein.chain, "femoral vein")
    _assert_chain_inside(field, field.popliteal_vein.chain, "popliteal vein")
    _assert_chain_inside(
        field, field.great_saphenous_vein.chain, "great saphenous vein"
    )
    _assert_chain_inside(
        field, field.small_saphenous_vein.chain, "small saphenous vein"
    )
    _assert_chain_inside(
        field, field.superficial_lymphatics.chain, "medial superficial lymph"
    )
    _assert_chain_inside(
        field,
        field.superficial_lymphatics.chain2,
        "lateral superficial lymph",
    )
    _assert_chain_inside(field, field.deep_lymphatics.chain, "deep lymph")
    _assert_chain_inside(field, field.femoral_nerve.chain, "femoral nerve")
    _assert_chain_inside(field, field.sciatic_nerve.chain, "sciatic nerve")
    _assert_chain_inside(field, field.tibial_nerve.chain, "tibial nerve")
    _assert_chain_inside(
        field, field.common_fibular_nerve.chain, "common fibular nerve"
    )
    _assert_chain_inside(field, field.saphenous_nerve.chain, "saphenous nerve")
    _assert_chain_inside(field, field.sural_nerve.chain, "sural nerve")
    assert_true(field.distance(field.inguinal_nodes.c4) < 0)
    assert_true(field.distance(field.popliteal_nodes.c4) < 0)


def test_every_named_hair_group_has_an_interior() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT)
    var skin = SkinField(dims)
    var parts = named_hair_parts()
    var index = 0
    while index < len(parts):
        var part = parts[index]
        var field = HairField(dims, part)
        assert_true(field.distance(field.a0) < 0)
        assert_true(field.distance(Vector3(10, 0, 0)) > 0)
        if part == THIGH_HAIR:
            assert_almost_equal(
                field.radius, Float32(0.0000145), atol=Float64(1e-8)
            )
        else:
            assert_almost_equal(
                field.radius, Float32(0.000021), atol=Float64(1e-8)
            )
        assert_true((field.a1 - field.a0).length() > Float32(2) * field.radius)
        assert_true(skin.distance(field.a0) > Float32(-0.001))
        assert_true(skin.distance(field.a0) < Float32(0.001))
        var n = field.gradient(Vector3(10, 0, 0))
        assert_true(n.length() > Float32(0.5))
        index += 1


def test_skin_and_hair_meshes_have_positions_normals_and_uvs() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    _assert_mesh(skin_mesh(person, RIGHT, 8))
    _assert_mesh(hair_mesh(person, CALF_HAIR, LEFT, 8))


def test_skin_and_hair_mass_are_positive() raises:
    var step = MAX_STEP
    var short = skin_mass(HumanoidSpec(Length(5.5, FOOT), FEMALE), LEFT, step)
    assert_true(short.mass.to(GRAM) > Float32(0))
    var calf = hair_mass(
        HumanoidSpec(Length(5.5, FOOT), FEMALE), CALF_HAIR, LEFT
    )
    assert_true(calf.mass.to(GRAM) > Float32(0))


def test_skin_and_hair_refuse_bad_inputs() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    with assert_raises():
        _ = HairField(dims, HairPart(2))
    with assert_raises():
        _ = hair_distance(dims, HairPart(2), Vector3(0, 0, 0))
    with assert_raises():
        _ = hair_occupancy(dims, HairPart(2), Vector3(0, 0, 0))
    with assert_raises():
        _ = hair_from_dimensions(dims, HairPart(2), 8)
    with assert_raises():
        _ = hair_mesh(HumanoidSpec(Length(6.0, FOOT), MALE), HairPart(2))
    with assert_raises():
        _ = hair_from_dimensions(dims, THIGH_HAIR, 7)
    with assert_raises():
        _ = hair_from_dimensions(dims, THIGH_HAIR, 65)
    with assert_raises():
        _ = skin_from_dimensions(dims, 7)
    with assert_raises():
        _ = skin_from_dimensions(dims, 65)
    with assert_raises():
        _ = hair_mass(HumanoidSpec(Length(6.0, FOOT), MALE), HairPart(2), RIGHT)
    with assert_raises():
        _ = hair_mass_from_dimensions(dims, HairPart(2), hair_tissue())


def test_add_leg_can_draw_integument() raises:
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
        INTEGUMENT,
        8,
    )
    assert_equal(len(scene.meshes), 3)


def test_skin_and_hair_look_materials() raises:
    var bare = skin_phong()
    assert_true(bare.kind == PHONG)
    assert_true(bare.map == NO_TEXTURE)
    var image = skin_albedo(MIN_SOFT_LOOK)
    assert_equal(image.width, MIN_SOFT_LOOK)
    assert_equal(image.height, MIN_SOFT_LOOK)
    assert_true(image.color_space == SRGB)
    var store = TextureStore()
    var mapped = skin_phong(store.add(image^))
    assert_true(mapped.map != NO_TEXTURE)
    assert_equal(mapped.color.r, UInt8(255))
    var keratin = hair_phong()
    assert_true(keratin.kind == PHONG)
    assert_true(bare.side == DOUBLE_SIDE)
    with assert_raises():
        _ = skin_albedo(MIN_SOFT_LOOK - 1)
    with assert_raises():
        _ = skin_albedo(MAX_SOFT_LOOK + 1)


def _outer_surface(
    field: SkinField, inside: Vector3, direction: Vector3
) -> Vector3:
    """Return the outer surface reached from `inside` along `direction`."""
    var low = inside
    var high = inside + direction * Float32(0.50)
    for _ in range(18):
        var middle = (low + high) * Float32(0.5)
        if field.distance(middle) < 0:
            low = middle
        else:
            high = middle
    return high


def _assert_chain_inside(
    field: SkinField, chain: TubeChain, name: String
) raises:
    """Assert that all five centerline stations lie below the skin."""
    if field.distance(chain.p0) >= 0:
        print(name, "p0 lies outside skin by", field.distance(chain.p0))
    if field.distance(chain.p1) >= 0:
        print(name, "p1 lies outside skin by", field.distance(chain.p1))
    if field.distance(chain.p2) >= 0:
        print(name, "p2 lies outside skin by", field.distance(chain.p2))
    if field.distance(chain.p3) >= 0:
        print(name, "p3 lies outside skin by", field.distance(chain.p3))
    if field.distance(chain.p4) >= 0:
        print(name, "p4 lies outside skin by", field.distance(chain.p4))
    assert_true(field.distance(chain.p0) < 0)
    assert_true(field.distance(chain.p1) < 0)
    assert_true(field.distance(chain.p2) < 0)
    assert_true(field.distance(chain.p3) < 0)
    assert_true(field.distance(chain.p4) < 0)


def _assert_mesh(bone: BufferGeometry) raises:
    """Refuse a mesh with missing attributes or no triangles."""
    assert_true(bone.has_attribute(String(POSITION)))
    assert_true(bone.has_attribute(String(NORMAL)))
    assert_true(bone.has_attribute(String(UV)))
    assert_true(bone.triangle_count() > 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
