# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A gamepad axis must be a `GamepadAxis`, not a bare integer."""

from extensions.gamepad.ids import GamepadAxis


def main():
    var value: GamepadAxis = 0
    _ = value.is_valid()
