# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A player's input from a gamepad, through SDL's standard browser
mapping, and from the keyboard."""

from controls.held_keys import HeldKeys
from controls.input import (
    ARROW_DOWN,
    ARROW_LEFT,
    ARROW_RIGHT,
    ARROW_UP,
    KEY_A,
    KEY_D,
    KEY_R,
    KEY_S,
    KEY_W,
)
from extensions.gamepad.web import WebGamepadState, WebHub
from extensions.village.character import MoveInput, no_input
from controls.input import KEY_F, Key
from extensions.village.pad_input import (
    KEY_B,
    KEY_C,
    KEY_E,
    KEY_G,
    KEY_H,
    KEY_M,
    KEY_Q,
    KEY_SIX,
    KEY_SPACE,
    KEY_T,
    KEY_V,
    KEY_X,
    KEY_Z,
    combined,
    fight_input,
    gamepad_input,
    keyboard_input,
    stick,
)
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_false,
    assert_true,
)


def _pad(state: WebGamepadState) raises -> MoveInput:
    """Return the input of a web pad in one state."""
    var hub = WebHub()
    var first = WebGamepadState(0, "Xbox Wireless Controller", 4, 17)
    _ = hub.connect(first)
    var next = state.copy()
    next.timestamp = 1
    _ = hub.update(next)
    return gamepad_input(hub.pads[0].gamepad)


def _state() -> WebGamepadState:
    """Return a pad at rest, in the browser's standard layout."""
    return WebGamepadState(0, "Xbox Wireless Controller", 4, 17)


def test_a_stick_reads_nothing_in_its_dead_zone() raises:
    var rest = stick(3000, -3000)
    assert_equal(rest[0], 0)
    assert_equal(rest[1], 0)
    var full = stick(32767, 0)
    assert_almost_equal(full[0], 1, atol=1e-4)
    var half = stick(0, -19660)
    assert_almost_equal(half[1], -0.5, atol=1e-3)
    var corner = stick(32767, 32767)
    assert_almost_equal(corner[0], 0.7071, atol=1e-3)


def test_the_left_stick_moves_and_the_right_stick_looks() raises:
    var state = _state()
    state.axes[1] = -1
    state.axes[0] = 0.5
    state.axes[2] = 1
    state.axes[3] = 1
    var input = _pad(state)
    assert_true(input.forward > 0.8)
    assert_true(input.right > 0.2)
    # A stick leaned to its corner leans along each axis by a half root
    # two, as its throw is round.
    assert_almost_equal(input.look_right, 0.7071, atol=1e-3)
    assert_almost_equal(input.look_up, -0.7071, atol=1e-3)
    assert_false(input.run)
    assert_false(input.jump)
    assert_false(input.use)


def test_the_buttons_jump_run_and_steer() raises:
    var state = _state()
    # The south button, and the right trigger all the way down.
    for button in [0, 7]:
        state.digital_buttons[button] = True
        state.analog_buttons[button] = 1
    var input = _pad(state)
    assert_true(input.jump)
    assert_true(input.run)
    var east = _state()
    east.digital_buttons[1] = True
    east.analog_buttons[1] = 1
    assert_true(_pad(east).run)
    var click = _state()
    click.digital_buttons[10] = True
    click.analog_buttons[10] = 1
    assert_true(_pad(click).run)
    # The west button uses.
    var west = _state()
    west.digital_buttons[2] = True
    west.analog_buttons[2] = 1
    assert_true(_pad(west).use)
    assert_false(input.use)
    var up = _state()
    up.digital_buttons[12] = True
    up.digital_buttons[15] = True
    var steer = _pad(up)
    assert_equal(steer.forward, 1)
    assert_equal(steer.right, 1)
    var down = _state()
    down.digital_buttons[13] = True
    down.digital_buttons[14] = True
    var back = _pad(down)
    assert_equal(back.forward, -1)
    assert_equal(back.right, -1)


def test_the_keyboard_moves_looks_runs_and_jumps() raises:
    var keys = HeldKeys()
    assert_equal(keyboard_input(keys, False).forward, 0)
    for key in [KEY_W, KEY_D, ARROW_RIGHT, ARROW_UP, KEY_SPACE, KEY_E]:
        keys.press(key)
    var input = keyboard_input(keys, True)
    assert_equal(input.forward, 1)
    assert_equal(input.right, 1)
    assert_equal(input.look_right, 1)
    assert_equal(input.look_up, 1)
    assert_true(input.run)
    assert_true(input.jump)
    assert_true(input.use)
    var back = HeldKeys()
    for key in [KEY_S, KEY_A, ARROW_LEFT, ARROW_DOWN, KEY_R]:
        back.press(key)
    var other = keyboard_input(back, False)
    assert_equal(other.forward, -1)
    assert_equal(other.right, -1)
    assert_equal(other.look_right, -1)
    assert_equal(other.look_up, -1)
    assert_true(other.run)
    assert_false(other.jump)
    assert_false(other.use)


def test_two_inputs_add() raises:
    var a = MoveInput(0.8, -0.5, 0.2, 0, True, False, True)
    var b = MoveInput(0.8, 0.2, -0.9, 0.3, False, True)
    var both = combined(a, b)
    assert_equal(both.forward, 1)
    assert_almost_equal(both.right, -0.3, atol=1e-6)
    assert_almost_equal(both.look_right, -0.7, atol=1e-6)
    assert_almost_equal(both.look_up, 0.3, atol=1e-6)
    assert_true(both.run)
    assert_true(both.jump)
    assert_true(both.use)
    var none = combined(no_input(), no_input())
    assert_false(none.run)
    assert_false(none.use)
    var second = no_input()
    second.use = True
    assert_true(combined(no_input(), second).use)


def _fight(
    south: Bool = False,
    west: Bool = False,
    north: Bool = False,
    east: Bool = False,
    right_shoulder: Bool = False,
    left_shoulder: Bool = False,
    left_trigger: Bool = False,
    right_stick: Bool = False,
    back: Bool = False,
) -> MoveInput:
    """Return the input of some gamepad buttons held."""
    return fight_input(
        no_input(),
        south,
        west,
        north,
        east,
        right_shoulder,
        left_shoulder,
        left_trigger,
        right_stick,
        back,
    )


def _all(input: MoveInput) -> List[Bool]:
    """Return each of an input's buttons."""
    return [
        input.run,
        input.jump,
        input.use,
        input.light,
        input.heavy,
        input.rising,
        input.tempest,
        input.fang,
        input.mystic,
        input.dodge,
        input.guard,
        input.lock,
        input.high,
        input.middle,
        input.low,
        input.boost,
        input.heal,
    ]


def test_the_shoulders_and_the_trigger_fight() raises:
    for held in _all(_fight()):
        assert_false(held)
    # The south button jumps; with the guard held it takes the low stance.
    var jump = _fight(south=True)
    assert_true(jump.jump)
    assert_false(jump.low)
    var low = _fight(south=True, left_shoulder=True)
    assert_false(low.jump)
    assert_true(low.low)
    assert_true(low.guard)
    # The west button uses, or takes the middle stance, or makes the demon
    # fang.
    assert_true(_fight(west=True).use)
    var fang = _fight(west=True, left_trigger=True)
    assert_false(fang.use)
    assert_true(fang.fang)
    assert_false(_fight(west=True).fang)
    var middle = _fight(west=True, left_shoulder=True)
    assert_false(middle.use)
    assert_true(middle.middle)
    # The north button: the heavy attack, the tempest, or the high stance.
    var heavy = _fight(north=True)
    assert_true(heavy.heavy)
    assert_false(heavy.tempest)
    var tempest = _fight(north=True, left_trigger=True)
    assert_false(tempest.heavy)
    assert_true(tempest.tempest)
    var high = _fight(north=True, left_shoulder=True)
    assert_false(high.heavy)
    assert_true(high.high)
    var both = _fight(north=True, left_shoulder=True, left_trigger=True)
    assert_true(both.tempest)
    assert_false(both.high)
    # The right shoulder: a light attack, or the rising edge.
    var light = _fight(right_shoulder=True)
    assert_true(light.light)
    assert_false(light.rising)
    var rising = _fight(right_shoulder=True, left_trigger=True)
    assert_false(rising.light)
    assert_true(rising.rising)
    assert_false(rising.mystic)
    # The right shoulder and the north button together, with the trigger
    # held: the mystic arte.
    var mystic = _fight(north=True, right_shoulder=True, left_trigger=True)
    assert_true(mystic.mystic)
    assert_false(_fight(north=True, right_shoulder=True).mystic)
    assert_false(_fight(north=True, left_trigger=True).mystic)
    assert_true(_fight(east=True).dodge)
    assert_true(_fight(right_stick=True).lock)
    assert_true(_fight(back=True).heal)
    # The left trigger and the left shoulder: the companion's boost attack.
    var boost = _fight(left_shoulder=True, left_trigger=True)
    assert_true(boost.boost)
    assert_false(boost.high)
    assert_false(_fight(left_shoulder=True).boost)
    assert_false(_fight(left_trigger=True).boost)


def test_a_pad_reads_its_fight_buttons() raises:
    # The right shoulder is button 5 of the browser's layout, the left
    # trigger 6, the left shoulder 4, the north button 3 and the right
    # stick 11.
    var light = _state()
    light.digital_buttons[5] = True
    light.analog_buttons[5] = 1
    assert_true(_pad(light).light)
    var rising = light.copy()
    rising.digital_buttons[6] = True
    rising.analog_buttons[6] = 1
    assert_true(_pad(rising).rising)
    var high = _state()
    for button in [3, 4]:
        high.digital_buttons[button] = True
        high.analog_buttons[button] = 1
    var stance = _pad(high)
    assert_true(stance.high)
    assert_true(stance.guard)
    var lock = _state()
    lock.digital_buttons[11] = True
    lock.analog_buttons[11] = 1
    assert_true(_pad(lock).lock)
    # The back button is button 8.
    var heal = _state()
    heal.digital_buttons[8] = True
    heal.analog_buttons[8] = 1
    assert_true(_pad(heal).heal)


def test_the_keyboard_fights() raises:
    var keys = HeldKeys()
    for key in [
        KEY_F,
        KEY_G,
        KEY_Z,
        KEY_X,
        KEY_B,
        KEY_C,
        KEY_V,
        KEY_T,
        KEY_SIX,
        Key(KEY_SIX.value + 1),
        Key(KEY_SIX.value + 2),
        KEY_H,
        KEY_M,
        KEY_Q,
    ]:
        keys.press(key)
    var input = keyboard_input(keys, False)
    var fights = _all(input)
    for k in range(3, len(fights)):
        assert_true(fights[k])
    for k in range(3, len(fights)):
        assert_false(_all(keyboard_input(HeldKeys(), False))[k])


def test_the_fight_buttons_add() raises:
    var held = MoveInput(
        0,
        0,
        0,
        0,
        False,
        False,
        light=True,
        heavy=True,
        rising=True,
        tempest=True,
        fang=True,
        mystic=True,
        dodge=True,
        guard=True,
        lock=True,
        high=True,
        middle=True,
        low=True,
        boost=True,
        heal=True,
    )
    for pair in [
        combined(held, no_input()),
        combined(no_input(), held),
    ]:
        var buttons = _all(pair)
        for k in range(3, len(buttons)):
            assert_true(buttons[k])
    var none = _all(combined(no_input(), no_input()))
    for k in range(3, len(none)):
        assert_false(none[k])


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
