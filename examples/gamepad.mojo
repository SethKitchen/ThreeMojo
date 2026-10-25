# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Print what the gamepads on this Linux machine do.

    mojo run -I . examples/gamepad/hubs.mojo [SECONDS]

The HID hub runs the pads that SDL's HIDAPI drivers know: DualSense,
DualShock 4, Switch Pro and Xbox controllers on Bluetooth. Their light
shows the player, the south button rumbles them, and the north button
turns their motion sensors on. The evdev hub runs every other pad, and
skips the ones the HID hub runs. The program stops after SECONDS, 30 by
default.

Given a path that ends in `.png`, the program needs no pad. It feeds one
fixed state to a pad of the web backend and draws what the pad reads:
the two sticks, the two triggers and SDL's buttons. That is the gallery
image.
"""

from std.sys import argv
from std.time import perf_counter_ns, sleep
from extensions.gamepad.gamepad import (
    GAMEPAD_BUTTON_DOWN,
    GAMEPAD_SENSOR_UPDATE,
    GAMEPAD_TOUCHPAD_DOWN,
    GamepadEvent,
)
from extensions.gamepad.hid import HidrawFile
from extensions.gamepad.hidapi import HidHub
from extensions.gamepad.ids import (
    BUTTON_COUNT,
    BUTTON_NORTH,
    BUTTON_SOUTH,
    GamepadAxis,
    GamepadButton,
)
from extensions.gamepad.joystick import SENSOR_ACCEL, SENSOR_GYRO
from extensions.gamepad.linux import (
    EvdevFile,
    EvdevHub,
    GAMEPAD_ADDED,
    DeviceChange,
    default_mapping_database,
)
from extensions.gamepad.web import WebGamepadState, WebHub
from render.framebuffer import Color, Framebuffer
from render.png import encode as encode_png
from std.pathlib import Path
from units.si import Duration64, SECOND

comptime WIDTH = 520
comptime HEIGHT = 240


def _report(changes: List[DeviceChange]):
    """Print the pads that came and went."""
    for change in changes:
        var what = "added" if change.kind == GAMEPAD_ADDED else "removed"
        print(what, change.name, "at", change.path)


def _show(name: String, events: List[GamepadEvent]):
    """Print a pad's button presses, and its first touch and sensor events."""
    for event in events:
        if event.kind == GAMEPAD_BUTTON_DOWN:
            print(name, "pressed button", event.button.value)
        elif event.kind == GAMEPAD_TOUCHPAD_DOWN:
            print(name, "touched", event.x, event.y)
        elif (
            event.kind == GAMEPAD_SENSOR_UPDATE and event.sensor == SENSOR_GYRO
        ):
            print(name, "turned", event.data[0], event.data[1], event.data[2])


def _box(
    mut image: Framebuffer, x: Int, y: Int, w: Int, h: Int, color: Color
) raises:
    """Fill a rectangle that is inside the image."""
    for row in range(y, y + h):
        for column in range(x, x + w):
            image.set_pixel(column, row, color)


def _picture(path: String) raises:
    """Draw a pad of the web backend in one fixed state, and write a PNG."""
    var hub = WebHub()
    var state = WebGamepadState(0, "Xbox Wireless Controller", 4, 17)
    _ = hub.connect(state)
    # The browser's standard layout: the south button, the right shoulder
    # and the left trigger are down, and both sticks lean. SDL's mapping
    # binds each trigger to a button, so a trigger is all the way down.
    for button in [0, 5, 6]:
        state.digital_buttons[button] = True
        state.analog_buttons[button] = 1.0
    state.axes[0] = 0.7
    state.axes[1] = -0.5
    state.axes[2] = -0.4
    state.axes[3] = 0.8
    state.timestamp = 1.0
    _ = hub.update(state)
    ref pad = hub.pads[0].gamepad
    var image = Framebuffer(WIDTH, HEIGHT, Color(24, 26, 32))
    var side = 120
    for stick in range(2):
        # A stick: a square, and a dot where the stick is.
        var left = 60 + stick * 280
        _box(image, left, 20, side, side, Color(60, 64, 76))
        var x = pad.get_axis(GamepadAxis(stick * 2))
        var y = pad.get_axis(GamepadAxis(stick * 2 + 1))
        var dot_x = left + (x + 32768) * (side - 12) // 65535
        var dot_y = 20 + (y + 32768) * (side - 12) // 65535
        _box(image, dot_x, dot_y, 12, 12, Color(240, 240, 240))
        # Its trigger: a bar that fills as the trigger goes down.
        var fill = pad.get_axis(GamepadAxis(4 + stick)) * side // 32767
        _box(image, left, 150, side, 10, Color(60, 64, 76))
        _box(image, left, 150, fill, 10, Color(90, 200, 120))
    # SDL's buttons, in order: lit while down.
    var cell = WIDTH // BUTTON_COUNT
    for button in range(BUTTON_COUNT):
        var down = pad.get_button(GamepadButton(button))
        var color = Color(240, 190, 60) if down else Color(60, 64, 76)
        _box(image, button * cell + 2, 190, cell - 4, cell - 4, color)
    Path(path).write_bytes(encode_png(image))
    print("Wrote", path)


def main() raises:
    if len(argv()) > 1 and String(argv()[1]).endswith(".png"):
        _picture(String(argv()[1]))
        return
    var seconds = 30.0
    if len(argv()) > 1:
        seconds = Float64(atol(argv()[1]))
    var database = default_mapping_database()
    var hid = HidHub[HidrawFile]()
    var evdev = EvdevHub[EvdevFile]()
    var start = perf_counter_ns()
    while Float64(Int(perf_counter_ns()) - Int(start)) * 1e-9 < seconds:
        _report(hid.detect(database))
        _report(evdev.detect(database, hid.claimed()))
        for index in range(len(hid.pads)):
            ref pad = hid.pads[index]
            var events = pad.update()
            if not pad.pad:
                continue
            _show(pad.device.name, events)
            for event in events:
                if event.kind != GAMEPAD_BUTTON_DOWN:
                    continue
                if event.button == BUTTON_SOUTH:
                    _ = pad.rumble(0xFFFF, 0x8000, Duration64(0.2, SECOND))
                elif event.button == BUTTON_NORTH:
                    var on = not pad.pad.value().sensor_enabled(SENSOR_GYRO)
                    for type in [SENSOR_GYRO, SENSOR_ACCEL]:
                        if pad.pad.value().has_sensor(type):
                            _ = pad.set_sensor_enabled(type, on)
        for index in range(len(evdev.pads)):
            ref pad = evdev.pads[index]
            var events = pad.update()
            _show(pad.info.name, events)
            for event in events:
                if (
                    event.kind == GAMEPAD_BUTTON_DOWN
                    and event.button == BUTTON_SOUTH
                ):
                    _ = pad.rumble(0xFFFF, 0x8000, Duration64(0.2, SECOND))
        sleep(0.008)
