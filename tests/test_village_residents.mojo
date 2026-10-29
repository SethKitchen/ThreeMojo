# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's people and animals: their bodies, their clips, their
flipbooks and their routes."""

from core.assets import Assets
from extensions.attire.cover import Cover
from extensions.attire.garment import Garment
from extensions.attire.kinds import (
    LINEN,
    OVER_LAYER,
    TORSO_SLOT,
    UNDER_LAYER,
    WOOL,
)
from extensions.attire.outfit import Outfit
from core.scene import Scene
from extensions.animals.registry import CHICKEN, RABBIT, SpeciesId
from extensions.humanoid.rig.joints import CHEST, HIPS, SPINE
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
    Obstacle,
)
from extensions.village.clothes import dyed_outfit
from extensions.village.interior import Doorway
from extensions.village.residents import (
    APPROACH,
    INDOORS,
    THRESHOLD,
    Body,
    Flipbook,
    GIVE_UP,
    Herd,
    HouseId,
    JUMP_PLAY,
    NO_HOUSE,
    Residents,
    ResidentsParameters,
    Route,
    Villager,
    clip_of,
    facing_turn,
    play_rate,
    visit,
    wander_route,
)
from controls.third_person_controls import yaw_of
from core.geometry_store import GeometryId
from math.vector3 import Vector3
from render.framebuffer import Color
from std.math import cos, pi
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
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


def _homes() -> List[Doorway]:
    """Return one home: a door at (2, 4), a meter wide along x, that
    swings toward -z into its house."""
    return [Doorway(2, 4, 1, 0, 0, -1, 1, 2.1, 0, True)]


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


def test_a_stuck_resident_gives_up_on_its_point() raises:
    var ground = _flat()
    var walker = Character(
        CharacterParameters(), 0, 0, Angle(0.0, RADIAN), ground
    )
    var route = Route(
        [Vector3(0, 0, -5), Vector3(5, 0, 0)], Duration(1.0, SECOND)
    )
    # Standing still on its way, it waits, then rests and moves on.
    var second = Duration(1.0, SECOND)
    _ = route.steer(walker, second)
    _ = route.steer(walker, second)
    assert_equal(route.next, 0)
    assert_true(route.stalled >= 2)
    _ = route.steer(walker, second)
    var steer = route.steer(walker, second)
    assert_equal(route.next, 1)
    assert_equal(steer[0].forward, 0)
    assert_true(route.stalled == 0)
    # Moving on its way, it is not stuck.
    route.resting = 0
    walker.velocity = Vector3(1, 0, 0)
    _ = route.steer(walker, second)
    assert_true(route.stalled == 0)
    assert_true(GIVE_UP > 2 and GIVE_UP < 3)


def test_residents_bump_into_each_other() raises:
    var ground = _flat()
    var assets = Assets()
    var scene = Scene()
    var p = _small()
    p.rest = Duration(0.0, SECOND)
    # Two rabbits that both start and graze at one point: each pushes the
    # other away.
    p.herds.append(Herd(RABBIT, 2, 0, 0, 0, 8))
    var lots = List[Lot]()
    var residents = Residents(scene, assets, p, ground, lots, _homes())
    for _ in range(30):
        residents.update(scene, Duration(0.1, SECOND), ground, List[Obstacle]())
    ref a = residents.beasts[0].character
    ref b = residents.beasts[1].character
    var gap = (a.position - b.position).length()
    var reach = a.parameters.radius.to(METER) + b.parameters.radius.to(METER)
    assert_true(gap > reach * 0.8)


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
                HumanoidSpec(Length(60.0, INCH), FEMALE),
                0,
                0,
                1,
                1,
                False,
                Outfit(),
                NO_HOUSE,
            )
        )
    with assert_raises(contains="villagers"):
        p.check()
    p = _small()
    p.villagers.append(
        Villager(
            HumanoidSpec(Length(60.0, INCH), FEMALE),
            0,
            0,
            2000,
            1,
            False,
            Outfit(),
            NO_HOUSE,
        )
    )
    with assert_raises(contains="wander"):
        p.check()
    p = _small()
    p.villagers.append(
        Villager(
            HumanoidSpec(Length(60.0, INCH), FEMALE),
            0,
            0,
            1,
            1,
            False,
            Outfit(),
            HouseId(-2),
        )
    )
    with assert_raises(contains="home"):
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
    p.herds.append(Herd(RABBIT, 1, 0, 0, 1, 1, flee=Length(-1.0, METER)))
    with assert_raises(contains="flee"):
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
    for coarseness in [Float64(0.5), Float64(9)]:
        p = _small()
        p.animal_coarseness = coarseness
        with assert_raises(contains="coarseness"):
            p.check()


def test_a_body_stands_where_its_character_stands_and_plays_its_stance() raises:
    var ground = _flat()
    var assets = Assets()
    var scene = Scene()
    var body = Body(
        scene,
        assets,
        HumanoidSpec(Length(60.0, INCH), FEMALE),
        Outfit(),
        500,
        8,
    )
    assert_true(body.lift > 0.6 and body.lift < 1.0)
    # An empty outfit leaves the body bare.
    assert_equal(len(body.garments), 0)
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


def test_a_garment_that_shows_nothing_casts_nothing() raises:
    var assets = Assets()
    var scene = Scene()
    # A long coat over a narrow band round the waist hides the band.
    var band = Cover()
    band.reach_to(SPINE, 0.7, 0.3)
    var coat = Cover()
    coat.reach_to(HIPS)
    coat.reach_to(SPINE)
    coat.reach_to(CHEST)
    var outfit = Outfit()
    outfit.add(
        Garment("band", TORSO_SLOT, UNDER_LAYER, LINEN, band^, Color(9, 9, 9))
    )
    outfit.add(
        Garment("coat", TORSO_SLOT, OVER_LAYER, WOOL, coat^, Color(90, 90, 90))
    )
    var body = Body(
        scene,
        assets,
        HumanoidSpec(Length(60.0, INCH), FEMALE),
        outfit,
        500,
        8,
    )
    assert_equal(len(body.garments), 2)
    assert_equal(body.garments[0], -1)
    assert_true(scene.skinned_meshes[body.garments[1]].cast_shadow)


def test_residents_wander_and_stand_in_the_players_way() raises:
    var ground = _flat()
    var assets = Assets()
    var scene = Scene()
    var p = _small()
    p.villagers.append(
        Villager(
            HumanoidSpec(Length(60.0, INCH), FEMALE),
            0,
            0,
            3,
            4,
            True,
            dyed_outfit(2, True),
            HouseId(0),
        )
    )
    p.herds.append(Herd(RABBIT, 2, 5, 5, 2, 8))
    p.herds.append(Herd(CHICKEN, 1, -5, 5, 2, 9))
    var lots = List[Lot]()
    var residents = Residents(scene, assets, p, ground, lots, _homes())
    assert_equal(len(residents.bodies), 1)
    # The villager's route ends with a visit to their home.
    var walk = residents.walks[0].points.copy()
    assert_almost_equal(walk[len(walk) - 3].z, 4 - INDOORS, atol=1e-5)
    # The villager wears a shirt, hose, a tunic, boots and a hood, and
    # each garment casts a shadow.
    assert_equal(len(residents.bodies[0].garments), 5)
    for mesh in residents.bodies[0].garments:
        assert_true(scene.skinned_meshes[mesh].cast_shadow)
    assert_equal(len(residents.beasts), 3)
    assert_equal(len(residents.books), 2)
    assert_equal(len(residents.books[0].frames), 2)
    assert_true(residents.books[0].stride > 0)
    assert_equal(len(residents.books[1].frames), 0)
    var start = residents.beasts[0].character.position
    for _ in range(20):
        residents.update(scene, Duration(0.1, SECOND), ground, List[Obstacle]())
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
    # A held villager slows to a stop, stands, and turns to face the
    # point.
    var point = residents.people[0].position + Vector3(0, 0, 5)
    residents.hold(0, 2, point)
    for _ in range(8):
        residents.update(scene, Duration(0.1, SECOND), ground, List[Obstacle]())
    var here = residents.people[0].position
    for _ in range(4):
        residents.update(scene, Duration(0.1, SECOND), ground, List[Obstacle]())
    var stood = residents.people[0].position - here
    assert_true(stood.length() < 0.01)
    var toward = point - residents.people[0].position
    var miss = residents.people[0].heading.to(RADIAN) - yaw_of(
        Vector3(toward.x, 0, toward.z)
    ).to(RADIAN)
    assert_almost_equal(cos(miss), 1, atol=1e-4)
    # The hold counts down, and once it is over their route steers them
    # again.
    assert_almost_equal(residents.holds[0], 0.8, atol=1e-4)
    for _ in range(9):
        residents.update(scene, Duration(0.1, SECOND), ground, List[Obstacle]())
    assert_true(residents.holds[0] <= 0)
    with assert_raises(contains="one of the residents"):
        residents.hold(1, 2, point)
    with assert_raises(contains="one of the residents"):
        residents.hold(-1, 2, point)
    with assert_raises(contains="negative"):
        residents.hold(0, -1, point)


def test_a_shy_animal_runs_from_the_player_and_a_tame_one_does_not() raises:
    var ground = _flat()
    var assets = Assets()
    var scene = Scene()
    var p = _small()
    p.rest = Duration(30.0, SECOND)
    # A shy rabbit and a tame one, each grazing at one point.
    p.herds.append(Herd(RABBIT, 1, 0, 0, 0, 8, flee=Length(6.0, METER)))
    p.herds.append(Herd(RABBIT, 1, 0, 3, 0, 9))
    var lots = List[Lot]()
    var residents = Residents(scene, assets, p, ground, lots, _homes())
    var player = Vector3(-2, 0, 1.5)
    var shy = residents.beasts[0].character.position
    var tame = residents.beasts[1].character.position
    var before = (shy - player).length()
    for _ in range(10):
        residents.update(
            scene, Duration(0.1, SECOND), ground, List[Obstacle](), player
        )
    ref runner = residents.beasts[0].character
    # The shy one ran straight away, faster than it walks.
    assert_true((runner.position - player).length() > before + 0.5)
    assert_true(runner.stance == RUNNING)
    assert_true(
        runner.parameters.run_speed.to(METER_PER_SECOND)
        > runner.parameters.walk_speed.to(METER_PER_SECOND) * 2.9
    )
    # The tame one kept grazing where it was.
    var still = residents.beasts[1].character.position - tame
    assert_true(still.length() < 0.05)


def test_a_villager_visits_their_home_through_its_door() raises:
    var route = Route([Vector3(0, 0, 0)], Duration(1.0, SECOND))
    visit(route, _homes()[0])
    assert_equal(len(route.points), 6)
    # The door's middle is (2.5, 4); the house is toward -z.
    assert_almost_equal(route.points[1].z, 4 + APPROACH, atol=1e-5)
    assert_almost_equal(route.points[2].z, 4 + THRESHOLD, atol=1e-5)
    assert_almost_equal(route.points[3].z, 4 - INDOORS, atol=1e-5)
    assert_almost_equal(route.points[3].x, 2.5, atol=1e-5)
    assert_almost_equal(route.points[5].z, 4 + APPROACH, atol=1e-5)
    # A home that is not one of the village's houses is refused.
    var ground = _flat()
    var assets = Assets()
    var scene = Scene()
    var p = _small()
    p.villagers.append(
        Villager(
            HumanoidSpec(Length(60.0, INCH), FEMALE),
            0,
            0,
            3,
            4,
            False,
            Outfit(),
            HouseId(1),
        )
    )
    with assert_raises(contains="home"):
        _ = Residents(scene, assets, p, ground, List[Lot](), _homes())


def test_an_empty_village_has_no_residents() raises:
    var ground = _flat()
    var assets = Assets()
    var scene = Scene()
    var lots = List[Lot]()
    var residents = Residents(
        scene, assets, _small(), ground, lots, List[Doorway]()
    )
    residents.update(scene, Duration(0.1, SECOND), ground, List[Obstacle]())
    assert_equal(len(residents.obstacles()), 0)
    assert_equal(len(scene.meshes), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
