# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An input device class must be a `DeviceClass`, not a bare integer."""

from extensions.gamepad.evdev import DeviceClass


def main():
    var value: DeviceClass = 0
    _ = value.is_valid()
