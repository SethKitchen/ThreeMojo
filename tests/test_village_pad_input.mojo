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
from extensions.village.pad_input import (
    KEY_SPACE,
    combined,
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
    for key in [KEY_W, KEY_D, ARROW_RIGHT, ARROW_UP, KEY_SPACE]:
        keys.press(key)
    var input = keyboard_input(keys, True)
    assert_equal(input.forward, 1)
    assert_equal(input.right, 1)
    assert_equal(input.look_right, 1)
    assert_equal(input.look_up, 1)
    assert_true(input.run)
    assert_true(input.jump)
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


def test_two_inputs_add() raises:
    var a = MoveInput(0.8, -0.5, 0.2, 0, True, False)
    var b = MoveInput(0.8, 0.2, -0.9, 0.3, False, True)
    var both = combined(a, b)
    assert_equal(both.forward, 1)
    assert_almost_equal(both.right, -0.3, atol=1e-6)
    assert_almost_equal(both.look_right, -0.7, atol=1e-6)
    assert_almost_equal(both.look_up, 0.3, atol=1e-6)
    assert_true(both.run)
    assert_true(both.jump)
    var none = combined(no_input(), no_input())
    assert_false(none.run)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
