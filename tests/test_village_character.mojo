# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The village's character controller: walking, running and jumping, and
the houses, trees, water and bounds that stop it."""

from extensions.building.material import brick
from extensions.building.model import Furnishing
from extensions.vegetation.ground import Canyon, Ground, Lot, Pond
from extensions.village.house import (
    HouseParameters,
    house_lot,
    house_model,
    house_stair,
)
from extensions.village.interior import house_interior
from extensions.village.terrain import Floor, Terrain, WallSpan
from extensions.village.character import (
    AIRBORNE,
    RUNNING,
    STANDING,
    WALKING,
    Character,
    CharacterParameters,
    MoveInput,
    Obstacle,
    Stance,
    lot_push,
    no_input,
    obstacle_push,
)
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
    DEGREE_PER_SECOND,
    METER,
    METER_PER_SECOND,
    METER_PER_SECOND_SQUARED,
    RADIAN,
    SECOND,
    Acceleration,
    Angle,
    AngularVelocity,
    Duration,
    Length,
    Velocity,
)


def _flat() raises -> Ground:
    """Return level ground with no pond."""
    return Ground(hill_height=Length(0.0, METER))


def _walker(ground: Ground) raises -> Character:
    """Return a person at the middle, facing -z."""
    return Character(CharacterParameters(), 0, 0, Angle(0.0, RADIAN), ground)


def _ahead(run: Bool = False, jump: Bool = False) -> MoveInput:
    """Return a full lean forward."""
    return MoveInput(1, 0, 0, 0, run, jump)


def _run(
    mut walker: Character,
    input: MoveInput,
    seconds: Float32,
    ground: Ground,
    lots: List[Lot] = List[Lot](),
    obstacles: List[Obstacle] = List[Obstacle](),
) raises:
    """Step a character by frames of a thirtieth of a second."""
    var terrain = Terrain(ground, lots.copy(), List[WallSpan](), List[Floor]())
    _walk(walker, input, seconds, terrain, obstacles)


def _walk(
    mut walker: Character,
    input: MoveInput,
    seconds: Float32,
    terrain: Terrain,
    obstacles: List[Obstacle] = List[Obstacle](),
) raises:
    """Step a character on a terrain by frames of a thirtieth of a
    second."""
    for _ in range(Int(seconds * 30)):
        walker.step(
            input,
            Angle(0.0, RADIAN),
            Duration(1.0 / 30.0, SECOND),
            terrain,
            obstacles,
        )


def test_a_stance_is_one_of_four() raises:
    assert_true(STANDING.is_valid())
    assert_true(AIRBORNE.is_valid())
    assert_false(Stance(4).is_valid())
    assert_false(Stance(-1).is_valid())
    var still = no_input()
    assert_equal(still.forward, 0)
    assert_false(still.jump)


def test_a_character_walks_and_runs_where_the_stick_points() raises:
    var ground = _flat()
    var walker = _walker(ground)
    assert_true(walker.stance == STANDING)
    _run(walker, _ahead(), 1, ground)
    assert_true(walker.stance == WALKING)
    assert_almost_equal(walker.speed().to(METER_PER_SECOND), 1.4, atol=1e-3)
    assert_true(walker.position.z < -1)
    assert_true(walker.travelled > 1)
    _run(walker, _ahead(run=True), 1, ground)
    assert_true(walker.stance == RUNNING)
    assert_almost_equal(walker.speed().to(METER_PER_SECOND), 4.5, atol=1e-3)
    # A stick to the right turns the character to face +x.
    _run(walker, MoveInput(0, 1, 0, 0, False, False), 1, ground)
    assert_almost_equal(walker.heading.to(DEGREE), -90, atol=1e-2)
    assert_true(walker.velocity.x > 1)
    _run(walker, no_input(), 1, ground)
    assert_true(walker.stance == STANDING)


def test_a_jump_needs_a_fresh_press_and_lands() raises:
    var ground = _flat()
    var walker = _walker(ground)
    walker.step(
        _ahead(jump=True),
        Angle(0.0, RADIAN),
        Duration(0.1, SECOND),
        ground,
        List[Obstacle](),
    )
    assert_true(walker.stance == AIRBORNE)
    assert_true(walker.position.y > 0.2)
    # In the air, the stick steers only a little.
    assert_true(walker.speed().to(METER_PER_SECOND) < 1)
    _run(walker, _ahead(jump=True), 1.5, ground)
    assert_false(walker.stance == AIRBORNE)
    assert_almost_equal(walker.position.y, 0, atol=1e-6)
    # Holding the button does not jump again.
    _run(walker, _ahead(jump=True), 0.5, ground)
    assert_false(walker.stance == AIRBORNE)
    # A jump reaches about 0.9 meters: v^2 / 2g.
    var high = Float32(0)
    walker.step(
        no_input(),
        Angle(0.0, RADIAN),
        Duration(0.0, SECOND),
        ground,
        List[Obstacle](),
    )
    for _ in range(60):
        walker.step(
            MoveInput(0, 0, 0, 0, False, True),
            Angle(0.0, RADIAN),
            Duration(1.0 / 60.0, SECOND),
            ground,
            List[Obstacle](),
        )
        high = max(high, walker.position.y)
    assert_almost_equal(high, 0.9, atol=0.05)


def test_a_character_falls_where_the_ground_drops_away() raises:
    var cliff = Ground(
        hill_height=Length(0.0, METER),
        canyon=Canyon(
            Length(3.0, METER),
            Length(100.0, METER),
            Length(40.0, METER),
            Length(0.0, METER),
        ),
    )
    var walker = _walker(cliff)
    var fell = False
    for _ in range(90):
        walker.step(
            _ahead(run=True),
            Angle(0.0, RADIAN),
            Duration(1.0 / 30.0, SECOND),
            cliff,
            List[Obstacle](),
        )
        if walker.stance == AIRBORNE:
            fell = True
    assert_true(fell)
    assert_true(walker.position.y < -10)


def test_houses_trees_and_bounds_stop_a_character() raises:
    var ground = _flat()
    var walker = _walker(ground)
    var lots: List[Lot] = [Lot(0, -5, 2, 1, 0)]
    _run(walker, _ahead(), 6, ground, lots)
    # Stopped at the house's near wall, a radius away.
    assert_almost_equal(walker.position.z, -3.7, atol=1e-3)
    var tree = _walker(ground)
    var trunks: List[Obstacle] = [Obstacle(0, -3, 0.5)]
    _run(tree, _ahead(), 4, ground, List[Lot](), trunks)
    assert_true(tree.position.z > -3)
    # A character passes over the obstacle it is told to skip, such as
    # its own, and is stopped by the others.
    var crowd: List[Obstacle] = [Obstacle(0, -3, 0.5), Obstacle(0, -6, 0.5)]
    var bare = Terrain(ground)
    var skipping = _walker(ground)
    for _ in range(120):
        skipping.step(
            _ahead(),
            Angle(0.0, RADIAN),
            Duration(1.0 / 30.0, SECOND),
            bare,
            crowd,
            0,
        )
    assert_true(skipping.position.z < -4)
    assert_true(skipping.position.z > -6)
    var far = _walker(ground)
    far.parameters.bounds = Length(2.0, METER)
    _run(far, _ahead(), 4, ground)
    assert_almost_equal(far.position.z, -2, atol=1e-3)


def test_a_character_wades_but_does_not_swim() raises:
    var pond = Ground(
        hill_height=Length(0.0, METER),
        pond=Pond(
            Length(0.0, METER),
            Length(-8.0, METER),
            Length(5.0, METER),
            Length(2.0, METER),
        ),
    )
    var walker = _walker(pond)
    _run(walker, _ahead(), 10, pond)
    var depth = pond.water_level() - pond.height_at(
        walker.position.x, walker.position.z
    )
    assert_true(depth <= 0.5)
    assert_true(walker.position.z > -8)
    # Along the shore, the character slides rather than stops.
    var slider = Character(
        CharacterParameters(), -0.5, -2, Angle(0.0, RADIAN), pond
    )
    _run(slider, MoveInput(1, -0.5, 0, 0, False, False), 6, pond)
    assert_true(slider.position.x < -2)
    var dry = Character(
        CharacterParameters(), 0.5, -2, Angle(0.0, RADIAN), pond
    )
    _run(dry, MoveInput(1, 0.5, 0, 0, False, False), 6, pond)
    assert_true(dry.position.x > 2)


def test_lot_push_moves_a_circle_out_the_shortest_way() raises:
    var lot = Lot(0, 0, 2, 1, 0)
    var clear = lot_push(lot, 5, 5, 0.5)
    assert_almost_equal(clear.x, 5, atol=1e-6)
    var inside = lot_push(lot, 1.8, 0.1, 0.5)
    assert_almost_equal(inside.x, 2.5, atol=1e-5)
    var deep = lot_push(lot, 0.1, -0.8, 0.5)
    assert_almost_equal(deep.z, -1.5, atol=1e-5)
    var side = lot_push(lot, 2.2, 0.3, 0.5)
    assert_almost_equal(side.x, 2.5, atol=1e-5)
    var front = lot_push(lot, 0.3, 1.2, 0.5)
    assert_almost_equal(front.z, 1.5, atol=1e-5)
    var corner = lot_push(lot, 2.2, 1.2, 0.5)
    var dx = corner.x - 2
    var dz = corner.z - 1
    assert_almost_equal(dx * dx + dz * dz, 0.25, atol=1e-4)
    var past = lot_push(lot, 2.4, 1.4, 0.5)
    assert_almost_equal(past.x, 2.4, atol=1e-6)
    # A turned lot pushes along its own axes.
    var turned = lot_push(Lot(0, 0, 2, 1, Float32(pi / 2)), 0.1, 1.8, 0.5)
    assert_almost_equal(turned.z, 2.5, atol=1e-4)


def test_obstacle_push_moves_a_circle_straight_away() raises:
    var trunk = Obstacle(0, 0, 0.5)
    var clear = obstacle_push(trunk, 2, 0, 0.5)
    assert_almost_equal(clear.x, 2, atol=1e-6)
    var near = obstacle_push(trunk, 0, 0.6, 0.5)
    assert_almost_equal(near.z, 1, atol=1e-5)
    var middle = obstacle_push(trunk, 0, 0, 0.5)
    assert_almost_equal(middle.x, 1, atol=1e-6)


def test_a_character_that_cannot_move_is_refused() raises:
    var ground = _flat()
    var p = CharacterParameters()
    p.check()
    p.walk_speed = Velocity(0.0, METER_PER_SECOND)
    with assert_raises(contains="walking"):
        p.check()
    p = CharacterParameters()
    p.run_speed = Velocity(1.0, METER_PER_SECOND)
    with assert_raises(contains="run"):
        p.check()
    p = CharacterParameters()
    p.run_speed = Velocity(1.0e5, METER_PER_SECOND)
    with assert_raises(contains="run"):
        p.check()
    p = CharacterParameters()
    p.acceleration = Acceleration(0.0, METER_PER_SECOND_SQUARED)
    with assert_raises(contains="acceleration"):
        p.check()
    p = CharacterParameters()
    p.air_control = 2
    with assert_raises(contains="air"):
        p.check()
    p.air_control = -1
    with assert_raises(contains="air"):
        p.check()
    p = CharacterParameters()
    p.turn_speed = AngularVelocity(0.0, DEGREE_PER_SECOND)
    with assert_raises(contains="turning"):
        p.check()
    p = CharacterParameters()
    p.jump_speed = Velocity(-1.0, METER_PER_SECOND)
    with assert_raises(contains="jump"):
        p.check()
    p.jump_speed = Velocity(1.0e5, METER_PER_SECOND)
    with assert_raises(contains="jump"):
        p.check()
    p = CharacterParameters()
    p.gravity = Acceleration(0.0, METER_PER_SECOND_SQUARED)
    with assert_raises(contains="gravity"):
        p.check()
    p = CharacterParameters()
    p.radius = Length(0.0, METER)
    with assert_raises(contains="radius"):
        p.check()
    p = CharacterParameters()
    p.wade_depth = Length(-1.0, METER)
    with assert_raises(contains="wade"):
        p.check()
    p.wade_depth = Length(1.0e5, METER)
    with assert_raises(contains="wade"):
        p.check()
    p = CharacterParameters()
    p.step_down = Length(-1.0, METER)
    with assert_raises(contains="step down"):
        p.check()
    p = CharacterParameters()
    p.bounds = Length(0.0, METER)
    with assert_raises(contains="bounds"):
        p.check()
    var huge = Float32.MAX * 2
    with assert_raises(contains="x"):
        _ = Character(
            CharacterParameters(), huge, 0, Angle(0.0, RADIAN), ground
        )
    with assert_raises(contains="z"):
        _ = Character(
            CharacterParameters(), 0, huge, Angle(0.0, RADIAN), ground
        )
    with assert_raises(contains="heading"):
        _ = Character(CharacterParameters(), 0, 0, Angle(huge, RADIAN), ground)
    var walker = _walker(ground)
    with assert_raises(contains="negative"):
        walker.step(
            no_input(),
            Angle(0.0, RADIAN),
            Duration(-1.0, SECOND),
            ground,
            List[Obstacle](),
        )
    with assert_raises(contains="endless"):
        walker.step(
            no_input(),
            Angle(0.0, RADIAN),
            Duration(1.0e10, SECOND),
            ground,
            List[Obstacle](),
        )
    with assert_raises(contains="yaw"):
        walker.step(
            no_input(),
            Angle(huge, RADIAN),
            Duration(0.1, SECOND),
            ground,
            List[Obstacle](),
        )


def test_a_press_in_the_air_does_not_jump_again() raises:
    var ground = _flat()
    var walker = _walker(ground)
    var none = List[Obstacle]()
    var step = Duration(1.0 / 30.0, SECOND)
    var yaw = Angle(0.0, RADIAN)
    walker.step(MoveInput(0, 0, 0, 0, False, True), yaw, step, ground, none)
    walker.step(no_input(), yaw, step, ground, none)
    var rising = walker.velocity.y
    walker.step(MoveInput(0, 0, 0, 0, False, True), yaw, step, ground, none)
    assert_true(walker.velocity.y < rising)


def test_a_character_below_the_ground_rises_out_of_it() raises:
    var ground = _flat()
    var walker = _walker(ground)
    walker.grounded = False
    walker.position = Vector3(0, -1, 0)
    walker.velocity = Vector3(0, 8, 0)
    _run(walker, no_input(), 0.1, ground)
    assert_false(walker.grounded)
    assert_true(walker.position.y > -1)
    _run(walker, no_input(), 3, ground)
    assert_true(walker.grounded)


def test_a_character_in_deep_water_stays_and_one_at_the_edge_slides() raises:
    var pond = Ground(
        hill_height=Length(0.0, METER),
        pond=Pond(
            Length(5.0, METER),
            Length(0.0, METER),
            Length(5.0, METER),
            Length(2.0, METER),
        ),
    )
    # In the deep middle, every step is refused.
    var stuck = Character(CharacterParameters(), 5, 0, Angle(0.0, RADIAN), pond)
    _run(stuck, MoveInput(1, 1, 0, 0, False, False), 1, pond)
    assert_almost_equal(stuck.position.x, 5, atol=1e-6)
    assert_almost_equal(stuck.position.z, 0, atol=1e-6)
    # Walk east until the water stops it, then lean east and south: only
    # the step along z is allowed.
    var edge = Character(CharacterParameters(), -1, 0, Angle(0.0, RADIAN), pond)
    _run(edge, MoveInput(0, 1, 0, 0, False, False), 3, pond)
    var x = edge.position.x
    _run(edge, MoveInput(-1, 1, 0, 0, False, False), 1, pond)
    assert_true(edge.position.z > 0.3)
    assert_true(edge.position.x >= x - 1.0e-3)


def test_a_wall_stops_a_character_and_a_door_lets_it_in() raises:
    var ground = _flat()
    # A wall across the way at z = -3, with a gap a meter wide from x =
    # -0.5 to 0.5, and a lintel over the gap from 2.1 meters.
    var walls: List[WallSpan] = [
        WallSpan(-5, -3, -0.5, -3, 0.1, 0, 3),
        WallSpan(0.5, -3, 5, -3, 0.1, 0, 3),
        WallSpan(-0.5, -3, 0.5, -3, 0.1, 2.1, 3),
    ]
    var terrain = Terrain(ground, List[Lot](), walls.copy(), List[Floor]())
    var through = _walker(ground)
    _walk(through, _ahead(), 5, terrain)
    assert_true(through.position.z < -4)
    # Beside the gap, the wall stops it a radius and half a thickness
    # away.
    var stopped = Character(
        CharacterParameters(), 2, 0, Angle(0.0, RADIAN), terrain
    )
    _walk(stopped, _ahead(), 5, terrain)
    assert_almost_equal(stopped.position.z, -3 + 0.1 + 0.3, atol=1e-3)


def test_a_floor_carries_a_character_and_stands_over_water() raises:
    var pond = Ground(
        hill_height=Length(0.0, METER),
        pond=Pond(
            Length(0.0, METER),
            Length(-6.0, METER),
            Length(4.0, METER),
            Length(2.0, METER),
        ),
    )
    # A jetty over the pond, 0.3 meters above the ground's edge.
    var floors: List[Floor] = [Floor(Lot(0, -6, 0.6, 5, 0), 0.3, 1.0e30)]
    var terrain = Terrain(pond, List[Lot](), List[WallSpan](), floors^)
    var walker = Character(
        CharacterParameters(), 0, -1.5, Angle(0.0, RADIAN), terrain
    )
    assert_almost_equal(walker.position.y, 0.3, atol=1e-6)
    _walk(walker, _ahead(), 4, terrain)
    # It walks out over the deep water on the jetty.
    assert_true(walker.position.z < -4)
    assert_almost_equal(walker.position.y, 0.3, atol=1e-6)
    assert_true(walker.grounded)


def test_a_character_climbs_a_stair_and_comes_down() raises:
    var house = HouseParameters(
        "stair house", Length(9.0, METER), Length(7.0, METER), 2, brick()
    )
    var model = house_model(house)
    # No furniture stands in the walker's way upstairs.
    model.furnishings = List[Furnishing]()
    var stair = house_stair(model).value()
    var lot = house_lot(house, 0, 0, Angle(0.0, RADIAN))
    var ground = _flat()
    var inside = house_interior(model, lot, 0, ground)
    var walls = inside.walls.copy()
    walls.extend(inside.furniture.copy())
    var terrain = Terrain(ground, List[Lot](), walls^, inside.floors.copy())
    # On the landing, in the middle of the stair's width. The scene's z is
    # the plan's -y.
    var middle = -Float32((stair.y0 + stair.y1) / 2)
    var walker = Character(
        CharacterParameters(),
        Float32(stair.x0) - 0.5,
        middle,
        Angle(0.0, RADIAN),
        terrain,
    )
    assert_almost_equal(walker.position.y, 0, atol=1e-5)
    # Right, along +x: up the stair, tread by tread, onto the floor above.
    var top = Float32(stair.height())
    _walk(walker, MoveInput(0, 1, 0, 0, False, False), 4, terrain)
    assert_true(walker.position.x > Float32(stair.x1))
    assert_almost_equal(walker.position.y, top, atol=1e-4)
    assert_true(walker.grounded)
    # Back toward the front, along over the well, and toward it again:
    # the railing on its open side holds the walker on the floor above.
    _walk(walker, MoveInput(-1, 0, 0, 0, False, False), 1, terrain)
    _walk(walker, MoveInput(0, -1, 0, 0, False, False), 2, terrain)
    assert_true(walker.position.x < Float32(stair.x1) - 0.5)
    _walk(walker, MoveInput(1, 0, 0, 0, False, False), 2, terrain)
    assert_almost_equal(walker.position.y, top, atol=1e-4)
    assert_true(walker.position.z > -Float32(stair.y0))
    # Down again, from past the stair's top, left along -x.
    walker.position = Vector3(Float32(stair.x1) + 1, top, middle)
    walker.velocity = Vector3(0, 0, 0)
    _walk(walker, MoveInput(0, -1, 0, 0, False, False), 5, terrain)
    assert_true(walker.position.x < Float32(stair.x0))
    assert_almost_equal(walker.position.y, 0, atol=1e-4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
