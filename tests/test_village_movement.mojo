# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The player's movement: the sprint, the brakes, strafing, slopes, a
ledge's grace, a buffered jump, a short hop, and a hard landing."""

from extensions.vegetation.ground import Ground
from extensions.village.character import (
    Character,
    CharacterParameters,
    MoveInput,
    Obstacle,
    no_input,
    player_movement,
)
from extensions.village.terrain import Terrain
from math.vector3 import Vector3
from std.math import nan
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


def _flat() raises -> Terrain:
    """Return level ground with no pond."""
    return Terrain(Ground(hill_height=Length(0.0, METER)))


def _player(terrain: Terrain) raises -> Character:
    """Return the player at the middle, facing -z."""
    return Character(player_movement(), 0, 0, Angle(0.0, RADIAN), terrain)


def _step(
    mut walker: Character,
    input: MoveInput,
    seconds: Float32,
    terrain: Terrain,
    face: Optional[Angle] = None,
) raises:
    """Step a character by frames of a thirtieth of a second."""
    for _ in range(Int(seconds * 30 + 0.5)):
        walker.step(
            input,
            Angle(0.0, RADIAN),
            Duration(1.0 / 30.0, SECOND),
            terrain,
            List[Obstacle](),
            face=face,
        )


def _run_ahead() -> MoveInput:
    """Return a full lean forward, running."""
    return MoveInput(1, 0, 0, 0, True, False)


def test_the_player_moves_with_its_own_parameters() raises:
    var p = player_movement()
    assert_almost_equal(p.sprint_speed.to(METER_PER_SECOND), 6.6, atol=1e-5)
    assert_true(p.coyote.to(SECOND) > 0)
    assert_true(p.jump_cut < 1)
    p.check()
    var plain = CharacterParameters()
    assert_equal(plain.sprint_speed.to(METER_PER_SECOND), 0)
    assert_equal(plain.jump_cut, 1)


def test_the_new_parameters_are_checked() raises:
    var p = player_movement()
    p.sprint_speed = Velocity(-1.0, METER_PER_SECOND)
    with assert_raises(contains="sprint"):
        p.check()
    p = player_movement()
    p.sprint_speed = Velocity(1.0e4, METER_PER_SECOND)
    with assert_raises(contains="sprint"):
        p.check()
    p = player_movement()
    p.sprint_turn = AngularVelocity(0.0, DEGREE_PER_SECOND)
    with assert_raises(contains="sprinting turn"):
        p.check()
    p = player_movement()
    p.deceleration = Acceleration(0.0, METER_PER_SECOND_SQUARED)
    with assert_raises(contains="deceleration"):
        p.check()
    p = player_movement()
    p.coyote = Duration(-1.0, SECOND)
    with assert_raises(contains="coyote"):
        p.check()
    p = player_movement()
    p.landing_time = Duration(10.0, SECOND)
    with assert_raises(contains="coyote"):
        p.check()
    p = player_movement()
    p.jump_cut = -0.1
    with assert_raises(contains="jump cut"):
        p.check()
    p = player_movement()
    p.back_share = 1.1
    with assert_raises(contains="jump cut"):
        p.check()
    p = player_movement()
    p.climb_drag = -1
    with assert_raises(contains="climb drag"):
        p.check()
    p = player_movement()
    p.climb_drag = 5
    with assert_raises(contains="climb drag"):
        p.check()
    p = player_movement()
    p.hard_landing = Velocity(0.0, METER_PER_SECOND)
    with assert_raises(contains="hard landing"):
        p.check()


def test_a_long_run_becomes_a_sprint() raises:
    var terrain = _flat()
    var walker = _player(terrain)
    _step(walker, _run_ahead(), 0.4, terrain)
    assert_false(walker.sprinting)
    _step(walker, _run_ahead(), 1.2, terrain)
    assert_true(walker.sprinting)
    assert_almost_equal(walker.speed().to(METER_PER_SECOND), 6.6, atol=0.05)
    # Tired, it runs.
    walker.tired = True
    _step(walker, _run_ahead(), 1, terrain)
    assert_false(walker.sprinting)
    assert_almost_equal(walker.speed().to(METER_PER_SECOND), 4.5, atol=0.05)
    # A stick leaned part of the way runs, and does not sprint.
    var half = _player(terrain)
    _step(half, MoveInput(0.7, 0, 0, 0, True, False), 2, terrain)
    assert_false(half.sprinting)
    # A character with no sprint never sprints.
    var plain = Character(
        CharacterParameters(), 0, 0, Angle(0.0, RADIAN), terrain
    )
    _step(plain, _run_ahead(), 2, terrain)
    assert_false(plain.sprinting)


def test_the_player_brakes_harder_than_it_speeds_up() raises:
    var terrain = _flat()
    var player = _player(terrain)
    var plain = Character(
        CharacterParameters(), 0, 0, Angle(0.0, RADIAN), terrain
    )
    _step(player, _run_ahead(), 0.5, terrain)
    _step(plain, _run_ahead(), 0.5, terrain)
    _step(player, no_input(), 0.2, terrain)
    _step(plain, no_input(), 0.2, terrain)
    assert_true(
        player.speed().to(METER_PER_SECOND) < plain.speed().to(METER_PER_SECOND)
    )
    # Turning back brakes too.
    var turner = _player(terrain)
    _step(turner, _run_ahead(), 0.5, terrain)
    _step(turner, MoveInput(-1, 0, 0, 0, True, False), 0.1, terrain)
    assert_true(turner.speed().to(METER_PER_SECOND) < 3)


def test_a_player_facing_a_foe_strafes_and_backs_away_slower() raises:
    var terrain = _flat()
    # Facing -x, a step along z is across the way it faces.
    var face = Angle(90.0, DEGREE)
    var strafer = _player(terrain)
    _step(strafer, MoveInput(1, 0, 0, 0, True, False), 1, terrain, face)
    assert_almost_equal(strafer.heading.to(DEGREE), 90, atol=0.5)
    assert_false(strafer.sprinting)
    var across = strafer.speed().to(METER_PER_SECOND)
    assert_almost_equal(across, 4.5, atol=0.05)
    # Back away from the way it faces, along +x, at the back share.
    var backer = _player(terrain)
    _step(backer, MoveInput(0, 1, 0, 0, True, False), 1, terrain, face)
    assert_almost_equal(
        backer.speed().to(METER_PER_SECOND), 4.5 * 0.7, atol=0.05
    )
    with assert_raises(contains="facing"):
        _step(
            backer,
            no_input(),
            0.1,
            terrain,
            Angle(nan[DType.float32](), RADIAN),
        )


def test_uphill_is_slower() raises:
    var hill = Terrain(Ground(hill_height=Length(0.0, METER), climb=0.5))
    # Half a second of a run: up to speed, and not yet a sprint.
    var climber = _player(hill)
    _step(climber, _run_ahead(), 0.5, hill)
    assert_false(climber.sprinting)
    assert_true(climber.speed().to(METER_PER_SECOND) < 4.5 * 0.85)
    # Downhill is not.
    var runner = _player(hill)
    _step(runner, MoveInput(-1, 0, 0, 0, True, False), 0.5, hill)
    assert_almost_equal(runner.speed().to(METER_PER_SECOND), 4.5, atol=0.1)
    # In the air, the hill does not drag.
    var flier = _player(hill)
    flier.position.y += 3
    _step(flier, _run_ahead(), 0.1, hill)
    assert_false(flier.grounded)


def test_a_ledges_grace_lets_a_late_jump_go() raises:
    var terrain = _flat()
    var walker = _player(terrain)
    # Over a drop: it falls, and jumps within the grace.
    walker.position = Vector3(0, 2, 0)
    _step(walker, no_input(), 1.0 / 30.0, terrain)
    assert_false(walker.grounded)
    _step(walker, MoveInput(0, 0, 0, 0, False, True), 1.0 / 30.0, terrain)
    assert_true(walker.velocity.y > 3)
    assert_true(walker.jumped)
    # After the grace, it falls.
    var late = _player(terrain)
    late.position = Vector3(0, 3, 0)
    _step(late, no_input(), 0.3, terrain)
    _step(late, MoveInput(0, 0, 0, 0, False, True), 1.0 / 30.0, terrain)
    assert_true(late.velocity.y < 0)
    # Without a grace, it falls at once.
    var plain = Character(
        CharacterParameters(), 0, 0, Angle(0.0, RADIAN), terrain
    )
    plain.position = Vector3(0, 2, 0)
    _step(plain, no_input(), 1.0 / 30.0, terrain)
    _step(plain, MoveInput(0, 0, 0, 0, False, True), 1.0 / 30.0, terrain)
    assert_true(plain.velocity.y < 0)
    # A body a blow throws up gets no grace.
    var thrown = _player(terrain)
    thrown.grounded = False
    thrown.velocity = Vector3(0, 4, 0)
    _step(thrown, MoveInput(0, 0, 0, 0, False, True), 1.0 / 30.0, terrain)
    assert_true(thrown.velocity.y < 4)
    assert_false(thrown.jumped)


def test_a_jump_pressed_just_before_landing_goes_as_it_lands() raises:
    var terrain = _flat()
    var walker = _player(terrain)
    walker.position = Vector3(0, 0.3, 0)
    walker.grounded = False
    walker.velocity = Vector3(0, -3, 0)
    walker.jumped = True
    _step(walker, MoveInput(0, 0, 0, 0, False, True), 2.0 / 30.0, terrain)
    _step(walker, MoveInput(0, 0, 0, 0, False, True), 2.0 / 30.0, terrain)
    assert_true(walker.velocity.y > 2)
    # A press long before landing is forgotten.
    var early = _player(terrain)
    early.position = Vector3(0, 3, 0)
    early.grounded = False
    early.jumped = True
    _step(early, MoveInput(0, 0, 0, 0, False, True), 1.0 / 30.0, terrain)
    _step(early, MoveInput(0, 0, 0, 0, False, True), 1.5, terrain)
    assert_true(early.grounded)
    assert_equal(early.buffered, -1)


def test_a_tapped_jump_is_lower_than_a_held_one() raises:
    var terrain = _flat()
    var tap = _player(terrain)
    _step(tap, MoveInput(0, 0, 0, 0, False, True), 1.0 / 30.0, terrain)
    var risen = tap.velocity.y
    _step(tap, no_input(), 1.0 / 30.0, terrain)
    assert_true(tap.cut)
    assert_true(tap.velocity.y < risen * 0.5)
    var hold = _player(terrain)
    var top_tap = Float32(0)
    var top_hold = Float32(0)
    _step(hold, MoveInput(0, 0, 0, 0, False, True), 1.0 / 30.0, terrain)
    for _ in range(20):
        _step(hold, MoveInput(0, 0, 0, 0, False, True), 1.0 / 30.0, terrain)
        _step(tap, no_input(), 1.0 / 30.0, terrain)
        top_hold = max(top_hold, hold.position.y)
        top_tap = max(top_tap, tap.position.y)
    assert_true(top_tap < top_hold * 0.7)


def test_a_hard_landing_slows_the_player() raises:
    var terrain = _flat()
    var walker = _player(terrain)
    walker.position = Vector3(0, 6, 0)
    walker.grounded = False
    _step(walker, no_input(), 1.2, terrain)
    assert_true(walker.grounded)
    assert_true(walker.landed > 9)
    _step(walker, _run_ahead(), 0.2, terrain)
    assert_true(walker.speed().to(METER_PER_SECOND) <= 1.41)
    _step(walker, _run_ahead(), 0.6, terrain)
    assert_true(walker.speed().to(METER_PER_SECOND) > 2)
    # A short fall is no hard landing.
    var soft = _player(terrain)
    soft.position = Vector3(0, 1, 0)
    soft.grounded = False
    _step(soft, no_input(), 1, terrain)
    assert_equal(soft.landed, 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
