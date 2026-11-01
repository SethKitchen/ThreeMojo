# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for outfits, and for dressing a game humanoid in one."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
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
    NO_RUFFLES,
    ARMOR_LAYER,
    LEGS_SLOT,
    PLATE,
    BROCADE,
    DAMASK,
    TARTAN,
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
    HEAD,
    HIPS,
    LEFT_THIGH,
    RIGHT_SHIN,
    RIGHT_THIGH,
    SPINE,
)
from render.framebuffer import Color
from extensions.attire.skirt import skirt_top
from math.vector3 import Vector3
from extensions.attire.apparel import cassock, crown, straw_hat
from extensions.attire.armory import (
    great_helm,
    great_pauldrons,
    plate_legs,
    scale_shirt,
)
from extensions.attire.mesh_ops import ACCENT
from extensions.attire.outfit import (
    Dressed,
    Outfit,
    dress,
    dress_pieces,
    _head_skin,
    garment_detail,
    still_face_geometry,
)
from objects.skinned_mesh import SKIN_INDEX, SKIN_WEIGHT
from extensions.attire.tailor import chemise, doublet, skirt
from extensions.attire.apparel import trousers
from core.deform import skin_carriers, skin_pose
from units.si import DEGREE, Angle
from extensions.attire.apparel import fur_mantle
from extensions.attire.garment import jerkin
from render.texture_store import NO_TEXTURE
from std.testing import (
    TestSuite,
    assert_almost_equal,
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
    var boots_look = assets.materials.get(
        scene.skinned_meshes[dressed.meshes[5]].material
    )
    assert_true(hauberk_look.bump_map != NO_TEXTURE)
    assert_true(hauberk_look.bump_map == coif_look.bump_map)
    assert_true(boots_look.bump_map != NO_TEXTURE)
    assert_true(boots_look.bump_map != hauberk_look.bump_map)
    # The mail has no opening, so the shirt and the gambeson under it are
    # cut away to its hems: they draw nothing.
    assert_equal(dressed.meshes[0], -1)
    assert_equal(dressed.meshes[2], -1)
    # The outfit hides most of the skin.
    var skin_after = assets.geometries.get(
        scene.skinned_meshes[person.skins[0]].geometry
    ).triangle_count()
    assert_true(skin_after * 3 < skin_before)
    # The coif covers the head: the hair hides.
    assert_false(scene.node(person.hair.value()).visible)
    assert_false(scene.node(person.strands[0].node.value()).visible)
    assert_false(scene.node(person.cards[0].node.value()).visible)
    # A gambeson worn alone shows, with its quilting.
    var padded = Outfit()
    padded.add(gambeson())
    var alone = dress(scene, assets, person, padded)
    assert_true(alone.meshes[0] >= 0)
    var gambeson_look = assets.materials.get(
        scene.skinned_meshes[alone.meshes[0]].material
    )
    assert_true(gambeson_look.bump_map != NO_TEXTURE)
    assert_true(gambeson_look.bump_map != hauberk_look.bump_map)


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


def test_a_hood_closes_over_a_speaking_face() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var speaker = add_game_humanoid(
        scene,
        assets,
        root,
        coarse_spec(),
        2400,
        12,
        8,
        8,
        workers=1,
        facial_animation=True,
        face_stand_in=400,
    )
    var still = still_face_geometry(scene, speaker).value()
    var before = assets.geometries.get(still).triangle_count()
    var hooded = Outfit()
    hooded.add(hood())
    var dressed = dress(scene, assets, speaker, hooded)
    # The hood is cut from the still face too: some of its vertices only
    # the head bone turns. It hides the still face's scalp.
    ref piece = assets.geometries.get(
        scene.skinned_meshes[dressed.meshes[0]].geometry
    )
    ref bones = piece.attribute_view(String(SKIN_INDEX))
    ref weights = piece.attribute_view(String(SKIN_WEIGHT))
    var headed = 0
    for v in range(piece.vertex_count()):
        if Int(bones.component(v, 0)) == HEAD.value and (
            weights.component(v, 0) == 1
        ):
            headed += 1
    assert_true(headed > 0)
    assert_true(assets.geometries.get(still).triangle_count() < before)
    assert_false(scene.node(speaker.hair.value()).visible)
    # A person without a still face has none to dress.
    var plain = coarse_person(scene, assets)
    assert_false(Bool(still_face_geometry(scene, plain)))


def test_a_face_is_dressed_as_a_skin_the_head_turns() raises:
    var body = BufferGeometry()
    body.set_attribute(String(POSITION), BufferAttribute([0, 0, 0], 3))
    body.set_attribute(String(UV), BufferAttribute([0.5, 0.5], 2))
    body.set_attribute("thinness", BufferAttribute([0.2], 1))
    body.set_attribute(String(SKIN_INDEX), BufferAttribute([3, 0, 0, 0], 4))
    body.set_attribute(String(SKIN_WEIGHT), BufferAttribute([1, 0, 0, 0], 4))
    var face = BufferGeometry()
    face.set_attribute(
        String(POSITION), BufferAttribute([0, 1, 0, 1, 1, 0, 0, 2, 0], 3)
    )
    face.set_attribute(String(UV), BufferAttribute([0, 0, 1, 0, 0, 1], 2))
    face.set_index([0, 1, 2])
    var skin = _head_skin(face, body)
    # The head turns each vertex wholly; the face keeps what it has, and
    # what it lacks is zero.
    assert_equal(skin.vertex_count(), 3)
    for v in range(3):
        assert_equal(
            Int(skin.attribute_view(String(SKIN_INDEX)).component(v, 0)),
            HEAD.value,
        )
        assert_equal(
            skin.attribute_view(String(SKIN_WEIGHT)).component(v, 0), 1
        )
        assert_equal(skin.attribute_view("thinness").component(v, 0), 0)
    assert_equal(skin.attribute_view(String(UV)).component(1, 0), 1)
    assert_equal(len(skin.index), 3)


def test_a_hat_sits_on_a_speaking_head() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var speaker = add_game_humanoid(
        scene,
        assets,
        root,
        coarse_spec(),
        2400,
        12,
        8,
        8,
        workers=1,
        facial_animation=True,
        face_stand_in=400,
    )
    var hatted = Outfit()
    hatted.add(straw_hat())
    var dressed = dress(scene, assets, speaker, hatted)
    # The hat is made round the still face's head.
    assert_true(
        assets.geometries.get(
            scene.skinned_meshes[dressed.meshes[0]].geometry
        ).triangle_count()
        > 0
    )


def _legs_drawn(
    scene: Scene, assets: Assets, person: GameHumanoid
) raises -> Int:
    """Count the skin's triangles wholly on a leg, from the knee to the
    hips."""
    ref skin = assets.geometries.get(
        scene.skinned_meshes[person.skins[0]].geometry
    )
    ref points = skin.attribute_view(String(POSITION))
    var knee = person.rig.at(RIGHT_SHIN).y
    var hips = person.rig.at(HIPS).y - 0.1
    var count = 0
    for t in range(len(skin.index) // 3):
        var inside = True
        for c in range(3):
            var p = points.vector3(skin.index[3 * t + c])
            if not (p.y > knee and p.y < hips and abs(p.x) > 0.03):
                inside = False
        if inside:
            count += 1
    return count


def test_a_long_skirt_hides_the_legs_inside_it() raises:
    var scene = Scene()
    var assets = Assets()
    var bare = coarse_person(scene, assets)
    var before = _legs_drawn(scene, assets, bare)
    assert_true(before > 0)
    # A robe to the ankles hides the thighs and the knees inside it, but
    # for a few triangles by the crotch, where its own cover decides.
    var robed = Outfit()
    robed.add(cassock())
    _ = dress(scene, assets, bare, robed)
    assert_true(_legs_drawn(scene, assets, bare) * 8 < before)
    # A tunic's short skirt hides them only where its own cover reaches,
    # at the top of the thighs: a kick lifts them out.
    var other = coarse_person(scene, assets)
    var short = Outfit()
    short.add(tunic())
    _ = dress(scene, assets, other, short)
    assert_true(_legs_drawn(scene, assets, other) * 10 > before * 9)


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


def test_a_coarse_skin_s_garments_take_less_detail() raises:
    var counts: List[Int] = [2500, 100, 10000, 40000]
    var shares: List[Float32] = [0.5, 0.5, 1, 1]
    for k in range(len(counts)):
        var skin = BufferGeometry()
        skin.set_attribute(
            String(POSITION),
            BufferAttribute(List[Float32](length=9, fill=0), 3),
        )
        skin.set_index(List[Int](length=3 * counts[k], fill=0))
        assert_almost_equal(garment_detail(skin), shares[k])
    var between = BufferGeometry()
    between.set_attribute(
        String(POSITION), BufferAttribute(List[Float32](length=9, fill=0), 3)
    )
    between.set_index(List[Int](length=3 * 4900, fill=0))
    assert_almost_equal(garment_detail(between), 0.7, atol=1e-4)


def test_a_design_draws_a_garment_in_parts() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var outfit = Outfit()
    outfit.add(shirt())
    var coat = doublet()
    coat.design = BROCADE
    outfit.add(coat^)
    var legs = hose()
    legs.design = TARTAN
    outfit.add(legs^)
    outfit.add(boots())
    var dressed = dress(scene, assets, person, outfit)
    # The doublet has no opening, so the shirt under it draws nothing.
    assert_equal(len(dressed.parts[0]), 0)
    assert_equal(dressed.meshes[0], -1)
    # A plain shirt worn alone is one part, drawn without a map.
    var plain = Outfit()
    plain.add(shirt())
    var alone = dress(scene, assets, person, plain)
    assert_equal(len(alone.parts[0]), 1)
    assert_equal(alone.parts[0][0], alone.meshes[0])
    ref linen = scene.skinned_meshes[alone.meshes[0]]
    assert_equal(assets.materials.get(linen.material).map, NO_TEXTURE)
    # A brocade doublet: the brocade, its plain panel, its braided trim.
    assert_equal(len(dressed.parts[1]), 3)
    assert_equal(dressed.parts[1][0], dressed.meshes[1])
    var maps = List[Int]()
    for k in dressed.parts[1]:
        var id = assets.materials.get(scene.skinned_meshes[k].material).map
        maps.append(id.value)
    assert_true(maps[0] != NO_TEXTURE.value)
    assert_equal(maps[1], NO_TEXTURE.value)
    assert_true(maps[2] != NO_TEXTURE.value and maps[2] != maps[0])
    # The brocade's vertex colors are white but for wear.
    ref brocade = assets.geometries.get(
        scene.skinned_meshes[dressed.meshes[1]].geometry
    )
    ref colors = brocade.attribute_view(String(COLOR))
    assert_almost_equal(colors.component(0, 1), 1, atol=0.01)
    # Tartan braids nothing, and the boots hide the hose's hems.
    assert_equal(len(dressed.parts[2]), 1)
    # Leather boots wear hide.
    ref hide = scene.skinned_meshes[dressed.meshes[3]]
    assert_true(assets.materials.get(hide.material).map != NO_TEXTURE)
    # Damask lies on the doublet's body and panel alike, and braids its
    # trim.
    var other = coarse_person(scene, assets)
    var fine = Outfit()
    var damask = doublet()
    damask.design = DAMASK
    fine.add(damask^)
    assert_equal(len(dress(scene, assets, other, fine).parts[0]), 2)
    # A garment hidden wholly has no parts.
    var bare = Dressed([-1], [BufferGeometry()])
    assert_equal(len(bare.parts[0]), 0)


def test_frills_fur_and_hide_each_draw_their_part() raises:
    var scene = Scene()
    var assets = Assets()
    var plain = coarse_person(scene, assets)
    var frilled = coarse_person(scene, assets)
    var bare = Outfit()
    var linen = chemise()
    linen.ruffles = NO_RUFFLES
    bare.add(linen^)
    var frills = Outfit()
    frills.add(chemise())
    var one = dress(scene, assets, plain, bare)
    var two = dress(scene, assets, frilled, frills)
    var smooth = _mesh_of(scene, assets, one.meshes[0]).triangle_count()
    var ruffled = _mesh_of(scene, assets, two.meshes[0]).triangle_count()
    assert_true(ruffled > smooth + 100)
    # Fur stands in shells, each testing a higher share of its strands.
    var furred = coarse_person(scene, assets)
    var pelts = Outfit()
    pelts.add(fur_mantle())
    pelts.add(jerkin())
    var worn = dress(scene, assets, furred, pelts)
    assert_true(len(worn.parts[0]) > 2)
    var strands = NO_TEXTURE
    var last = Float32(0)
    for k in range(1, len(worn.parts[0])):
        ref look = assets.materials.get(
            scene.skinned_meshes[worn.parts[0][k]].material
        )
        assert_true(look.alpha_test > last)
        last = look.alpha_test
        if k == 1:
            strands = look.alpha_map
        assert_equal(look.alpha_map, strands)
    assert_true(strands != NO_TEXTURE)
    # Leather's hide mottles its sheen too.
    ref hide = assets.materials.get(
        scene.skinned_meshes[worn.meshes[1]].material
    )
    assert_true(hide.roughness_map != NO_TEXTURE)
    assert_equal(hide.roughness_map, hide.map)


def _mesh_of(scene: Scene, assets: Assets, mesh: Int) raises -> BufferGeometry:
    """Return the geometry a garment draws, in its bind pose."""
    return assets.geometries.get(scene.skinned_meshes[mesh].geometry).clone()


def _posed(scene: Scene, assets: Assets, mesh: Int) raises -> BufferGeometry:
    """Return a skinned mesh's geometry, carried by its bones as they stand:
    its positions and its normals."""
    var geometry = assets.geometries.get(
        scene.skinned_meshes[mesh].geometry
    ).clone()
    var count = geometry.vertex_count()
    var carriers = skin_carriers(geometry, skin_pose(scene, mesh), count)
    var placed = geometry.clone_attribute(String(POSITION))
    var normals = geometry.clone_attribute(String(NORMAL))
    for v in range(count):
        var p = placed.vector3(v)
        p.apply_matrix4(carriers[v])
        placed.set_component(v, 0, p.x)
        placed.set_component(v, 1, p.y)
        placed.set_component(v, 2, p.z)
        var n = normals.vector3(v)
        n.transform_direction(carriers[v])
        normals.set_component(v, 0, n.x)
        normals.set_component(v, 1, n.y)
        normals.set_component(v, 2, n.z)
    geometry.set_attribute(String(POSITION), placed^)
    geometry.set_attribute(String(NORMAL), normals^)
    return geometry^


def _poking(
    legs: BufferGeometry,
    skirt: BufferGeometry,
    under: List[Bool],
    axis: Vector3,
) raises -> Int:
    """Return how many of the legs' vertices that `under` names stand
    more than 3 mm out past the outer face of the skirt nearest them. The
    outer face looks away from a vertical axis; the lining looks in."""
    ref placed = legs.attribute_view(String(POSITION))
    ref over = skirt.attribute_view(String(POSITION))
    ref facing = skirt.attribute_view(String(NORMAL))
    var outer = List[Bool]()
    for s in range(over.count()):
        var away = over.vector3(s) - axis
        away.y = 0
        outer.append(facing.vector3(s).dot(away) > 0)
    var count = 0
    for v in range(placed.count()):
        if not under[v]:
            continue
        var p = placed.vector3(v)
        var nearest = 0
        var closest = Float32(1e30)
        for s in range(over.count()):
            if not outer[s]:
                continue
            var d = (over.vector3(s) - p).length_sq()
            if d < closest:
                closest = d
                nearest = s
        if (p - over.vector3(nearest)).dot(facing.vector3(nearest)) > 0.003:
            count += 1
    return count


def test_trousers_stay_under_a_tunic_as_a_thigh_swings() raises:
    for angle in [Float32(-35), Float32(35)]:
        var scene = Scene()
        var assets = Assets()
        var person = coarse_person(scene, assets)
        var outfit = Outfit()
        outfit.add(trousers())
        outfit.add(tunic())
        var dressed = dress(scene, assets, person, outfit)
        var top = skirt_top(person.rig)
        # The legs' vertices under the tunic's skirt, at rest.
        var hem = Float32(1e9)
        var coat = _mesh_of(scene, assets, dressed.meshes[1])
        ref hung = coat.attribute_view(String(POSITION))
        for v in range(hung.count()):
            hem = min(hem, hung.vector3(v).y)
        var legs = _mesh_of(scene, assets, dressed.meshes[0])
        ref rest = legs.attribute_view(String(POSITION))
        var under = List[Bool]()
        for v in range(rest.count()):
            var y = rest.vector3(v).y
            under.append(y < top - 0.02 and y > hem + 0.02)
        # One thigh swings forward or back, as in a stride.
        scene.node(person.bones[RIGHT_THIGH.value]).rotate_x(
            Angle(angle, DEGREE)
        )
        scene.update()
        var posed = _posed(scene, assets, dressed.meshes[0])
        var skirt = _posed(scene, assets, dressed.meshes[1])
        var axis = person.rig.joints[HIPS.value]
        assert_equal(_poking(posed, skirt, under, axis), 0)


def test_a_garment_that_covers_nothing_draws_nothing() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var outfit = Outfit()
    outfit.add(
        Garment(
            "nothing", TORSO_SLOT, OVER_LAYER, LINEN, Cover(), Color(9, 9, 9)
        )
    )
    var dressed = dress(scene, assets, person, outfit)
    assert_equal(dressed.meshes[0], -1)
    assert_false(dressed.shells[0].has_attribute(String(POSITION)))
    assert_equal(len(dressed.parts[0]), 0)


def test_a_skirt_hangs_clear_of_plate_on_one_thigh() raises:
    var scene = Scene()
    var assets = Assets()
    var person = coarse_person(scene, assets)
    var cuisse = Cover()
    cuisse.reach_to(LEFT_THIGH, 0.8)
    var plate = Garment(
        "left cuisse",
        LEGS_SLOT,
        ARMOR_LAYER,
        PLATE,
        cuisse^,
        Color(200, 200, 205),
    )
    var outfit = Outfit()
    outfit.add(plate^)
    outfit.add(skirt())
    var dressed = dress(scene, assets, person, outfit)
    assert_true(dressed.meshes[1] >= 0)
    # The skirt stands out past the plate on the left thigh.
    var reach = _skirt_reach(person, dressed.shells[1], 0.15)
    assert_true(reach > _skirt_reach(person, dressed.shells[0], 0.15))


def _skirt_reach(
    person: GameHumanoid, shell: BufferGeometry, below: Float32
) raises -> Float32:
    """Return how far a skirt's shell reaches from the hips' axis, a band
    of 10 cm about `below` under the skirt's top."""
    var top = skirt_top(person.rig)
    var hips = person.rig.joints[HIPS.value]
    ref placed = shell.attribute_view(String(POSITION))
    var reach = Float32(0)
    for v in range(placed.count()):
        var p = placed.vector3(v)
        if abs(top - below - p.y) < 0.05:
            reach = max(reach, Vector3(p.x - hips.x, 0, p.z - hips.z).length())
    return reach


def test_a_skirt_hangs_clear_of_plate_on_the_legs() raises:
    var scene = Scene()
    var assets = Assets()
    var alone = coarse_person(scene, assets)
    var plated = coarse_person(scene, assets)
    var bare = Outfit()
    bare.add(scale_shirt())
    var armored = Outfit()
    armored.add(plate_legs())
    armored.add(scale_shirt())
    var one = dress(scene, assets, alone, bare)
    var two = dress(scene, assets, plated, armored)
    # Over the thighs' plate, the shirt's skirt stands farther out.
    var without = _skirt_reach(alone, one.shells[0], 0.2)
    var over = _skirt_reach(plated, two.shells[1], 0.2)
    assert_true(without > 0)
    assert_true(over > without)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
