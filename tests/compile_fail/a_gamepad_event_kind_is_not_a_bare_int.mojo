# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A gamepad event kind must be a `GamepadEventKind`, not a bare integer."""

from extensions.gamepad.gamepad import GamepadEventKind


def main():
    var value: GamepadEventKind = 0
    _ = value.is_valid()
