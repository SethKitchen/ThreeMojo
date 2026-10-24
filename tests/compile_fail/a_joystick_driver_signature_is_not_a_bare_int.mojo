# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A joystick driver signature must be a `DriverSignature`, not a bare integer."""

from extensions.gamepad.guid import DriverSignature


def main():
    var value: DriverSignature = 0
    _ = value.is_valid()
