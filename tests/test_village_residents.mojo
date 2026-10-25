# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's people and animals: their bodies, their clips, their
flipbooks and their routes."""

from core.assets import Assets
from core.object3d import Object3D
from core.scene import Scene
from extensions.animals.registry import CHICKEN, RABBIT, SpeciesId
from extensions.humanoid.sex import FEMALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.vegetation.ground import Ground, Lot, Pond
from extensions.village.character import (
    AIRBORNE,
    RUNNING,
    STANDING,
    WALKING,
    Character,
    CharacterParameters,
    MoveInput,
    Obstacle,
)
from extensions.village.residents import (
    Body,
    Flipbook,
    Herd,
    JUMP_PLAY,
    Residents,
    ResidentsParameters,
    Route,
    Villager,
    clip_of,
    facing_turn,
    play_rate,
    wander_route,
)
from core.geometry_store import GeometryId
from math.vector3 import Vector3
from std.math import pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import (
    DEGREE,
    INCH,
    METER,
    METER_PER_SECOND,
    RADIAN,
    SECOND,
    Angle,
    Duration,
    Length,
    Velocity,
)


def _flat() raises -> Ground:
    """Return level ground with no pond."""
    return Ground(hill_height=Length(0.0, METER))


def _small() -> ResidentsParameters:
    """Return residents built with the smallest budgets."""
    var p = ResidentsParameters()
    p.triangles = 500
    p.detail = 8
    p.phases = 2
    p.rest = Duration(0.5, SECOND)
    return p^


def test_each_stance_plays_its_clip_at_its_rate() raises:
    assert_equal(clip_of(STANDING), 0)
    assert_equal(clip_of(WALKING), 1)
    assert_equal(clip_of(RUNNING), 2)
    assert_equal(clip_of(AIRBORNE), 3)
    var walk = Velocity(1.4, METER_PER_SECOND)
    assert_almost_equal(play_rate(WALKING, walk), 1, atol=1e-5)
    assert_almost_equal(
        play_rate(WALKING, Velocity(0.1, METER_PER_SECOND)), 0.6, atol=1e-5
    )
    assert_almost_equal(
        play_rate(RUNNING, Velocity(20.0, METER_PER_SECOND)), 1.6, atol=1e-5
    )
    assert_almost_equal(play_rate(AIRBORNE, walk), JUMP_PLAY, atol=1e-6)
    assert_equal(play_rate(STANDING, walk), 1)
    assert_almost_equal(
        facing_turn(Angle(0.0, RADIAN)).to(RADIAN), Float32(pi), atol=1e-6
    )


def test_a_route_walks_rests_and_moves_on() raises:
    var ground = _flat()
    var walker = Character(
        CharacterParameters(), 0, 0, Angle(0.0, RADIAN), ground
    )
    var route = Route(
        [Vector3(0, 0, -2), Vector3(3, 0, 0)], Duration(1.0, SECOND), True
    )
    var steer = route.steer(walker, Duration(0.1, SECOND))
    assert_equal(steer[0].forward, 1)
    assert_true(steer[0].run)
    assert_almost_equal(steer[1].to(DEGREE), 0, atol=1e-3)
    walker.position = Vector3(0, 0, -1.8)
    steer = route.steer(walker, Duration(0.1, SECOND))
    assert_equal(steer[0].forward, 0)
    assert_equal(route.next, 1)
    steer = route.steer(walker, Duration(0.5, SECOND))
    assert_equal(steer[0].forward, 0)
    assert_almost_equal(route.resting, 0.5, atol=1e-6)
    with assert_raises(contains="point"):
        _ = Route(List[Vector3](), Duration(1.0, SECOND))
    with assert_raises(contains="rest"):
        _ = Route([Vector3(0, 0, 0)], Duration(-1.0, SECOND))


def test_a_wander_keeps_off_the_lots_and_out_of_the_water() raises:
    var pond = Ground(
        hill_height=Length(0.0, METER),
        pond=Pond(
            Length(6.0, METER),
            Length(0.0, METER),
            Length(4.0, METER),
            Length(1.0, METER),
        ),
    )
    var lots: List[Lot] = [Lot(-6, 0, 2, 2, 0)]
    var route = wander_route(7, 0, 0, 10, 32, pond, lots, Duration(1.0, SECOND))
    assert_true(len(route.points) > 20)
    for point in route.points:
        assert_true(lots[0].reach(point.x, point.z) >= 1)
        assert_true(pond.height_at(point.x, point.z) >= pond.water_level())
    # Where nothing is clear, the route stands at its middle.
    var walled: List[Lot] = [Lot(0, 0, 50, 50, 0)]
    var stuck = wander_route(
        7, 0, 0, 10, 3, pond, walled, Duration(1.0, SECOND)
    )
    assert_equal(len(stuck.points), 1)
    with assert_raises(contains="points"):
        _ = wander_route(7, 0, 0, 10, 0, pond, lots, Duration(1.0, SECOND))
    with assert_raises(contains="reach"):
        _ = wander_route(7, 0, 0, -1, 3, pond, lots, Duration(1.0, SECOND))


def test_a_flipbook_shows_the_pose_of_the_stride() raises:
    var book = Flipbook(
        GeometryId(9), [GeometryId(1), GeometryId(2), GeometryId(3)], 1.5
    )
    var ground = _flat()
    var walker = Character(
        CharacterParameters(), 0, 0, Angle(0.0, RADIAN), ground
    )
    assert_equal(book.frame(walker).value, 9)
    walker.stance = WALKING
    walker.travelled = 1.5 * 4 + 0.6
    assert_equal(book.frame(walker).value, 2)
    walker.travelled = 1.5 * 4 + 1.49
    assert_equal(book.frame(walker).value, 3)
    var still = Flipbook(GeometryId(9), List[GeometryId](), 1.5)
    assert_equal(still.frame(walker).value, 9)
    var legless = Flipbook(GeometryId(9), [GeometryId(1)], 0)
    assert_equal(legless.frame(walker).value, 9)


def test_residents_that_cannot_be_built_are_refused() raises:
    var p = _small()
    p.check()
    for _ in range(65):
        p.villagers.append(
            Villager(
                HumanoidSpec(Length(60.0, INCH), FEMALE), 0, 0, 1, 1, False
            )
        )
    with assert_raises(contains="villagers"):
        p.check()
    p = _small()
    p.villagers.append(
        Villager(HumanoidSpec(Length(60.0, INCH), FEMALE), 0, 0, 2000, 1, False)
    )
    with assert_raises(contains="wander"):
        p.check()
    p = _small()
    for _ in range(65):
        p.herds.append(Herd(RABBIT, 1, 0, 0, 1, 1))
    with assert_raises(contains="herds"):
        p.check()
    p = _small()
    p.herds.append(Herd(SpeciesId(99), 1, 0, 0, 1, 1))
    with assert_raises(contains="species"):
        p.check()
    p = _small()
    p.herds.append(Herd(RABBIT, 0, 0, 0, 1, 1))
    with assert_raises(contains="animals"):
        p.check()
    p = _small()
    p.herds.append(Herd(RABBIT, 1, 0, 0, 2000, 1))
    with assert_raises(contains="pasture"):
        p.check()
    p = _small()
    p.triangles = 10
    with assert_raises(contains="triangles"):
        p.check()
    p = _small()
    p.detail = 2
    with assert_raises(contains="detail"):
        p.check()
    p = _small()
    p.phases = 0
    with assert_raises(contains="phases"):
        p.check()
    p = _small()
    p.rest = Duration(-1.0, SECOND)
    with assert_raises(contains="rest"):
        p.check()


def test_a_body_stands_where_its_character_stands_and_plays_its_stance() raises:
    var ground = _flat()
    var assets = Assets()
    var scene = Scene()
    var body = Body(
        scene, assets, HumanoidSpec(Length(60.0, INCH), FEMALE), 500, 8
    )
    assert_true(body.lift > 0.6 and body.lift < 1.0)
    var walker = Character(
        CharacterParameters(), 2, 3, Angle(0.0, RADIAN), ground
    )
    var step = Duration(0.1, SECOND)
    body.pose(scene, walker, step)
    assert_almost_equal(scene.node(body.carrier).position.x, 2, atol=1e-6)
    assert_almost_equal(
        scene.node(body.carrier).position.y, body.lift, atol=1e-6
    )
    for stance in [WALKING, RUNNING, AIRBORNE, STANDING]:
        walker.stance = stance
        body.pose(scene, walker, step)
        assert_true(body.playing == stance)
    walker.stance = AIRBORNE
    body.pose(scene, walker, step)
    ref jump = body.mixer.action(body.actions[3])
    assert_true(jump.phase > 0.5)
    assert_almost_equal(jump.time_scale, JUMP_PLAY, atol=1e-6)


def test_residents_wander_and_stand_in_the_players_way() raises:
    var ground = _flat()
    var assets = Assets()
    var scene = Scene()
    var p = _small()
    p.villagers.append(
        Villager(HumanoidSpec(Length(60.0, INCH), FEMALE), 0, 0, 3, 4, True)
    )
    p.herds.append(Herd(RABBIT, 2, 5, 5, 2, 8))
    p.herds.append(Herd(CHICKEN, 1, -5, 5, 2, 9))
    var lots = List[Lot]()
    var residents = Residents(scene, assets, p, ground, lots)
    assert_equal(len(residents.bodies), 1)
    assert_equal(len(residents.beasts), 3)
    assert_equal(len(residents.books), 2)
    assert_equal(len(residents.books[0].frames), 2)
    assert_true(residents.books[0].stride > 0)
    assert_equal(len(residents.books[1].frames), 0)
    var start = residents.beasts[0].character.position
    for _ in range(20):
        residents.update(
            scene, Duration(0.1, SECOND), ground, lots, List[Obstacle]()
        )
    var moved = residents.beasts[0].character.position - start
    assert_true(moved.length() > 0.01)
    var mesh = residents.beasts[0].mesh
    var node = residents.beasts[0].node
    assert_almost_equal(
        scene.node(node).position.x,
        residents.beasts[0].character.position.x,
        atol=1e-6,
    )
    assert_true(scene.meshes[mesh].geometry.value >= 0)
    var obstacles = residents.obstacles()
    assert_equal(len(obstacles), 4)
    assert_almost_equal(
        obstacles[0].x, residents.people[0].position.x, atol=1e-6
    )


def test_an_empty_village_has_no_residents() raises:
    var ground = _flat()
    var assets = Assets()
    var scene = Scene()
    var lots = List[Lot]()
    var residents = Residents(scene, assets, _small(), ground, lots)
    residents.update(
        scene, Duration(0.1, SECOND), ground, lots, List[Obstacle]()
    )
    assert_equal(len(residents.obstacles()), 0)
    assert_equal(len(scene.meshes), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
