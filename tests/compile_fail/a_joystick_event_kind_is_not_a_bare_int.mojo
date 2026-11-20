# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A joystick event kind must be a `JoystickEventKind`, not a bare integer."""

from extensions.gamepad.joystick import JoystickEventKind


def main():
    var value: JoystickEventKind = 0
    _ = value.is_valid()
