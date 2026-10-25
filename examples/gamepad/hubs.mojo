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
from extensions.gamepad.ids import BUTTON_NORTH, BUTTON_SOUTH
from extensions.gamepad.joystick import SENSOR_ACCEL, SENSOR_GYRO
from extensions.gamepad.linux import (
    EvdevFile,
    EvdevHub,
    GAMEPAD_ADDED,
    DeviceChange,
    default_mapping_database,
)
from units.si import Duration64, SECOND


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


def main() raises:
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
