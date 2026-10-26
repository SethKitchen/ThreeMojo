# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.gamepad.web`, SDL's browser joystick driver.

The browser's pads are states that the test makes, as a page would read
them from `navigator.getGamepads()`. The expected behavior is SDL 3.2.24's
`src/joystick/emscripten/SDL_sysjoystick.c`: a change is sent only when a
value differs from the last state, a state with the same nonzero
timestamp is old, and an axis is `(Sint16)(32767. * value)`.
"""

from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.gamepad.gamepad import GAMEPAD_BUTTON_DOWN, GAMEPAD_BUTTON_UP
from extensions.gamepad.ids import (
    AXIS_LEFTX,
    AXIS_LEFTY,
    AXIS_LEFT_TRIGGER,
    BUTTON_DPAD_UP,
    BUTTON_GUIDE,
    BUTTON_SOUTH,
    BUTTON_START,
)
from extensions.gamepad.mapping import MappingDatabase
from extensions.gamepad.web import (
    WEB_MAX_INPUTS,
    WebGamepad,
    WebGamepadState,
    WebHub,
    axis_value,
    web_mapping_database,
)
from units.si import Duration64, SECOND

comptime XBOX_ID = "Xbox 360 Controller (XInput STANDARD GAMEPAD)"


def _seconds(value: Float64) -> Duration64:
    return Duration64(value, SECOND)


def _state(index: Int = 0) -> WebGamepadState:
    return WebGamepadState(index, XBOX_ID, 4, 17)


def test_mapping_database() raises:
    var database = web_mapping_database()
    assert_true(database.default_index >= 0)
    var pad = WebGamepad(_state(), database)
    assert_equal(pad.name, XBOX_ID)
    assert_equal(pad.gamepad.joystick.axis_count(), 4)
    assert_equal(pad.gamepad.joystick.button_count(), 17)
    assert_equal(pad.gamepad.joystick.hat_count(), 0)
    assert_false(pad.rumble_available)


def test_axis_value() raises:
    assert_equal(axis_value(0.5), 16383)
    assert_equal(axis_value(-0.5), -16383)
    assert_equal(axis_value(1.0), 32767)
    assert_equal(axis_value(-1.0), -32767)
    # Out of range is clamped, where SDL's cast is undefined.
    assert_equal(axis_value(3.0), 32767)
    assert_equal(axis_value(-3.0), -32767)


def test_buttons_and_axes() raises:
    var database = web_mapping_database()
    var pad = WebGamepad(_state(), database)
    var state = _state()
    state.digital_buttons[0] = True
    state.analog_buttons[0] = 1
    state.digital_buttons[6] = True
    state.analog_buttons[6] = 0.75
    state.axes[0] = 0.5
    state.axes[1] = -1
    var events = pad.update(state)
    assert_true(pad.gamepad.get_button(BUTTON_SOUTH))
    assert_equal(pad.gamepad.get_axis(AXIS_LEFTX), 16383)
    assert_equal(pad.gamepad.get_axis(AXIS_LEFTY), -32767)
    # The trigger is a button in the standard layout: fully down.
    assert_equal(pad.gamepad.get_axis(AXIS_LEFT_TRIGGER), 32767)
    var downs = 0
    for event in events:
        if event.kind == GAMEPAD_BUTTON_DOWN:
            downs += 1
    assert_equal(downs, 1)
    # The analog value is kept for the next comparison.
    assert_equal(pad.analog_buttons[6], 0.75)
    # The rest of the standard layout.
    state.digital_buttons[0] = False
    state.digital_buttons[9] = True
    state.digital_buttons[12] = True
    state.digital_buttons[16] = True
    events = pad.update(state)
    assert_false(pad.gamepad.get_button(BUTTON_SOUTH))
    assert_true(pad.gamepad.get_button(BUTTON_START))
    assert_true(pad.gamepad.get_button(BUTTON_DPAD_UP))
    assert_true(pad.gamepad.get_button(BUTTON_GUIDE))
    var ups = 0
    for event in events:
        if event.kind == GAMEPAD_BUTTON_UP:
            ups += 1
    assert_equal(ups, 1)


def test_timestamps() raises:
    var database = web_mapping_database()
    var pad = WebGamepad(WebGamepadState(0, XBOX_ID, 4, 17, 10), database)
    var state = WebGamepadState(0, XBOX_ID, 4, 17, 10)
    state.digital_buttons[0] = True
    # The same nonzero timestamp: an old state, which changes nothing.
    _ = pad.update(state)
    assert_false(pad.gamepad.get_button(BUTTON_SOUTH))
    state.timestamp = 11
    _ = pad.update(state)
    assert_true(pad.gamepad.get_button(BUTTON_SOUTH))
    # A timestamp of 0 always counts.
    state.timestamp = 0
    state.digital_buttons[0] = False
    _ = pad.update(state)
    assert_false(pad.gamepad.get_button(BUTTON_SOUTH))
    _ = pad.update(state)
    assert_false(pad.gamepad.get_button(BUTTON_SOUTH))


def test_short_state() raises:
    # A state with fewer inputs than the pad reads the rest as at rest.
    var database = web_mapping_database()
    var pad = WebGamepad(_state(), database)
    var full = _state()
    full.digital_buttons[16] = True
    full.axes[3] = 1
    _ = pad.update(full)
    assert_true(pad.gamepad.get_button(BUTTON_GUIDE))
    var short = WebGamepadState(0, XBOX_ID, 2, 4)
    _ = pad.update(short)
    assert_false(pad.gamepad.get_button(BUTTON_GUIDE))
    assert_equal(pad.gamepad.joystick.get_axis(3), 0)


def test_no_inputs() raises:
    var database = web_mapping_database()
    var pad = WebGamepad(WebGamepadState(0, "Pad", 0, 0), database)
    assert_equal(len(pad.update(WebGamepadState(0, "Pad", 0, 0))), 0)


def test_bad_mapping() raises:
    with assert_raises():
        _ = WebHub("not a mapping")


def test_state_limits() raises:
    var state = WebGamepadState(0, "Pad", 100, -3)
    assert_equal(len(state.axes), WEB_MAX_INPUTS)
    assert_equal(len(state.digital_buttons), 0)
    assert_equal(len(state.analog_buttons), 0)


def test_no_mapping() raises:
    var empty = MappingDatabase()
    with assert_raises():
        _ = WebGamepad(_state(), empty)


def test_rumble() raises:
    var database = web_mapping_database()
    var silent = WebGamepad(_state(), database)
    assert_false(silent.rumble_at(100, 200, _seconds(1), _seconds(0)))
    assert_false(silent.take_rumble())
    var pad = WebGamepad(_state(), database, rumble_available=True)
    with assert_raises():
        _ = pad.rumble_at(70000, 0, _seconds(1), _seconds(0))
    assert_true(pad.rumble_at(1000, 2000, _seconds(5), _seconds(0)))
    var request = pad.take_rumble()
    assert_true(request)
    assert_equal(request.value()[0], 1000)
    assert_equal(request.value()[1], 2000)
    assert_false(pad.take_rumble())
    # The same strengths only extend the time.
    assert_true(pad.rumble_at(1000, 2000, _seconds(5), _seconds(0.5)))
    assert_false(pad.take_rumble())
    # SDL sends it again after 2 seconds.
    pad.tick(_seconds(1))
    assert_false(pad.take_rumble())
    pad.tick(_seconds(2.6))
    assert_true(pad.take_rumble())
    # At the end of the duration it stops.
    pad.tick(_seconds(6))
    var stop = pad.take_rumble()
    assert_true(stop)
    assert_equal(stop.value()[0], 0)
    assert_equal(stop.value()[1], 0)
    pad.tick(_seconds(9))
    assert_false(pad.take_rumble())


def test_hub() raises:
    var hub = WebHub()
    assert_equal(hub.find(-1), -1)
    assert_equal(hub.find(0), -1)
    assert_true(hub.connect(_state(0)))
    assert_true(hub.connect(_state(3), rumble_available=True))
    assert_false(hub.connect(_state(3)))
    assert_equal(hub.find(3), 1)
    assert_true(hub.pads[1].rumble_available)
    var state = _state(3)
    state.digital_buttons[0] = True
    assert_true(len(hub.update(state)) > 0)
    assert_true(hub.pads[1].gamepad.get_button(BUTTON_SOUTH))
    assert_equal(len(hub.update(_state(7))), 0)
    assert_true(hub.disconnect(0))
    assert_false(hub.disconnect(0))
    assert_equal(len(hub.pads), 1)
    assert_equal(hub.find(3), 0)
    # A pad that no mapping fits is not connected.
    hub.database = MappingDatabase()
    assert_false(hub.connect(_state(5)))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
