# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A controller type must be a `ControllerType`, not a bare integer."""

from extensions.gamepad.controller_type import ControllerType


def main():
    var value: ControllerType = 0
    _ = value.is_valid()
