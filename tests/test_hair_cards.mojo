# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for hair cards: a groom drawn as ribbons of fibers."""

from core.assets import Assets
from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, POSITION, UV, BufferGeometry
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.head.frame import head_muscle_dimensions
from extensions.humanoid.skeleton.head.hair.beard import (
    CHIN_STRAP,
    CLEAN_SHAVEN,
    FORKED_BEARD,
    FULL_BEARD,
    GOATEE,
    LONG_BEARD,
    MUSTACHE,
    MUTTON_CHOPS,
    SHORT_BEARD,
    STUBBLE,
    Beard,
    BeardShape,
    beard_mesh,
)
from extensions.humanoid.skeleton.head.hair.cards import (
    _surface_normal,
    add_beard_cards,
    beard_groom,
    beard_reach,
    CARD_POINTS,
    CARD_TILE,
    FIBER_TEXELS,
    ROOT_SHADE,
    TIP_SHARE,
    HairCards,
    add_cards,
    add_hair_cards,
    card_groom,
    card_material,
    card_width,
    fiber_heights,
    fiber_texture,
)
from extensions.humanoid.skeleton.head.hair.groom import HairGroom
from extensions.humanoid.skeleton.head.hair.shading import HairLight, HairLook
from extensions.humanoid.skeleton.head.hair.styles import PONYTAIL
from materials.material import BASIC, DOUBLE_SIDE
from math.vector3 import Vector3
from render.texture_store import NO_TEXTURE
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import FOOT, Length


def _strand(mut groom: HairGroom, x: Float32, count: Int):
    """Add a strand of `count` points hanging from (x, 0.3, 0), facing
    plus z."""
    var points = List[Vector3]()
    for k in range(count):
        points.append(Vector3(x, 0.3 - Float32(k) * 0.01, 0))
    var normals = List[Vector3](length=count, fill=Vector3(0, 0, 1))
    var depths = List[Float32](length=count, fill=0)
    groom.add(points, normals, depths, 1)


def _look() -> HairLook:
    """Return a brown fiber."""
    return HairLook(Vector3(0.2, 0.1, 0.05))


def test_the_fibers_ridge_and_part() raises:
    var alpha = fiber_heights(1)
    assert_equal(len(alpha), FIBER_TEXELS * FIBER_TEXELS)
    var lowest = Float32(1)
    var highest = Float32(0)
    var above = 0
    for a in alpha:
        lowest = min(lowest, a)
        highest = max(highest, a)
        if a >= 0.5:
            above += 1
    # Gaps between the fibers and where a fiber ends, and full ridges.
    assert_equal(lowest, 0)
    assert_true(highest > 0.95 and highest <= 1)
    # Most of a tile stays above the cutoff, so a far card stays whole.
    assert_true(Float32(above) / Float32(len(alpha)) > 0.5)
    assert_true(fiber_heights(1) == alpha)
    assert_false(fiber_heights(2) == alpha)
    var fibers = fiber_texture(1)
    assert_equal(fibers.width, FIBER_TEXELS)
    assert_equal(fibers.height, FIBER_TEXELS)


def test_a_card_groom_keeps_the_guides() raises:
    var groom = HairGroom()
    _strand(groom, 0, 40)
    _strand(groom, 0.01, 40)
    # A follower of the first strand, and a strand of one point.
    groom.guides[1] = 0
    _strand(groom, 0.02, 1)
    _strand(groom, 0.03, 5)
    var cards = card_groom(groom)
    assert_equal(len(cards), 2)
    # A long strand keeps its root, its tip and evenly spaced points.
    assert_equal(cards.starts[1], CARD_POINTS)
    assert_true(cards.points[0] == groom.points[0])
    assert_true(cards.points[CARD_POINTS - 1] == groom.points[39])
    # A short one keeps all of its points.
    assert_equal(cards.starts[2] - cards.starts[1], 5)
    assert_equal(cards.guides[0], -1)
    with assert_raises(contains="two points of its strand"):
        _ = card_groom(groom, 1)
    # With no guide records, every strand is a guide.
    groom.guides.clear()
    assert_equal(len(card_groom(groom, 4)), 3)
    var single = HairGroom()
    _strand(single, 0, 1)
    with assert_raises(contains="needs a guide strand"):
        _ = card_groom(single)
    with assert_raises(contains="needs a guide strand"):
        _ = card_groom(HairGroom())


def test_a_card_is_as_wide_as_its_share_of_the_scalp() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var few = card_width(person, 150)
    var many = card_width(person, 600)
    assert_true(few > many)
    assert_true(many > 0.015 and many < 0.03)
    with assert_raises(contains="one card or more"):
        _ = card_width(person, 0)


def test_cards_refuse_what_cannot_be_drawn() raises:
    var assets = Assets()
    var id = assets.geometries.add(BufferGeometry())
    with assert_raises(contains="need a strand"):
        _ = HairCards(HairGroom(), id, _look(), 0.01, 0.005)
    var groom = HairGroom()
    _strand(groom, 0, 3)
    groom.depths.append(0)
    with assert_raises(contains="must match the groom"):
        _ = HairCards(groom^, id, _look(), 0.01, 0.005)
    var widths: List[Float32] = [0, 1, 0.01, 0.01]
    var tips: List[Float32] = [0.005, 0.005, 0, 1]
    for k in range(len(widths)):
        var strand = HairGroom()
        _strand(strand, 0, 3)
        with assert_raises(contains="widths must be positive"):
            _ = HairCards(strand^, id, _look(), widths[k], tips[k])


def test_a_card_is_a_ribbon_along_its_strand() raises:
    var assets = Assets()
    var id = assets.geometries.add(BufferGeometry())
    var groom = HairGroom()
    _strand(groom, 0, 5)
    _strand(groom, 0.05, 3)
    var cards = HairCards(groom^, id, _look(), 0.02, 0.004)
    var lights: List[HairLight] = [
        HairLight(Vector3(0, 0, 1), Vector3(2, 2, 2))
    ]
    cards.shade(assets, lights, Vector3(0, 0.3, 1), Vector3(0.1, 0.1, 0.1))
    ref mesh = assets.geometries.get(id)
    ref places = mesh.attribute_view(String(POSITION))
    assert_equal(places.count(), 16)
    assert_equal(mesh.triangle_count(), 2 * (4 + 2))
    # The root is as wide as asked, across the strand and the normal.
    var root = places.vector3(1) - places.vector3(0)
    assert_true(abs(root.length() - 0.02) < 1e-5)
    assert_true(abs(root.x) > 0.0199)
    var tip = places.vector3(9) - places.vector3(8)
    assert_true(abs(tip.length() - 0.004) < 1e-5)
    ref uv = mesh.attribute_view(String(UV))
    assert_equal(uv.component(0, 0), 0)
    assert_equal(uv.component(1, 0), 1)
    assert_true(abs(uv.component(8, 1) - 0.04 / CARD_TILE) < 1e-4)
    # The root is darker than the rest of the card.
    ref colors = mesh.attribute_view(String(COLOR))
    assert_true(colors.component(0, 0) > 0)
    var root_share = colors.component(0, 0) / max(
        colors.component(6, 0), Float32(1e-9)
    )
    assert_true(root_share < 0.9 and root_share > ROOT_SHADE * 0.5)
    # A strand of one point makes no card.
    cards.groom.starts[1] = 1
    with assert_raises(contains="two points of its strand"):
        _ = cards.mesh()


def test_the_card_material_cuts_the_fibers() raises:
    var look = card_material(NO_TEXTURE)
    assert_equal(look.kind, BASIC)
    assert_equal(look.side, DOUBLE_SIDE)
    assert_true(look.vertex_colors)
    assert_equal(look.alpha_test, 0.5)


def test_cards_in_a_scene() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var groom = HairGroom()
    _strand(groom, 0, 6)
    _strand(groom, 0.02, 6)
    var cards = add_cards(scene, assets, root, groom^, _look(), 0.02)
    assert_equal(len(scene.meshes), 1)
    assert_true(scene.meshes[0].cast_shadow)
    assert_true(cards.node.value() == scene.meshes[0].node)
    assert_true(cards.material.value() == scene.meshes[0].material)
    assert_true(abs(cards.tip_width - 0.02 * TIP_SHARE) < 1e-6)
    assert_equal(assets.geometries.get(cards.geometry).triangle_count(), 20)


def test_a_person_grows_cards() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var cards = add_hair_cards(scene, assets, root, person, 30, style=PONYTAIL)
    assert_true(len(cards.groom) > 20)
    assert_equal(cards.groom.guides[0], -1)
    assert_true(abs(cards.root_width - card_width(person, 30)) < 1e-6)


def test_a_beard_reaches_as_far_as_its_style() raises:
    assert_true(abs(beard_reach(MUSTACHE) - 0.016) < 1e-6)
    assert_equal(beard_reach(SHORT_BEARD), beard_reach(CHIN_STRAP))
    assert_true(abs(beard_reach(GOATEE) - 0.024) < 1e-6)
    assert_equal(beard_reach(GOATEE), beard_reach(MUTTON_CHOPS))
    assert_true(abs(beard_reach(FULL_BEARD) - 0.05) < 1e-6)
    assert_true(beard_reach(LONG_BEARD) > beard_reach(FORKED_BEARD))
    with assert_raises(contains="grows no cards"):
        _ = beard_reach(CLEAN_SHAVEN)
    with assert_raises(contains="grows no cards"):
        _ = beard_reach(STUBBLE)
    with assert_raises(contains="named style"):
        _ = beard_reach(Beard(40))


def test_a_beard_s_strands_lie_on_it_down_its_lock() raises:
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var dims = head_muscle_dimensions(person)
    var shape = BeardShape(dims, LONG_BEARD)
    var shell = beard_mesh(dims, LONG_BEARD, 12)
    var groom = beard_groom(shape, shell, 40)
    assert_equal(len(groom), 40)
    var longest = Float32(0)
    for strand in range(len(groom)):
        var first = groom.starts[strand]
        var last = groom.starts[strand + 1] - 1
        assert_true(last > first)
        # Each point lies on the beard's surface, just off it.
        for k in range(first, last + 1):
            assert_true(abs(shape.distance(groom.points[k])) < 0.004)
        longest = max(longest, groom.points[first].y - groom.points[last].y)
    # Some strands run far down the lock.
    assert_true(longest > 0.08)
    with assert_raises(contains="one strand or more"):
        _ = beard_groom(shape, shell, 0)
    var empty = BufferGeometry()
    empty.set_attribute(String(POSITION), BufferAttribute(List[Float32](), 3))
    with assert_raises(contains="needs a vertex"):
        _ = beard_groom(shape, empty, 4)
    # Where the field is the same everywhere, its normal looks forward.
    var bare = BeardShape(dims, CLEAN_SHAVEN)
    assert_true(_surface_normal(bare, shape.mouth) == Vector3(0, 0, 1))


def test_a_beard_grows_cards() raises:
    var scene = Scene()
    var assets = Assets()
    var root = scene.add(Object3D())
    var person = HumanoidSpec(Length(6.0, FOOT), MALE)
    var dims = head_muscle_dimensions(person)
    var cards = add_beard_cards(
        scene,
        assets,
        root,
        person,
        beard_mesh(dims, FORKED_BEARD, 12),
        FORKED_BEARD,
        30,
    )
    assert_equal(len(cards.groom), 30)
    assert_true(cards.root_width < card_width(person, 600))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
