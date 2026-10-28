# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for outfits, and for dressing a game humanoid in one."""

from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, UV, BufferGeometry
from core.object3d import NodeId
from core.scene import Scene
from extensions.attire.dye import DYE
from extensions.attire.cover import Cover, cover_of
from extensions.attire.garment import (
    Garment,
    boots,
    coif,
    cuirass,
    fauld,
    gambeson,
    gloves,
    hauberk,
    hood,
    hose,
    shirt,
    surcoat,
    tunic,
)
from extensions.attire.kinds import (
    LINEN,
    OVER_LAYER,
    TORSO_SLOT,
    UNDER_LAYER,
    WOOL,
    Layer,
)
from extensions.humanoid.rig.joints import CHEST, HIPS, SPINE
from render.framebuffer import Color
from extensions.attire.outfit import Outfit, dress, dress_pieces
from objects.skinned_mesh import SKIN_INDEX
from render.texture_store import NO_TEXTURE
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.humanoid.rig.game import GameHumanoid
from extensions.humanoid.skeleton.head.hair.strands import HairStrands
from tests._attire_fixtures import empty_mesh, line_rig
from tests._attire_people import coarse_person


def test_an_outfit_holds_one_garment_a_slot_and_layer() raises:
    var outfit = Outfit()
    outfit.add(hauberk())
    outfit.add(shirt())
    outfit.add(gambeson())
    with assert_raises(contains="already has a mid garment in the torso"):
        outfit.add(tunic())
    var refused = hose()
    refused.layer = Layer(9)
    with assert_raises(contains="named layer"):
        outfit.add(refused.copy())
    outfit.check()
    # From the skin out: the shirt, the gambeson, then the mail.
    assert_equal(outfit.order(), [1, 2, 0])
    # A garment slipped past `add` is caught by `check`.
    outfit.garments.append(tunic())
    with assert_raises(contains="already has"):
        outfit.check()


def test_a_person_is_dressed_from_the_skin_out() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets, guides=6)
    var skin_before = assets.geometries.get(
        scene.skinned_meshes[person.skins[0]].geometry
    ).triangle_count()
    var outfit = Outfit()
    outfit.add(shirt())
    outfit.add(hose())
    outfit.add(gambeson())
    outfit.add(hauberk())
    outfit.add(coif())
    outfit.add(boots())
    outfit.add(gloves())
    outfit.add(cuirass())
    outfit.add(fauld())
    outfit.add(surcoat())
    var meshes_before = len(scene.skinned_meshes)
    var dressed = dress(scene, assets, person, outfit)
    assert_equal(len(dressed.meshes), 10)
    var drawn = 0
    for k in range(10):
        var at = dressed.meshes[k]
        if at < 0:
            continue
        drawn += 1
        ref mesh = scene.skinned_meshes[at]
        ref piece = assets.geometries.get(mesh.geometry)
        assert_true(piece.triangle_count() > 0)
        assert_true(piece.has_attribute(String(COLOR)))
        assert_true(piece.has_attribute(String(DYE)))
        assert_true(piece.has_attribute(String(NORMAL)))
        assert_true(piece.has_attribute(String(SKIN_INDEX)))
        assert_true(piece.has_attribute(String(UV)))
        assert_equal(mesh.node, person.root)
        assert_equal(mesh.skeleton.bone_count(), len(person.bones))
    assert_equal(len(scene.skinned_meshes), meshes_before + drawn)
    # The hauberk and the coif share one map of rings. The gambeson has
    # its quilting, and the boots have none.
    var hauberk_look = assets.materials.get(
        scene.skinned_meshes[dressed.meshes[3]].material
    )
    var coif_look = assets.materials.get(
        scene.skinned_meshes[dressed.meshes[4]].material
    )
    var gambeson_look = assets.materials.get(
        scene.skinned_meshes[dressed.meshes[2]].material
    )
    var boots_look = assets.materials.get(
        scene.skinned_meshes[dressed.meshes[5]].material
    )
    assert_true(hauberk_look.bump_map != NO_TEXTURE)
    assert_true(hauberk_look.bump_map == coif_look.bump_map)
    assert_true(gambeson_look.bump_map != NO_TEXTURE)
    assert_true(gambeson_look.bump_map != hauberk_look.bump_map)
    assert_true(boots_look.bump_map == NO_TEXTURE)
    # The shirt shows at most a sliver past the gambeson and the mail.
    var shirt_shown = 0
    if dressed.meshes[0] >= 0:
        shirt_shown = assets.geometries.get(
            scene.skinned_meshes[dressed.meshes[0]].geometry
        ).triangle_count()
    var gambeson_shown = assets.geometries.get(
        scene.skinned_meshes[dressed.meshes[2]].geometry
    ).triangle_count()
    assert_true(shirt_shown < gambeson_shown)
    # The outfit hides most of the skin.
    var skin_after = assets.geometries.get(
        scene.skinned_meshes[person.skins[0]].geometry
    ).triangle_count()
    assert_true(skin_after * 3 < skin_before)
    # The coif covers the head: the hair hides.
    assert_false(scene.node(person.hair.value()).visible)
    assert_false(scene.node(person.strands[0].node.value()).visible)


def test_a_garment_hidden_wholly_draws_nothing() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    # A long coat over a narrow band round the waist hides the band.
    var band = Cover()
    band.reach_to(SPINE, 0.7, 0.3)
    var vest = Garment(
        "band", TORSO_SLOT, UNDER_LAYER, LINEN, band^, Color(9, 9, 9)
    )
    var coat = Garment(
        "coat",
        TORSO_SLOT,
        OVER_LAYER,
        WOOL,
        cover_of([HIPS, SPINE, CHEST]),
        Color(90, 90, 90),
    )
    var outfit = Outfit()
    outfit.add(vest^)
    outfit.add(coat^)
    var dressed = dress(scene, assets, person, outfit)
    assert_equal(dressed.meshes[0], -1)
    assert_true(dressed.meshes[1] >= 0)


def test_a_bare_head_keeps_its_hair_and_a_bald_one_is_fine() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var outfit = Outfit()
    outfit.add(tunic())
    _ = dress(scene, assets, person, outfit)
    assert_true(scene.node(person.hair.value()).visible)
    # A person with no hair shell and strands with no node still dress.
    var bald = coarse_person(scene, assets, guides=6)
    var hair = bald.hair.value()
    bald.hair = None
    bald.strands[0].node = None
    var hooded = Outfit()
    hooded.add(hood())
    _ = dress(scene, assets, bald, hooded)
    assert_true(scene.node(hair).visible)


def test_an_outfit_that_does_not_check_is_refused() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var outfit = Outfit()
    outfit.garments.append(tunic())
    outfit.garments.append(tunic())
    with assert_raises(contains="already has"):
        _ = dress(scene, assets, person, outfit)


def test_nothing_to_wear_or_no_skin_makes_nothing() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var before = len(scene.skinned_meshes)
    var dressed = dress(scene, assets, person, Outfit())
    assert_equal(len(dressed.meshes), 0)
    assert_equal(len(scene.skinned_meshes), before)
    # An empty skin gives each garment an empty piece.
    var outfit = Outfit()
    outfit.add(shirt())
    outfit.add(tunic())
    var over = List[Float32]()
    var shells = List[BufferGeometry]()
    var pieces = dress_pieces(empty_mesh(), person, outfit, over, shells)
    assert_equal(len(pieces), 2)
    assert_equal(pieces[0].triangle_count(), 0)
    assert_equal(pieces[1].triangle_count(), 0)
    assert_equal(len(over), 0)
    assert_equal(len(shells), 2)
    # A person with no skin cannot be dressed.
    var skinless = GameHumanoid(
        line_rig(),
        person.root,
        List[NodeId](),
        List[Int](),
        List[HairStrands](),
    )
    with assert_raises(contains="with a skin"):
        _ = dress(scene, assets, skinless, outfit)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
