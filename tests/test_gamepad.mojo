# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `extensions.gamepad.joystick` and `extensions.gamepad.gamepad`.

The scripted pad is SDL 3.2.24's virtual joystick: six axes, six buttons
and a hat, with its triggers at rest at -32768. The expected bindings,
events, axes and buttons after each step are the ones SDL gives for the
same mapping and the same steps, built from source and run on Linux.
Like SDL's virtual driver, the script sends every axis when one changes,
every button when one changes, and the hat when it changes.
"""

from extensions.gamepad.effects import (
    MAX_RUMBLE_DURATION,
    RumbleState,
    require_color,
)
from units.si import Duration64, Frequency, SECOND
from std.testing import (
    TestSuite,
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
)
from extensions.gamepad.gamepad import (
    GAMEPAD_AXIS_MOTION,
    GAMEPAD_BUTTON_DOWN,
    GAMEPAD_BUTTON_UP,
    Gamepad,
    GamepadEvent,
    GamepadEventKind,
)
from extensions.gamepad.guid import (
    BUS_USB,
    DRIVER_NONE,
    DRIVER_RAWINPUT,
    DRIVER_WGI,
    DRIVER_XINPUT,
    JoystickGuid,
    ProductId,
    VendorId,
    create_joystick_guid,
    string_to_guid,
)
from extensions.gamepad.ids import (
    AXIS_COUNT,
    AXIS_LEFTX,
    AXIS_LEFT_TRIGGER,
    AXIS_RIGHT_TRIGGER,
    BUTTON_COUNT,
    BUTTON_DPAD_DOWN,
    BUTTON_DPAD_UP,
    BUTTON_EAST,
    BUTTON_GUIDE,
    BUTTON_MISC1,
    BUTTON_SOUTH,
    BUTTON_WEST,
    FACE_STYLE_ABXY,
    FACE_STYLE_BAYX,
    FACE_STYLE_SONY,
    GAMEPAD_TYPE_PS4,
    GAMEPAD_TYPE_PS5,
    GAMEPAD_TYPE_STANDARD,
    GAMEPAD_TYPE_XBOX360,
    GamepadAxis,
    GamepadButton,
    LABEL_A,
    LABEL_B,
    LABEL_CROSS,
)
from extensions.gamepad.joystick import (
    JOYSTICK_AXIS_MOTION,
    JOYSTICK_BUTTON,
    JOYSTICK_HAT_MOTION,
    Joystick,
    JoystickEventKind,
    SENSOR_ACCEL,
    SENSOR_GYRO,
    SensorType,
)
from extensions.gamepad.mapping import (
    BIND_AXIS,
    BIND_BUTTON,
    BIND_HAT,
    HAT_CENTERED,
    HAT_DOWN,
    HAT_RIGHT,
    HAT_UP,
    MappingDatabase,
)

comptime ORACLE_GUID = "ff00bc6a341200007856000000007601"


struct VirtualPad(Movable):
    """SDL's virtual joystick: the state it holds and what it sends."""

    var gamepad: Gamepad
    var axes: List[Int]
    var buttons: List[Bool]
    var hat: Int
    var axes_changed: Bool
    var buttons_changed: Bool
    var hat_changed: Bool

    def __init__(out self, mapping: String) raises:
        var database = MappingDatabase()
        _ = database.add_mapping(ORACLE_GUID + ",Oracle Pad," + mapping)
        var joystick = Joystick(
            "Oracle Pad", string_to_guid(ORACLE_GUID), 6, 6, 1
        )
        var index = database.mapping_for_device(
            "Oracle Pad", joystick.guid, None
        )
        self.gamepad = Gamepad(joystick^, database.mappings[index])
        self.axes = [0, 0, 0, 0, -32768, -32768]
        self.buttons = List[Bool](length=6, fill=False)
        self.hat = 0
        self.axes_changed = False
        self.buttons_changed = False
        self.hat_changed = False

    def axis(mut self, axis: Int, value: Int):
        self.axes[axis] = value
        self.axes_changed = True

    def button(mut self, button: Int, down: Bool):
        self.buttons[button] = down
        self.buttons_changed = True

    def set_hat(mut self, value: Int):
        self.hat = value
        self.hat_changed = True

    def step(mut self) -> String:
        """Send the changes, then describe the events and the state as the
        oracle prints them."""
        if self.axes_changed:
            for index in range(6):
                self.gamepad.joystick.send_axis(index, self.axes[index])
        if self.buttons_changed:
            for index in range(6):
                self.gamepad.joystick.send_button(index, self.buttons[index])
        if self.hat_changed:
            self.gamepad.joystick.send_hat(0, self.hat)
        self.axes_changed = False
        self.buttons_changed = False
        self.hat_changed = False
        var text = String()
        for event in self.gamepad.update():
            text += _event_text(event)
        return text + self.state()

    def state(self) -> String:
        var text = String("axes")
        for index in range(AXIS_COUNT):
            text += " " + String(self.gamepad.get_axis(GamepadAxis(index)))
        text += " buttons"
        for index in range(BUTTON_COUNT):
            if self.gamepad.get_button(GamepadButton(index)):
                text += " " + String(index)
        return text


def _event_text(event: GamepadEvent) -> String:
    if event.kind == GAMEPAD_AXIS_MOTION:
        return (
            "axis "
            + String(event.axis.value)
            + " "
            + String(event.value)
            + ", "
        )
    if event.kind == GAMEPAD_BUTTON_DOWN:
        return "down " + String(event.button.value) + ", "
    return "up " + String(event.button.value) + ", "


comptime ORACLE_MAPPING = (
    "a:b0,b:b1,x:+a4,y:-a4,back:h0.4,dpup:h0.1,dpdown:b2,dpleft:-a5,"
    "dpright:+a5,leftx:a0,lefty:a1~,+rightx:a2,-rightx:a3,righty:b3,"
    "lefttrigger:a4,righttrigger:h0.2,start:b4,type:ps4,"
)


def test_kinds_check_their_range() raises:
    assert_true(JoystickEventKind(6).is_valid())
    assert_false(JoystickEventKind(7).is_valid())
    assert_true(GamepadEventKind(6).is_valid())
    assert_false(GamepadEventKind(7).is_valid())
    assert_false(GamepadEventKind(-1).is_valid())


def test_the_bindings_match_sdl() raises:
    var pad = VirtualPad(ORACLE_MAPPING)
    ref bindings = pad.gamepad.bindings
    assert_equal(len(bindings), 17)
    # SDL: "bind in 2 a4 0 -32768 out 1 button 3".
    assert_equal(bindings[3].input_type, BIND_AXIS)
    assert_equal(bindings[3].input_axis, 4)
    assert_equal(bindings[3].input_axis_min, 0)
    assert_equal(bindings[3].input_axis_max, -32768)
    assert_equal(bindings[3].output_button.value, 3)
    # SDL: "bind in 2 a1 32767 -32768 out 2 axis 1 -32768 32767".
    assert_equal(bindings[10].input_axis_min, 32767)
    assert_equal(bindings[10].input_axis_max, -32768)
    assert_equal(bindings[10].output_axis_min, -32768)
    # SDL: "bind in 2 a3 -32768 32767 out 2 axis 2 0 -32768".
    assert_equal(bindings[12].output_axis.value, 2)
    assert_equal(bindings[12].output_axis_max, -32768)
    # SDL: "bind in 3 h0.2 out 2 axis 5 0 32767".
    assert_equal(bindings[15].input_type, BIND_HAT)
    assert_equal(bindings[15].input_hat_mask, 2)
    assert_equal(bindings[15].output_type, BIND_AXIS)
    assert_equal(bindings[15].output_axis_max, 32767)
    assert_equal(bindings[16].input_type, BIND_BUTTON)
    assert_equal(bindings[16].output_button.value, 6)
    assert_equal(pad.gamepad.type, GAMEPAD_TYPE_PS4)
    assert_equal(pad.gamepad.button_label(BUTTON_SOUTH), LABEL_CROSS)
    assert_equal(pad.gamepad.name, "Oracle Pad")


def test_a_scripted_pad_matches_sdl() raises:
    var pad = VirtualPad(ORACLE_MAPPING)
    assert_equal(pad.state(), "axes 0 -1 16383 0 0 0 buttons 3")
    pad.axis(0, 20000)
    assert_equal(
        pad.step(),
        (
            "axis 0 20000, axis 0 20000, axis 1 -1, axis 1 -1, axis 2 16383, "
            "axis 2 16383, axis 2 -16384, axis 2 -16384, down 3, down 3, "
            "down 13, down 13, axes 20000 -1 16383 0 0 0 buttons 3 13"
        ),
    )
    pad.axis(1, -30000)
    assert_equal(
        pad.step(), "axis 1 29999, axes 20000 29999 16383 0 0 0 buttons 3 13"
    )
    pad.axis(2, 16000)
    pad.axis(3, -8000)
    assert_equal(
        pad.step(),
        (
            "axis 2 24383, axis 2 -12384, axes 20000 29999 24383 0 0 0 buttons"
            " 3 13"
        ),
    )
    pad.axis(2, -100)
    pad.axis(3, 100)
    assert_equal(
        pad.step(),
        (
            "axis 2 16333, axis 2 -16434, axes 20000 29999 16333 0 0 0 buttons"
            " 3 13"
        ),
    )
    pad.axis(4, 32767)
    assert_equal(
        pad.step(),
        "up 3, down 2, axes 20000 29999 16333 0 32767 0 buttons 2 13",
    )
    pad.axis(4, 10000)
    assert_equal(
        pad.step(), "up 2, axes 20000 29999 16333 0 21383 0 buttons 13"
    )
    pad.axis(4, -32768)
    assert_equal(
        pad.step(), "up 2, down 3, axes 20000 29999 16333 0 0 0 buttons 3 13"
    )
    pad.axis(4, -20000)
    assert_equal(
        pad.step(), "down 3, axes 20000 29999 16333 0 6383 0 buttons 3 13"
    )
    pad.axis(4, 0)
    assert_equal(
        pad.step(), "up 3, up 2, axes 20000 29999 16333 0 16383 0 buttons 13"
    )
    pad.axis(5, -32768)
    assert_equal(pad.step(), "axes 20000 29999 16333 0 16383 0 buttons 13")
    pad.axis(5, 32767)
    assert_equal(
        pad.step(),
        "up 13, down 14, axes 20000 29999 16333 0 16383 0 buttons 14",
    )
    pad.axis(5, 0)
    assert_equal(
        pad.step(), "up 14, up 13, axes 20000 29999 16333 0 16383 0 buttons"
    )
    pad.button(0, True)
    pad.button(3, True)
    assert_equal(
        pad.step(),
        "down 0, axis 3 32767, axes 20000 29999 16333 32767 16383 0 buttons 0",
    )
    pad.button(0, False)
    pad.button(3, False)
    pad.button(2, True)
    pad.button(5, True)
    assert_equal(
        pad.step(),
        (
            "up 0, down 12, axis 3 -32768, axes 20000 29999 16333 0 16383 0"
            " buttons 12"
        ),
    )
    pad.set_hat(HAT_RIGHT | HAT_DOWN)
    assert_equal(
        pad.step(),
        (
            "down 4, axis 5 32767, axes 20000 29999 16333 0 16383 32767 buttons"
            " 4 12"
        ),
    )
    pad.set_hat(HAT_UP)
    assert_equal(
        pad.step(),
        (
            "up 4, down 11, axis 5 0, axes 20000 29999 16333 0 16383 0 buttons"
            " 11 12"
        ),
    )
    pad.set_hat(HAT_CENTERED)
    assert_equal(
        pad.step(), "up 11, axes 20000 29999 16333 0 16383 0 buttons 12"
    )
    # Putting the pad at rest releases the buttons and zeroes the axes.
    var rest = pad.gamepad.recenter()
    assert_equal(len(rest), 5)
    assert_equal(rest[0].kind, GAMEPAD_BUTTON_UP)
    assert_equal(rest[0].button, BUTTON_DPAD_DOWN)
    assert_equal(rest[1].kind, GAMEPAD_AXIS_MOTION)
    assert_equal(rest[1].value, 0)


def test_controls_report_what_the_mapping_binds() raises:
    var pad = VirtualPad(ORACLE_MAPPING)
    assert_true(pad.gamepad.has_button(BUTTON_SOUTH))
    assert_false(pad.gamepad.has_button(BUTTON_GUIDE))
    assert_true(pad.gamepad.has_axis(AXIS_LEFT_TRIGGER))
    var bare = VirtualPad("a:b0,")
    assert_false(bare.gamepad.has_axis(AXIS_LEFTX))
    assert_equal(bare.gamepad.get_axis(AXIS_LEFTX), 0)
    assert_false(bare.gamepad.get_button(BUTTON_EAST))


def test_the_type_and_face_come_from_the_mapping_or_the_device() raises:
    var face = VirtualPad("a:b0,face:sony,")
    assert_equal(face.gamepad.face_style, FACE_STYLE_SONY)
    var labels = VirtualPad(
        "a:b0,hint:!SDL_GAMECONTROLLER_USE_BUTTON_LABELS:=1,"
    )
    assert_equal(labels.gamepad.face_style, FACE_STYLE_BAYX)
    var plain = VirtualPad("a:b0,")
    assert_equal(plain.gamepad.type, GAMEPAD_TYPE_STANDARD)
    assert_equal(plain.gamepad.face_style, FACE_STYLE_ABXY)
    assert_equal(plain.gamepad.button_label(BUTTON_SOUTH), LABEL_A)
    # A DualSense GUID makes a PS5 pad without a type field.
    var database = MappingDatabase()
    var guid = "030000004c050000e60c000011010000"
    _ = database.add_mapping(guid + ",PS5,a:b0,")
    var joystick = Joystick("PS5", string_to_guid(guid), 0, 1, 0)
    var ps5 = Gamepad(joystick^, database.mappings[0])
    assert_equal(ps5.type, GAMEPAD_TYPE_PS5)
    assert_equal(ps5.face_style, FACE_STYLE_SONY)
    # An axis the joystick does not have reads 0, which is the middle of a
    # trigger's input range. SDL gives 16383 too.
    var missing = VirtualPad("lefttrigger:a9,righttrigger:b1,")
    assert_equal(missing.gamepad.get_axis(AXIS_LEFT_TRIGGER), 16383)


def test_hidapi_mappings_are_fixed_up() raises:
    var database = MappingDatabase()
    var guid = "03000000" + "5e04" + "0000" + "8e02" + "0000" + "0000" + "6800"
    _ = database.add_mapping(guid + ",Old,a:b0,dpup:b11,misc1:b15,")
    var joystick = Joystick("Old", string_to_guid(guid), 0, 12, 1)
    var pad = Gamepad(joystick^, database.mappings[0])
    assert_equal(pad.bindings[1].input_type, BIND_HAT)
    assert_equal(pad.bindings[2].input_button, 11)
    pad.joystick.send_hat(0, HAT_UP)
    assert_true(pad.get_button(BUTTON_DPAD_UP))
    pad.joystick.send_button(11, True)
    assert_true(pad.get_button(BUTTON_MISC1))


def test_a_joystick_keeps_its_state() raises:
    with assert_raises():
        _ = Joystick("x", JoystickGuid(), -1, 0, 0)
    with assert_raises():
        _ = Joystick("x", JoystickGuid(), 0, -1, 0)
    with assert_raises():
        _ = Joystick("x", JoystickGuid(), 0, 0, -1)
    var joystick = Joystick("Pad", JoystickGuid(), 2, 2, 1)
    assert_equal(joystick.axis_count(), 2)
    assert_equal(joystick.button_count(), 2)
    assert_equal(joystick.hat_count(), 1)
    # Inputs it does not have read as rest and are ignored.
    assert_equal(joystick.get_axis(-1), 0)
    assert_equal(joystick.get_axis(2), 0)
    assert_false(joystick.get_button(-1))
    assert_false(joystick.get_button(2))
    assert_equal(joystick.get_hat(-1), 0)
    assert_equal(joystick.get_hat(1), 0)
    joystick.send_axis(5, 1)
    joystick.send_axis(-1, 1)
    joystick.send_button(5, True)
    joystick.send_button(-1, True)
    joystick.send_hat(5, 1)
    joystick.send_hat(-1, 1)
    assert_equal(len(joystick.take_events()), 0)
    # A repeat is not an event.
    joystick.send_button(1, True)
    joystick.send_button(1, True)
    joystick.send_hat(0, HAT_UP)
    joystick.send_hat(0, HAT_UP)
    var events = joystick.take_events()
    assert_equal(len(events), 2)
    assert_equal(events[0].kind, JOYSTICK_BUTTON)
    assert_equal(events[1].kind, JOYSTICK_HAT_MOTION)
    assert_equal(len(joystick.take_events()), 0)


def test_a_real_axis_holds_back_its_first_jitter() raises:
    # Not a virtual GUID, so the first motion must be more than 409.
    var joystick = Joystick("Pad", JoystickGuid(), 1, 0, 0)
    joystick.send_axis(0, 100)
    assert_equal(len(joystick.take_events()), 0)
    joystick.send_axis(0, 100)
    joystick.send_axis(0, 400)
    assert_equal(len(joystick.take_events()), 0)
    joystick.send_axis(0, 1000)
    var events = joystick.take_events()
    assert_equal(len(events), 2)
    assert_equal(events[0].kind, JOYSTICK_AXIS_MOTION)
    assert_equal(events[0].value, 100)
    assert_equal(events[1].value, 1000)
    joystick.send_axis(0, 1000)
    assert_equal(len(joystick.take_events()), 0)
    joystick.send_axis(0, 1001)
    assert_equal(len(joystick.take_events()), 1)


def test_an_axis_that_starts_at_an_end_takes_a_new_rest() raises:
    # A trigger that reports -32768 first, then a small value, rests there.
    var joystick = Joystick("Pad", JoystickGuid(), 1, 0, 0)
    joystick.send_axis(0, -32768)
    joystick.send_axis(0, 50)
    assert_equal(joystick.axes[0].initial_value, 50)
    assert_equal(len(joystick.take_events()), 0)
    var high = Joystick("Pad", JoystickGuid(), 1, 0, 0)
    high.send_axis(0, 32767)
    high.send_axis(0, 30000)
    assert_equal(high.axes[0].initial_value, 32767)
    assert_true(high.axes[0].has_second_value)
    var low = Joystick("Pad", JoystickGuid(), 1, 0, 0)
    low.send_axis(0, -32767)
    low.send_axis(0, 9000)
    assert_equal(low.axes[0].initial_value, -32767)
    var middle = Joystick("Pad", JoystickGuid(), 1, 0, 0)
    middle.send_axis(0, -32766)
    middle.send_axis(0, 50)
    assert_equal(middle.axes[0].initial_value, -32766)


def test_button_and_hat_bindings_drive_axes() raises:
    # The expected steps are SDL's for the same mapping.
    var pad = VirtualPad("leftx:b0,-lefty:h0.1,+lefty:h0.4,lefttrigger:b1,")
    pad.button(0, True)
    assert_equal(pad.step(), "axis 0 32767, axes 32767 0 0 0 0 0 buttons")
    assert_equal(pad.gamepad.get_axis(AXIS_LEFTX), 32767)
    pad.set_hat(HAT_UP)
    var events = pad.step()
    assert_equal(events, "axis 1 -32768, axes 32767 -32768 0 0 0 0 buttons")
    pad.set_hat(HAT_DOWN)
    assert_equal(
        pad.step(), "axis 1 0, axis 1 32767, axes 32767 32767 0 0 0 0 buttons"
    )
    pad.button(1, True)
    assert_equal(
        pad.step(), "axis 4 32767, axes 32767 32767 0 0 32767 0 buttons"
    )


def test_a_button_bound_to_nothing_is_dropped() raises:
    var pad = VirtualPad("a:b0,")
    var events = List[GamepadEvent]()
    pad.gamepad._send_button(events, GamepadButton(-1), True)
    assert_equal(len(events), 0)


def test_half_axes_and_unmatched_values() raises:
    var pad = VirtualPad("leftx:+a0,-lefty:+a1,x:+a4,")
    pad.axis(0, -5000)
    pad.axis(1, 32767)
    pad.axis(4, 32767)
    _ = pad.step()
    # Out of the input range reads as 0.
    assert_equal(pad.gamepad.get_axis(AXIS_LEFTX), 0)
    # 0 to 32767 in, 0 to -32768 out.
    assert_equal(pad.gamepad.get_axis(GamepadAxis(1)), -32768)
    assert_true(pad.gamepad.get_button(BUTTON_WEST))
    # A value no binding matches releases what the axis held.
    pad.axis(4, -32768)
    assert_equal(pad.step(), "up 2, axes 0 -32768 0 0 0 0 buttons")


def test_a_mapping_with_no_bindings_reads_rest() raises:
    var pad = VirtualPad("platform:Linux,")
    assert_false(pad.gamepad.has_axis(AXIS_LEFTX))
    assert_false(pad.gamepad.has_button(BUTTON_SOUTH))
    pad.axis(0, 1000)
    pad.button(0, True)
    pad.set_hat(HAT_UP)
    assert_equal(pad.step(), "axes 0 0 0 0 0 0 buttons")
    assert_equal(len(pad.gamepad.recenter()), 0)


def test_only_the_bound_hat_drives_a_control() raises:
    var database = MappingDatabase()
    _ = database.add_mapping(ORACLE_GUID + ",Two Hats,dpup:h1.1,")
    var joystick = Joystick("Two Hats", string_to_guid(ORACLE_GUID), 0, 0, 2)
    var pad = Gamepad(joystick^, database.mappings[0])
    pad.joystick.send_hat(0, HAT_UP)
    assert_equal(len(pad.update()), 0)
    pad.joystick.send_hat(1, HAT_UP)
    var events = pad.update()
    assert_equal(len(events), 1)
    assert_equal(events[0].button, BUTTON_DPAD_UP)


def test_an_axis_at_its_top_end_takes_a_new_rest() raises:
    var joystick = Joystick("Pad", JoystickGuid(), 1, 0, 0)
    joystick.send_axis(0, 32767)
    joystick.send_axis(0, 50)
    assert_equal(joystick.axes[0].initial_value, 50)


def test_state_corners() raises:
    """The checks around SDL's state calls, which no recorded device hits."""
    # A rumble longer than SDL's longest is cut to it.
    var state = RumbleState()
    _ = state.commit(True, True, 1, 1, Duration64(100, SECOND), Duration64(0))
    assert_true(state.expiration.value() == MAX_RUMBLE_DURATION)
    with assert_raises():
        require_color(-1, 0, 0)
    # Two pads SDL knows are centered at zero, even with more axes.
    for pair in [(0x05A0, 0x3232), (0x0E8F, 0x3013)]:
        var known = create_joystick_guid(
            BUS_USB,
            VendorId(pair[0]),
            ProductId(pair[1]),
            0,
            "",
            "Pad",
            DRIVER_NONE,
            0,
        )
        var stick = Joystick("Pad", known, 3, 0, 0)
        assert_true(stick.axes[2].has_initial_value)
        _ = Joystick("Pad", known, 0, 0, 0)
    # XInput, RawInput and WGI pads rest their triggers at the bottom.
    for driver in [DRIVER_XINPUT, DRIVER_RAWINPUT, DRIVER_WGI]:
        var guid = JoystickGuid()
        guid.data[14] = UInt8(driver.value)
        var pad = Joystick("Pad", guid, 6, 0, 0)
        var left = 2 if driver == DRIVER_XINPUT else 4
        assert_equal(pad.get_axis(left), -32768)
    var joystick = Joystick("Pad", JoystickGuid(), 2, 1, 0)
    with assert_raises():
        joystick.add_touchpad(-1)
    with assert_raises():
        joystick.add_sensor(SensorType(9), Frequency(0))
    with assert_raises():
        joystick.set_sensor_enabled(SENSOR_GYRO, True)
    joystick.add_touchpad(1)
    joystick.add_sensor(SENSOR_GYRO, Frequency(0))
    # A reading of a sensor that is off, or missing, is dropped.
    joystick.send_sensor(SENSOR_GYRO, Duration64(0), 1)
    joystick.send_sensor(SENSOR_ACCEL, Duration64(0), 1)
    # A touch on a touchpad or finger that does not exist is dropped, and a
    # position outside 0 to 1 is clamped.
    joystick.send_touchpad(1, 0, True, 0.5, 0.5, 1)
    joystick.send_touchpad(-1, 0, True, 0.5, 0.5, 1)
    joystick.send_touchpad(0, 1, True, 0.5, 0.5, 1)
    joystick.send_touchpad(0, -1, True, 0.5, 0.5, 1)
    joystick.send_touchpad(0, 0, True, -2, 3, 1)
    var database = MappingDatabase()
    _ = database.add_mapping(
        "00000000000000000000000000000000,Pad,leftx:a0,lefty:a1,a:b0,"
    )
    var gamepad = Gamepad(joystick^, database.mappings[0])
    var finger = gamepad.touchpad_finger(0, 0)
    assert_equal(finger.x, 0)
    assert_equal(finger.y, 1)
    assert_equal(gamepad.touchpad_finger_count(-1), 0)
    assert_equal(gamepad.touchpad_finger_count(1), 0)
    with assert_raises():
        _ = gamepad.touchpad_finger(1, 0)
    with assert_raises():
        _ = gamepad.touchpad_finger(0, 1)
    with assert_raises():
        _ = gamepad.touchpad_finger(0, -1)
    assert_equal(gamepad.sensor_data_rate(SENSOR_ACCEL).value, 0)
    with assert_raises():
        _ = gamepad.sensor_data(SENSOR_ACCEL)
    for axis in [-1, 3]:
        with assert_raises():
            _ = gamepad.acceleration(SENSOR_ACCEL, axis)
        with assert_raises():
            _ = gamepad.angular_velocity(SENSOR_GYRO, axis)
    with assert_raises():
        _ = gamepad.angular_velocity(SensorType(-1), 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
