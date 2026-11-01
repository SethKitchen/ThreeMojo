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
from extensions.humanoid.rig.game_hair import (
    GameHairMotion,
    _toward,
    move_hair,
)
from extensions.humanoid.sex import MALE
from extensions.humanoid.skeleton.head.hair.beard import (
    CLEAN_SHAVEN,
    FULL_BEARD,
    STUBBLE,
    Beard,
)
from extensions.humanoid.skeleton.head.hair.shading import HairLight
from extensions.humanoid.skeleton.head.hair.simulation import HairWind
from extensions.humanoid.spec import HumanoidSpec
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from std.sys import num_logical_cores
from std.math import inf
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, FOOT, METER, Angle, Length


def _spec() -> HumanoidSpec:
    """Return the six-foot male template."""
    return HumanoidSpec(Length(6.0, FOOT), MALE)


def _person(
    mut scene: Scene,
    mut assets: Assets,
    cards: Int = 12,
    guides: Int = 6,
    beard: Beard = CLEAN_SHAVEN,
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
        beard=beard,
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
    # Hair far from the camera rides its head as it lay.
    scene.node(person.cards[0].node.value()).visible = True
    var far = person.cards[0].groom.points.copy()
    scene.node(person.root).set_position(0, 0, 0.3)
    scene.update()
    motion.update(
        scene,
        assets,
        person,
        _lights(),
        Vector3(0, 1.6, 40),
        Vector3(0.1, 0.1, 0.1),
        still,
    )
    assert_true(person.cards[0].groom.points == far)


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
    with assert_raises(contains="reach"):
        _ = GameHairMotion(scene, person, _spec(), reach=Length(0.0, METER))
    with assert_raises(contains="reach"):
        _ = GameHairMotion(
            scene, person, _spec(), reach=Length(inf[DType.float32](), METER)
        )
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


def test_a_beard_grows_cards_but_stubble_does_not() raises:
    var scene = Scene()
    var assets = Assets()
    var bearded = _person(scene, assets, 12, 0, FULL_BEARD)
    assert_equal(len(bearded.cards), 2)
    assert_true(len(bearded.cards[1].groom) >= 40)
    var stubbled = _person(scene, assets, 12, 0, STUBBLE)
    assert_equal(len(stubbled.cards), 1)
    var bare = _person(scene, assets, 0, 0, FULL_BEARD)
    assert_equal(len(bare.cards), 0)


def test_a_crowd_s_hair_moves_at_once_as_each_person_s_would() raises:
    var scene = Scene()
    var assets = Assets()
    var people = List[GameHumanoid]()
    people.append(_person(scene, assets))
    people.append(_person(scene, assets))
    # The second person stands far down the street.
    scene.node(people[1].root).set_position(0, 0, -40)
    scene.update()
    var motions = List[GameHairMotion]()
    for k in range(2):
        motions.append(GameHairMotion(scene, people[k], _spec()))
    var alone = _person(scene, assets)
    scene.update()
    var single = GameHairMotion(scene, alone, _spec())
    var near = people[0].cards[0].groom.points.copy()
    var far = people[1].cards[0].groom.points.copy()
    for k in range(2):
        scene.node(people[k].root).rotate_y(Angle(9.0, DEGREE))
    scene.node(alone.root).rotate_y(Angle(9.0, DEGREE))
    scene.update()
    var eye = Vector3(0, 1.6, 2)
    var still = HairWind(Vector3(1, 0, 0), 0)
    var ambient = Vector3(0.1, 0.1, 0.1)
    move_hair(motions, scene, assets, people, _lights(), eye, ambient, still, 3)
    single.update(scene, assets, alone, _lights(), eye, ambient, still)
    # The near person's hair swings as one person's alone does; the far
    # person's rides the head as it lay.
    assert_false(people[0].cards[0].groom.points == near)
    assert_true(people[0].cards[0].groom.points == alone.cards[0].groom.points)
    assert_true(
        people[0].strands[0].groom.points == alone.strands[0].groom.points
    )
    assert_true(people[1].cards[0].groom.points == far)
    # Nobody to move costs nothing.
    var nobody = List[GameHairMotion]()
    var none = List[GameHumanoid]()
    move_hair(nobody, scene, assets, none, _lights(), eye, ambient, still)


def test_a_crowd_s_hair_refuses_what_it_cannot_move() raises:
    var scene = Scene()
    var assets = Assets()
    var people = List[GameHumanoid]()
    people.append(_person(scene, assets))
    scene.update()
    var motions = List[GameHairMotion]()
    var eye = Vector3(0, 1.6, 2)
    var still = HairWind(Vector3(1, 0, 0), 0)
    var ambient = Vector3(0.1, 0.1, 0.1)
    with assert_raises(contains="one motion for each person"):
        move_hair(
            motions, scene, assets, people, _lights(), eye, ambient, still
        )
    motions.append(GameHairMotion(scene, people[0], _spec()))
    with assert_raises(contains="workers"):
        move_hair(
            motions, scene, assets, people, _lights(), eye, ambient, still, 0
        )
    # A groom that fails on a thread fails the frame.
    motions[0].simulations[0].physics.iterations = 16777217
    with assert_raises(contains="settle count"):
        move_hair(
            motions, scene, assets, people, _lights(), eye, ambient, still, 2
        )


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
