# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for outfits, and for dressing a game humanoid in one."""

from core.assets import Assets
from core.buffer_geometry import COLOR, NORMAL, POSITION, UV, BufferGeometry
from core.object3d import NodeId
from core.scene import Scene
from extensions.attire.dye import DYE
from extensions.attire.band import BAND_HEIGHT
from extensions.attire.cover import Cover, cover_of
from extensions.attire.garment import (
    Garment,
    belt,
    boots,
    coif,
    cuirass,
    fauld,
    gambeson,
    gloves,
    hauberk,
    hood,
    hose,
    sabatons,
    shirt,
    surcoat,
    tunic,
)
from extensions.attire.kinds import (
    LINEN,
    OVER_LAYER,
    SKIRTED,
    TORSO_SLOT,
    UNDER_LAYER,
    WOOL,
    Layer,
)
from extensions.humanoid.rig.joints import (
    CHEST,
    HIPS,
    LEFT_THIGH,
    RIGHT_THIGH,
    SPINE,
)
from render.framebuffer import Color
from extensions.attire.apparel import crown, straw_hat
from extensions.attire.armory import great_helm, great_pauldrons
from extensions.attire.mesh_ops import ACCENT
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
from core.object3d import Object3D
from extensions.humanoid.rig.game import add_game_humanoid
from extensions.humanoid.skeleton.head.hair.beard import GOATEE
from tests._attire_people import coarse_person, coarse_spec


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
    var person = coarse_person(scene, assets, guides=6, cards=6)
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
    assert_false(scene.node(person.cards[0].node.value()).visible)


def _pieces(
    scene: Scene, assets: Assets, person: GameHumanoid, outfit: Outfit
) raises -> List[BufferGeometry]:
    """Return the pieces of an outfit made from a person's body skin."""
    var over = List[Float32]()
    var shells = List[BufferGeometry]()
    return dress_pieces(
        assets.geometries.get(
            scene.skinned_meshes[person.skins[0]].geometry
        ).clone(),
        person,
        outfit,
        over,
        shells,
    )


def test_a_last_over_a_last_hides_it() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var shod = Outfit()
    shod.add(boots())
    var alone = _pieces(scene, assets, person, shod)
    shod.add(sabatons())
    var over = List[Float32]()
    var shells = List[BufferGeometry]()
    var under = dress_pieces(
        assets.geometries.get(
            scene.skinned_meshes[person.skins[0]].geometry
        ).clone(),
        person,
        shod,
        over,
        shells,
    )
    # The boots under the sabatons keep no last of their own; the whole
    # shells keep theirs.
    assert_true(under[0].vertex_count() < alone[0].vertex_count())
    assert_true(under[1].triangle_count() > 0)
    assert_true(shells[0].vertex_count() > under[0].vertex_count())


def test_a_longer_skirt_over_a_skirt_hides_it() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var cover = Cover()
    cover.reach_to(HIPS)
    cover.reach_to(SPINE)
    cover.reach_to(CHEST)
    cover.reach_to(RIGHT_THIGH, 0.12)
    cover.reach_to(LEFT_THIGH, 0.12)
    var short = Garment(
        "short",
        TORSO_SLOT,
        OVER_LAYER,
        WOOL,
        cover^,
        Color(90, 90, 90),
        form=SKIRTED,
        flare=0.2,
    )
    # A short skirt over the tunic's leaves the tunic's skirt to show
    # below it; a surcoat that falls past it hides it.
    var under_short = Outfit()
    under_short.add(tunic())
    under_short.add(short^)
    var under_long = Outfit()
    under_long.add(tunic())
    under_long.add(surcoat())
    var shown = _pieces(scene, assets, person, under_short)[0].triangle_count()
    var hidden = _pieces(scene, assets, person, under_long)[0].triangle_count()
    assert_true(shown > hidden)


def test_a_belt_is_a_level_band_over_the_tunic() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var belted = Outfit()
    belted.add(tunic())
    belted.add(belt())
    var pieces = _pieces(scene, assets, person, belted)
    # The belt's top and bottom edges are level: it spans no more than
    # its own depth.
    ref placed = pieces[1].attribute_view(String(POSITION))
    var low = Float32(1e9)
    var high = Float32(-1e9)
    for v in range(placed.count()):
        low = min(low, placed.vector3(v).y)
        high = max(high, placed.vector3(v).y)
    assert_true(placed.count() > 0)
    assert_true(high - low <= BAND_HEIGHT * 1.01)
    # The tunic shows whole under it.
    var alone = Outfit()
    alone.add(tunic())
    assert_equal(
        pieces[0].triangle_count(),
        _pieces(scene, assets, person, alone)[0].triangle_count(),
    )


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
    var bald = coarse_person(scene, assets, guides=6, cards=6)
    var hair = bald.hair.value()
    bald.hair = None
    bald.strands[0].node = None
    bald.cards[0].node = None
    var hooded = Outfit()
    hooded.add(hood())
    _ = dress(scene, assets, bald, hooded)
    assert_true(scene.node(hair).visible)


def test_a_hood_hides_a_beard() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var bearded = add_game_humanoid(
        scene,
        assets,
        root,
        coarse_spec(),
        3000,
        12,
        8,
        8,
        workers=1,
        beard=GOATEE,
    )
    var hooded = Outfit()
    hooded.add(hood())
    _ = dress(scene, assets, bearded, hooded)
    assert_false(scene.node(bearded.beard.value()).visible)
    assert_false(scene.node(bearded.hair.value()).visible)


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


def _shell_triangles(scene: Scene, assets: Assets, node: NodeId) raises -> Int:
    """Return how many triangles the mesh on a node draws."""
    for mesh in scene.meshes:  # pragma: no branch
        if mesh.node == node:
            return assets.geometries.get(mesh.geometry).triangle_count()
    return -1


def test_a_hat_keeps_the_hair_and_lays_it_under_its_crown() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets, guides=6, cards=6)
    var shell = person.hair.value()
    var before = _shell_triangles(scene, assets, shell)
    var cards = person.cards[0].groom.points.copy()
    var outfit = Outfit()
    outfit.add(straw_hat())
    var dressed = dress(scene, assets, person, outfit)
    # The hair shows under the hat; its shell over the band is cut away,
    # and the cards over the band are laid under the hat.
    assert_true(scene.node(shell).visible)
    assert_true(scene.node(person.cards[0].node.value()).visible)
    assert_true(_shell_triangles(scene, assets, shell) < before)
    assert_false(person.cards[0].groom.points == cards)
    ref hat = assets.geometries.get(
        scene.skinned_meshes[dressed.meshes[0]].geometry
    )
    assert_true(hat.has_attribute(String(ACCENT)))
    # A crown is open over the hair, so the shell stays whole.
    var crowned = coarse_person(scene, assets)
    var whole = crowned.hair.value()
    var count = _shell_triangles(scene, assets, whole)
    var regalia = Outfit()
    regalia.add(crown())
    _ = dress(scene, assets, crowned, regalia)
    assert_equal(_shell_triangles(scene, assets, whole), count)


def test_great_pauldrons_dome_the_shoulders() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var skin_before = assets.geometries.get(
        scene.skinned_meshes[person.skins[0]].geometry
    ).triangle_count()
    var outfit = Outfit()
    outfit.add(great_pauldrons())
    var dressed = dress(scene, assets, person, outfit)
    assert_true(dressed.meshes[0] >= 0)
    # A dome hides none of the skin under it.
    assert_equal(
        assets.geometries.get(
            scene.skinned_meshes[person.skins[0]].geometry
        ).triangle_count(),
        skin_before,
    )
    ref domes = assets.geometries.get(
        scene.skinned_meshes[dressed.meshes[0]].geometry
    )
    assert_true(domes.triangle_count() > 200)


def test_a_great_helm_hides_the_hair() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets, cards=6)
    var outfit = Outfit()
    outfit.add(great_helm())
    _ = dress(scene, assets, person, outfit)
    assert_false(scene.node(person.hair.value()).visible)
    assert_false(scene.node(person.cards[0].node.value()).visible)
    # A person whose hair has no shell still wears a closed hat.
    var shorn = coarse_person(scene, assets, cards=6)
    shorn.hair = None
    var hatted = Outfit()
    hatted.add(straw_hat())
    _ = dress(scene, assets, shorn, hatted)
    assert_true(scene.node(shorn.cards[0].node.value()).visible)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
