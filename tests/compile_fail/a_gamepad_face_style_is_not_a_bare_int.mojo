# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A gamepad face style must be a `FaceStyle`, not a bare integer."""

from extensions.gamepad.ids import FaceStyle


def main():
    var value: FaceStyle = 0
    _ = value.is_valid()
