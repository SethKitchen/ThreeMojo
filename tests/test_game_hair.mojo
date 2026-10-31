# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for a game humanoid's hair cards and its hair in motion."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.humanoid.rig.game import (
    GameHumanoid,
    add_game_humanoid,
    game_build_settings,
)
from extensions.humanoid.rig.game_hair import GameHairMotion, _toward
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.simulation import HairWind
from extensions.humanoid.spec import HumanoidSpec
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.sys import num_logical_cores
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, FOOT, Angle, Length


def _spec() -> HumanoidSpec:
    """Return the six-foot male template."""
    return HumanoidSpec(Length(6.0, FOOT), MALE)


def _person(
    mut scene: Scene, mut assets: Assets, cards: Int = 12, guides: Int = 6
) raises -> GameHumanoid:
    """Return a coarse person with a few strands and a few cards."""
    var root = scene.add(Object3D())
    return add_game_humanoid(
        scene,
        assets,
        root,
        _spec(),
        3000,
        12,
        8,
        8,
        guides=guides,
        followers=1 if guides > 0 else 0,
        workers=num_logical_cores(),
        cards=cards,
    )


def _lights() -> List[HairLight]:
    """Return one light from above and in front."""
    var key = Vector3(0, 1, 1)
    key.normalize()
    return [HairLight(key, Vector3(2, 2, 2))]


def test_the_settings_record_the_cards() raises:
    var none = game_build_settings(3000)
    assert_false(none.has("cards"))
    var some = game_build_settings(3000, cards=40)
    assert_equal(some.string("cards"), "40")
    with assert_raises(contains="cards must be nonnegative"):
        _ = game_build_settings(cards=-1)
    with assert_raises(contains="do not support strand hair"):
        _ = game_build_settings(facial_animation=True, cards=4)


def test_a_person_grows_cards_over_a_thin_shell() raises:
    var scene = Scene()
    var assets = Assets()
    var person = _person(scene, assets)
    assert_equal(len(person.cards), 1)
    assert_equal(len(person.strands), 1)
    assert_true(len(person.cards[0].groom) > 6)
    var bare = _person(scene, assets, 0)
    assert_equal(len(bare.cards), 0)


def test_the_hair_swings_as_the_head_moves() raises:
    var scene = Scene()
    var assets = Assets()
    var person = _person(scene, assets)
    scene.update()
    var motion = GameHairMotion(scene, person, _spec())
    assert_equal(len(motion.simulations), 2)
    var before = person.cards[0].groom.points.copy()
    var strands_before = person.strands[0].groom.points.copy()
    # The person steps forward and turns: the loose points lag behind.
    scene.node(person.root).set_position(0, 0, 0.05)
    scene.node(person.root).rotate_y(Angle(7.0, DEGREE))
    scene.update()
    var eye = Vector3(0, 1.6, 2)
    var still = HairWind(Vector3(1, 0, 0), 0)
    motion.update(
        scene, assets, person, _lights(), eye, Vector3(0.1, 0.1, 0.1), still
    )
    var moved = False
    for k in range(len(before)):
        if (person.cards[0].groom.points[k] - before[k]).length() > 1e-4:
            moved = True
    assert_true(moved)
    assert_false(person.strands[0].groom.points == strands_before)
    # A groom a helmet hides is not moved.
    scene.node(person.cards[0].node.value()).visible = False
    var hidden = person.cards[0].groom.points.copy()
    scene.update()
    motion.update(
        scene, assets, person, _lights(), eye, Vector3(0.1, 0.1, 0.1), still
    )
    assert_true(person.cards[0].groom.points == hidden)


def test_a_person_with_cards_alone_or_no_hair_moves() raises:
    var scene = Scene()
    var assets = Assets()
    var carded = _person(scene, assets, 8, 0)
    var bald = _person(scene, assets, 0, 0)
    scene.update()
    var motion = GameHairMotion(scene, carded, _spec())
    assert_equal(len(motion.simulations), 1)
    var still = HairWind(Vector3(1, 0, 0), 0)
    # No lights: the hair is lit from all round alone.
    motion.update(
        scene,
        assets,
        carded,
        List[HairLight](),
        Vector3(0, 1.6, 2),
        Vector3(0.1, 0.1, 0.1),
        still,
    )
    var none = GameHairMotion(scene, bald, _spec())
    assert_equal(len(none.simulations), 0)
    none.update(
        scene,
        assets,
        bald,
        _lights(),
        Vector3(0, 1.6, 2),
        Vector3(0.1, 0.1, 0.1),
        still,
    )
    # A direction with no length is kept as it is.
    var flat = _toward(Matrix4(), Vector3(0, 0, 0))
    assert_true(flat == Vector3(0, 0, 0))


def test_hair_motion_refuses_what_it_cannot_move() raises:
    var scene = Scene()
    var assets = Assets()
    var person = _person(scene, assets)
    scene.update()
    with assert_raises(contains="one step an update"):
        _ = GameHairMotion(scene, person, _spec(), steps=0)
    var motion = GameHairMotion(scene, person, _spec(), steps=2)
    assert_equal(motion.steps, 2)
    var other = _person(scene, assets, 0)
    scene.update()
    with assert_raises(contains="another person"):
        motion.update(
            scene,
            assets,
            other,
            _lights(),
            Vector3(0, 1.6, 2),
            Vector3(0.1, 0.1, 0.1),
            HairWind(Vector3(1, 0, 0), 0),
        )
    var card_node = person.cards[0].node
    person.cards[0].node = None
    with assert_raises(contains="cards must hang from a node"):
        _ = GameHairMotion(scene, person, _spec())
    person.cards[0].node = card_node
    person.strands[0].node = None
    with assert_raises(contains="groom must hang from a node"):
        _ = GameHairMotion(scene, person, _spec())


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
