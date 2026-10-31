# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The fight's messages: packed commands and snapshots, which fighters a
player hears of, and the commands a player keeps until the server has
them."""

from extensions.vegetation.ground import Ground
from extensions.village.character import (
    Character,
    CharacterParameters,
    MoveInput,
)
from extensions.village.combat import (
    CombatMove,
    CombatStance,
    Fighter,
    FighterParameters,
    HEAVY,
    HIGH_STANCE,
    LOW_STANCE,
    WHIRLWIND,
)
from extensions.village.netcode import (
    BUTTON_COUNT,
    COMMAND_BYTES,
    EVERY_TENTH,
    EVERY_THIRD,
    EVERY_TICK,
    FAR,
    HISTORY,
    MIDDLE,
    NEAR,
    RELEVANCES,
    SNAPSHOT_BYTES,
    UNHEARD,
    FighterSnapshot,
    InputHistory,
    Relevance,
    apply_snapshot,
    axis_byte,
    buttons_of,
    byte_axis,
    heard,
    input_of,
    pack_command,
    pack_snapshot,
    relevance,
    snapshot_of,
    unpack_command,
    unpack_snapshot,
)
from extensions.village.styles import ARCHERY, MAGIC, FightingStyle
from extensions.village.terrain import Terrain
from math.vector3 import Vector3
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from units.si import DEGREE, METER, RADIAN, Angle, Length


def _all_held() -> MoveInput:
    """Return an input with every button held and the sticks leaned."""
    return MoveInput(
        0.5,
        -0.25,
        1,
        -1,
        True,
        True,
        True,
        light=True,
        heavy=True,
        rising=True,
        whirlwind=True,
        ground_wave=True,
        ultimate=True,
        dodge=True,
        guard=True,
        lock=True,
        high=True,
        middle=True,
        low=True,
        assist=True,
        heal=True,
        swap=True,
        taunt=True,
        book=True,
    )


def _snapshot() -> FighterSnapshot:
    """Return a snapshot of a fighter in a whirlwind."""
    return FighterSnapshot(
        513,
        Vector3(-12.345, 1.5, 200.01),
        Angle(-1.0, RADIAN),
        432,
        0.5,
        0.25,
        3.3,
        WHIRLWIND,
        0.456,
        LOW_STANCE,
        ARCHERY,
        17,
    )


def test_a_fighter_is_heard_by_how_far_it_is() raises:
    for value in [-1, RELEVANCES]:
        assert_false(Relevance(value).is_valid())
    for value in [0, RELEVANCES - 1]:
        assert_true(Relevance(value).is_valid())
    assert_true(relevance(NEAR) == EVERY_TICK)
    assert_true(relevance(NEAR + 1) == EVERY_THIRD)
    assert_true(relevance(MIDDLE + 1) == EVERY_TENTH)
    assert_true(relevance(FAR + 1) == UNHEARD)
    assert_true(heard(EVERY_TICK, 7, 3))
    assert_true(heard(EVERY_THIRD, 1, 2))
    assert_false(heard(EVERY_THIRD, 2, 2))
    assert_true(heard(EVERY_TENTH, 7, 3))
    assert_false(heard(EVERY_TENTH, 8, 3))
    assert_false(heard(UNHEARD, 0, 0))
    # Over ten ticks, a fighter heard every third is heard three or four
    # times.
    var count = 0
    for tick in range(10):
        if heard(EVERY_THIRD, tick, 5):
            count += 1
    assert_true(count == 3 or count == 4)


def test_a_sticks_lean_fits_a_byte() raises:
    assert_equal(Int(axis_byte(-1)), 0)
    assert_equal(Int(axis_byte(0)), 127)
    assert_equal(Int(axis_byte(1)), 254)
    assert_equal(Int(axis_byte(9)), 254)
    assert_equal(byte_axis(axis_byte(-1)), -1)
    assert_equal(byte_axis(255), 1)
    for k in range(21):
        var lean = Float32(k) / 10 - 1
        assert_almost_equal(byte_axis(axis_byte(lean)), lean, atol=0.5 / 127)


def test_a_command_packs_every_button_and_stick() raises:
    var bytes = pack_command(70000, _all_held())
    assert_equal(len(bytes), COMMAND_BYTES)
    var back = unpack_command(bytes)
    assert_equal(back[0], 70000)
    var input = back[1]
    assert_almost_equal(input.forward, 0.5, atol=0.01)
    assert_almost_equal(input.right, -0.25, atol=0.01)
    assert_equal(input.look_right, 1)
    assert_equal(input.look_up, -1)
    var held = buttons_of(input)
    assert_equal(len(held), BUTTON_COUNT)
    for k in range(20):
        assert_true(held[k])
    assert_false(held[20])
    var none = unpack_command(
        pack_command(0, MoveInput(0, 0, 0, 0, False, False))
    )
    for flag in buttons_of(none[1]):
        assert_false(flag)
    # A command can sit anywhere in a message.
    var message = List[UInt8]()
    message.append(9)
    message.extend(bytes.copy())
    assert_equal(unpack_command(message, 1)[0], 70000)
    with assert_raises(contains="four bytes"):
        _ = pack_command(-1, _all_held())
    with assert_raises(contains="four bytes"):
        _ = pack_command(0x100000000, _all_held())
    with assert_raises(contains="twelve"):
        _ = unpack_command(bytes, 1)
    with assert_raises(contains="twelve"):
        _ = unpack_command(bytes, -1)


def test_an_input_needs_its_sticks_and_buttons() raises:
    var sticks: List[Float32] = [0, 0, 0]
    var buttons = List[Bool](length=BUTTON_COUNT, fill=False)
    with assert_raises(contains="four sticks"):
        _ = input_of(sticks, buttons)
    sticks.append(0)
    _ = buttons.pop()
    with assert_raises(contains="four sticks"):
        _ = input_of(sticks, buttons)


def test_a_snapshot_packs_a_fighter() raises:
    var bytes = pack_snapshot(_snapshot())
    assert_equal(len(bytes), SNAPSHOT_BYTES)
    var back = unpack_snapshot(bytes)
    assert_equal(back.id, 513)
    assert_almost_equal(back.position.x, -12.345, atol=0.006)
    assert_almost_equal(back.position.y, 1.5, atol=0.006)
    assert_almost_equal(back.position.z, 200.01, atol=0.006)
    assert_almost_equal(back.heading.to(RADIAN), -1, atol=1e-3)
    assert_equal(back.health, 432)
    assert_almost_equal(back.stamina, 0.5, atol=0.003)
    assert_almost_equal(back.mana, 0.25, atol=0.003)
    assert_almost_equal(back.special, 3.3, atol=0.011)
    assert_true(back.move == WHIRLWIND)
    assert_almost_equal(back.clock, 0.456, atol=6e-4)
    assert_true(back.stance == LOW_STANCE)
    assert_true(back.style == ARCHERY)
    assert_equal(back.combo, 17)
    # A heading past a half turn either way comes back within one.
    var turned = _snapshot()
    turned.heading = Angle(400.0, DEGREE)
    var again = unpack_snapshot(pack_snapshot(turned))
    assert_almost_equal(again.heading.to(DEGREE), 40, atol=0.01)
    turned.heading = Angle(200.0, DEGREE)
    assert_almost_equal(
        unpack_snapshot(pack_snapshot(turned)).heading.to(DEGREE),
        -160,
        atol=0.01,
    )
    # A place past 327 meters, and a combo past 255, are kept to the most.
    turned.position = Vector3(1000, -1000, 0)
    turned.combo = 900
    var far = unpack_snapshot(pack_snapshot(turned))
    assert_almost_equal(far.position.x, 327.67, atol=0.01)
    assert_almost_equal(far.position.y, -327.67, atol=0.01)
    assert_equal(far.combo, 255)
    turned.combo = -4
    assert_equal(unpack_snapshot(pack_snapshot(turned)).combo, 0)


def test_a_snapshot_refuses_what_it_cannot_carry() raises:
    var bad = _snapshot()
    bad.id = 70000
    with assert_raises(contains="two bytes"):
        _ = pack_snapshot(bad)
    bad.id = -1
    with assert_raises(contains="two bytes"):
        _ = pack_snapshot(bad)
    var moves = _snapshot()
    moves.move = CombatMove(99)
    with assert_raises(contains="each be one"):
        _ = pack_snapshot(moves)
    var stance = _snapshot()
    stance.stance = CombatStance(3)
    with assert_raises(contains="each be one"):
        _ = pack_snapshot(stance)
    var style = _snapshot()
    style.style = FightingStyle(9)
    with assert_raises(contains="each be one"):
        _ = pack_snapshot(style)
    var bytes = pack_snapshot(_snapshot())
    with assert_raises(contains="twenty"):
        _ = unpack_snapshot(bytes, 1)
    with assert_raises(contains="twenty"):
        _ = unpack_snapshot(bytes, -1)
    var broken = bytes.copy()
    broken[15] = 99
    with assert_raises(contains="each be one"):
        _ = unpack_snapshot(broken)
    var stanced = bytes.copy()
    stanced[18] = 3
    with assert_raises(contains="each be one"):
        _ = unpack_snapshot(stanced)
    var styled = bytes.copy()
    styled[18] = UInt8(7 << 2)
    with assert_raises(contains="each be one"):
        _ = unpack_snapshot(styled)


def test_a_client_takes_the_servers_snapshot() raises:
    var terrain = Terrain(Ground(hill_height=Length(0.0, METER)))
    var character = Character(
        CharacterParameters(), 0, 0, Angle(0.0, RADIAN), terrain
    )
    var fighter = Fighter(FighterParameters())
    fighter.health = 321
    fighter.stamina = 40
    fighter.mana = 50
    fighter.combo = 4
    var taken = snapshot_of(9, character, fighter)
    assert_equal(taken.id, 9)
    assert_almost_equal(taken.stamina, 0.4, atol=1e-6)
    assert_almost_equal(taken.mana, 0.5, atol=1e-6)
    var none = FighterParameters()
    none.mana = 0
    var plain = Fighter(none)
    assert_equal(snapshot_of(1, character, plain).mana, 0)
    var copy = Fighter(FighterParameters())
    var place = Character(
        CharacterParameters(), 3, 3, Angle(1.0, RADIAN), terrain
    )
    var shot = _snapshot()
    shot.style = MAGIC
    shot.move = HEAVY
    shot.stance = HIGH_STANCE
    apply_snapshot(shot, place, copy)
    assert_almost_equal(place.position.x, -12.345, atol=1e-4)
    assert_almost_equal(place.heading.to(RADIAN), -1, atol=1e-6)
    assert_equal(copy.health, 432)
    assert_almost_equal(copy.stamina, 50, atol=1e-4)
    assert_almost_equal(copy.mana, 25, atol=1e-4)
    assert_true(copy.move == HEAVY)
    assert_true(copy.style == MAGIC)
    assert_true(copy.stance == HIGH_STANCE)
    assert_equal(copy.combo, 17)
    # The same style again keeps the traits.
    apply_snapshot(shot, place, copy)
    assert_true(copy.style == MAGIC)
    assert_true(copy.traits.ward)


def test_a_player_keeps_each_command_until_the_server_has_it() raises:
    var history = InputHistory()
    var still = MoveInput(0, 0, 0, 0, False, False)
    var first = history.send(10, still)
    assert_equal(len(first), COMMAND_BYTES)
    var second = history.send(11, _all_held())
    assert_equal(len(second), 2 * COMMAND_BYTES)
    assert_equal(unpack_command(second, COMMAND_BYTES)[0], 11)
    assert_equal(history.waiting(), 2)
    history.ack(10)
    assert_equal(history.waiting(), 1)
    history.ack(50)
    assert_equal(history.waiting(), 0)
    with assert_raises(contains="follow"):
        _ = history.send(11, still)
    _ = history.send(12, still)
    with assert_raises(contains="follow"):
        _ = history.send(12, still)
    # It keeps the last `HISTORY` at most.
    for tick in range(13, 13 + HISTORY + 5):
        _ = history.send(tick, still)
    assert_equal(history.waiting(), HISTORY)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
