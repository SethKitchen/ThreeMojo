# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for stature-scaled lymph nodes and trunks."""

from core.assets import Assets
from core.buffer_geometry import BufferGeometry, NORMAL, POSITION, UV
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.side import LEFT, RIGHT
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.bone import bone_phong
from extensions.humanoid.skeleton.leg.assembly import add_leg
from extensions.humanoid.skeleton.leg.contents import LYMPH
from extensions.humanoid.skeleton.leg.lymph.dimensions import (
    DEEP_LYMPHATICS,
    INGUINAL_NODES,
    POPLITEAL_NODES,
    SUPERFICIAL_LYMPHATICS,
    LymphField,
    LymphPart,
    is_node_group,
    lymph_distance,
    lymph_part_label,
    named_lymph_parts,
)
from extensions.humanoid.skeleton.leg.lymph.geometry import (
    lymph_from_dimensions,
    lymph_mesh,
)
from extensions.humanoid.skeleton.leg.lymph.mass import (
    lymph_mass,
    lymph_mass_from_dimensions,
    lymph_occupancy,
)
from extensions.humanoid.skeleton.leg.muscles.dimensions import (
    muscle_dimensions,
)
from extensions.humanoid.skeleton.look import (
    cartilage_phong,
    ligament_phong,
    lymph_phong,
    meniscus_phong,
    muscle_phong,
    tendon_phong,
)
from extensions.humanoid.skeleton.soft_tissue import (
    LYMPH as LYMPH_KIND,
    SOFT_EMPTY,
    SOFT_FILL,
    SoftTissueKind,
    lymph_tissue,
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


def test_lymph_parts_are_named() raises:
    var parts = named_lymph_parts()
    assert_equal(len(parts), 4)
    var index = 0
    while index < len(parts):
        assert_true(parts[index].is_valid())
        var label = lymph_part_label(parts[index])
        assert_true(label.byte_length() > 0)
        index += 1
    assert_false(LymphPart(-1).is_valid())
    assert_false(LymphPart(4).is_valid())
    assert_equal(lymph_part_label(LymphPart(99)), "lymph")
    assert_true(is_node_group(INGUINAL_NODES))
    assert_true(is_node_group(POPLITEAL_NODES))
    assert_false(is_node_group(SUPERFICIAL_LYMPHATICS))
    assert_false(is_node_group(DEEP_LYMPHATICS))
    with assert_raises():
        _ = is_node_group(LymphPart(4))


def test_lymph_labels_match_the_diagram() raises:
    assert_equal(lymph_part_label(INGUINAL_NODES), "inguinal nodes")
    assert_equal(lymph_part_label(POPLITEAL_NODES), "popliteal nodes")
    assert_equal(
        lymph_part_label(SUPERFICIAL_LYMPHATICS), "superficial lymphatics"
    )
    assert_equal(lymph_part_label(DEEP_LYMPHATICS), "deep lymphatics")


def test_lymph_tissue() raises:
    assert_true(LYMPH_KIND.is_valid())
    var tissue = lymph_tissue()
    assert_true(tissue.kind == LYMPH_KIND)
    assert_almost_equal(
        tissue.wet_density.to(GRAM_PER_CUBIC_CENTIMETER),
        Float32(1.01),
        atol=TOLERANCE,
    )
    assert_almost_equal(tissue.water_fraction, Float32(0.95), atol=TOLERANCE)
    assert_almost_equal(
        tissue.elastic_modulus.to(MEGAPASCAL), Float32(0.02), atol=TOLERANCE
    )
    tissue.validate()


def test_every_named_lymph_solid_has_an_interior() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT)
    var left = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE), LEFT)
    var parts = named_lymph_parts()
    var index = 0
    while index < len(parts):
        var part = parts[index]
        var field = LymphField(dims, part)
        var inside = field.chain.p2
        if field.nodes:
            inside = field.c0
        assert_true(lymph_distance(dims, part, inside) < 0)
        assert_true(lymph_occupancy(dims, part, inside) == SOFT_FILL)
        assert_true(
            lymph_occupancy(dims, part, Vector3(10, 0, 0)) == SOFT_EMPTY
        )
        var n = field.gradient(Vector3(10, 0, 0))
        assert_true(n.length() > Float32(0.5))
        var left_field = LymphField(left, part)
        var left_inside = left_field.chain.p2
        if left_field.nodes:
            left_inside = left_field.c0
        assert_true(left_field.distance(left_inside) < 0)
        index += 1


def test_lymphatic_routes_connect_the_expected_nodes() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE), RIGHT)
    var inguinal = LymphField(dims, INGUINAL_NODES)
    var popliteal = LymphField(dims, POPLITEAL_NODES)
    var superficial = LymphField(dims, SUPERFICIAL_LYMPHATICS)
    var deep = LymphField(dims, DEEP_LYMPHATICS)
    assert_true(superficial.two_chains)
    assert_false(deep.two_chains)
    _assert_same_point(superficial.chain.p4, inguinal.c0)
    _assert_same_point(superficial.chain2.p4, popliteal.c0)
    _assert_same_point(deep.chain.p2, popliteal.c4)
    _assert_same_point(deep.chain.p4, inguinal.c4)
    assert_true(inguinal.distance(inguinal.c3) < 0)
    assert_true(inguinal.distance(inguinal.c4) < 0)
    assert_true(popliteal.distance(popliteal.c3) < 0)
    assert_true(popliteal.distance(popliteal.c4) < 0)


def test_lymph_mesh_has_positions_normals_and_uvs() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    _assert_mesh(lymph_mesh(person, INGUINAL_NODES, RIGHT, 8))
    _assert_mesh(lymph_mesh(person, SUPERFICIAL_LYMPHATICS, LEFT, 8))
    _assert_mesh(lymph_mesh(person, POPLITEAL_NODES, RIGHT, 8))
    _assert_mesh(lymph_mesh(person, DEEP_LYMPHATICS, RIGHT, 8))


def test_lymph_mass_is_positive() raises:
    var step = Length(5.0, MILLIMETER)
    var nodes = lymph_mass(
        HumanoidSpec(Length(6.0, FOOT), MALE), INGUINAL_NODES, RIGHT, step
    )
    assert_true(nodes.mass.to(GRAM) > Float32(0))
    var trunk = lymph_mass(
        HumanoidSpec(Length(5.5, FOOT), FEMALE), DEEP_LYMPHATICS, LEFT, step
    )
    assert_true(trunk.mass.to(GRAM) > Float32(0))


def test_lymph_field_refuses_a_bad_part() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    with assert_raises():
        _ = LymphField(dims, LymphPart(4))
    with assert_raises():
        _ = lymph_from_dimensions(dims, LymphPart(4), 8)
    with assert_raises():
        _ = lymph_mesh(HumanoidSpec(Length(6.0, FOOT), MALE), LymphPart(4))
    with assert_raises():
        _ = lymph_from_dimensions(dims, INGUINAL_NODES, 7)
    with assert_raises():
        _ = lymph_from_dimensions(dims, INGUINAL_NODES, 65)


def test_lymph_mass_refuses_a_bad_part_or_tissue() raises:
    var dims = muscle_dimensions(HumanoidSpec(Length(6.0, FOOT), MALE))
    with assert_raises():
        _ = lymph_mass(
            HumanoidSpec(Length(6.0, FOOT), MALE), LymphPart(4), RIGHT
        )
    with assert_raises():
        _ = lymph_mass_from_dimensions(
            dims, LymphPart(4), lymph_tissue(), Length(20.0, MILLIMETER)
        )
    var bad = lymph_tissue()
    bad.kind = SoftTissueKind(11)
    with assert_raises():
        _ = lymph_mass_from_dimensions(
            dims, INGUINAL_NODES, bad, Length(20.0, MILLIMETER)
        )


def test_add_leg_can_draw_only_lymph() raises:
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
        LYMPH,
        8,
        lymph_paint=assets.materials.add(lymph_phong()),
    )
    assert_equal(len(scene.meshes), 4)


def test_lymph_look_material() raises:
    var paint = lymph_phong()
    assert_true(paint.kind == PHONG)


def _assert_mesh(bone: BufferGeometry) raises:
    """Refuse a mesh with missing attributes or no triangles."""
    assert_true(bone.has_attribute(String(POSITION)))
    assert_true(bone.has_attribute(String(NORMAL)))
    assert_true(bone.has_attribute(String(UV)))
    assert_true(bone.triangle_count() > 0)


def _assert_same_point(a: Vector3, b: Vector3) raises:
    """Assert that two topology endpoints are the same point."""
    assert_almost_equal(a.x, b.x, atol=TOLERANCE)
    assert_almost_equal(a.y, b.y, atol=TOLERANCE)
    assert_almost_equal(a.z, b.z, atol=TOLERANCE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
